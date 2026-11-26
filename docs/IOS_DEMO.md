# Running JamSCAN on an iPhone (demo only)

JamSCAN targets Android. The `mobile/ios/` project exists so the app can be
shown on an iPhone or the iOS Simulator. It is not set up for the App Store
or TestFlight, and CI does not build it.

## Requirements

- A Mac with the full Xcode app from the App Store (the command-line tools
  alone are not enough). After installing it, run:

  ```bash
  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
  ```

  ```bash
  sudo xcodebuild -runFirstLaunch
  ```

- In Xcode, Settings > Components: install the iOS platform.
- `flutter doctor` should show a tick next to Xcode. CocoaPods is not needed:
  every plugin the app uses builds through Swift Package Manager.

## iOS Simulator

The simulator reaches the Mac at `localhost`. Start the backend as described
in [SETUP.md](SETUP.md), then from `mobile/`:

```bash
open -a Simulator
```

```bash
flutter run -d iPhone --dart-define=JAMSCAN_API_URL=http://localhost:8000
```

The simulator has no camera, so live scanning shows as unavailable. To
scan a cover, drag a photo onto the simulator window to add it to Photos,
then import it in the app.

## Real iPhone (free Apple ID)

1. Open `mobile/ios/Runner.xcworkspace` in Xcode. Under Runner > Signing &
   Capabilities, set Team to your Personal Team. If Xcode says the bundle
   identifier is taken, change `com.jamscan.jamscan` to something unique to
   you (for example `com.<yourname>.jamscan`) and do not commit that change.
2. Connect the iPhone with a cable. On the phone, turn on Settings > Privacy &
   Security > Developer Mode and restart when asked.
3. Start the backend so the phone can reach it over Wi-Fi:

   ```bash
   python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
   ```

4. From `mobile/`, run the app with the Mac's Wi-Fi address
   (`ipconfig getifaddr en0`). Use `--release`: on iOS a debug build only
   starts while `flutter run` is attached, so its home-screen icon does not
   open it.

   ```bash
   flutter run --release -d <iPhone name> --dart-define=JAMSCAN_API_URL=http://<mac-ip>:8000
   ```

   If Flutter reports that it cannot find `build/ios/iphoneos/Runner.app`,
   the build still succeeded; install the copy Xcode wrote instead:

   ```bash
   xcrun devicectl device install app --device <iPhone name> build/ios/Release-iphoneos/Runner.app
   ```

5. The first time, iOS blocks the app until you trust the developer: Settings
   > General > VPN & Device Management > your Apple ID > Trust.
6. Allow camera and local network access when the app asks.

With a free Apple ID the installed app stops opening after 7 days; run
step 4 again to reinstall it. The backend address is built into the app, so
reinstall it too when the Mac's Wi-Fi address changes.

Start the app with `flutter run`, not Xcode's Run button. `permission_handler`
finds `ios/Runner/Info.plist` from the working directory to decide which
permissions to compile in; a build started from Xcode cannot find it, and
every permission request then returns "denied".

## Differences from Android

- Live scanning assumes the phone is held upright (portrait).
- iOS camera frames use video-range YUV, so the live analysis sees slightly
  lower contrast than on Android. Recognition has not been measured on iOS.
