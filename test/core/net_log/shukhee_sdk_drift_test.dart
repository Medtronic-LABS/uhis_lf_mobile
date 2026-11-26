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

final _dioRe = RegExp(_dioConstruction);
final _injectedDefault = RegExp(r'\bdio\s*\?\?\s*Dio\s*\(');

/// file -> number of `Dio(` constructions, comments stripped; zeros omitted.
Map<String, int> countDioSites(Map<String, String> fileToSource) => {
  for (final e in fileToSource.entries)
    if (_dioRe.allMatches(_stripComments(e.value)).isNotEmpty)
      e.key: _dioRe.allMatches(_stripComments(e.value)).length,
};

/// Problems with the SDK's Dio construction; empty when it is safe.
List<String> driftProblems(Map<String, String> fileToSource) {
  final sites = countDioSites(fileToSource);
  final total = sites.values.fold<int>(0, (a, b) => a + b);
  final problems = <String>[];
  if (total != 1) {
    problems.add('Expected one Dio( in the SDK, found $sites. $_hint');
  }
  final client = fileToSource.entries
      .where((e) => e.key.endsWith('src/shukhee_client.dart'))
      .toList();
  if (client.isEmpty) {
    problems.add('lib/src/shukhee_client.dart moved. $_hint');
  } else {
    if (!sites.keys.any((k) => k.endsWith('src/shukhee_client.dart'))) {
      problems.add('The only Dio( must be in shukhee_client.dart. $_hint');
    }
    if (!_injectedDefault.hasMatch(_stripComments(client.single.value))) {
      problems.add(
        'The SDK Dio must stay the `dio ?? Dio(` default so our injected '
        'Dio is used. $_hint',
      );
    }
  }
  return problems;
}

void main() {
  test('shukhee_sdk builds exactly one Dio, as the injected-Dio default', () {
    final lib = _sdkLibDir();
    final sources = {
      for (final f in lib.listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart')) f.path: f.readAsStringSync(),
    };
    final problems = driftProblems(sources);
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  group('the drift check guards itself', () {
    const ok = 'class C { C(c, {Dio? dio}) : _d = dio ?? Dio(BaseOptions()); }';
    const path = 'sdk/lib/src/shukhee_client.dart';

    test('accepts the injected default', () {
      expect(driftProblems({path: ok}), isEmpty);
    });

    test('reports a second Dio in another file', () {
      final p = driftProblems({
        path: ok,
        'sdk/lib/src/x.dart': 'final d = Dio();',
      });
      expect(p, hasLength(1));
      expect(p.single, contains('bypass the network log'));
    });

    test('reports a Dio not written as `dio ??`', () {
      final p = driftProblems({path: 'final d = Dio(BaseOptions());'});
      expect(p.single, contains('dio ?? Dio('));
    });
  });
}
