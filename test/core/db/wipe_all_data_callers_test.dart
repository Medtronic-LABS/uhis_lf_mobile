import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `AuthState` has no path to the database, so "logout keeps network_log" is
/// enforced structurally: the only caller of `wipeAllData(` outside its
/// definition is the login-sync path. A future call from the logout path (or
/// anywhere else) fails this test.
void main() {
  test('only offline_sync_service.dart calls wipeAllData', () {
    final callers = <String>{};
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final code = f
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      if (RegExp(r'\.wipeAllData\(').hasMatch(code)) callers.add(f.path);
    }

    expect(callers, {'lib/core/sync/offline_sync_service.dart'});
  });
}
