import 'package:dio/dio.dart';

import '../core/network/api_client.dart';

/// Этап 11F — wraps `POST /api/uploads`, the exact same backend endpoint
/// (and the same `files` multipart field name) frontend/src/lib/adminApi.js's
/// `uploadImages` already uses, and which Этап 11 opened up to any
/// authenticated user (not just admin) specifically so a provider could
/// upload photos for their own profile/service. No second media API here —
/// confirmed directly against backend/internal/handlers/upload_handler.go
/// before writing this (jpg/jpeg/png/webp/gif only, 8MB per file — server-
/// enforced, this class doesn't duplicate that validation).
class UploadService {
  UploadService(this._client);

  final ApiClient _client;

  /// Uploads one or more local image files (by filesystem path, as returned
  /// by image_picker's `XFile.path`) and returns their public URLs in the
  /// same order the backend returned them (which is the order they were
  /// attached — `UploadHandler.Upload` iterates `form.File["files"]` in
  /// request order).
  Future<List<String>> uploadImages(List<String> filePaths) async {
    final formData = FormData();
    for (final path in filePaths) {
      formData.files.add(
        MapEntry('files', await MultipartFile.fromFile(path)),
      );
    }
    final json = await _client.postMultipart('/api/uploads', formData);
    final raw = json['urls'] as List? ?? const [];
    return raw.map((e) => e.toString()).toList();
  }

  /// `POST /api/uploads/video` (admin-only on the server, field `video`) —
  /// the same endpoint and field the web admin's `uploadVideo` uses. One
  /// file per request: the server transcodes each upload before answering
  /// (mp4/webm/mov, up to 200MB — checked server-side), so the answer can
  /// take minutes. Returns the public URL of the transcoded file.
  Future<String> uploadVideo(String filePath) async {
    final formData = FormData()
      ..files.add(MapEntry('video', await MultipartFile.fromFile(filePath)));
    final json = await _client.postMultipart(
      '/api/uploads/video',
      formData,
      receiveTimeout: const Duration(minutes: 10),
    );
    return json['url'].toString();
  }
}
