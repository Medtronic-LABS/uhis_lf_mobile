import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/api/frappe_client.dart';
import 'package:uhis_next/features/visit/naba/guideline_visual_repository.dart';
import 'package:uhis_next/features/visit/naba/naba_models.dart';

import '../../../helpers/scripted_dio_adapter.dart';
import 'naba_visuals_fixtures.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('naba_visuals_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  (GuidelineVisualRepository, ScriptedDioAdapter) build(
    List<Future<ResponseBody> Function(RequestOptions)> responses,
  ) {
    final adapter = ScriptedDioAdapter(responses);
    final client = FrappeClient(
      baseUrl: 'https://frappe.test',
      authTokenProvider: () async => 'jwt',
      tenantIdProvider: () async => '1',
      dio: Dio(BaseOptions(baseUrl: 'https://frappe.test'))
        ..httpClientAdapter = adapter,
    );
    return (
      GuidelineVisualRepository(client, cacheRoot: () async => tmp),
      adapter,
    );
  }

  final svg = wrappedSvg();
  final image = NabaVisualImage.tryParse(imageJson('anc-1-1-01', 1))!;
  File cached() => File('${tmp.path}/naba_visuals/${image.sha256}.svg');

  test(
    'miss: downloads, verifies, caches, and returns the embedded raster',
    () async {
      final (repo, adapter) = build([
        (_) async => bytesResponseBody(utf8.encode(svg)),
      ]);

      final data = await repo.load(image);

      expect(data?.raster, tinyPng);
      expect(
        adapter.requests.single.uri.toString(),
        'https://frappe.test$visualImagePath'
        'anc-1-1-01',
      );
      expect(cached().readAsStringSync(), svg);
    },
  );

  test('hit: served from disk with no request', () async {
    cached()
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(svg);
    final (repo, adapter) = build([(_) async => bytesResponseBody(const [])]);

    final data = await repo.load(image);

    expect(data?.raster, tinyPng);
    expect(adapter.callCount, 0);
  });

  test('corrupt cache file is replaced by a fresh download', () async {
    cached()
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('garbage');
    final (repo, adapter) = build([
      (_) async => bytesResponseBody(utf8.encode(svg)),
    ]);

    expect((await repo.load(image))?.raster, tinyPng);
    expect(adapter.callCount, 1);
    expect(cached().readAsStringSync(), svg);
  });

  test('sha256 mismatch: nothing cached, null returned', () async {
    final (repo, _) = build([
      (_) async =>
          bytesResponseBody(utf8.encode(wrappedSvg(raster: [1, 2, 3]))),
    ]);

    expect(await repo.load(image), isNull);
    expect(cached().existsSync(), isFalse);
  });

  for (final status in [401, 404, 429]) {
    test('HTTP $status → null', () async {
      final (repo, _) = build([
        (_) async => jsonResponseBody({'exc_type': 'X'}, statusCode: status),
      ]);

      expect(await repo.load(image), isNull);
      expect(cached().existsSync(), isFalse);
    });
  }

  test('imagePath outside the visual_image method is refused', () async {
    final (repo, adapter) = build([
      (_) async => bytesResponseBody(utf8.encode(svg)),
    ]);
    final rogue = NabaVisualImage.tryParse({
      ...imageJson('x', 1),
      'imagePath': '/api/method/frappe.client.get_list',
    })!;

    expect(await repo.load(rogue), isNull);
    expect(adapter.callCount, 0);
  });

  test('concurrent loads of one image share a single request', () async {
    final (repo, adapter) = build([
      (_) async => bytesResponseBody(utf8.encode(svg)),
    ]);

    final results = await Future.wait([repo.load(image), repo.load(image)]);

    expect(results.every((r) => r?.raster != null), isTrue);
    expect(adapter.callCount, 1);
  });

  group('decode', () {
    test('extracts the base64 raster, tolerating whitespace', () {
      final b64 = base64Encode(tinyPng);
      final spaced = '${b64.substring(0, 10)}\n  ${b64.substring(10)}';
      final data = GuidelineVisualRepository.decode(
        '<svg><image xlink:href="data:image/jpeg;base64,$spaced"/></svg>',
      );

      expect(data.raster, tinyPng);
    });

    test('falls back to the SVG when nothing is embedded', () {
      const plain = '<svg><rect width="1" height="1"/></svg>';
      final data = GuidelineVisualRepository.decode(plain);

      expect(data.raster, isNull);
      expect(data.svg, plain);
    });
  });
}
