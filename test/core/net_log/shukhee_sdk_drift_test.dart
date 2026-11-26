import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _dioConstruction = r'\bDio\s*\(';
const _hint =
    'A second Dio in shukhee_sdk would bypass the network log. '
    'Attach NetworkLogInterceptor to it (or inject our Dio) before shipping.';

Directory _sdkLibDir() {
  final config = File('.dart_tool/package_config.json');
  if (!config.existsSync()) {
    fail('.dart_tool/package_config.json is missing; run `flutter pub get`.');
  }
  final packages =
      (jsonDecode(config.readAsStringSync())
              as Map<String, dynamic>)['packages']
          as List<dynamic>;
  final entry = packages.cast<Map<String, dynamic>>().where(
    (p) => p['name'] == 'shukhee_sdk',
  );
  if (entry.isEmpty) fail('shukhee_sdk is not in package_config.json.');
  var root = entry.first['rootUri'] as String;
  if (!root.endsWith('/')) root = '$root/';
  final rootUri = config.absolute.uri.resolve(root);
  final lib = Directory.fromUri(
    rootUri.resolve((entry.first['packageUri'] as String?) ?? 'lib/'),
  );
  if (!lib.existsSync()) fail('shukhee_sdk lib dir not found at ${lib.path}.');
  return lib;
}

String _stripComments(String src) =>
    src.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

void main() {
  test('shukhee_sdk builds exactly one Dio, as the injected-Dio default', () {
    final lib = _sdkLibDir();
    final sites = <String>[];
    for (final f in lib.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final n = RegExp(
        _dioConstruction,
      ).allMatches(_stripComments(f.readAsStringSync())).length;
      if (n > 0) sites.add('${f.path} x$n');
    }
    final clientPath = '${lib.path}/src/shukhee_client.dart';
    expect(
      File(clientPath).existsSync(),
      isTrue,
      reason: 'lib/src/shukhee_client.dart moved. $_hint',
    );
    expect(
      sites,
      hasLength(1),
      reason: 'Expected one Dio( in the SDK, found $sites. $_hint',
    );
    expect(
      sites.single,
      endsWith('src/shukhee_client.dart x1'),
      reason: 'The only Dio( must be in shukhee_client.dart. $_hint',
    );
    final src = _stripComments(File(clientPath).readAsStringSync());
    expect(
      RegExp(r'\bdio\s*\?\?\s*Dio\s*\(').hasMatch(src),
      isTrue,
      reason:
          'The SDK Dio must stay the `dio ?? Dio(` default so our '
          'injected Dio is used. $_hint',
    );
  });
}
