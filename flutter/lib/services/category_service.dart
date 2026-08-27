import '../core/network/api_client.dart';
import '../models/category.dart';

/// Wraps GET /api/categories and GET /api/categories/:slug — no other
/// category endpoints exist (creating/editing categories is admin-only,
/// which this app deliberately never calls).
class CategoryService {
  CategoryService(this._client);

  final ApiClient _client;

  Future<List<Category>> fetchCategories() async {
    final json = await _client.getJson('/api/categories');
    final raw = json['categories'] as List? ?? const [];
    return raw.map((e) => Category.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<Category> fetchBySlug(String slug) async {
    final json = await _client.getJson('/api/categories/$slug');
    return Category.fromJson(Map<String, dynamic>.from(json['category'] as Map));
  }
}
