import 'package:flutter/foundation.dart';

import '../models/album.dart';

/// The three top-level tabs of the app.
enum AppTab { scan, library, profile }

/// Selected tab, plus a result waiting to be shown on the Scan tab.
class ShellController extends ChangeNotifier {
  AppTab _tab = AppTab.scan;
  Album? _pendingResult;

  AppTab get tab => _tab;

  set tab(AppTab value) {
    if (_tab == value) {
      return;
    }
    _tab = value;
    notifyListeners();
  }

  /// Switches to the Scan tab and asks it to show [album] as a result,
  /// for example when a past scan is opened from the profile.
  void showResult(Album album) {
    _pendingResult = album;
    _tab = AppTab.scan;
    notifyListeners();
  }

  /// Returns the pending result once, then clears it.
  Album? takePendingResult() {
    final album = _pendingResult;
    _pendingResult = null;
    return album;
  }
}
