# App shell and user interface

This change implements the S1-07 wireframes (revision 4) as a working Flutter
UI. The sources for the wireframes are on the `docs/S1-07-wireframes` branch.
Recognition, catalogue search, accounts, lists and previews are mocked, so you
can go through every screen in the app. The navigation follows
`docs/Navigational_Diagram.drawio`.

## Scrum tasks covered

| Task | Where |
| --- | --- |
| Set up routing | `lib/routing/app_routes.dart` (named routes), `lib/routing/app_navigation.dart` (typed helpers) |
| Navigation bar | `lib/widgets/taskbars.dart`, `lib/screens/shell/app_shell.dart` |
| Placeholder screens | Every wireframe screen is implemented. Data comes from mocks (see below). |
| Album result screen | `lib/screens/scan/result_card.dart` (10a–c), `lib/screens/album/album_details_screen.dart` (11) |
| Base theme from wireframes | `lib/theme/app_theme.dart` |
| Mock auth state | `lib/state/auth_controller.dart` |
| Navigation widget tests | `test/navigation/navigation_test.dart`, `test/screens/` |

## Navigation

- The app opens on the **Scan** tab (camera page). The shell keeps three tabs
  alive: Scan, Library and Profile.
- Scan pages use the **History / Scan / Search** taskbar. Every other page uses
  **Profile / Scan / Library**, as in the wireframes.
- Pages pushed on top (album details, list detail, manual search) show the
  taskbar too. Tapping a tab closes them and switches tabs.
- The system back button returns to the Scan tab before it leaves the app.
- Guests can scan, search and play previews. Saving, lists and history open
  the sign-in prompt (13), as required by UC-01.

## Screens

| Wireframe | Implementation |
| --- | --- |
| 01, 02b, 03 | `screens/scan/scan_screen.dart`. 02a is the Android permission dialog. 03 is the system photo picker. |
| 04, 05, 06, 07 | `screens/scan/scan_flow_screen.dart` |
| 08a, 08b | `screens/search/manual_search_screen.dart` |
| 10a, 10b, 10c | `screens/scan/result_card.dart` |
| 11 | `screens/album/album_details_screen.dart` |
| 12 | `screens/album/save_album_sheet.dart` |
| 13 | `widgets/sign_in_prompt.dart` |
| 14 | `screens/history/history_sheet.dart` |
| 15a, 15b, 15c | `screens/library/library_screen.dart` |
| 16a, 16b, 20 | `screens/library/list_detail_screen.dart` |
| 17 | `screens/library/filter_sort_sheet.dart` |
| 18, 18b | `screens/library/entry_sheets.dart` |
| 19a, 19b | `screens/library/list_dialogs.dart` |
| 21a, 21b | `screens/profile/profile_screen.dart` |
| 22 | `screens/auth/login_screen.dart` |
| 23a, 23b | `screens/settings/settings_screen.dart` |

## What is mocked, and how to replace it

Every service and store is created in `lib/app_scope.dart` (`AppDependencies`).
Screens only talk to these classes, so a real implementation can replace a mock
without changing the UI.

| Mock | Replace with |
| --- | --- |
| `MockRecognitionService` returns, in turn: match, several candidates, not recognised, too blurry. This lets you reach every scan screen. | Visual search (S1-05 follow-up) |
| `MockCatalogService` searches `lib/mock/mock_catalog.dart` | The Discogs client from S1-05, through the backend |
| `AuthController` keeps accounts in memory. Demo account: `demo@jamscan.app` / `jamscan123` | Real authentication |
| `LibraryStore`, `HistoryStore` keep data in memory per account | The drift `ListDao` and a history DAO (S1-06) |
| `PreviewPlayer` simulates 30 s of playback with a timer | An audio package such as just_audio |

The mock album data is illustrative sample data, not a Discogs export.

## Not possible yet without new packages

The lockfile is enforced in CI, so this change adds no dependencies.

- **Live camera preview.** The viewfinder is a placeholder. The shutter opens
  the system camera through the existing `CameraCaptureService` (S1-03).
  Adding the `camera` package would make the feed live.
- **Audio.** Previews are simulated (see `PreviewPlayer`).
- **Cover images.** Covers are neutral placeholders until Discogs images are
  fetched.

## Data model gaps found while building the UI

The wireframes need fields the drift tables (DATA_MODEL.md) do not have yet:

- `ListEntries`: a ghost flag (`is_ghost`) and a "looking for" note
- `Albums`: label, catalogue number, country, genres and styles, community
  rating and rating count
- `Tracks`: duration and printed position (`A1`, `B2`)

## Relationship to S1-03 and S1-04

`lib/services/gallery_import_service.dart` is byte-identical to the file on
`feature/S1-04-gallery-import`, so both branches merge cleanly. The Scan tab
now replaces the S1-03 welcome screen as the home page.
`lib/screens/camera_capture_screen.dart` and its test are untouched. Delete
them once S1-04 is merged.

## Checks

```bash
cd mobile
dart format lib test
flutter analyze
flutter test
```
