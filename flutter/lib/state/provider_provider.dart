import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../models/listing.dart';
import '../models/provider_profile.dart';
import 'listings_provider.dart';
import 'providers.dart';

/// The current user's own provider profile — null when they haven't
/// "Стать услугодателем" yet, distinguishing that (a normal, common state)
/// from a genuine network/server error. `ProviderService.me()` throws
/// `ApiErrorType.notFound` for "no profile"; every other `ApiException`
/// (and any other error) is rethrown so a real failure still shows the
/// screen's own error/retry UI rather than silently looking like "not a
/// provider yet".
final providerProfileProvider = FutureProvider<ProviderProfile?>((
  ref,
) async {
  try {
    return await ref.watch(providerServiceProvider).me();
  } on ApiException catch (e) {
    if (e.type == ApiErrorType.notFound) return null;
    rethrow;
  }
});

/// Every provider-profile/listing mutation this stage adds, same "plain
/// async methods + invalidate exactly what just went stale" shape
/// [ListingManagementActions] already established.
class ProviderActions {
  ProviderActions(this._ref);

  final Ref _ref;

  void _invalidateMyListings() {
    _ref.invalidate(myListingsProvider);
    // The public catalog should pick up a new/edited/deleted service too,
    // same "no app restart needed" guarantee ListingManagementActions
    // already gives restaurant edits.
    _ref.invalidate(listingsProvider(null));
  }

  Future<ProviderProfile> become({
    required String displayName,
    String city = '',
    String description = '',
    String phone = '',
    String whatsapp = '',
    String telegram = '',
    String avatarUrl = '',
  }) async {
    final provider = await _ref
        .read(providerServiceProvider)
        .create(
          displayName: displayName,
          city: city,
          description: description,
          phone: phone,
          whatsapp: whatsapp,
          telegram: telegram,
          avatarUrl: avatarUrl,
        );
    _ref.invalidate(providerProfileProvider);
    return provider;
  }

  Future<ProviderProfile> updateProfile({
    required String displayName,
    String city = '',
    String description = '',
    String phone = '',
    String whatsapp = '',
    String telegram = '',
    String avatarUrl = '',
  }) async {
    final provider = await _ref
        .read(providerServiceProvider)
        .update(
          displayName: displayName,
          city: city,
          description: description,
          phone: phone,
          whatsapp: whatsapp,
          telegram: telegram,
          avatarUrl: avatarUrl,
        );
    _ref.invalidate(providerProfileProvider);
    return provider;
  }

  Future<Listing> createListing({
    required int categoryId,
    required String nameRu,
    required String nameKz,
    String descriptionRu = '',
    String descriptionKz = '',
    String city = '',
    int price = 0,
    String priceType = 'fixed',
    List<String> imageUrls = const [],
  }) async {
    final listing = await _ref
        .read(providerServiceProvider)
        .createListing(
          categoryId: categoryId,
          nameRu: nameRu,
          nameKz: nameKz,
          descriptionRu: descriptionRu,
          descriptionKz: descriptionKz,
          city: city,
          price: price,
          priceType: priceType,
          imageUrls: imageUrls,
        );
    _invalidateMyListings();
    return listing;
  }

  Future<Listing> updateListing(
    Listing current, {
    required String nameRu,
    required String nameKz,
    String descriptionRu = '',
    String descriptionKz = '',
    String city = '',
    int price = 0,
    String priceType = 'fixed',
    List<String>? imageUrls,
    bool? isActive,
  }) async {
    final listing = await _ref
        .read(listingManagementServiceProvider)
        .updateListing(
          current,
          nameRu: nameRu,
          nameKz: nameKz,
          descriptionRu: descriptionRu,
          descriptionKz: descriptionKz,
          city: city,
          price: price,
          priceType: priceType,
          imageUrls: imageUrls,
          isActive: isActive,
        );
    _invalidateMyListings();
    return listing;
  }

  Future<void> deleteListing(int id) async {
    await _ref.read(listingManagementServiceProvider).deleteListing(id);
    _invalidateMyListings();
  }
}

final providerActionsProvider = Provider<ProviderActions>(
  (ref) => ProviderActions(ref),
);
