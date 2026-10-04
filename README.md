# JamSCAN

An Android application for physical music collectors, built with Flutter/Dart
and a Python/FastAPI backend.

## Start here

- [Set up and run the project](docs/SETUP.md)
- [Work together on GitHub](docs/TEAM_WORKFLOW.md)
- [Branch and coding conventions](CONTRIBUTING.md)
- [Configure main-branch protection](docs/GITHUB_SETUP.md)
- [S1-01 acceptance checklist](docs/S1-01.md)
- [S1-05 API validation and live evidence](docs/S1-05.md)
- [Task ownership, completion audit, and report alignment](docs/TASK_STATUS.md)

## Current scope

This foundation implements **S1-01**: a shared project structure, a minimal
Android application, a backend health endpoint, build checks, and collaboration
guidelines. The app displays a single JamSCAN welcome screen. No API keys are
needed to build or test it.

Navigation, camera/gallery access, album models, recognition, external API
integrations, and local persistence belong to later tasks.

S1-05 adds backend development tools to validate Discogs metadata and iTunes
HTTPS previews. Live Discogs authentication, search, and metadata checks and
iTunes search/preview checks have passed. Visual search is deferred to its
separate task. These tools do not add application endpoints or mobile playback.

## S1-01 verification

The foundation was approved and merged through [PR #1](https://github.com/emrecandir9/JamScan/pull/1).
Android and backend checks passed, the APK launched in an Android emulator,
and `main` is protected with both CI checks required. Emre confirmed access
for all four teammates, one required approval, prevention of bypassing, and
the sprint-board update to Done. The final documentation was also approved
and merged through [PR #2](https://github.com/emrecandir9/JamScan/pull/2) on
2026-09-30, with both CI checks passing. S1-01 is complete; evidence is recorded
in [the S1-01 checklist](docs/S1-01.md).

## Repository structure

```text
mobile/
  lib/          Flutter entry point and application widget
  test/         Widget tests
  android/      Android platform project
backend/
  app/          FastAPI application
  scripts/      Opt-in external API validation tools
  tests/        Health and offline API validation tests
  Dockerfile    Backend development container
docs/          Setup, collaboration, and acceptance documentation
.github/
  workflows/    Automated quality checks and build validation
```

Riverpod is the planned state-management library, and SQLite/Drift is the
planned local-storage stack. Add them when the relevant story needs them.

## Everyday workflow

Update `main`, create a task branch, make and test changes, push the branch,
then open a pull request into `main`. A teammate reviews it; merge once the
review is approved and checks are green. See the step-by-step
[team guide](docs/TEAM_WORKFLOW.md).
