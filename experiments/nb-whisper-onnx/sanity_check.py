#!/usr/bin/env python3
"""Run a converted whisper model against real audio via sherpa-onnx's Python
bindings, forcing the target language explicitly (never auto-detect — see
README.md for why that matters).

Usage:
    ./venv/bin/python3 sanity_check.py \
        --encoder nb-whisper-base-encoder.onnx \
        --decoder nb-whisper-base-decoder.onnx \
        --tokens nb-whisper-base-tokens.txt \
        --language no \
        test_audio/*.wav

Or, to check every wav in test_audio/ against its reference .txt:
    ./venv/bin/python3 sanity_check.py --encoder ... --decoder ... --tokens ... --all
"""
import argparse
import wave
from pathlib import Path

import numpy as np
import sherpa_onnx

TEST_AUDIO_DIR = Path(__file__).parent / "test_audio"


def read_wave(path: Path) -> tuple[np.ndarray, int]:
    with wave.open(str(path), "rb") as w:
        assert w.getsampwidth() == 2, f"{path} is not 16-bit PCM — convert with ffmpeg first"
        rate = w.getframerate()
        raw = w.readframes(w.getnframes())
    samples = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    return samples, rate


def transcribe(recognizer: sherpa_onnx.OfflineRecognizer, wav_path: Path) -> str:
    samples, rate = read_wave(wav_path)
    stream = recognizer.create_stream()
    stream.accept_waveform(rate, samples)
    recognizer.decode_stream(stream)
    return stream.result.text


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--encoder", required=True, type=Path)
    parser.add_argument("--decoder", required=True, type=Path)
    parser.add_argument("--tokens", required=True, type=Path)
    parser.add_argument("--language", default="no", help="Forced language code — never left empty")
    parser.add_argument("--num-threads", type=int, default=2)
    parser.add_argument("wavs", nargs="*", type=Path, help="Wav files to transcribe")
    parser.add_argument("--all", action="store_true", help=f"Transcribe every *.wav in {TEST_AUDIO_DIR}")
    args = parser.parse_args()

    wavs = args.wavs
    if args.all:
        wavs = sorted(TEST_AUDIO_DIR.glob("*.wav"))
    if not wavs:
        parser.error("no wav files given — pass paths or --all after running fetch_test_audio.py")

    recognizer = sherpa_onnx.OfflineRecognizer.from_whisper(
        encoder=str(args.encoder),
        decoder=str(args.decoder),
        tokens=str(args.tokens),
        language=args.language,
        task="transcribe",
        num_threads=args.num_threads,
    )

    for wav in wavs:
        text = transcribe(recognizer, wav)
        print(f"\n[{wav.name}]")
        ref_path = wav.with_suffix(".txt")
        if ref_path.exists():
            print(f"  reference:  {ref_path.read_text().strip()}")
        print(f"  hypothesis: {text}")


if __name__ == "__main__":
    main()
