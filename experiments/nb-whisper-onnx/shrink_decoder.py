#!/usr/bin/env python3
"""Shrink the one tensor onnxruntime's dynamic quantizer can't reach.

sherpa-onnx's export-onnx.py already runs quantize_dynamic(op_types=["MatMul"])
on the decoder, but it only quantizes MatMul nodes of the form
MatMul(activation, weight) — weight as the *second* operand, matching how
nn.Linear normally traces. Whisper's tied output-projection computes
MatMul(token_embedding.weight, activation) instead (weight first), which the
quantizer's pattern matcher doesn't recognize, so that one tensor — also the
single largest tensor in the whole model (vocab_size x d_model) — stays fp32
even after "quantization".

Rather than hand-rolling int8 weight-only quantization for just this one
tensor (real risk: scale/zero-point plumbing to get subtly wrong), this
downcasts it to fp16 with a Cast node restoring fp32 at the matmul boundary.
Verified numerically to produce identical transcription output to the
int8-only version on real audio — see README.md.

Usage:
    ./venv/bin/python3 shrink_decoder.py nb-whisper-base-decoder.int8.onnx \
        -o nb-whisper-base-decoder.int8.fp16emb.onnx
"""
import argparse
from pathlib import Path

import numpy as np
import onnx
from onnx import TensorProto, numpy_helper


def find_largest_fp32_initializer(model: onnx.ModelProto) -> str:
    largest = max(
        (i for i in model.graph.initializer if i.data_type == TensorProto.FLOAT),
        key=lambda i: len(i.raw_data),
    )
    return largest.name


def shrink(in_path: Path, out_path: Path, tensor_name: str | None) -> None:
    model = onnx.load(str(in_path))

    target_name = tensor_name or find_largest_fp32_initializer(model)
    target = next(i for i in model.graph.initializer if i.name == target_name)
    before_bytes = len(target.raw_data)
    print(f"downcasting '{target_name}' ({list(target.dims)}, {before_bytes / 1e6:.1f}MB fp32) to fp16")

    arr = numpy_helper.to_array(target).astype(np.float16)
    model.graph.initializer.remove(target)
    fp16_name = target_name + "_fp16"
    model.graph.initializer.append(numpy_helper.from_array(arr, name=fp16_name))

    # Insert a Cast(fp16 -> float32) that produces the *original* tensor
    # name, so every existing consumer node needs zero changes.
    cast_node = onnx.helper.make_node(
        "Cast",
        inputs=[fp16_name],
        outputs=[target_name],
        to=TensorProto.FLOAT,
        name=f"Cast_{target_name.replace('.', '_')}_fp16_to_fp32",
    )
    model.graph.node.insert(0, cast_node)

    onnx.checker.check_model(model)
    onnx.save(model, str(out_path))

    after_bytes = out_path.stat().st_size
    print(f"before: {in_path.stat().st_size / 1e6:.1f}MB  after: {after_bytes / 1e6:.1f}MB")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("decoder_onnx", type=Path, help="An already int8-quantized decoder .onnx")
    parser.add_argument("-o", "--out", type=Path, required=True)
    parser.add_argument(
        "--tensor",
        default=None,
        help="Initializer name to downcast (default: auto-detect the largest fp32 one)",
    )
    args = parser.parse_args()
    shrink(args.decoder_onnx, args.out, args.tensor)
