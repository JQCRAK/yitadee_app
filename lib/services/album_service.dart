import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/album_model.dart';
import 'spaces_service.dart';

class AlbumService {
  AlbumService._();
  static final AlbumService instance = AlbumService._();

  final _col = FirebaseFirestore.instance.collection('albums');

  // ─── Paginated fetch (10 per page) ───────────────────────────────────────
  Future<(List<AlbumModel>, DocumentSnapshot?)> fetchPage({
    DocumentSnapshot? after,
  }) async {
    Query q = _col.orderBy('createdAt', descending: true).limit(10);
    if (after != null) q = q.startAfterDocument(after);
    final snap = await q.get();
    final docs = snap.docs;
    final last = docs.isNotEmpty ? docs.last : null;
    return (docs.map(AlbumModel.fromDoc).toList(), last);
  }

  // ─── Fetch all (used by dropdowns only) ──────────────────────────────────
  Future<List<AlbumModel>> fetchAll() async {
    final snap = await _col.orderBy('title').get();
    return snap.docs.map(AlbumModel.fromDoc).toList();
  }

  Future<AlbumModel?> fetchById(String albumId) async {
    final doc = await _col.doc(albumId).get();
    if (!doc.exists) return null;
    return AlbumModel.fromDoc(doc);
  }

  // ─── Check duplicate title ────────────────────────────────────────────────
  Future<bool> titleExists(String title, {String? excludeId}) async {
    final snap = await _col
        .where('title', isEqualTo: title.trim())
        .limit(2)
        .get();
    if (snap.docs.isEmpty) return false;
    if (excludeId == null) return true;
    return snap.docs.any((d) => d.id != excludeId);
  }

  // ─── Create ───────────────────────────────────────────────────────────────
  Future<(String?, String?)> create({
    required String title,
    required String artistId,
    required String artistName,
    required Uint8List coverBytes,
    required bool isPaid,
    required double price,
    DateTime? releaseDate, // ← NUEVO
  }) async {
    title = title.trim();
    if (title.isEmpty) return (null, 'Album title cannot be empty.');

    if (await titleExists(title)) {
      return (null, 'An album named "$title" already exists.');
    }

    final docRef = _col.doc();
    final albumId = docRef.id;

    final coverKey = 'music/albums/${albumId}_cover.jpg';
    final coverUrl = await SpacesService.instance.uploadWithKey(
      coverKey,
      coverBytes,
    );
    if (coverUrl == null) return (null, 'Failed to upload album cover.');

    final effectivePrice = isPaid ? price : 0.0;

    await docRef.set({
      'title': title,
      'artistId': artistId,
      'artistName': artistName,
      'coverUrl': coverUrl,
      'isPaid': isPaid,
      'price': effectivePrice,
      'trackCount': 0,
      'releaseDate': releaseDate != null
          ? Timestamp.fromDate(releaseDate)
          : null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return (albumId, null);
  }

  // ─── Update metadata ──────────────────────────────────────────────────────
  Future<String?> update({
    required String albumId,
    required String title,
    required String artistId,
    required String artistName,
    required bool isPaid,
    required double price,
    DateTime? releaseDate, // ← NUEVO
  }) async {
    title = title.trim();
    if (title.isEmpty) return 'Album title cannot be empty.';

    if (await titleExists(title, excludeId: albumId)) {
      return 'An album named "$title" already exists.';
    }

    final effectivePrice = isPaid ? price : 0.0;

    await _col.doc(albumId).update({
      'title': title,
      'artistId': artistId,
      'artistName': artistName,
      'isPaid': isPaid,
      'price': effectivePrice,
      'releaseDate': releaseDate != null
          ? Timestamp.fromDate(releaseDate)
          : null,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // If album is paid, ensure all tracks are free (business rule)
    if (isPaid) {
      await _setAllTracksPrice(albumId, free: true);
    }

    return null;
  }

  // ─── Update cover — delete old, upload new ────────────────────────────────
  Future<String?> updateCover(String albumId, Uint8List coverBytes) async {
    final coverKey = 'music/albums/${albumId}_cover.jpg';
    await SpacesService.instance.deleteFile(coverKey);

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final newKey = 'music/albums/${albumId}_cover_$timestamp.jpg';
    final coverUrl = await SpacesService.instance.uploadWithKey(
      newKey,
      coverBytes,
    );
    if (coverUrl == null) return 'Failed to upload new cover.';

    await _col.doc(albumId).update({
      'coverUrl': coverUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return null;
  }

  // ─── Set all tracks in an album to free (when album is paid) ─────────────
  Future<void> _setAllTracksPrice(String albumId, {required bool free}) async {
    final songs = await FirebaseFirestore.instance
        .collection('songs')
        .where('albumId', isEqualTo: albumId)
        .get();

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in songs.docs) {
      batch.update(doc.reference, {
        'isPaid': !free,
        'price': 0.0,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  // ─── Increment / decrement trackCount ────────────────────────────────────
  Future<void> incrementTrackCount(String albumId) async {
    await _col.doc(albumId).update({
      'trackCount': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> decrementTrackCount(String albumId) async {
    await _col.doc(albumId).update({
      'trackCount': FieldValue.increment(-1),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ─── Delete album ─────────────────────────────────────────────────────────
  Future<String?> delete(String albumId) async {
    final songs = await FirebaseFirestore.instance
        .collection('songs')
        .where('albumId', isEqualTo: albumId)
        .limit(1)
        .get();

    if (songs.docs.isNotEmpty) {
      return 'Remove all tracks from this album first.';
    }

    final album = await fetchById(albumId);
    if (album != null && album.coverUrl.isNotEmpty) {
      final uri = Uri.tryParse(album.coverUrl);
      if (uri != null) {
        final key = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
        await SpacesService.instance.deleteFile(key);
      }
    }

    await _col.doc(albumId).delete();
    return null;
  }
}
