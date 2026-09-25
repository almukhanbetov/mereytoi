import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_client.dart';
import '../services/auth_service.dart';
import '../services/booking_service.dart';
import '../services/category_service.dart';
import '../services/event_service.dart';
import '../services/listing_management_service.dart';
import '../services/listing_service.dart';
import '../services/manager_chat_service.dart';
import '../services/notification_service.dart';
import '../services/provider_chat_service.dart';
import '../services/provider_service.dart';
import '../services/public_provider_service.dart';
import '../services/statistics_service.dart';
import '../services/upload_service.dart';

/// Dependency wiring — every Service is built once from the single shared
/// [ApiClient], so Screens never construct a Dio/Service themselves
/// (Screen → Repository/Service → Dio → API, per the requested architecture).
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient.instance);

final categoryServiceProvider = Provider<CategoryService>(
  (ref) => CategoryService(ref.watch(apiClientProvider)),
);
final listingServiceProvider = Provider<ListingService>(
  (ref) => ListingService(ref.watch(apiClientProvider)),
);
final statisticsServiceProvider = Provider<StatisticsService>(
  (ref) => StatisticsService(ref.watch(apiClientProvider)),
);
final bookingServiceProvider = Provider<BookingService>(
  (ref) => BookingService(ref.watch(apiClientProvider)),
);
final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(ref.watch(apiClientProvider)),
);
final eventServiceProvider = Provider<EventService>(
  (ref) => EventService(ref.watch(apiClientProvider)),
);
final managerChatServiceProvider = Provider<ManagerChatService>(
  (ref) => ManagerChatService(ref.watch(apiClientProvider)),
);
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(ref.watch(apiClientProvider)),
);
final listingManagementServiceProvider = Provider<ListingManagementService>(
  (ref) => ListingManagementService(ref.watch(apiClientProvider)),
);
final providerServiceProvider = Provider<ProviderService>(
  (ref) => ProviderService(ref.watch(apiClientProvider)),
);
final uploadServiceProvider = Provider<UploadService>(
  (ref) => UploadService(ref.watch(apiClientProvider)),
);
final providerChatServiceProvider = Provider<ProviderChatService>(
  (ref) => ProviderChatService(ref.watch(apiClientProvider)),
);
final publicProviderServiceProvider = Provider<PublicProviderService>(
  (ref) => PublicProviderService(ref.watch(apiClientProvider)),
);
