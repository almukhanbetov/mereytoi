import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/site_statistics.dart';
import 'providers.dart';

final statisticsProvider = FutureProvider<SiteStatistics>((ref) {
  return ref.watch(statisticsServiceProvider).fetchStatistics();
});
