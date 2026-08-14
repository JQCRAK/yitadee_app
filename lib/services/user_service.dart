import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'spaces_service.dart';

class UserService {
  UserService._();
  static final UserService instance = UserService._();

  static const _keyUsername        = 'cached_username';
  static const _keyEmail           = 'cached_email';
  static const _keyPhotoPath       = 'cached_photo_path';
  static const _keyPhotoUrl        = 'cached_photo_url';
  static const _keyMemberSince     = 'cached_member_since';
  static const _keyRole            = 'cached_role';
  static const _keyRoleCheckCount  = 'cached_role_check_count';
  static const _keyLoaded          = 'cached_loaded';
  static const _keyFavorites       = 'cached_favorites';

  static const _maxRoleChecks = 3;

  String? _username;
  String? _email;
  String? _photoPath;
  String? _photoUrl;
  String? _memberSince;
  String? _role;
  int     _roleCheckCount = 0;
  List<String> _favorites = [];
  bool    _loaded = false;

  final photoNotifier = ValueNotifier<String>('');

  String       get username       => _username   ?? '';
  String       get email          => _email      ?? '';
  String       get photoPath      => _photoPath  ?? '';
  String       get photoUrl       => _photoUrl   ?? '';
  String       get memberSince    => _memberSince ?? '';
  String       get role           => _role       ?? 'user';
  bool         get isAdmin        => _role == 'admin';
  List<String> get favorites      => List.unmodifiable(_favorites);
  bool         get isLoaded       => _loaded;
  int          get roleCheckCount => _roleCheckCount;

  bool get shouldCheckRoleInFirestore =>
      !isAdmin && _roleCheckCount < _maxRoleChecks;

  String get initial {
    if (_username != null && _username!.isNotEmpty) {
      return _username![0].toUpperCase();
    }
    return '?';
  }

  // ─── Load from SharedPreferences ─────────────────────────────────────────
  Future<void> loadFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    _username       = prefs.getString(_keyUsername);
    _email          = prefs.getString(_keyEmail);
    _photoPath      = prefs.getString(_keyPhotoPath);
    _photoUrl       = prefs.getString(_keyPhotoUrl);
    _memberSince    = prefs.getString(_keyMemberSince);
    _role           = prefs.getString(_keyRole) ?? 'user';
    _roleCheckCount = prefs.getInt(_keyRoleCheckCount) ?? 0;
    _favorites      = prefs.getStringList(_keyFavorites) ?? [];
    _loaded         = prefs.getBool(_keyLoaded) ?? false;

