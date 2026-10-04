# JamSCAN

JamSCAN is an Android application in development for physical music collectors.
Its planned workflow connects album-cover recognition, release information,
audio previews, and personal collections and wishlists.

## Architecture

- **Mobile:** Flutter and Dart provide the Android interface.
- **Backend:** Python and FastAPI provide the foundation for the REST API and
  external-service integrations.
- **External services:** Discogs supplies release metadata, and the iTunes
  Search API supplies links to available audio previews.
- **Planned persistence:** SQLite with Drift will store collections and related
  data locally. Riverpod is the planned state-management library.
- **Development tools:** Docker supports a consistent backend environment,
  while GitHub Actions runs quality checks, tests, and builds.

The project is being built incrementally. The current mobile app contains a
welcome screen, and the backend exposes a health endpoint. Development scripts
validate external API access; the complete scanning and playback workflow is
not yet integrated.

## Getting started

Follow the [setup guide](docs/SETUP.md) to install the required Flutter,
Android, Java, and Python tools and run the project locally.

- [Mobile application](mobile/README.md)
- [Backend and API validation tools](backend/README.md)
- [Contribution and coding conventions](CONTRIBUTING.md)
- [GitHub collaboration workflow](docs/TEAM_WORKFLOW.md)
- [Repository protection settings](docs/GITHUB_SETUP.md)

Keep API credentials in backend environment variables. Use
[`backend/.env.example`](backend/.env.example) as a local configuration template;
never commit real credentials or include them in the mobile application.

## Repository structure

```text
mobile/
  lib/          Flutter application code
  test/         Mobile tests
  android/      Android platform configuration
backend/
  app/          FastAPI application
  scripts/      External API validation tools
  tests/        Backend and integration validation tests
  Dockerfile    Backend development container
docs/           Setup, design decisions, and validation documentation
.github/
  workflows/    Automated quality checks and builds
```

## Development workflow

Create a separate branch for each change, follow the shared coding conventions,
and run the relevant checks before opening a pull request into `main`.
Changes require passing CI and a teammate's approval before merging.

See [CONTRIBUTING.md](CONTRIBUTING.md) for formatting, linting, testing, and build
commands. Live API validation is opt-in; automated tests use mocked external
responses and do not require API credentials.
