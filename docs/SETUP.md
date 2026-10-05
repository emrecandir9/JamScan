# Local development setup

## Tools

| Tool | Version / purpose |
| --- | --- |
| Git | Clone, branches, commits, and pushes |
| Flutter | **3.47.5 stable**, including Dart 3.13.4 |
| Android Studio | Android SDK, command-line tools, and emulator |
| Java | **JDK 17**, used by the Android build |
| Python | **3.12**, used by the backend and CI |
| Docker | Optional locally; CI checks the backend container |

Install Flutter from the [official SDK archive](https://docs.flutter.dev/install/archive)
and add its `bin` directory to your PATH. Follow the
[Android setup guide](https://docs.flutter.dev/platform-integration/android/setup)
to install the SDK/platform/build tools requested by `flutter doctor -v`.
Use an Android emulator or a physical Android device to run the app.

```bash
flutter --version
flutter doctor -v
flutter doctor --android-licenses
```

Read any SDK license prompts yourself. Missing iOS/Xcode or Chrome support
does not block this Android-only project. If Flutter selects an incompatible
Java installation, point it to JDK 17 with `flutter config --jdk-dir=PATH_TO_JDK_17`.

## Mobile

From the repository root:

```bash
cd mobile
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build apk --debug
```

The APK is written to `mobile/build/app/outputs/flutter-apk/app-debug.apk`.
This is a development build, not a Play Store release. No emulator is required
to build the APK or run the widget test.

To run it, start an Android emulator from Android Studio or connect a device
with USB debugging enabled:

```bash
flutter devices
flutter run -d DEVICE_ID
```

Replace `DEVICE_ID` with an Android device ID from `flutter devices`. The
app should show **JamSCAN** and **Welcome to JamSCAN**. It does not call the
backend yet; mobile and backend can be checked independently.

## Run an existing APK on a Mac

An APK runs on Android, so use Android Studio's emulator to test it on macOS.
You do not need to rebuild the project or start the backend for this welcome screen.

1. Open Android Studio and select **More Actions → Virtual Device Manager**,
   or **Tools → Device Manager** with a project open.
2. Create a virtual phone, select a compatible Android system image
   (`arm64-v8a` on Apple Silicon), download it if necessary, and finish setup.
3. Start the emulator and wait for its Android home screen.
4. For a local build, drag `mobile/build/app/outputs/flutter-apk/app-debug.apk`
   onto the emulator screen. For a GitHub Actions artifact, download and unzip
   `jamscan-debug-apk`, then drag the `app-debug.apk` from the extracted folder
   onto the emulator. Downloading an artifact does not create the local build path.
5. Open **JamSCAN** in the emulator's app list. Confirm the title **JamSCAN**
   and message **Welcome to JamSCAN** appear.

Emre completed this installation and launch check for S1-01. See the
[acceptance evidence](S1-01.md). Screens beyond this welcome page are future work.

## Backend

From the repository root, on macOS/Linux:

```bash
cd backend
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements-dev.lock
python -m pip install --no-deps -e .
python -m uvicorn app.main:app --reload
```

On Windows PowerShell, use `py -3.12 -m venv .venv` and activate with
`.\.venv\Scripts\Activate.ps1`; the remaining Python commands are the same.
If activation is unavailable, call `.venv\Scripts\python.exe` directly.

Open <http://127.0.0.1:8000/health> to see `{"status":"ok"}`, or
<http://127.0.0.1:8000/docs> for interactive API documentation. Stop with Ctrl+C.
No external API keys or database are required for S1-01.

With the virtual environment active, from `backend/`:

```bash
ruff format --check .
ruff check .
python -m pytest
python -m pip check
python -m build
```

The health test checks the real HTTP route through FastAPI's test client.
External API validation tests use mocked HTTP and need no credentials.
The package build writes a wheel and source archive under `backend/dist/`.

## External API validation

S1-05 adds source-checkout development scripts for Discogs and iTunes HTTPS
previews. They are separate from FastAPI routes and do not run automatically
in CI. Follow [S1-05](S1-05.md#how-to-tell-it-works) to load your local
`backend/.env`, run `python -m scripts.validate_apis`, and interpret the five
checks. Never commit `.env` or copy its token into the mobile application.

## Optional backend container

From the repository root, with Docker running:

```bash
docker build -t jamscan-backend ./backend
docker run --rm -p 127.0.0.1:8000:8000 jamscan-backend
```

Open the same `/health` and `/docs` URLs. Use either the local Python server
or the container at a time because both examples use port 8000.

## Updating dependencies

For mobile changes, update `mobile/pubspec.yaml`, run `flutter pub get`, and
commit both `pubspec.yaml` and `pubspec.lock`. The exact Flutter version in
`pubspec.yaml` is also read by CI; coordinate SDK changes with the team.

For backend changes, edit `backend/pyproject.toml`, then run from `backend/`
using Python 3.12 and the virtual environment:

```bash
python -m pip install 'pip-tools>=7,<8'
python -m piptools compile --strip-extras --output-file=requirements.lock pyproject.toml
python -m piptools compile --strip-extras --extra=dev --output-file=requirements-dev.lock pyproject.toml
python -m pip install -r requirements-dev.lock
python -m pip install --no-deps -e .
python -m pip check
```

Commit both lock files along with `pyproject.toml` and rerun checks. Runtime
dependencies go in `requirements.lock`; the dev lock also includes test,
lint, and packaging tools. The container uses only the runtime lock.

## GitHub Actions

`.github/workflows/ci.yml` runs on task-branch pushes and PRs into `main`.
Both jobs always run, including for documentation changes, so required checks
are not left waiting because of a path filter.

- **Mobile checks:** dependency lock, formatting, analysis, widget test, APK.
- **Backend checks:** dependency consistency, formatting, lint, API test,
  Python package build, Docker build, and container health check.

In a successful Actions run, download **jamscan-debug-apk** under Artifacts.
GitHub retains it for seven days. Generated output and local SDK paths are
ignored by Git; do not upload them as source files.
