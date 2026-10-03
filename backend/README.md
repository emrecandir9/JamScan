# JamSCAN backend

Minimal FastAPI starter for S1-01. The only application endpoint is
`GET /health`, which returns `{"status":"ok"}` without external services.

See [setup](../docs/SETUP.md) for Python, Docker, and check commands, and
[contribution guidelines](../CONTRIBUTING.md) for team conventions.

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
2026-10-03. The sanitized report is saved in
[S1-05 evidence](../docs/evidence/S1-05-api-validation.json). To rerun with your
local `.env`, first export its variables as described in the S1-05 guide; the
script does not load that file automatically.

These are source-checkout development tools using the existing `httpx` dev
dependency. They are not included in the production backend package/container.
Normal tests use mocked HTTP and do not contact external providers.
