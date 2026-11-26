# /// script
# requires-python = ">=3.11"
# dependencies = ["av", "numpy"]
# ///
"""Turn test videos into grey frames for the mobile live-detection replay test.

Each video becomes ``<output>/<name>/NNNNN.pgm``: 8-bit grey frames sampled at
``--fps`` (5 matches the app's 200 ms analysis interval) and scaled to fit
``--width`` x ``--height`` (360 x 640 gives the same 180 x 320 analysis frame
as a 1280 x 720 camera stream). Screen recordings carry the phone's status
and navigation bars; ``--crop-top`` and ``--crop-bottom`` cut them off as
fractions of the height.

The videos and frames are not committed. Run with uv, which installs the
dependencies::

    uv run backend/scripts/prepare_replay_frames.py video1.mp4 video2.mp4 \
        --output mobile/build/replay
"""

import argparse
from pathlib import Path

import av
import numpy as np


def write_pgm(path: Path, grey: np.ndarray) -> None:
    height, width = grey.shape
    path.write_bytes(f"P5\n{width} {height}\n255\n".encode() + grey.tobytes())


def resize_area(grey: np.ndarray, width: int, height: int) -> np.ndarray:
    """Box-filter resize, enough for downscaling."""
    src_h, src_w = grey.shape
    ys = (np.arange(height + 1) * src_h / height).astype(int)
    xs = (np.arange(width + 1) * src_w / width).astype(int)
    rows = np.add.reduceat(grey.astype(np.float32), ys[:-1], axis=0)
    rows /= np.diff(ys)[:, None]
    out = np.add.reduceat(rows, xs[:-1], axis=1) / np.diff(xs)[None, :]
    return np.clip(out + 0.5, 0, 255).astype(np.uint8)


def convert(video: Path, out_dir: Path, args: argparse.Namespace) -> int:
    out_dir.mkdir(parents=True, exist_ok=True)
    # Frames left from an earlier, longer run would be replayed too.
    for old in out_dir.glob("*.pgm"):
        old.unlink()
    with av.open(str(video)) as container:
        stream = container.streams.video[0]
        next_time = None
        written = 0
        for frame in container.decode(stream):
            # Phone recordings have a variable frame rate: sample by
            # timestamp, not by frame count.
            time = frame.time or 0.0
            if next_time is None:
                next_time = time
            if time + 1e-6 < next_time:
                continue
            next_time += 1 / args.fps
            grey = frame.to_ndarray(format="gray")
            h = grey.shape[0]
            grey = grey[int(h * args.crop_top) : int(h * (1 - args.crop_bottom))]
            gh, gw = grey.shape
            # Only ever shrink: the box filter cannot enlarge.
            scale = min(1.0, args.width / gw, args.height / gh)
            grey = resize_area(grey, round(gw * scale), round(gh * scale))
            write_pgm(out_dir / f"{written:05d}.pgm", grey)
            written += 1
    return written


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("videos", nargs="+", type=Path)
    parser.add_argument("--output", type=Path, default=Path("mobile/build/replay"))
    parser.add_argument("--fps", type=float, default=5.0)
    parser.add_argument("--width", type=int, default=360)
    parser.add_argument("--height", type=int, default=640)
    parser.add_argument("--crop-top", type=float, default=0.05)
    parser.add_argument("--crop-bottom", type=float, default=0.10)
    parser.add_argument(
        "--names", nargs="*", help="Folder name per video (default: clip1, clip2, ...)"
    )
    args = parser.parse_args()
    names = args.names or [f"clip{i + 1}" for i in range(len(args.videos))]
    for video, name in zip(args.videos, names, strict=True):
        count = convert(video, args.output / name, args)
        print(f"{video.name}: {count} frames -> {args.output / name}")


if __name__ == "__main__":
    main()
