/// The single in-app purchase: "Remove Ads" (non-consumable). It switches off interstitials;
/// rewarded ads stay, because those are the player's own choice.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

abstract class PurchaseService {
  /// The store answered and the product exists - only then is the button shown.
  bool get available;

  /// Localised price from the store ("$1.99"), empty until known.
  String get price;

  /// Called when ownership of Remove Ads is confirmed (new purchase or restore).
  set onRemoveAdsOwned(void Function() callback);

  Future<void> init();
  Future<void> buyRemoveAds();
  Future<void> restore();
}

class NoPurchases implements PurchaseService {
  @override
  bool get available => false;

  @override
  String get price => '';

  @override
  set onRemoveAdsOwned(void Function() callback) {}

  @override
  Future<void> init() async {}

  @override
  Future<void> buyRemoveAds() async {}

  @override
  Future<void> restore() async {}
}

class StorePurchases implements PurchaseService {
  /// Must match the managed product created in Play Console.
  static const String removeAdsId = String.fromEnvironment('REMOVE_ADS_PRODUCT_ID', defaultValue: 'remove_ads');

  ProductDetails? _product;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  void Function() _owned = () {};

  @override
  bool get available => _product != null;

  @override
  String get price => _product?.price ?? '';

  @override
  set onRemoveAdsOwned(void Function() callback) => _owned = callback;

  @override
  Future<void> init() async {
    try {
      final iap = InAppPurchase.instance;
      if (!await iap.isAvailable()) return;
      _sub ??= iap.purchaseStream.listen(_onPurchases, onError: (_) {});
      final response = await iap.queryProductDetails({removeAdsId});
      if (response.productDetails.isNotEmpty) _product = response.productDetails.first;
      // Picks up a purchase made on another device or before a reinstall.
      await iap.restorePurchases();
    } catch (e) {
      debugPrint('purchases init failed: $e');
    }
  }

  void _onPurchases(List<PurchaseDetails> purchases) {
    for (final p in purchases) {
      try {
        if (p.productID == removeAdsId &&
            (p.status == PurchaseStatus.purchased || p.status == PurchaseStatus.restored)) {
          _owned();
        }
        if (p.pendingCompletePurchase) {
          unawaited(InAppPurchase.instance.completePurchase(p).catchError((_) {}));
        }
      } catch (e) {
        debugPrint('purchase update failed: $e');
      }
    }
  }

  @override
  Future<void> buyRemoveAds() async {
    final product = _product;
    if (product == null) return;
    try {
      await InAppPurchase.instance.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product));
    } catch (e) {
      debugPrint('purchase failed: $e');
    }
  }

  @override
  Future<void> restore() async {
    try {
      await InAppPurchase.instance.restorePurchases();
    } catch (e) {
      debugPrint('restore failed: $e');
    }
  }
}
