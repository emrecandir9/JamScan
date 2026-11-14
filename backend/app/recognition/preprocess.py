"""Decode, check, and normalise cover images for the embedding model.

Reference covers and query photos must go through the same steps, so the
index records :data:`PREPROCESS_VERSION` and refuses to load when it differs.
"""

from dataclasses import dataclass
from io import BytesIO

import numpy as np
from PIL import Image, ImageOps, UnidentifiedImageError

PREPROCESS_VERSION = "square-224-imagenet-v1"
MODEL_INPUT_SIZE = 224
MAX_IMAGE_PIXELS = 40_000_000
QUALITY_SIDE = 512

_MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)
_STD = np.array([0.229, 0.224, 0.225], dtype=np.float32)


class InvalidImageError(ValueError):
    """Raised when uploaded bytes are not a usable image."""


@dataclass(frozen=True)
class ImageQuality:
    """Variance of the Laplacian (sharpness) and mean grey level (0-255)."""

    sharpness: float
    brightness: float


def load_image(data: bytes) -> Image.Image:
    """Decode an upload as upright RGB, rejecting empty or oversized images."""
    if not data:
        raise InvalidImageError("The image is empty.")
    try:
        with Image.open(BytesIO(data)) as image:
            width, height = image.size
            if width * height > MAX_IMAGE_PIXELS:
                raise InvalidImageError("The image has too many pixels.")
            upright = ImageOps.exif_transpose(image)
            return upright.convert("RGB")
    except (UnidentifiedImageError, Image.DecompressionBombError, OSError) as error:
        raise InvalidImageError("The file is not a supported image.") from error


def square_crop(image: Image.Image) -> Image.Image:
    """Centre-crop to a square; the phone already sends square cover crops."""
    width, height = image.size
    side = min(width, height)
    left = (width - side) // 2
    top = (height - side) // 2
    return image.crop((left, top, left + side, top + side))


def measure_quality(image: Image.Image) -> ImageQuality:
    """Estimate blur and exposure on a downscaled greyscale copy."""
    grey = image.convert("L")
    grey.thumbnail((QUALITY_SIDE, QUALITY_SIDE), Image.Resampling.BILINEAR)
    pixels = np.asarray(grey, dtype=np.float32)
    if min(pixels.shape) < 3:
        return ImageQuality(sharpness=0.0, brightness=float(pixels.mean()))
    laplacian = (
        pixels[:-2, 1:-1]
        + pixels[2:, 1:-1]
        + pixels[1:-1, :-2]
        + pixels[1:-1, 2:]
        - 4 * pixels[1:-1, 1:-1]
    )
    return ImageQuality(
        sharpness=float(laplacian.var()), brightness=float(pixels.mean())
    )


def to_model_input(image: Image.Image) -> np.ndarray:
    """Return a ``(1, 3, 224, 224)`` float32 tensor with ImageNet normalisation.

    The whole cover is resized rather than cropped further, because album
    artwork often carries identifying text close to its edges.
    """
    resized = square_crop(image).resize(
        (MODEL_INPUT_SIZE, MODEL_INPUT_SIZE), Image.Resampling.BICUBIC
    )
    pixels = np.asarray(resized, dtype=np.float32) / 255.0
    normalised = (pixels - _MEAN) / _STD
    return normalised.transpose(2, 0, 1)[np.newaxis].astype(np.float32)
