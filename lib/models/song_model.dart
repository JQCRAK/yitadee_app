import 'package:cloud_firestore/cloud_firestore.dart';

enum SongGenre {
  autotuneRap('Autotune Rap', 'autotune_rap'),
  pluggnb('PluggnB', 'pluggnb'),
  hipHop('Hip Hop', 'hip_hop'),
  rnb('R&B', 'rnb'),
  other('Other', 'other');

  const SongGenre(this.label, this.value);
  final String label;
  final String value;

  static SongGenre fromValue(String value) => SongGenre.values.firstWhere(
    (g) => g.value == value,
    orElse: () => SongGenre.other,
  );
}

enum SongType { single, albumTrack }

class SongModel {
  final String id;
  final String title;
  final String artistId;
  final String artistName;
  final String featuring;
  final String genre;
  final String customGenre;
  final String audioUrl;
  final String coverUrl;
  final int duration;
  final SongType type;
  final String albumId;
  final String albumTitle;
  final int trackNumber;
  final int trackOrder; // ← NUEVO: orden manual dentro del álbum
  final bool isPaid;
  final double price;
  final String lyrics;
  final int plays;
  final DateTime? releaseDate; // ← NUEVO
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const SongModel({
    required this.id,
    required this.title,
    required this.artistId,
    required this.artistName,
    required this.featuring,
    required this.genre,
    required this.customGenre,
    required this.audioUrl,
    required this.coverUrl,
    required this.duration,
    required this.type,
    required this.albumId,
    required this.albumTitle,
    required this.trackNumber,
    required this.isPaid,
    required this.price,
    required this.lyrics,
    required this.plays,
    this.trackOrder = 0,
    this.releaseDate,
    this.createdAt,
    this.updatedAt,
  });

  factory SongModel.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SongModel(
      id: doc.id,
      title: data['title'] ?? '',
      artistId: data['artistId'] ?? '',
      artistName: data['artistName'] ?? '',
      featuring: data['featuring'] ?? '',
      genre: data['genre'] ?? '',
      customGenre: data['customGenre'] ?? '',
      audioUrl: data['audioUrl'] ?? '',
      coverUrl: data['coverUrl'] ?? '',
      duration: (data['duration'] ?? 0) as int,
      type: data['type'] == 'album_track'
          ? SongType.albumTrack
          : SongType.single,
      albumId: data['albumId'] ?? '',
      albumTitle: data['albumTitle'] ?? '',
      trackNumber: (data['trackNumber'] ?? 0) as int,
      trackOrder: (data['trackOrder'] ?? 0) as int,
      isPaid: data['isPaid'] ?? false,
      price: (data['price'] ?? 0.0).toDouble(),
      lyrics: data['lyrics'] ?? '',
      plays: (data['plays'] ?? 0) as int,
      releaseDate: (data['releaseDate'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
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
    'albumId': albumId,
    'albumTitle': albumTitle,
    'trackNumber': trackNumber,
    'trackOrder': trackOrder,
    'isPaid': isPaid,
    'price': isPaid ? price : 0.0,
    'lyrics': lyrics,
    'plays': plays,
    'releaseDate': releaseDate != null
        ? Timestamp.fromDate(releaseDate as DateTime)
        : null,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  String get genreDisplay {
    if (genre == 'other' && customGenre.isNotEmpty) return customGenre;
    return SongGenre.fromValue(genre).label;
  }

  String get durationDisplay {
    if (duration <= 0) return '--:--';
    final m = duration ~/ 60;
    final s = duration % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get uploadDateDisplay {
    final date = releaseDate ?? createdAt;
    if (date == null) return '';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String get releaseDateDisplay {
    if (releaseDate == null) return '';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[releaseDate!.month - 1]} ${releaseDate!.day}, ${releaseDate!.year}';
  }

  bool get isSingle => type == SongType.single;
  bool get isAlbumTrack => type == SongType.albumTrack;
}
