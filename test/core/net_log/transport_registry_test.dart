import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'transport_registry.dart';

const _register =
    'Attach the network log to this transport '
    '(ApiClient.attachNetworkLog / NetworkLogInterceptor.attach) and register '
    'the site in test/core/net_log/transport_registry.dart.';

final _httpCall = RegExp(r'http\.(get|post|put|delete|Client|Request)\(');

String stripComments(String src) =>
    src.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

/// (file | pattern) -> match count, for one source file.
Map<String, int> scanSource(String file, String src) {
  final code = stripComments(src);
  final found = <String, int>{};
  for (final p in transportPatterns) {
    final n = RegExp(p).allMatches(code).length;
    if (n > 0) found['$file | $p'] = n;
  }
  return found;
}

Map<String, int> scanLib() {
  final found = <String, int>{};
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));
  for (final f in files) {
    found.addAll(scanSource(f.path, f.readAsStringSync()));
  }
  return found;
}

/// Human-readable differences between a scan and a registry; empty when equal.
List<String> diffAgainst(
  Map<String, int> scanned,
  Iterable<TransportEntry> registry,
) {
  final expected = {for (final e in registry) e.key: e.count};
  final problems = <String>[];
  for (final k in {...scanned.keys, ...expected.keys}) {
    final s = scanned[k], e = expected[k];
    if (s == e) continue;
    final file = k.split(' | ').first;
    problems.add(
      e == null
          ? '$file has $s unregistered transport(s) [$k]. $_register'
          : s == null
          ? '$file no longer has the registered transport [$k]; '
                'remove the entry from the registry.'
          : '$file has $s site(s) but the registry says $e [$k]. $_register',
    );
  }
  return problems;
}

/// Text inside the balanced parentheses opening at [open].
String? callArgs(String src, int open) {
  var depth = 0;
  String? quote;
  for (var i = open; i < src.length; i++) {
    final c = src[i];
    if (quote != null) {
      if (c == r'\') {
        i++;
      } else if (c == quote) {
        quote = null;
      }
      continue;
    }
    if (c == "'" || c == '"') {
      quote = c;
    } else if (c == '(') {
      depth++;
    } else if (c == ')' && --depth == 0) {
      return src.substring(open + 1, i);
    }
  }
  return null;
}

/// Text before a construction call that marks it as a call, not a declaration.
final _callContext = RegExp(r'(=|\(|,|\?|:|=>|\breturn|\bawait|\bnew)$');

/// Argument text of every call to [name]. A match is a declaration (skipped)
/// unless the text before it ends in an operator that introduces an
/// expression, so `cond ? Foo(x) : null` is still a call.
List<({String file, String args})> callsOf(
  String name,
  Map<String, String> sources,
) {
  final re = RegExp('(?<![A-Za-z0-9_])$name\\(');
  final calls = <({String file, String args})>[];
  sources.forEach((file, src) {
    final code = stripComments(src);
    for (final m in re.allMatches(code)) {
      if (!_callContext.hasMatch(code.substring(0, m.start).trimRight())) {
        continue;
      }
      final args = callArgs(code, m.end - 1);
      if (args != null) calls.add((file: file, args: args));
    }
  });
  return calls;
}

/// First positional argument is the ApiClient (`api`, `widget.api`, ...).
final apiArg = RegExp(r'^\s*(widget\.)?(api|apiClient)\s*(,|$)');
final contextArg = RegExp(r'^\s*context\s*(,|$)');

/// Missing or too-rare evidence for [e] in [src] (comment-stripped).
List<String> evidenceProblems(TransportEntry e, String src) {
  final code = stripComments(src);
  final file = e.evidenceFile ?? e.file;
  final problems = <String>[];
  final main = e.evidenceToken ?? e.kind.evidenceToken;
  final seen = main.allMatches(code).length;
  if (seen < e.minEvidence) {
    problems.add(
      '$file (${e.kind.name}) has "$main" $seen time(s), needs '
      '${e.minEvidence}. ${e.reason}. $_register',
    );
  }
  for (final t in e.extraEvidence) {
    if (!code.contains(t)) {
      problems.add(
        '$file (${e.kind.name}) lacks "$t". ${e.reason}. $_register',
      );
    }
  }
  return problems;
}

/// Calls of [name] whose arguments do not match [mustHave].
List<String> callsMissing(
  String name,
  Map<String, String> sources,
  Pattern mustHave,
) {
  return [
    for (final c in callsOf(name, sources))
      if (!c.args.contains(mustHave))
        '${c.file}: $name( call has no $mustHave argument; a dropped '
            'argument silently stops logging for that client. $_register',
  ];
}