    if (_photoPath != null && _photoPath!.isNotEmpty) {
      if (File(_photoPath!).existsSync()) {
        photoNotifier.value = _photoPath!;
      } else {
        _photoPath = null;
        if (_photoUrl != null && _photoUrl!.isNotEmpty) {
          photoNotifier.value = _photoUrl!;
        }
      }
    }
  }

  // ─── Load from Firestore (full load) ─────────────────────────────────────
  Future<void> loadFromFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!doc.exists) return;

      final data = doc.data()!;
      _username   = data['displayName'] ?? data['username'] ?? user.displayName ?? '';
      _email      = data['email'] ?? user.email ?? '';
      _role       = (data['role'] ?? 'user') as String;

      final createdAt = data['createdAt'] as Timestamp?;
      if (createdAt != null) {
        final date = createdAt.toDate();
        _memberSince = '${_monthName(date.month)} ${date.year}';
      }

      final rawFavorites = data['favorites'];
      if (rawFavorites is List) {
        _favorites = rawFavorites.map((e) => e.toString()).toList();
      }

      final photoUrl = (data['photoUrl'] ?? '') as String;
      if (photoUrl.isNotEmpty && photoUrl != _photoUrl) {
        _photoUrl = photoUrl;
        await _downloadAndCachePhoto(photoUrl);
      }

      if (isAdmin) {
        _roleCheckCount = 0;
      } else {
        _roleCheckCount = (_roleCheckCount + 1).clamp(0, _maxRoleChecks);
      }

      await _saveToPrefs();
    } catch (_) {}
  }

  // ─── Check ONLY the role field in Firestore ───────────────────────────────
  Future<bool> checkRoleFromFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    if (!shouldCheckRoleInFirestore) return false;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!doc.exists) return false;

      final newRole    = (doc.data()?['role'] ?? 'user') as String;
      final roleChanged = newRole != _role;

      _role = newRole;

      if (isAdmin) {
        _roleCheckCount = 0;
      } else {
        _roleCheckCount = (_roleCheckCount + 1).clamp(0, _maxRoleChecks);
      }

      await _saveToPrefs();
      return roleChanged;
    } catch (_) {
      return false;
    }
  }

  // ─── Delete account ───────────────────────────────────────────────────────
  /// Deletes the Firestore document, the profile photo from storage,
  /// clears local cache, and finally deletes the Firebase Auth account.
  /// Returns null on success or an error message string on failure.
  Future<String?> deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'Not logged in.';

    try {
      final result = await InternetAddress.lookup('google.com');
      if (result.isEmpty) return 'No internet connection.';
    } catch (_) {
      return 'No internet connection.';
    }

    try {
      // 1. Delete profile photo from DigitalOcean Spaces (if any)
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (doc.exists) {
          final oldUrl = (doc.data()?['photoUrl'] ?? '') as String;
          if (oldUrl.isNotEmpty) {
            final key = _extractKeyFromUrl(oldUrl);
            if (key != null && key.isNotEmpty) {
              await SpacesService.instance.deleteFile(key);
            }
          }
        }
      } catch (_) {
        // Non-fatal — continue deletion even if photo removal fails
      }

      // 2. Delete Firestore document
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .delete();

      // 3. Clear local cache (photos, prefs)
      await clearCache();

      // 4. Delete Firebase Auth account
      await user.delete();

      return null; // success
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        return 'requires-recent-login';
      }
      return 'Failed to delete account: ${e.message}';
    } catch (e) {
      return 'Failed to delete account: $e';
    }
  }

  // ─── Download remote photo and cache with unique filename ────────────────
  Future<void> _downloadAndCachePhoto(String url) async {
    try {
      final appDir  = await getApplicationDocumentsDirectory();
      await _deleteOldLocalPhotos(appDir.path);

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final localFile = File('${appDir.path}/profile_$timestamp.jpg');

      final client   = HttpClient();
      final request  = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      final bytes    = await response.fold<List<int>>(
        [],
        (prev, chunk) => prev..addAll(chunk),
      );
      await localFile.writeAsBytes(bytes);
      client.close();

      _photoPath = localFile.path;
      _notifyPhoto();
    } catch (_) {
      _photoPath = null;
      photoNotifier.value = url;
    }
  }

  Future<void> _deleteOldLocalPhotos(String dirPath) async {
    try {
      final dir   = Directory(dirPath);
      final files = dir.listSync().whereType<File>().where(
        (f) => f.path.contains('/profile_') && f.path.endsWith('.jpg'),
      );
      for (final f in files) {
        try { await f.delete(); } catch (_) {}
      }
    } catch (_) {}
  }

  void _notifyPhoto() {
    PaintingBinding.instance.imageCache.clear();
    photoNotifier.value = _photoPath ?? '';
  }

  String _monthName(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return months[month - 1];
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (_username    != null) await prefs.setString(_keyUsername,    _username!);
    if (_email       != null) await prefs.setString(_keyEmail,       _email!);
    if (_photoPath   != null) await prefs.setString(_keyPhotoPath,   _photoPath!);
    if (_photoUrl    != null) await prefs.setString(_keyPhotoUrl,    _photoUrl!);
    if (_memberSince != null) await prefs.setString(_keyMemberSince, _memberSince!);
    await prefs.setString(_keyRole,           _role ?? 'user');
    await prefs.setInt   (_keyRoleCheckCount, _roleCheckCount);
    await prefs.setStringList(_keyFavorites,  _favorites);
    _loaded = true;
    await prefs.setBool(_keyLoaded, true);
  }

  // ─── Update username ──────────────────────────────────────────────────────
  Future<String?> updateUsername(String newUsername) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'Not logged in.';

    try {
      final result = await InternetAddress.lookup('google.com');
      if (result.isEmpty) return 'No internet connection.';
    } catch (_) {
      return 'No internet connection.';
    }

    final query = await FirebaseFirestore.instance
        .collection('users')
        .where('username', isEqualTo: newUsername.toLowerCase())
        .limit(1)
        .get();

    if (query.docs.isNotEmpty && query.docs.first.id != user.uid) {
      return 'Username "@$newUsername" is already taken.';
    }

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .update({
      'username':    newUsername.toLowerCase(),
      'displayName': newUsername,
    });

    await user.updateDisplayName(newUsername);
    _username = newUsername;
    await _saveToPrefs();
    return null;
  }

  // ─── Update photo ─────────────────────────────────────────────────────────
  Future<String?> updatePhoto(String filePath) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'Not logged in.';

    try {
      final result = await InternetAddress.lookup('google.com');
      if (result.isEmpty) return 'No internet connection.';
    } catch (_) {
      return 'No internet connection.';
    }

    try {
      final originalBytes = await File(filePath).readAsBytes();
      final decoded       = img.decodeImage(originalBytes);
      if (decoded == null) return 'Could not process image.';

      final img.Image resized;
      if (decoded.width >= decoded.height) {
        resized = img.copyResize(decoded, width: 400);
      } else {
        resized = img.copyResize(decoded, height: 400);
      }
      final compressed = Uint8List.fromList(
        img.encodeJpg(resized, quality: 65),
      );

      final appDir    = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final localFile = File('${appDir.path}/profile_$timestamp.jpg');

      await _deleteOldLocalPhotos(appDir.path);
      await localFile.writeAsBytes(compressed);

      _photoPath = localFile.path;
      _notifyPhoto();
      await _saveToPrefs();

      String? oldKey;
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (doc.exists) {
          final oldUrl = (doc.data()?['photoUrl'] ?? '') as String;
          if (oldUrl.isNotEmpty) {
            oldKey = _extractKeyFromUrl(oldUrl);
          }
        }
      } catch (_) {}

      final newKey = 'profile_photos/${user.uid}_$timestamp.jpg';

      if (oldKey != null && oldKey.isNotEmpty) {
        await SpacesService.instance.deleteFile(oldKey);
      }

      final remoteUrl = await SpacesService.instance.uploadWithKey(
        newKey,
        compressed,
      );

      if (remoteUrl == null) {
        return 'Photo updated on device but failed to upload. Try again later.';
      }

      _photoUrl = remoteUrl;
      await _saveToPrefs();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'photoUrl': remoteUrl});

      return null;
    } catch (e) {
      return 'Failed to update photo: $e';
    }
  }

  String? _extractKeyFromUrl(String url) {
    try {
      if (url.isEmpty) return null;
      final uri  = Uri.parse(url);
      final path = uri.path;
      if (path.startsWith('/')) return path.substring(1);
      return path.isEmpty ? null : path;
    } catch (_) {
      return null;
    }
  }

  // ─── Toggle favorite ──────────────────────────────────────────────────────
  Future<String?> toggleFavorite(String itemId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'Not logged in.';

    final isFav = _favorites.contains(itemId);
    if (isFav) {
      _favorites.remove(itemId);
    } else {
      _favorites.add(itemId);
    }

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'favorites': _favorites});
      await _saveToPrefs();
      return null;
    } catch (e) {
      if (isFav) {
        _favorites.add(itemId);
      } else {
        _favorites.remove(itemId);
      }
      return 'Failed to update favorites.';
    }
  }

  bool isFavorite(String itemId) => _favorites.contains(itemId);

  // ─── Clear cache on sign out ──────────────────────────────────────────────
  Future<void> clearCache() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      await _deleteOldLocalPhotos(appDir.path);
    } catch (_) {}

    _username = _email = _photoPath = _photoUrl = _memberSince = _role = null;
    _roleCheckCount = 0;
    _favorites      = [];
    _loaded         = false;
    photoNotifier.value = '';
    PaintingBinding.instance.imageCache.clear();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUsername);
    await prefs.remove(_keyEmail);
    await prefs.remove(_keyPhotoPath);
    await prefs.remove(_keyPhotoUrl);
    await prefs.remove(_keyMemberSince);
    await prefs.remove(_keyRole);
    await prefs.remove(_keyRoleCheckCount);
    await prefs.remove(_keyFavorites);
    await prefs.remove(_keyLoaded);
  }
}