import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/promotion.dart';
import '../state/providers.dart';

/// How one purchase attempt ended.
enum PromotionPurchaseResult {
  /// The server verified the payment; the promotion exists.
  activated,

  /// The store reports the payment as pending (e.g. cash at a shop); the
  /// server activates it when the store confirms.
  pending,
  cancelled,
  failed,

  /// The store can't sell here (no Play/App Store, product not set up).
  unavailable,
}

/// The payment channel of this device: Google Play on Android, the App
/// Store on iOS. There is no other way to buy inside the app, and no link
/// to an outside payment page.
String? storeChannel() {
  if (kIsWeb) return null;
  if (Platform.isAndroid) return 'google';
  if (Platform.isIOS) return 'apple';
  return null;
}

/// Buys the 7-day promotion through the store. The order is opened on the
/// server first; the store purchase carries its token; the payment goes to
/// the server for verification, and only after the server confirms is the
/// store transaction finished. A purchase the app couldn't report (closed
/// mid-way) is re-delivered by the store and reported on the next start of
/// this controller; the server also activates it from store notifications.
class StorePurchaseController {
  StorePurchaseController(this._ref);

  final Ref _ref;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  Completer<PromotionPurchaseResult>? _waiting;
  String? _waitingProduct;

  static const _pendingKey = 'promotion_pending_order';

  InAppPurchase get _iap => InAppPurchase.instance;

  /// Starts listening to store updates (also re-delivered old purchases).
  void start() {
    if (storeChannel() == null) return;
    _sub ??= _iap.purchaseStream.listen((updates) async {
      for (final p in updates) {
        await _handle(p);
      }
    }, onError: (_) => _finish(PromotionPurchaseResult.failed));
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  /// The store's own product and its localized price, or null when the
  /// store can't sell it here.
  Future<ProductDetails?> product(String productId) async {
    if (storeChannel() == null || !await _iap.isAvailable()) return null;
    final res = await _iap.queryProductDetails({productId});
    if (res.error != null || res.productDetails.isEmpty) return null;
    return res.productDetails.first;
  }

  Future<PromotionPurchaseResult> buy({
    required int listingId,
    required ProductDetails product,
  }) async {
    final channel = storeChannel();
    if (channel == null || _waiting != null) {
      return PromotionPurchaseResult.unavailable;
    }
    start();
    final order = await _ref
        .read(promotionServiceProvider)
        .createOrder(listingId, channel);
    if (order.productId != product.id) {
      return PromotionPurchaseResult.unavailable;
    }
    await _remember(order);
    final waiting = _waiting = Completer<PromotionPurchaseResult>();
    _waitingProduct = product.id;
    final started = await _iap.buyConsumable(
      purchaseParam: PurchaseParam(
        productDetails: product,
        // Google: obfuscatedAccountId, Apple: appAccountToken. The server
        // accepts the payment only for the order with this token.
        applicationUserName: order.token,
      ),
      // The server consumes it after activation, never before.
      autoConsume: false,
    );
    if (!started) _finish(PromotionPurchaseResult.failed);
    return waiting.future.timeout(
      const Duration(minutes: 10),
      onTimeout: () {
        _waiting = null;
        return PromotionPurchaseResult.pending;
      },
    );
  }

  void _finish(PromotionPurchaseResult result) {
    final w = _waiting;
    _waiting = null;
    _waitingProduct = null;
    if (w != null && !w.isCompleted) w.complete(result);
  }

  Future<void> _handle(PurchaseDetails p) async {
    final ours = p.productID == _waitingProduct;
    switch (p.status) {
      case PurchaseStatus.pending:
        if (ours) _finish(PromotionPurchaseResult.pending);
        return;
      case PurchaseStatus.canceled:
        if (p.pendingCompletePurchase) await _complete(p);
        if (ours) _finish(PromotionPurchaseResult.cancelled);
        return;
      case PurchaseStatus.error:
        if (p.pendingCompletePurchase) await _complete(p);
        if (ours) _finish(PromotionPurchaseResult.failed);
        return;
      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        break;
    }

    final order = await _pendingOrder(p.productID);
    if (order == null) {
      // Not a purchase this device started; the server handles it from
      // the store notification.
      return;
    }
    final service = _ref.read(promotionServiceProvider);
    final proof = p.verificationData.serverVerificationData;
    try {
      final activated = storeChannel() == 'google'
          ? await service.confirmGoogle(order.id, proof)
          : await service.confirmApple(order.id, proof);
      if (!activated) {
        if (ours) _finish(PromotionPurchaseResult.pending);
        return;
      }
      await _complete(p);
      await _forget();
      if (ours) _finish(PromotionPurchaseResult.activated);
    } catch (_) {
      // Not finished on purpose: the store re-delivers it, and the server
      // may still activate it from the store notification.
      if (ours) _finish(PromotionPurchaseResult.failed);
    }
  }

  Future<void> _complete(PurchaseDetails p) async {
    if (!p.pendingCompletePurchase) return;
    try {
      await _iap.completePurchase(p);
    } catch (_) {}
  }

  Future<void> _remember(PromotionOrder order) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _pendingKey,
      jsonEncode({
        'id': order.id,
        'token': order.token,
        'product_id': order.productId,
      }),
    );
  }

  Future<PromotionOrder?> _pendingOrder(String productId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingKey);
    if (raw == null) return null;
    try {
      final order = PromotionOrder.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
      return order.productId == productId ? order : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _forget() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingKey);
  }
}

/// This device's payment channel (see [storeChannel]); a provider so a
/// test can stand in for a phone.
final storeChannelProvider = Provider<String?>((ref) => storeChannel());

final storePurchaseProvider = Provider<StorePurchaseController>((ref) {
  final c = StorePurchaseController(ref);
  ref.onDispose(c.dispose);
  return c;
});
