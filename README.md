# JamSCAN

An Android application for physical music collectors, built with Flutter/Dart
and a Python/FastAPI backend.

## Start here

- [Set up and run the project](docs/SETUP.md)
- [Work together on GitHub](docs/TEAM_WORKFLOW.md)
- [Branch and coding conventions](CONTRIBUTING.md)
- [Configure main-branch protection](docs/GITHUB_SETUP.md)
- [S1-01 acceptance checklist](docs/S1-01.md)
- [Album data model](docs/DATA_MODEL.md)

## Current scope

This foundation implements **S1-01**: a shared project structure, a minimal
Android application, a backend health endpoint, build checks, and collaboration
guidelines. The app displays a single JamSCAN welcome screen. No API keys are
needed to build or test it.

Navigation, camera/gallery access, album models, recognition, external API
integrations, and local persistence belong to later tasks.

## S1-01 verification

The foundation was approved and merged through [PR #1](https://github.com/emrecandir9/JamScan/pull/1).
Android and backend checks passed, the APK launched in an Android emulator,
and `main` is protected with both CI checks required. Emre confirmed access
for all four teammates, one required approval, prevention of bypassing, and
the sprint-board update to Done. All S1-01 acceptance criteria are satisfied;
only the final documentation PR needs review and merge. Evidence is recorded
in [the S1-01 checklist](docs/S1-01.md).

## Repository structure

```text
mobile/
  lib/          Flutter entry point and application widget
  test/         Widget tests
  android/      Android platform project
backend/
  app/          FastAPI application
  tests/        API tests
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
