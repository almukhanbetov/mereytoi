import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_thumbnail_video/index.dart';
import 'package:get_thumbnail_video/video_thumbnail.dart';

/// Loads one still frame for a video URL — `null` when it can't (offline,
/// timeout, unsupported file). Never plays or fully downloads the video:
/// the platform's metadata retriever reads only what it needs for one
/// frame (production `/uploads/*.mp4` serve HTTP ranges and keep `moov`
/// at the front, so that's the first few hundred KB).
typedef VideoThumbnailLoader = Future<Uint8List?> Function(String url);

/// Frame ~1s in rather than 0ms: many clips open on a black/fade-in frame.
const _frameAtMs = 1000;
const _timeout = Duration(seconds: 8);

Future<Uint8List?> _platformThumbnail(String url) async {
  try {
    final bytes = await VideoThumbnail.thumbnailData(
      video: url,
      imageFormat: ImageFormat.JPEG,
      maxWidth: 720,
      quality: 70,
      timeMs: _frameAtMs,
    ).timeout(_timeout);
    return bytes.isEmpty ? null : bytes;
  } catch (_) {
    return null;
  }
}

/// Session cache of frames by URL, so scrolling away and back (or reopening
/// the same service) never fetches a frame twice. Stores the *Future*, so
/// two cards asking for the same URL at once share one request. Bounded,
/// oldest evicted first. A failed load isn't cached — a later visit (e.g.
/// back online) tries again.
class VideoThumbnailCache {
  VideoThumbnailCache(this._loader, {this.capacity = 40});

  final VideoThumbnailLoader _loader;
  final int capacity;

  /// Insertion-ordered (Dart map literals are), so `keys.first` is the
  /// least recently used entry.
  final _entries = <String, Future<Uint8List?>>{};

  Future<Uint8List?> load(String url) {
    final cached = _entries.remove(url);
    if (cached != null) {
      _entries[url] = cached; // most recently used
      return cached;
    }
    final future = _loader(url).then((bytes) {
      if (bytes == null) _entries.remove(url);
      return bytes;
    });
    _entries[url] = future;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
    return future;
  }
}

final videoThumbnailCacheProvider = Provider<VideoThumbnailCache>(
  (ref) => VideoThumbnailCache(_platformThumbnail),
);
