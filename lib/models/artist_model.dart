import 'package:cloud_firestore/cloud_firestore.dart';

class ArtistModel {
  final String id;
  final String name;
  final String slug;       // lowercase, used for search deduplication
  final bool   isDefault;  // true only for "DropTop Quan"

  const ArtistModel({
    required this.id,
    required this.name,
    required this.slug,
    this.isDefault = false,
  });

  factory ArtistModel.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ArtistModel(
      id:        doc.id,
      name:      data['name']      ?? '',
      slug:      data['slug']      ?? '',
      isDefault: data['isDefault'] ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'name':      name,
    'slug':      slug,
    'isDefault': isDefault,
  };

  static String toSlug(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');
}