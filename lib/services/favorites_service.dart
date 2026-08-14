import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class FavoritesService extends ChangeNotifier {
  FavoritesService._();
  static final FavoritesService instance = FavoritesService._();

  final _firestore = FirebaseFirestore.instance;
  Set<String> _favorites = {};
  bool _loaded = false;

  Set<String> get favorites => _favorites;
  bool get isLoaded => _loaded;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  bool isFavorite(String songId) => _favorites.contains(songId);

  Future<void> loadFavorites() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (!doc.exists) return;
      final data = doc.data();
      final raw = data?['favorites'] as List<dynamic>? ?? [];
      _favorites = raw.map((e) => e.toString()).toSet();
      _loaded = true;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> toggleFavorite(String songId) async {
    final uid = _uid;
    if (uid == null) return;

    final wasAdded = _favorites.contains(songId);

    if (wasAdded) {
      _favorites.remove(songId);
    } else {
      _favorites.add(songId);
    }
    notifyListeners();

    try {
      await _firestore.collection('users').doc(uid).update({
        'favorites': wasAdded
            ? FieldValue.arrayRemove([songId])
            : FieldValue.arrayUnion([songId]),
      });
    } catch (_) {
      if (wasAdded) {
        _favorites.add(songId);
      } else {
        _favorites.remove(songId);
      }
      notifyListeners();
    }
  }

  void clear() {
    _favorites = {};
    _loaded = false;
    notifyListeners();
  }
}