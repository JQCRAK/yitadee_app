import 'package:cloud_firestore/cloud_firestore.dart';

class MerchBannerService {
  MerchBannerService._();
  static final MerchBannerService instance = MerchBannerService._();

  /// Returns the Shopify URL string, or null if not set.
  Future<String?> fetchShopifyUrl() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('social_links')
          .where('platform', isEqualTo: 'shopify')
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      final url = snap.docs.first.data()['url'] as String?;
      return (url != null && url.trim().isNotEmpty) ? url.trim() : null;
    } catch (_) {
      return null;
    }
  }
}