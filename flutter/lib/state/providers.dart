import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_client.dart';
import '../services/booking_service.dart';
import '../services/category_service.dart';
import '../services/listing_service.dart';
import '../services/statistics_service.dart';

/// Dependency wiring — every Service is built once from the single shared
/// [ApiClient], so Screens never construct a Dio/Service themselves
/// (Screen → Repository/Service → Dio → API, per the requested architecture).
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient.instance);

final categoryServiceProvider = Provider<CategoryService>((ref) => CategoryService(ref.watch(apiClientProvider)));
final listingServiceProvider = Provider<ListingService>((ref) => ListingService(ref.watch(apiClientProvider)));
final statisticsServiceProvider = Provider<StatisticsService>((ref) => StatisticsService(ref.watch(apiClientProvider)));
final bookingServiceProvider = Provider<BookingService>((ref) => BookingService(ref.watch(apiClientProvider)));
