import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

// ─── Locker Entry ─────────────────────────────────────────────────────────────
// Stored in Firestore under users/{uid}/locker as a list of maps
class LockerEntry {
  final String contentId;   // album or song Firestore ID
  final String contentType; // 'album' | 'single'
  final String productId;   // store product id
  final String purchaseToken;
  final DateTime purchasedAt;

  const LockerEntry({
    required this.contentId,
    required this.contentType,
    required this.productId,
    required this.purchaseToken,
    required this.purchasedAt,
  });

  Map<String, dynamic> toMap() => {
    'contentId':     contentId,
    'contentType':   contentType,
    'productId':     productId,
    'purchaseToken': purchaseToken,
    'purchasedAt':   Timestamp.fromDate(purchasedAt),
  };

  factory LockerEntry.fromMap(Map<String, dynamic> m) => LockerEntry(
    contentId:     m['contentId']     ?? '',
    contentType:   m['contentType']   ?? '',
    productId:     m['productId']     ?? '',
    purchaseToken: m['purchaseToken'] ?? '',
    purchasedAt:   (m['purchasedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
  );
}

// ─── Price → Product ID maps ──────────────────────────────────────────────────
// Android (Google Play): album_tier_X / single_tier_X
// iOS (App Store):       y_album_tier_X / y_single_tier_X

final Map<double, String> kAlbumProductIds = Platform.isIOS
    ? {
        5.0:   'y_album_tier_5',
        10.0:  'y_album_tier_10',
        25.0:  'y_album_tier_25',
        50.0:  'y_album_tier_50',
        100.0: 'y_album_tier_100',
      }
    : {
        5.0:   'album_tier_5',
        10.0:  'album_tier_10',
        25.0:  'album_tier_25',
        50.0:  'album_tier_50',
        100.0: 'album_tier_100',
      };

final Map<double, String> kSingleProductIds = Platform.isIOS
    ? {
        2.0: 'y_single_tier_2',
        5.0: 'y_single_tier_5',
      }
    : {
        2.0: 'single_tier_2',
        5.0: 'single_tier_5',
      };

// ─── Purchase Result ──────────────────────────────────────────────────────────
enum PurchaseResult { success, cancelled, error, alreadyOwned }

class PurchaseService extends ChangeNotifier {
  PurchaseService._();
  static final PurchaseService instance = PurchaseService._();

  final InAppPurchase _iap       = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  // In-memory locker cache  { contentId → LockerEntry }
  final Map<String, LockerEntry> _locker = {};
  bool _lockerLoaded = false;

  // Pending purchase state — set before launching purchase flow
  String? _pendingContentId;
  String? _pendingContentType;
  Completer<PurchaseResult>? _completer;

  // ─── Init (call once from main or after login) ──────────────────────────
  Future<void> init() async {
    final available = await _iap.isAvailable();
    if (!available) return;

    // Listen to purchase updates FIRST before anything else
    final stream = _iap.purchaseStream;
    _subscription?.cancel();
    _subscription = stream.listen(
      _onPurchaseUpdate,
      onDone:  _subscription?.cancel,
      onError: (e) => debugPrint('[PurchaseService] stream error: $e'),
    );

    // Load locker from Firestore into memory
    await _loadLocker();

    // ── CRITICAL: consume any pending/dangling purchases from previous sessions
    // This fixes "item already owned" errors on first purchase
    await _consumePendingPurchases();
  }

  // ─── Consume any purchases that were never acknowledged ──────────────────
  // Called at startup to clear Google Play's "already owned" state
  Future<void> _consumePendingPurchases() async {
    try {
      // restorePurchases triggers the purchase stream with all pending items
      // _onPurchaseUpdate will then call completePurchase on each one
      await _iap.restorePurchases();
    } catch (e) {
      debugPrint('[PurchaseService] _consumePendingPurchases error: $e');
    }
  }

  // ─── Load locker from Firestore ──────────────────────────────────────────
  Future<void> _loadLocker() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      final raw = List<Map<String, dynamic>>.from(
        (doc.data()?['locker'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
      );

      _locker.clear();
      for (final m in raw) {
        final entry = LockerEntry.fromMap(m);
        if (entry.contentId.isNotEmpty) {
          _locker[entry.contentId] = entry;
        }
      }
      _lockerLoaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[PurchaseService] _loadLocker error: $e');
    }
  }

  // ─── Public: force reload locker (e.g. after login) ──────────────────────
  Future<void> reloadLocker() => _loadLocker();

  // ─── Public: check ownership ──────────────────────────────────────────────
  bool isUnlocked(String contentId) => _locker.containsKey(contentId);

  List<LockerEntry> get lockerEntries => _locker.values.toList();
  bool get lockerLoaded => _lockerLoaded;

  // ─── Derive product ID from content type + price ─────────────────────────
  String? productIdFor({required String contentType, required double price}) {
    if (contentType == 'album') return kAlbumProductIds[price];
    if (contentType == 'single') return kSingleProductIds[price];
    return null;
  }

  // ─── Buy album ────────────────────────────────────────────────────────────
  Future<PurchaseResult> buyAlbum({
    required String albumId,
    required double price,
  }) => _purchase(contentId: albumId, contentType: 'album', price: price);

  // ─── Buy single ───────────────────────────────────────────────────────────
  Future<PurchaseResult> buySingle({
    required String songId,
    required double price,
  }) => _purchase(contentId: songId, contentType: 'single', price: price);

  // ─── Core purchase flow ───────────────────────────────────────────────────
  Future<PurchaseResult> _purchase({
    required String contentId,
    required String contentType,
    required double price,
  }) async {
    // Already owned?
    if (isUnlocked(contentId)) return PurchaseResult.alreadyOwned;

    final productId = productIdFor(contentType: contentType, price: price);
    if (productId == null) {
      debugPrint('[PurchaseService] No product id for $contentType @ $price');
      return PurchaseResult.error;
    }

    // Query product details from Play
    final response = await _iap.queryProductDetails({productId});
    if (response.error != null || response.productDetails.isEmpty) {
      debugPrint('[PurchaseService] queryProductDetails error: ${response.error}');
      return PurchaseResult.error;
    }

    final product = response.productDetails.first;

    // Store pending context so _onPurchaseUpdate knows what to unlock
    _pendingContentId   = contentId;
    _pendingContentType = contentType;
    _completer          = Completer<PurchaseResult>();

    final param = PurchaseParam(productDetails: product);

    // autoConsume: true → in_app_purchase handles consumption on Android AND iOS automatically
    await _iap.buyConsumable(purchaseParam: param, autoConsume: true);

    // Wait for purchase stream to resolve
    return _completer!.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () {
        _clearPending();
        return PurchaseResult.cancelled;
      },
    );
  }

  // ─── Purchase stream handler ──────────────────────────────────────────────
  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.purchased:
          await _handleSuccess(purchase);
          break;

        case PurchaseStatus.error:
          debugPrint('[PurchaseService] purchase error: ${purchase.error}');
          // Complete the transaction so it doesn't stay pending
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
          _completer?.complete(PurchaseResult.error);
          _clearPending();
          break;

        case PurchaseStatus.canceled:
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
          _completer?.complete(PurchaseResult.cancelled);
          _clearPending();
          break;

        case PurchaseStatus.restored:
          // Consume the restored purchase so Google Play clears the "already owned" state
          // Only save to locker if it's genuinely in our locker already (re-install restore)
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
          // If this restore matches something in locker already, skip saving again
          debugPrint('[PurchaseService] restored: ${purchase.productID}');
          break;

        case PurchaseStatus.pending:
          debugPrint('[PurchaseService] pending: ${purchase.productID}');
          break;
      }
    }
  }

  // ─── Handle successful purchase ───────────────────────────────────────────
  Future<void> _handleSuccess(PurchaseDetails purchase) async {
    final contentId   = _pendingContentId;
    final contentType = _pendingContentType;

    if (contentId == null || contentType == null) {
      debugPrint('[PurchaseService] success but no pending context');
      _completer?.complete(PurchaseResult.success);
      _clearPending();
      return;
    }

    // completePurchase handles consumption on both Android and iOS
    // (autoConsume: false was set so we control timing — we complete after saving)

    // Save to Firestore locker
    final entry = LockerEntry(
      contentId:     contentId,
      contentType:   contentType,
      productId:     purchase.productID,
      purchaseToken: purchase.verificationData.serverVerificationData,
      purchasedAt:   DateTime.now(),
    );

    await _saveToLocker(entry);

    _completer?.complete(PurchaseResult.success);
    _clearPending();
  }

  // ─── Save entry to Firestore + memory cache ───────────────────────────────
  Future<void> _saveToLocker(LockerEntry entry) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({
        'locker': FieldValue.arrayUnion([entry.toMap()]),
      });

      _locker[entry.contentId] = entry;
      notifyListeners();
    } catch (e) {
      debugPrint('[PurchaseService] _saveToLocker error: $e');
    }
  }

  // ─── Restore purchases (call from Settings) ───────────────────────────────
  Future<void> restorePurchases() async {
    await _iap.restorePurchases();
  }

  void _clearPending() {
    _pendingContentId   = null;
    _pendingContentType = null;
    _completer          = null;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}