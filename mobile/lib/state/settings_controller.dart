import 'package:flutter/foundation.dart';

import '../models/album.dart';

/// User preferences from the Settings screen. In memory for now.
class SettingsController extends ChangeNotifier {
  SettingsController({
    this._autoplayTopTrack = true,
    MediaFormat defaultFormat = MediaFormat.vinyl,
  }) : _defaultFormat = defaultFormat;

  bool _autoplayTopTrack;
  MediaFormat _defaultFormat;

  /// Start the most popular preview as soon as an album is recognised.
  bool get autoplayTopTrack => _autoplayTopTrack;

  set autoplayTopTrack(bool value) {
    if (_autoplayTopTrack == value) {
      return;
    }
    _autoplayTopTrack = value;
    notifyListeners();
  }

  /// Format preselected when saving an album to a collection.
  MediaFormat get defaultFormat => _defaultFormat;

  set defaultFormat(MediaFormat value) {
    if (_defaultFormat == value) {
      return;
    }
    _defaultFormat = value;
    notifyListeners();
  }
}
