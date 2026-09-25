import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/provider_public_profile.dart';
import 'providers.dart';

/// `GET /api/providers/:id` — ProviderProfileScreen's own data source.
/// `autoDispose` (not cached indefinitely): a provider's profile/listings
/// can change between visits, and this screen is opened rarely enough that
/// re-fetching each time is cheap and simpler than manual invalidation.
final publicProviderProfileProvider = FutureProvider.autoDispose
    .family<ProviderPublicProfile, int>((ref, providerId) async {
      return ref.read(publicProviderServiceProvider).get(providerId);
    });
