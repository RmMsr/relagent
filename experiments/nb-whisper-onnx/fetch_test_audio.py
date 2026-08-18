#!/usr/bin/env python3
"""Fetch two real (non-synthetic) Norwegian speech samples for sanity-checking
a converted model, with ground-truth transcripts. See README.md for why
espeak-ng or other TTS output is a bad test signal here.

- FLEURS: clean single-speaker read speech, out-of-domain for NbAiLab's models.
- NPSC: Norwegian Parliament recordings — the actual corpus NbAiLab's
  nb-whisper/nb-wav2vec2 models are fine-tuned on, i.e. in-domain.

Both are fetched via HuggingFace's public dataset APIs; no full dataset
download required.

Usage:
    ./venv/bin/python3 fetch_test_audio.py
"""
import json
import subprocess
import urllib.request
from pathlib import Path

import pyarrow.parquet as pq

OUT_DIR = Path(__file__).parent / "test_audio"


def fetch_fleurs() -> None:
    url = (
        "https://datasets-server.huggingface.co/first-rows"
        "?dataset=google%2Ffleurs&config=nb_no&split=test"
    )
    with urllib.request.urlopen(url) as r:
        data = json.load(r)
    row = data["rows"][1]["row"]  # index 1: a clean, medium-length sentence
    audio_url = row["audio"][0]["src"]
    transcript = row["transcription"]

    raw = OUT_DIR / "fleurs_no_raw.wav"
    urllib.request.urlretrieve(audio_url, raw)

    wav = OUT_DIR / "fleurs_no.wav"
    subprocess.run(
        ["ffmpeg", "-y", "-i", str(raw), "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", str(wav)],
        check=True, capture_output=True,
    )
    raw.unlink()
    (OUT_DIR / "fleurs_no.txt").write_text(transcript)
    print(f"wrote {wav} + reference transcript")


def fetch_npsc() -> None:
    parquet_url = (
        "https://huggingface.co/datasets/NbAiLab/NPSC/resolve/"
        "refs%2Fconvert%2Fparquet/16K_mp3_bokmaal/test/0000.parquet"
    )
    local_parquet = OUT_DIR / "_npsc_test_shard.parquet"
    if not local_parquet.exists():
        print("downloading NPSC test shard (~120MB, one-time)...")
        urllib.request.urlretrieve(parquet_url, local_parquet)

    pf = pq.ParquetFile(local_parquet)
    batch = next(pf.iter_batches(batch_size=20, columns=["sentence_id", "text", "audio"]))
    # sentence_id 7368: ~6.6s, clean single-speaker political speech
    row = next(r for r in batch.to_pylist() if r["sentence_id"] == 7368)

    mp3 = OUT_DIR / "npsc_sample.mp3"
    mp3.write_bytes(row["audio"]["bytes"])

    wav = OUT_DIR / "npsc_sample.wav"
    subprocess.run(
        ["ffmpeg", "-y", "-i", str(mp3), "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", str(wav)],
        check=True, capture_output=True,
    )
    mp3.unlink()
    local_parquet.unlink()
    (OUT_DIR / "npsc_sample.txt").write_text(row["text"])
    print(f"wrote {wav} + reference transcript")


if __name__ == "__main__":
    OUT_DIR.mkdir(exist_ok=True)
    fetch_fleurs()
    fetch_npsc()
