"""Turn preprocessed cover images into L2-normalised embedding vectors."""

from pathlib import Path
from typing import Protocol

import numpy as np
from PIL import Image

from app.recognition.preprocess import to_model_input


class Embedder(Protocol):
    """Anything that maps an image to a unit-length vector."""

    model_id: str
    dimension: int

    def embed(self, image: Image.Image) -> np.ndarray: ...


def l2_normalise(vectors: np.ndarray) -> np.ndarray:
    norms = np.linalg.norm(vectors, axis=-1, keepdims=True)
    return vectors / np.maximum(norms, 1e-12)


class OnnxDinoEmbedder:
    """DINOv2-small through ONNX Runtime on the CPU.

    The vector is the final class token. On the development set it separated
    correct covers from the closest wrong cover as well as adding the mean of
    the patch tokens, at half the size.
    """

    model_id = "dinov2-small/cls/v1"
    dimension = 384

    def __init__(self, model_path: Path) -> None:
        import onnxruntime

        if not model_path.is_file():
            raise FileNotFoundError(
                f"Model not found at {model_path}; run scripts.download_model."
            )
        self._session = onnxruntime.InferenceSession(
            str(model_path), providers=["CPUExecutionProvider"]
        )
        self._input_name = self._session.get_inputs()[0].name

    def embed(self, image: Image.Image) -> np.ndarray:
        (hidden,) = self._session.run(None, {self._input_name: to_model_input(image)})
        return l2_normalise(hidden[0, 0].astype(np.float32))
