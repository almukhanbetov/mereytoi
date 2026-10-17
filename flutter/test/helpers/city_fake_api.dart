import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:mereytoi_app/core/network/api_client.dart';
import 'package:mereytoi_app/models/city.dart';

/// The city fixtures the city-selector tests share — a subset of the
/// backend's GET /api/cities directory, same IDs and names.
const testCities = [
  City(id: 1, nameRu: 'Алматы', nameKz: 'Алматы', nameEn: 'Almaty'),
  City(id: 2, nameRu: 'Астана', nameKz: 'Астана', nameEn: 'Astana'),
  City(id: 4, nameRu: 'Караганда', nameKz: 'Қарағанды', nameEn: 'Karaganda'),
  City(id: 8, nameRu: 'Усть-Каменогорск', nameKz: 'Өскемен', nameEn: 'Oskemen'),
  City(id: 15, nameRu: 'Туркестан', nameKz: 'Түркістан', nameEn: 'Turkistan'),
];

Map<String, dynamic> cityJson(City c) => {
  'id': c.id,
  'name_ru': c.nameRu,
  'name_kz': c.nameKz,
  'name_en': c.nameEn,
};

/// Same fake-adapter seam the other service tests use (`ApiClient.test` +
/// a routing `HttpClientAdapter`): records every request and answers
/// GET /api/cities with [testCities] and GET /api/listings with an empty
/// list.
class CityFakeAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  List<RequestOptions> get listingRequests =>
      requests.where((r) => r.path == '/api/listings').toList();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final Object data = switch (options.path) {
      '/api/cities' => {'cities': testCities.map(cityJson).toList()},
      '/api/listings' => {'listings': <Object>[]},
      _ => {'error': 'not found'},
    };
    return ResponseBody.fromBytes(
      Uint8List.fromList(utf8.encode(jsonEncode(data))),
      options.path == '/api/cities' || options.path == '/api/listings'
          ? 200
          : 404,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

(ApiClient, CityFakeAdapter) fakeCityApi() {
  final adapter = CityFakeAdapter();
  final client = ApiClient.test(tokenProvider: () async => null);
  client.debugDio.httpClientAdapter = adapter;
  return (client, adapter);
}
