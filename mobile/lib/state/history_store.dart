import 'package:flutter/foundation.dart';

import '../mock/mock_library.dart';
import '../models/album.dart';
import '../models/history.dart';
import 'auth_controller.dart';

/// In-memory scan and search history of the signed-in user (UC-14).
///
/// Guests have no history: nothing is recorded until they sign in.
class HistoryStore extends ChangeNotifier {
  HistoryStore(this._auth) {
    _auth.addListener(_onAuthChanged);
  }

  final AuthController _auth;
  final Map<String, List<HistoryItem>> _byUser = {};
  int _nextId = 1;

  List<HistoryItem> get _items {
    final key = _auth.user?.email;
    if (key == null) {
      return [];
    }
    return _byUser.putIfAbsent(
      key,
      () => key == AuthController.demoEmail
          ? MockLibrary.demoHistory(DateTime.now(), nextId: _id)
          : [],
    );
  }

  String _id() => 'h${_nextId++}';

  void _onAuthChanged() => notifyListeners();

  /// Newest first.
  List<HistoryItem> get items => List.unmodifiable(_items);

  int get scanCount =>
      _items.where((item) => item.kind == HistoryKind.scan).length;

  void recordScan(Album album) {
    _add(
      HistoryItem(
        id: _id(),
        kind: HistoryKind.scan,
        createdAt: DateTime.now(),
        album: album,
      ),
    );
  }

  void recordSearch(String query, Album album, {bool afterFailedScan = false}) {
    _add(
      HistoryItem(
        id: _id(),
        kind: HistoryKind.search,
        createdAt: DateTime.now(),
        album: album,
        query: query,
        afterFailedScan: afterFailedScan,
      ),
    );
  }

  void remove(String id) {
    _items.removeWhere((item) => item.id == id);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }

  void deleteDataFor(String email) {
    _byUser.remove(email);
    notifyListeners();
  }

  void _add(HistoryItem item) {
    if (_auth.user == null) {
      return;
    }
    _items.insert(0, item);
    notifyListeners();
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }
}
