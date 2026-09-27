# Contributing to JamSCAN

## Branches and commits

`main` is the stable integrated version. Do development on a separate branch
for each task and open a pull request (PR) into `main`.

| Work | Branch example |
| --- | --- |
| Feature | `feature/S1-02-navigation` |
| Bug fix | `fix/S1-03-camera-permission` |
| Project maintenance | `chore/S1-01-repository-foundation` |
| Documentation | `docs/S1-01-setup-guide` |

Use a short commit message that explains the change:

```text
feat: add navigation shell
fix: handle denied camera permission
docs: explain local setup
test: add album model tests
chore: configure GitHub Actions
```

Keep a PR focused on one task. Do not include unrelated formatting changes,
generated build output, API keys, passwords, or signing keys.

## Coding conventions

### Dart / Flutter

- Use `lower_snake_case.dart` for filenames, `PascalCase` for types, and
  `camelCase` for methods and variables.
- Let `dart format` handle formatting; use the shared `flutter_lints` rules.
- Prefer small widgets/functions, clear names, and `const` where appropriate.
- Keep UI separate from networking and storage as those features are added.
- Keep `main.dart` focused on startup; put the application widget in `app.dart`.
- Commit `pubspec.lock` so every teammate resolves the same dependencies.

From `mobile/`, before opening a PR:

```bash
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter build apk --debug
```

### Python / FastAPI

- Use `snake_case` for modules/functions/variables and `PascalCase` for classes.
- Use four-space indentation, type hints, and Ruff formatting (88 columns).
- Keep routes separate from service/integration logic when those modules grow.
- Keep external API credentials in backend environment variables.
- Add dependencies in `pyproject.toml`, then update the committed lock files
  using the instructions in [SETUP.md](docs/SETUP.md#updating-dependencies).

From `backend/`, with the virtual environment activated:

```bash
ruff format .
ruff check .
python -m pytest
python -m build
```

## Reviews and merging

1. Explain the story, changes, and validation in the PR template.
2. Ask another team member to review. You cannot approve your own PR.
3. Resolve feedback and discussion threads; push fixes to the same branch.
4. Wait for `Mobile checks` and `Backend checks` to pass.
5. Merge after at least one teammate approves. Prefer **Squash and merge**.
6. Delete the merged task branch on GitHub and update your local `main`.

New commits may invalidate an approval, so obtain a fresh review when needed.
Never force-push to `main`. Do not disable protection to get a PR merged.

See [TEAM_WORKFLOW.md](docs/TEAM_WORKFLOW.md) for the beginner walkthrough
and [GITHUB_SETUP.md](docs/GITHUB_SETUP.md) for the settings that enforce it.
