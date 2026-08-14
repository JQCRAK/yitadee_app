import 'package:cloud_firestore/cloud_firestore.dart';

class AlbumModel {
  final String    id;
  final String    title;
  final String    artistId;
  final String    artistName;
  final String    coverUrl;
  final bool      isPaid;
  final double    price;
  final int       trackCount;
  final DateTime? releaseDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const AlbumModel({
    required this.id,
    required this.title,
    required this.artistId,
    required this.artistName,
    required this.coverUrl,
    required this.isPaid,
    required this.price,
    required this.trackCount,
    this.releaseDate,
    this.createdAt,
    this.updatedAt,
  });

  factory AlbumModel.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AlbumModel(
      id:          doc.id,
      title:       data['title']       ?? '',
      artistId:    data['artistId']    ?? '',
      artistName:  data['artistName']  ?? '',
      coverUrl:    data['coverUrl']    ?? '',
      isPaid:      data['isPaid']      ?? false,
      price:       (data['price']      ?? 0.0).toDouble(),
      trackCount:  (data['trackCount'] ?? 0) as int,
      releaseDate: (data['releaseDate'] as Timestamp?)?.toDate(),
      createdAt:   (data['createdAt']  as Timestamp?)?.toDate(),
      updatedAt:   (data['updatedAt']  as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
    'title':       title,
    'artistId':    artistId,
    'artistName':  artistName,
    'coverUrl':    coverUrl,
    'isPaid':      isPaid,
    'price':       isPaid ? price : 0.0,
    'trackCount':  trackCount,
    'releaseDate': releaseDate != null
        ? Timestamp.fromDate(releaseDate as DateTime)
        : null,
    'createdAt':   FieldValue.serverTimestamp(),
    'updatedAt':   FieldValue.serverTimestamp(),
  };
  String get uploadDateDisplay {
    final date = releaseDate ?? createdAt;
    if (date == null) return '';
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String get releaseDateDisplay {
    if (releaseDate == null) return '';
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[releaseDate!.month - 1]} ${releaseDate!.day}, ${releaseDate!.year}';
  }

  AlbumModel copyWith({
    String?   title,
    String?   artistId,
    String?   artistName,
    String?   coverUrl,
    bool?     isPaid,
    double?   price,
    int?      trackCount,
    DateTime? releaseDate,
  }) => AlbumModel(
    id:          id,
    title:       title       ?? this.title,
    artistId:    artistId    ?? this.artistId,
    artistName:  artistName  ?? this.artistName,
    coverUrl:    coverUrl    ?? this.coverUrl,
    isPaid:      isPaid      ?? this.isPaid,
    price:       price       ?? this.price,
    trackCount:  trackCount  ?? this.trackCount,
    releaseDate: releaseDate ?? this.releaseDate,
    createdAt:   createdAt,
    updatedAt:   updatedAt,
  );
}