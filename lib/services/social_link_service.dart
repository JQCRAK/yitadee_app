import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/social_link_model.dart';

class SocialLinkService {
  SocialLinkService._();
  static final SocialLinkService instance = SocialLinkService._();

  final _col = FirebaseFirestore.instance.collection('social_links');

  // Fetch all (max 6 docs — one per platform)
  Future<List<SocialLinkModel>> fetchAll() async {
    final snap = await _col.orderBy('platform').get();
    return snap.docs.map(SocialLinkModel.fromDoc).toList();
  }

  // Create — each platform can only have ONE url
  Future<String?> create({
    required SocialPlatform platform,
    required String         url,
  }) async {
    url = url.trim();
    if (url.isEmpty) return 'URL cannot be empty.';
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return 'URL must start with https://';
    }
    final existing = await _col
        .where('platform', isEqualTo: platform.value)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) {
      return '${platform.label} already exists. Edit the existing one.';
    }
    await _col.add({'platform': platform.value, 'url': url});
    return null;
  }

  // Update
  Future<String?> update({
    required String         id,
    required SocialPlatform platform,
    required String         url,
  }) async {
    url = url.trim();
    if (url.isEmpty) return 'URL cannot be empty.';
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return 'URL must start with https://';
    }
    await _col.doc(id).update({'platform': platform.value, 'url': url});
    return null;
  }

  // Delete
  Future<void> delete(String id) async {
    await _col.doc(id).delete();
  }
}