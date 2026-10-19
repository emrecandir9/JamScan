"""API entry point."""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.recognition.config import RecognitionSettings
from app.recognition.routes import router as recognition_router
from app.recognition.service import load_recognizer


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    settings = RecognitionSettings.from_env()
    app.state.recognition_settings = settings
    app.state.recognizer = load_recognizer(settings)
    yield


app = FastAPI(title="JamSCAN API", version="0.1.0", lifespan=lifespan)
app.include_router(recognition_router)


@app.get("/health", tags=["health"])
def health() -> dict[str, str]:
    """Confirm that the backend is running without calling external services."""
    return {"status": "ok"}
