FROM python:3.12-slim

WORKDIR /app
COPY pyproject.toml requirements.lock ./
COPY app ./app
RUN python -m pip install --no-cache-dir -r requirements.lock \
    && python -m pip install --no-cache-dir --no-deps . \
    && useradd --create-home appuser

USER appuser
EXPOSE 8000
CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
