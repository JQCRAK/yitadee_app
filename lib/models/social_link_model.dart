import 'package:cloud_firestore/cloud_firestore.dart';

enum SocialPlatform {
  shopify,
  twitch,
  youtube,
  instagram,
  tiktok,
  paypal;

  String get label => switch (this) {
    SocialPlatform.shopify   => 'Shopify',
    SocialPlatform.twitch    => 'Twitch',
    SocialPlatform.youtube   => 'YouTube',
    SocialPlatform.instagram => 'Instagram',
    SocialPlatform.tiktok    => 'TikTok',
    SocialPlatform.paypal    => 'PayPal',
  };

  String get value => name;

  static SocialPlatform fromValue(String v) =>
      SocialPlatform.values.firstWhere(
        (e) => e.value == v,
        orElse: () => SocialPlatform.instagram,
      );
}

class SocialLinkModel {
  const SocialLinkModel({
    required this.id,
    required this.platform,
    required this.url,
  });

  final String         id;
  final SocialPlatform platform;
  final String         url;

  String get displayLabel => platform.label;

  factory SocialLinkModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return SocialLinkModel(
      id:       doc.id,
      platform: SocialPlatform.fromValue(d['platform'] as String? ?? 'instagram'),
      url:      d['url'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'platform': platform.value,
    'url':      url,
  };
}