Map<String, String> readLib() => {
  for (final f
      in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
    f.path: f.readAsStringSync(),
};

String read(String path) {
  final f = File(path);
  if (!f.existsSync()) fail('$path is missing; update the registry.');
  return f.readAsStringSync();
}

void main() {
  test('every transport in lib/ is registered', () {
    final problems = diffAgainst(scanLib(), transportRegistry);
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('each registered file carries its coverage evidence', () {
    final missing = <String>[
      for (final e in transportRegistry)
        ...evidenceProblems(e, read(e.evidenceFile ?? e.file)),
    ];
    expect(missing, isEmpty, reason: missing.join('\n'));
  });

  test('eval_fhir_uploader stays inert: no package:http request calls', () {
    final src = stripComments(
      read('lib/features/visit/eval/eval_fhir_uploader.dart'),
    );
    expect(
      _httpCall.hasMatch(src),
      isFalse,
      reason:
          'eval_fhir_uploader.dart now makes an http request. '
          '$_register',
    );
  });

  group('client construction passes the recorder', () {
    final sources = readLib();

    for (final name in [
      'CallLogSyncClient',
      'FrappeClient',
      'ShukheeEncounterLinkClient',
      'ShukheeConsentClient',
    ]) {
      test('$name( receives networkRecorder', () {
        expect(
          callsOf(name, sources),
          isNotEmpty,
          reason: 'no $name( construction found; update this guard',
        );
        final bad = callsMissing(name, sources, 'networkRecorder');
        expect(bad, isEmpty, reason: bad.join('\n'));
      });
    }

    test('factories get their recorder from the ApiClient they are given', () {
      for (final f in {
        'buildFrappeAiClient': 'lib/core/api/frappe_client.dart',
        'buildShukheeConsentClient':
            'lib/features/teleconsult/shukhee_consent_client.dart',
      }.entries) {
        expect(
          stripComments(read(f.value)),
          contains('networkRecorder: '),
          reason:
              '${f.key} must pass networkRecorder to its client. '
              '$_register',
        );
      }
      expect(callsOf('buildFrappeAiClient', sources), isNotEmpty);
      final bad = [
        ...callsMissing('buildFrappeAiClient', sources, apiArg),
        ...callsMissing('buildShukheeConsentClient', sources, contextArg),
      ];
      expect(bad, isEmpty, reason: bad.join('\n'));
    });

    test('main.dart hands ApiClient to services that attach the log', () {
      final main = {'lib/main.dart': sources['lib/main.dart']!};
      for (final f in {
        'ScribeApiService': 'lib/core/api/scribe_api_service.dart',
        'UserHierarchyService': 'lib/core/auth/user_hierarchy_service.dart',
        'AssistantRepository':
            'lib/features/assistant/assistant_repository.dart',
      }.entries) {
        expect(
          callsOf(f.key, main),
          isNotEmpty,
          reason: 'no ${f.key}( in main.dart; update this guard',
        );
        final bad = callsMissing(f.key, main, apiArg);
        expect(bad, isEmpty, reason: bad.join('\n'));
        expect(
          stripComments(read(f.value)),
          contains('attachNetworkLog('),
          reason: '${f.value} must attach the network log. $_register',
        );
      }
    });
  });

  group('the guard guards itself', () {
    test('scanner reports an unregistered Dio( in a fixture', () {
      final scanned = scanSource(
        'lib/fake/new_client.dart',
        'final d = Dio(BaseOptions());\n// Dio( in a comment\n',
      );
      final problems = diffAgainst(scanned, const []);
      expect(problems, hasLength(1));
      expect(problems.single, contains('lib/fake/new_client.dart'));
      expect(problems.single, contains('register'));
    });

    for (final snippet in const [
      'final make = Dio.new;',
      'final s = WebSocket.connect(url);',
      'final c = HttpClient(context: ctx);',
      'class MyDio extends DioMixin {}',
      'class MyDio extends DioForNative {}',
    ]) {
      test('scanner reports a transport hidden as: $snippet', () {
        expect(scanSource('lib/fake/x.dart', snippet), isNotEmpty);
      });
    }

    test('removing a registry entry produces a diff', () {
      final trimmed = transportRegistry.skip(1).toList();
      final problems = diffAgainst({
        for (final e in transportRegistry) e.key: e.count,
      }, trimmed);
      expect(problems, hasLength(1));
      expect(problems.single, contains(transportRegistry.first.file));
    });

    test('call extraction handles nesting and flags a missing recorder', () {
      const ok = 'x = CallLogSyncClient(a: f(g(1)), networkRecorder: r(2));';
      const bad = 'x = CallLogSyncClient(a: f(g(1)), b: h(2));';
      const decl = 'CallLogSyncClient({required this.a}) {}';
      expect(
        callsOf('CallLogSyncClient', {'ok': ok}).single.args,
        'a: f(g(1)), networkRecorder: r(2)',
      );
      expect(
        callsMissing('CallLogSyncClient', {'ok': ok}, 'networkRecorder'),
        isEmpty,
      );
      expect(
        callsMissing('CallLogSyncClient', {'bad': bad}, 'networkRecorder'),
        hasLength(1),
      );
      expect(callsOf('CallLogSyncClient', {'d': decl}), isEmpty);
    });

    test('an unlogged FrappeClient( construction is reported (I1)', () {
      const bad = 'final c = FrappeClient(baseUrl: x, authTokenProvider: t);';
      const ok =
          'return FrappeClient(baseUrl: b, networkRecorder: api.networkRecorder);';
      expect(
        callsMissing('FrappeClient', {'bad': bad}, 'networkRecorder'),
        hasLength(1),
      );
      expect(
        callsMissing('FrappeClient', {'ok': ok}, 'networkRecorder'),
        isEmpty,
      );
    });

    test('a factory call must pass the ApiClient positionally (I2)', () {
      const wrongWord = 'x = buildFrappeAiClient(baseUrl: api.url);';
      const wrongRead = 'x = buildFrappeAiClient(ctx: context.read<Other>());';
      const good = 'x = buildFrappeAiClient(\n widget.api,\n baseUrl: b);';
      const goodClient = 'x = buildFrappeAiClient(apiClient, baseUrl: b);';
      for (final bad in [wrongWord, wrongRead]) {
        expect(
          callsMissing('buildFrappeAiClient', {'b': bad}, apiArg),
          hasLength(1),
        );
      }
      for (final ok in [good, goodClient]) {
        expect(callsMissing('buildFrappeAiClient', {'o': ok}, apiArg), isEmpty);
      }
      expect(
        callsMissing('buildShukheeConsentClient', {
          'b': 'x = buildShukheeConsentClient(ctx: context.read());',
        }, contextArg),
        hasLength(1),
      );
    });

    test('a conditional construction is still checked (I3)', () {
      const bad = 'final c = cond ? CallLogSyncClient(dio: d) : null;';
      const ok =
          'final c = cond ? CallLogSyncClient(networkRecorder: r) : null;';
      expect(
        callsMissing('CallLogSyncClient', {'bad': bad}, 'networkRecorder'),
        hasLength(1),
      );
      expect(
        callsMissing('CallLogSyncClient', {'ok': ok}, 'networkRecorder'),
        isEmpty,
      );
      const decls =
          'class A {\n  CallLogSyncClient({required this.a}) : b = 1;\n'
          '  factory CallLogSyncClient.x() => y;\n}\n'
          'Foo CallLogSyncClient(int a) {}';
      expect(callsOf('CallLogSyncClient', {'d': decls}), isEmpty);
    });

    test('evidence must appear enough times, outside comments (M4, M5)', () {
      const twoDios = TransportEntry(
        'f.dart',
        r'\bDio\s*\(',
        2,
        CoverageKind.attachNetworkLog,
        'r',
        evidenceToken: 'prepare(tempDio)',
        minEvidence: 2,
      );
      expect(
        evidenceProblems(twoDios, 'prepare(tempDio);\nprepare(tempDio);'),
        isEmpty,
      );
      expect(evidenceProblems(twoDios, 'prepare(tempDio);'), hasLength(1));
      expect(
        evidenceProblems(twoDios, '// prepare(tempDio);\nprepare(tempDio);'),
        hasLength(1),
      );
      const chain = TransportEntry(
        'api_client.dart',
        r'\bDio\s*\(',
        1,
        CoverageKind.apiClientChain,
        'r',
        evidenceToken: 'client.attachNetworkLog(',
      );
      expect(
        evidenceProblems(chain, 'void attachNetworkLog(Dio d) => x(d);'),
        hasLength(1),
      );
      expect(evidenceProblems(chain, 'client.attachNetworkLog(dio);'), isEmpty);
    });
  });
}
