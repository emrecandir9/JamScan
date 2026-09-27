# Contributing to JamSCAN

## Branching Strategy

The `main` branch contains the stable integrated version of JamSCAN.

Developers must not work directly on `main`.

Create a branch for each task.

### Branch Naming

Features:

feature/<story-id>-<description>

Example:

feature/S1-02-navigation

Bug fixes:

fix/<story-id>-<description>

Example:

fix/S1-03-camera-permission

Maintenance:

chore/<description>

Example:

chore/update-dependencies


## Development Workflow

1. Update local main:

   git checkout main
   git pull origin main

2. Create a feature branch:

   git checkout -b feature/S1-02-navigation

3. Implement the task.

4. Commit changes.

5. Push the branch to GitHub.

6. Open a Pull Request into `main`.

7. At least one other team member reviews the Pull Request.

8. Automated checks must pass.

9. Merge the Pull Request into `main`.

10. Delete the feature branch after merging.


## Commit Convention

Use short descriptive commit messages.

Examples:

feat: add navigation shell

fix: handle denied camera permission

docs: document development workflow

test: add album model tests

chore: configure GitHub Actions


## Coding Conventions

### Dart / Flutter

- Follow standard Dart formatting.
- Run `dart format .` before submitting a Pull Request.
- Run `flutter analyze`.
- Use meaningful class, method, and variable names.
- Use `PascalCase` for classes.
- Use `camelCase` for variables and methods.
- Avoid very large widgets and functions.

### Python / FastAPI

- Follow PEP 8 naming conventions.
- Use `snake_case` for variables and functions.
- Use `PascalCase` for classes.
- Add type hints where practical.
- Keep API routes and business logic separated as the backend grows.

## Pull Requests

Every Pull Request must:

- target `main`
- correspond to a Sprint task
- pass automated checks
- be reviewed by at least one other team member
- contain no passwords, API keys, or secrets