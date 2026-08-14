import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/artist_model.dart';

class ArtistService {
  ArtistService._();
  static final ArtistService instance = ArtistService._();

  final _col = FirebaseFirestore.instance.collection('artists');

  // ─── Paginated fetch (10 per page) ───────────────────────────────────────
  Future<(List<ArtistModel>, DocumentSnapshot?)> fetchPage({
    DocumentSnapshot? after,
  }) async {
    Query q = _col.orderBy('name').limit(10);
    if (after != null) q = q.startAfterDocument(after);
    final snap = await q.get();
    final docs = snap.docs;
    final last = docs.isNotEmpty ? docs.last : null;
    return (docs.map(ArtistModel.fromDoc).toList(), last);
  }

  // ─── One-time fetch (for dropdowns) ──────────────────────────────────────
  Future<List<ArtistModel>> fetchAll() async {
    final snap = await _col.orderBy('name').get();
    return snap.docs.map(ArtistModel.fromDoc).toList();
  }

  // ─── Fetch default artist ─────────────────────────────────────────────────
  Future<ArtistModel?> fetchDefault() async {
    final snap = await _col.where('isDefault', isEqualTo: true).limit(1).get();
    if (snap.docs.isEmpty) return null;
    return ArtistModel.fromDoc(snap.docs.first);
  }

  // ─── Create ───────────────────────────────────────────────────────────────
  Future<String?> create(String name) async {
    name = name.trim();
    if (name.isEmpty) return 'Artist name cannot be empty.';
    final slug = ArtistModel.toSlug(name);
    final existing = await _col.where('slug', isEqualTo: slug).limit(1).get();
    if (existing.docs.isNotEmpty) {
      return 'An artist named "$name" already exists.';
    }
    await _col.add({'name': name, 'slug': slug, 'isDefault': false});
    return null;
  }

  // ─── Update name ──────────────────────────────────────────────────────────
  Future<String?> updateName(String artistId, String newName) async {
    newName = newName.trim();
    if (newName.isEmpty) return 'Artist name cannot be empty.';
    final slug = ArtistModel.toSlug(newName);
    final existing = await _col.where('slug', isEqualTo: slug).limit(1).get();
    if (existing.docs.isNotEmpty && existing.docs.first.id != artistId) {
      return 'An artist named "$newName" already exists.';
    }
    await _col.doc(artistId).update({'name': newName, 'slug': slug});
    return null;
  }

  // ─── Delete ───────────────────────────────────────────────────────────────
  Future<String?> delete(String artistId) async {
    final songs = await FirebaseFirestore.instance
        .collection('songs')
        .where('artistId', isEqualTo: artistId)
        .limit(1)
        .get();
    if (songs.docs.isNotEmpty) {
      return 'Cannot delete: this artist has songs. Reassign or delete those songs first.';
    }
    await _col.doc(artistId).delete();
    return null;
  }

  // ─── Seed default artist if collection is empty ───────────────────────────
  Future<void> seedDefaultIfNeeded() async {
    final snap = await _col.limit(1).get();
    if (snap.docs.isNotEmpty) return;
    await _col.add({
      'name':      'DropTop Quan',
      'slug':      'droptop-quan',
      'isDefault': true,
    });
  }
}