import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/song_model.dart';
import 'album_service.dart';
import 'spaces_service.dart';

class SongService {
  SongService._();
  static final SongService instance = SongService._();

  final _col = FirebaseFirestore.instance.collection('songs');

  // ─── Paginated singles (no album) ────────────────────────────────────────
  Future<(List<SongModel>, DocumentSnapshot?)> fetchSinglesPage({
    DocumentSnapshot? after,
  }) async {
    Query q = _col
        .where('type', isEqualTo: 'single')
        .orderBy('createdAt', descending: true)
        .limit(10);
    if (after != null) q = q.startAfterDocument(after);
    final snap = await q.get();
    final docs = snap.docs;
    final last = docs.isNotEmpty ? docs.last : null;
    return (docs.map(SongModel.fromDoc).toList(), last);
  }

  // ─── Album tracks ─────────────────────────────────────────────────────────
  Future<List<SongModel>> fetchAlbumTracks(String albumId) async {
    final snap = await _col
        .where('albumId', isEqualTo: albumId)
        .orderBy('trackNumber')
        .get();
    final tracks = snap.docs.map(SongModel.fromDoc).toList();
    // Ordenar por trackOrder si existe, sino usar trackNumber
    tracks.sort((a, b) {
      final aOrder = a.trackOrder > 0 ? a.trackOrder : a.trackNumber;
      final bOrder = b.trackOrder > 0 ? b.trackOrder : b.trackNumber;
      return aOrder.compareTo(bOrder);
    });
    return tracks;
  }

