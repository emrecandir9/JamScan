# JamSCAN backend

FastAPI backend for JamSCAN. `GET /health` returns `{"status":"ok"}` without
external services. `POST /recognitions` identifies an album cover (S2-03).

See [setup](../docs/SETUP.md) for Python, Docker, and check commands, and
[contribution guidelines](../CONTRIBUTING.md) for team conventions.

## Album-cover recognition (S2-03)

Recognition needs a model and a reference index, which are not stored in Git:

```bash
python -m scripts.download_model
python -m scripts.fetch_dev_covers   # needs DISCOGS_TOKEN
python -m scripts.build_index
```

Without them the API still starts and `/recognitions` returns `503`. See
[S2-03](../docs/S2-03.md) for the API contract, the dataset format, settings,
and validation results.

## External API validation (S1-05)

With the development environment activated, run from `backend/`:

```bash
python -m scripts.validate_apis --provider itunes
python -m scripts.validate_apis
```

The first command checks public iTunes song search and an HTTPS audio preview.
The second also checks Discogs; authenticated checks require `DISCOGS_TOKEN`.
Without it, public metadata is still checked and the report exits nonzero to
show incomplete validation. See [S1-05](../docs/S1-05.md) for credentials,
options, live evidence, rate limits, and preview usage conditions.

All five live checks passed with a locally configured Discogs token on
2026-10-04. The sanitized report is saved in
[S1-05 evidence](../docs/evidence/S1-05-api-validation.json). To rerun with your
local `.env`, first export its variables as described in the S1-05 guide; the
script does not load that file automatically.

These are source-checkout development tools using the existing `httpx` dev
dependency. They are not included in the production backend package/container.
Normal tests use mocked HTTP and do not contact external providers.
