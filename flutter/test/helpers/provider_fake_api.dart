import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:mereytoi_app/core/network/api_client.dart';

/// An in-memory stand-in for the provider endpoints the onboarding uses
/// (`/api/provider*`, `/api/uploads`, `/api/users/me/listings`), behind the
/// same `ApiClient.test` + `HttpClientAdapter` seam the other service
/// tests use. Records every call and can be told to fail specific ones.
class ProviderFakeApi implements HttpClientAdapter {
  ProviderFakeApi({Map<String, dynamic>? existingProvider})
    : provider = existingProvider;

  /// The caller's provider profile (null = not a provider yet).
  Map<String, dynamic>? provider;

  /// Listings created through POST /api/provider/me/listings (also what
  /// GET /api/users/me/listings returns).
  final listings = <Map<String, dynamic>>[];

  /// What GET /api/provider/me/bookings returns for a provider.
  final bookings = <Map<String, dynamic>>[];

  final calls = <String>[];
  final bodies = <String, List<Object?>>{};

  /// `"METHOD /path"` → how many upcoming calls answer HTTP 500.
  final failWith500 = <String, int>{};

  /// `"METHOD /path"` → how many upcoming calls succeed on the "server"
  /// but lose the response (the client sees a network error).
  final loseResponse = <String, int>{};

  /// Respond 409 to POST /api/provider even though [provider] is null,
  /// then create it — as if another device created it a moment earlier.
  bool conflictOnCreate = false;

  /// When set, POST /api/provider/me/listings waits for it — lets a test
  /// observe the saving state and tap again meanwhile.
  Completer<void>? createGate;

  int count(String call) => calls.where((c) => c == call).length;

  var _nextUrl = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final key = '${options.method} ${options.path}';
    calls.add(key);
    bodies.putIfAbsent(key, () => []).add(options.data);

    if (key == 'POST /api/provider/me/listings' && createGate != null) {
      await createGate!.future;
    }
    if (options.method == 'PUT' && options.path.startsWith('/api/listings/')) {
      final id = int.parse(options.path.split('/').last);
      final i = listings.indexWhere((l) => l['id'] == id);
      if (i < 0) return _json({'error': 'listing not found'}, 404);
      listings[i] = {
        ...listings[i],
        ...Map<String, dynamic>.from(options.data as Map),
        'id': id,
      };
      return _json({'listing': listings[i]}, 200);
    }

    if ((failWith500[key] ?? 0) > 0) {
      failWith500[key] = failWith500[key]! - 1;
      return _json({'error': 'boom'}, 500);
    }

    final (Object body, int status) = switch (key) {
      'GET /api/provider/me' =>
        provider == null
            ? (<String, dynamic>{'error': 'no provider profile'}, 404)
            : (<String, dynamic>{'provider': provider}, 200),
      'POST /api/provider' => _createProvider(options.data as Map),
      'PUT /api/provider/me' => _updateProvider(options.data as Map),
      'POST /api/uploads' => (
        <String, dynamic>{
          'urls': [
            for (var i = 0; i < (options.data as FormData).files.length; i++)
              '/uploads/photo${_nextUrl++}.jpg',
          ],
        },
        200,
      ),
      'POST /api/provider/me/listings' => _createListing(options.data as Map),
      'GET /api/users/me/listings' => (
        <String, dynamic>{'listings': listings},
        200,
      ),
      'GET /api/provider/me/bookings' =>
        provider == null
            ? (<String, dynamic>{'error': 'provider_not_found'}, 404)
            : (<String, dynamic>{'bookings': bookings}, 200),
      _ => (<String, dynamic>{'error': 'not found'}, 404),
    };

    if ((loseResponse[key] ?? 0) > 0) {
      loseResponse[key] = loseResponse[key]! - 1;
      throw const SocketException('connection lost after the server acted');
    }
    return _json(body, status);
  }

  (Object, int) _createProvider(Map body) {
    if (conflictOnCreate) {
      conflictOnCreate = false;
      provider = {
        'id': 7,
        'user_id': 1,
        'display_name': 'Created elsewhere',
        'city': '',
        'status': 'active',
        'experience_years': null,
      };
      return ({'error': 'provider profile already exists'}, 409);
    }
    if (provider != null) {
      return ({'error': 'provider profile already exists'}, 409);
    }
    provider = {
      'id': 7,
      'user_id': 1,
      ...Map<String, dynamic>.from(body),
      'status': 'active',
    };
    return ({'provider': provider}, 201);
  }

  (Object, int) _updateProvider(Map body) {
    if (provider == null) return ({'error': 'no provider profile'}, 404);
    provider = {...provider!, ...Map<String, dynamic>.from(body)};
    return ({'provider': provider}, 200);
  }

  (Object, int) _createListing(Map body) {
    if (provider == null) {
      return ({'error': 'create a provider profile first'}, 403);
    }
    final listing = {
      'id': 100 + listings.length,
      ...Map<String, dynamic>.from(body),
      'rating': 0,
      'is_active': true,
    };
    listings.add(listing);
    return ({'listing': listing}, 201);
  }

  ResponseBody _json(Object data, int status) => ResponseBody.fromBytes(
    Uint8List.fromList(utf8.encode(jsonEncode(data))),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

(ApiClient, ProviderFakeApi) fakeProviderApi({
  Map<String, dynamic>? existingProvider,
}) {
  final api = ProviderFakeApi(existingProvider: existingProvider);
  final client = ApiClient.test(tokenProvider: () async => 'token');
  client.debugDio.httpClientAdapter = api;
  return (client, api);
}

/// Real temp image files for the multipart upload (contents don't matter
/// to the fake server).
List<String> tempPhotos(int n) {
  final dir = Directory.systemTemp.createTempSync('onboarding_photos');
  return [
    for (var i = 0; i < n; i++)
      (File('${dir.path}/p$i.jpg')..writeAsBytesSync([0xFF, 0xD8, i])).path,
  ];
}
