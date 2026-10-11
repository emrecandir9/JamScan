# JamSCAN

JamSCAN is an Android application in development for physical music collectors.
Its planned workflow connects album-cover recognition, release information,
audio previews, and personal collections and wishlists.

## Architecture

- [Set up and run the project](docs/SETUP.md)
- [Work together on GitHub](docs/TEAM_WORKFLOW.md)
- [Branch and coding conventions](CONTRIBUTING.md)
- [Configure main-branch protection](docs/GITHUB_SETUP.md)
- [S1-01 acceptance checklist](docs/S1-01.md)
- [Album data model](docs/DATA_MODEL.md)
- [App shell and user interface](docs/UI_SHELL.md)

The project is being built incrementally. The mobile app implements the
wireframed screens with mocked recognition, search, accounts and previews, and
the backend exposes a health endpoint. Development scripts
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
