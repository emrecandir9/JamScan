"""Download the pinned DINOv2-small ONNX model and verify its checksum."""

import argparse
import hashlib
from pathlib import Path

import httpx

from app.recognition.config import DEFAULT_MODEL_PATH

# Xenova's ONNX export of facebook/dinov2-small (Apache-2.0), pinned to a commit.
MODEL_URL = (
    "https://huggingface.co/Xenova/dinov2-small/resolve/"
    "c2bb04a51fab207c420665f1946016107bffc701/onnx/model.onnx"
)
MODEL_SHA256 = "83141175ec78b4ff9a2bb58a4c7c264ba0054d1c2e122e5a8114b79a8d4179ea"


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download(destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    partial = destination.with_suffix(destination.suffix + ".part")
    with httpx.stream("GET", MODEL_URL, follow_redirects=True, timeout=60) as response:
        response.raise_for_status()
        with partial.open("wb") as file:
            for chunk in response.iter_bytes():
                file.write(chunk)
    if sha256_of(partial) != MODEL_SHA256:
        partial.unlink()
        raise SystemExit("Checksum mismatch; the downloaded model was deleted.")
    partial.replace(destination)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_MODEL_PATH)
    args = parser.parse_args()
    if args.output.exists() and sha256_of(args.output) == MODEL_SHA256:
        print(f"Model already present: {args.output}")
        return 0
    download(args.output)
    print(f"Model saved to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
