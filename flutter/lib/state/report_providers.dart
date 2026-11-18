import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_report.dart';
import '../services/report_service.dart';
import 'providers.dart';

final reportServiceProvider = Provider<ReportService>(
  (ref) => ReportService(ref.watch(apiClientProvider)),
);

final myReportsProvider = FutureProvider.autoDispose<List<UserReport>>(
  (ref) => ref.watch(reportServiceProvider).mine(),
);
