import 'package:dio/browser.dart';
import 'package:dio/dio.dart';

void configureWebCredentials(Dio dio) {
  final adapter = BrowserHttpClientAdapter();
  adapter.withCredentials = true;
  dio.httpClientAdapter = adapter;
}
