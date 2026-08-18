#!/usr/bin/env python3
"""Reproduce the app's exact VAD-chunking + per-segment Whisper decode path,
offline, against known-good reference audio — no device needed.

sanity_check.py feeds a whole clip to Whisper in one shot and gets excellent
results. The app never does that: apps/lib/speech_recognition/sherpa_vad_asr.dart
feeds 512-sample windows into a Silero VAD, and only hands Whisper the audio
between VAD-detected speech boundaries, one segment at a time. This script
mirrors that logic (same VAD config values, same windowing, same per-segment
decode) using the real sherpa-onnx runtime, so a quality gap between this and
sanity_check.py's whole-clip results localizes the bug to VAD segmentation
itself rather than the model/runtime/token config (which sanity_check.py
already validates end-to-end).

Usage:
    ./venv/bin/python3 vad_chunk_check.py \
        --encoder out/nb-whisper-base/nb-whisper-base-encoder.int8.onnx \
        --decoder out/nb-whisper-base/nb-whisper-base-decoder.int8.fp16emb.onnx \
        --tokens  out/nb-whisper-base/nb-whisper-base-tokens.txt \
        --vad ../../apps/assets/silero_vad.onnx \
        --all
"""
import argparse
import wave
from pathlib import Path

import numpy as np
import sherpa_onnx

TEST_AUDIO_DIR = Path(__file__).parent / "test_audio"

# Must match apps/lib/speech_recognition/sherpa_vad_asr.dart exactly.
WINDOW_SIZE = 512
SAMPLE_RATE = 16000
VAD_THRESHOLD = 0.5
MIN_SILENCE_DURATION = 0.5
MIN_SPEECH_DURATION = 0.25
MAX_SPEECH_DURATION = 30.0


def read_wave(path: Path) -> np.ndarray:
    with wave.open(str(path), "rb") as w:
        assert w.getsampwidth() == 2, f"{path} is not 16-bit PCM — convert with ffmpeg first"
        assert w.getframerate() == SAMPLE_RATE, f"{path} is {w.getframerate()}Hz, expected {SAMPLE_RATE}"
        raw = w.readframes(w.getnframes())
    return np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0


def build_vad(vad_model_path: str) -> sherpa_onnx.VoiceActivityDetector:
    config = sherpa_onnx.VadModelConfig()
    config.silero_vad.model = vad_model_path
    config.silero_vad.threshold = VAD_THRESHOLD
    config.silero_vad.min_silence_duration = MIN_SILENCE_DURATION
    config.silero_vad.min_speech_duration = MIN_SPEECH_DURATION
    config.silero_vad.window_size = WINDOW_SIZE
    config.silero_vad.max_speech_duration = MAX_SPEECH_DURATION
    config.sample_rate = SAMPLE_RATE
    return sherpa_onnx.VoiceActivityDetector(config, buffer_size_in_seconds=30)


def chunk_and_transcribe(
    recognizer: sherpa_onnx.OfflineRecognizer,
    vad: sherpa_onnx.VoiceActivityDetector,
    samples: np.ndarray,
) -> list[tuple[float, str]]:
    """Yields (segment_duration_seconds, transcription) per VAD segment,
    in the same accept-window / drain-segments order as _processChunk()."""
    results = []
    pos = 0
    while pos + WINDOW_SIZE <= len(samples):
        vad.accept_waveform(samples[pos : pos + WINDOW_SIZE])
        pos += WINDOW_SIZE
        while not vad.empty():
            # NOTE: `front` is a reference valid only until the next method
            # call on this VAD instance (per sherpa_onnx's own docstring) —
            # materialize .samples into a plain numpy array BEFORE pop().
            samples_copy = np.array(vad.front.samples, dtype=np.float32)
            vad.pop()
            stream = recognizer.create_stream()
            stream.accept_waveform(SAMPLE_RATE, samples_copy)
            recognizer.decode_stream(stream)
            duration = len(samples_copy) / SAMPLE_RATE
            results.append((duration, stream.result.text))
    vad.flush()
    while not vad.empty():
        samples_copy = np.array(vad.front.samples, dtype=np.float32)
        vad.pop()
        stream = recognizer.create_stream()
        stream.accept_waveform(SAMPLE_RATE, samples_copy)
        recognizer.decode_stream(stream)
        duration = len(samples_copy) / SAMPLE_RATE
        results.append((duration, stream.result.text))
    return results


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--encoder", required=True, type=Path)
    parser.add_argument("--decoder", required=True, type=Path)
    parser.add_argument("--tokens", required=True, type=Path)
    parser.add_argument("--vad", required=True, type=Path, help="Path to silero_vad.onnx")
    parser.add_argument("--language", default="no")
    parser.add_argument("--num-threads", type=int, default=2)
    parser.add_argument("wavs", nargs="*", type=Path)
    parser.add_argument("--all", action="store_true", help=f"Every *.wav in {TEST_AUDIO_DIR}")
    args = parser.parse_args()

    wavs = args.wavs
    if args.all:
        wavs = sorted(TEST_AUDIO_DIR.glob("*.wav"))
    if not wavs:
        parser.error("no wav files given — pass paths or --all")

    recognizer = sherpa_onnx.OfflineRecognizer.from_whisper(
        encoder=str(args.encoder),
        decoder=str(args.decoder),
        tokens=str(args.tokens),
        language=args.language,
        task="transcribe",
        num_threads=args.num_threads,
    )

    for wav in wavs:
        samples = read_wave(wav)
        vad = build_vad(str(args.vad))
        segments = chunk_and_transcribe(recognizer, vad, samples)

        print(f"\n[{wav.name}] {len(samples) / SAMPLE_RATE:.1f}s total, {len(segments)} VAD segment(s)")
        ref_path = wav.with_suffix(".txt")
        if ref_path.exists():
            print(f"  whole-clip reference: {ref_path.read_text().strip()}")
        for i, (duration, text) in enumerate(segments):
            print(f"  segment {i} ({duration:.2f}s): {text!r}")


if __name__ == "__main__":
    main()