  // ─── Reorder album tracks (batch) ────────────────────────────────────────────
  Future<String?> reorderAlbumTracks(List<SongModel> tracks) async {
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (int i = 0; i < tracks.length; i++) {
        batch.update(_col.doc(tracks[i].id), {
          'trackOrder': i,
          'trackNumber': i + 1,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      return null;
    } catch (e) {
      return 'Failed to reorder tracks: $e';
    }
  }

  // ─── Check duplicate title ────────────────────────────────────────────────
  Future<bool> titleExists(String title, {String? excludeId}) async {
    final snap = await _col
        .where('title', isEqualTo: title.trim().toLowerCase())
        .limit(2)
        .get();
    if (snap.docs.isEmpty) return false;
    if (excludeId == null) return true;
    return snap.docs.any((d) => d.id != excludeId);
  }

  // ─── Increment plays ──────────────────────────────────────────────────────
  Future<void> incrementPlays(String songId) async {
    await _col.doc(songId).update({
      'plays': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ─── Upload song ──────────────────────────────────────────────────────────
  Future<String?> uploadSong({
    required String title,
    required String artistId,
    required String artistName,
    required String featuring,
    required String genre,
    required String customGenre,
    required String lyrics,
    required Uint8List coverBytes,
    required Uint8List audioBytes,
    required String audioExtension,
    required bool isPaid,
    required double price,
    required int duration,
    required SongType type,
    String? albumId,
    String? albumTitle,
    bool? albumIsPaid,
    int trackNumber = 0,
    int trackOrder = 0, // ← NUEVO
    DateTime? releaseDate, // ← NUEVO
    void Function(double)? onProgress,
  }) async {
    title = title.trim();
    if (title.isEmpty) return 'Song title cannot be empty.';

    if (await titleExists(title)) {
      return 'A song named "$title" already exists.';
    }

    bool effectiveIsPaid = isPaid;
    double effectivePrice = isPaid ? price : 0.0;
    if (albumIsPaid == true) {
      effectiveIsPaid = false;
      effectivePrice = 0.0;
    }

    final docRef = _col.doc();
    final songId = docRef.id;

    onProgress?.call(0.0);

    String coverUrl = '';
    if (coverBytes.isNotEmpty) {
      final coverKey = 'music/covers/$songId.jpg';
      final uploaded = await SpacesService.instance.uploadWithKey(
        coverKey,
        coverBytes,
      );
      if (uploaded == null) return 'Failed to upload song cover.';
      coverUrl = uploaded;
    }

    onProgress?.call(0.5);

    final audioKey = 'music/tracks/$songId.$audioExtension';
    final audioMimeType = audioExtension == 'wav' ? 'audio/wav' : 'audio/mpeg';
    final audioUrl = await SpacesService.instance.uploadWithKey(
      audioKey,
      audioBytes,
      contentType: audioMimeType,
    );
    if (audioUrl == null) return 'Failed to upload audio file.';

    onProgress?.call(0.9);

    await docRef.set({
      'title': title,
      'artistId': artistId,
      'artistName': artistName,
      'featuring': featuring,
      'genre': genre,
      'customGenre': customGenre,
      'audioUrl': audioUrl,
      'coverUrl': coverUrl,
      'duration': duration,
      'type': type == SongType.albumTrack ? 'album_track' : 'single',
      'albumId': albumId ?? '',
      'albumTitle': albumTitle ?? '',
      'trackNumber': trackNumber,
      'trackOrder': trackOrder, // ← NUEVO
      'isPaid': effectiveIsPaid,
      'price': effectivePrice,
      'lyrics': lyrics,
      'plays': 0,
      'releaseDate':
          releaseDate !=
              null // ← NUEVO
          ? Timestamp.fromDate(releaseDate)
          : null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (type == SongType.albumTrack && albumId != null) {
      await AlbumService.instance.incrementTrackCount(albumId);
    }

    onProgress?.call(1.0);
    return null;
  }

  // ─── Update cover image ───────────────────────────────────────────────────
  Future<String?> updateCover({
    required String songId,
    required String oldCoverUrl,
    required Uint8List coverBytes,
  }) async {
    if (coverBytes.isEmpty) return 'Cover image is empty.';

    if (oldCoverUrl.isNotEmpty) {
      final uri = Uri.tryParse(oldCoverUrl);
      if (uri != null) {
        final key = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
        await SpacesService.instance.deleteFile(key);
      }
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final newKey = 'music/covers/${songId}_$timestamp.jpg';
    final newUrl = await SpacesService.instance.uploadWithKey(
      newKey,
      coverBytes,
    );
    if (newUrl == null) return 'Failed to upload new cover.';

    await _col.doc(songId).update({
      'coverUrl': newUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return null;
  }

  // ─── Update audio file ────────────────────────────────────────────────────
  Future<String?> updateAudio({
    required String songId,
    required String audioUrl,
    required Uint8List audioBytes,
    required String audioExtension,
    required int duration,
  }) async {
    if (audioBytes.isEmpty) return 'Audio file is empty.';

    final uri = Uri.tryParse(audioUrl);
    if (uri != null) {
      final key = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
      await SpacesService.instance.deleteFile(key);
    }

    final newKey = 'music/tracks/$songId.$audioExtension';
    final audioMimeType = audioExtension == 'wav' ? 'audio/wav' : 'audio/mpeg';
    final newUrl = await SpacesService.instance.uploadWithKey(
      newKey,
      audioBytes,
      contentType: audioMimeType,
    );
    if (newUrl == null) return 'Failed to upload new audio file.';

    await _col.doc(songId).update({
      'audioUrl': newUrl,
      'duration': duration,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return null;
  }

  // ─── Update song metadata ─────────────────────────────────────────────────
  Future<String?> updateMeta({
    required String songId,
    required String title,
    required String artistId,
    required String artistName,
    required String featuring,
    required String genre,
    required String customGenre,
    required String lyrics,
    required bool isPaid,
    required double price,
    String? albumIsPaidCheck,
    DateTime? releaseDate, // ← NUEVO
    int? trackOrder, // ← NUEVO
  }) async {
    title = title.trim();
    if (title.isEmpty) return 'Song title cannot be empty.';

    if (await titleExists(title, excludeId: songId)) {
      return 'A song named "$title" already exists.';
    }

    bool effectiveIsPaid = isPaid;
    double effectivePrice = isPaid ? price : 0.0;
    if (albumIsPaidCheck != null && albumIsPaidCheck.isNotEmpty) {
      final album = await AlbumService.instance.fetchById(albumIsPaidCheck);
      if (album != null && album.isPaid) {
        effectiveIsPaid = false;
        effectivePrice = 0.0;
      }
    }

    await _col.doc(songId).update({
      'title': title,
      'artistId': artistId,
      'artistName': artistName,
      'featuring': featuring,
      'genre': genre,
      'customGenre': customGenre,
      'lyrics': lyrics,
      'isPaid': effectiveIsPaid,
      'price': effectivePrice,
      'releaseDate':
          releaseDate !=
              null // ← NUEVO
          ? Timestamp.fromDate(releaseDate)
          : null,
      if (trackOrder != null) 'trackOrder': trackOrder, // ← NUEVO
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return null;
  }

  // ─── Move single → album ──────────────────────────────────────────────────
  Future<String?> moveToAlbum({
    required String songId,
    required String albumId,
    required String albumTitle,
    required bool albumIsPaid,
    required int trackNumber,
  }) async {
    final bool songIsPaid = !albumIsPaid;
    final double songPrice = albumIsPaid ? 0.0 : 0.0;

    await _col.doc(songId).update({
      'type': 'album_track',
      'albumId': albumId,
      'albumTitle': albumTitle,
      'trackNumber': trackNumber,
      'trackOrder': trackNumber, // ← usa trackNumber como orden inicial
      'isPaid': songIsPaid,
      'price': songPrice,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await AlbumService.instance.incrementTrackCount(albumId);
    return null;
  }

  // ─── Remove track from album → becomes single ─────────────────────────────
  Future<String?> removeFromAlbum(String songId, String albumId) async {
    await _col.doc(songId).update({
      'type': 'single',
      'albumId': '',
      'albumTitle': '',
      'trackNumber': 0,
      'trackOrder': 0,
      'isPaid': false,
      'price': 0.0,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await AlbumService.instance.decrementTrackCount(albumId);
    return null;
  }

  // ─── Delete song ──────────────────────────────────────────────────────────
  Future<String?> delete(SongModel song) async {
    if (song.coverUrl.isNotEmpty) {
      final uri = Uri.tryParse(song.coverUrl);
      if (uri != null) {
        final key = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
        await SpacesService.instance.deleteFile(key);
      }
    }

    if (song.audioUrl.isNotEmpty) {
      final uri = Uri.tryParse(song.audioUrl);
      if (uri != null) {
        final key = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
        await SpacesService.instance.deleteFile(key);
      }
    }

    if (song.isAlbumTrack && song.albumId.isNotEmpty) {
      await AlbumService.instance.decrementTrackCount(song.albumId);
    }

    await _col.doc(song.id).delete();
    return null;
  }
}
