import 'package:dio/dio.dart';
import 'package:uhis_next/core/api/frappe_client.dart';

import 'scripted_dio_adapter.dart';

/// A [FrappeClient] whose responses come from a [ScriptedDioAdapter], with a
/// test token and tenant, for repository tests.
(FrappeClient, ScriptedDioAdapter) scriptedFrappeClient(
  List<Future<ResponseBody> Function(RequestOptions)> responses,
) {
  final adapter = ScriptedDioAdapter(responses);
  final dio = Dio(BaseOptions(baseUrl: 'https://frappe.test'))
    ..httpClientAdapter = adapter;
  return (
    FrappeClient(
      baseUrl: 'https://frappe.test',
      authTokenProvider: () async => 'jwt-1',
      tenantIdProvider: () async => '7',
      dio: dio,
    ),
    adapter,
  );
}
