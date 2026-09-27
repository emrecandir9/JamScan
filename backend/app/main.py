"""Minimal API entry point for the shared project foundation."""

from fastapi import FastAPI

app = FastAPI(title="JamSCAN API", version="0.1.0")


@app.get("/health", tags=["health"])
def health() -> dict[str, str]:
    """Confirm that the backend is running without calling external services."""
    return {"status": "ok"}
