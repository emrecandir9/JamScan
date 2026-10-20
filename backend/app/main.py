"""FastAPI entry point for the JamSCAN backend."""

from fastapi import FastAPI

from app.routes import router

app = FastAPI(title="JamSCAN API", version="0.1.0")

app.include_router(router)


@app.get("/health", tags=["health"])
def health() -> dict[str, str]:
    """Confirm that the backend is running without external services."""
    return {"status": "ok"}
