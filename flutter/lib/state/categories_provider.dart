import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/category.dart';
import 'providers.dart';

final categoriesProvider = FutureProvider<List<Category>>((ref) {
  return ref.watch(categoryServiceProvider).fetchCategories();
});
