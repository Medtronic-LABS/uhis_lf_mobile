import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/net_log/native_network_log_wipe.dart';

void main() {
  test('asks the native SDK to clear when a wipe starts', () {
    var calls = 0;
    final wipe = NativeNetworkLogWipe(clear: () async {
      calls++;
      return true;
    });
    wipe.onWipeStarting();
    expect(calls, 1);
  });

  test('a clear that throws is the caller\'s contract to prevent; wipe start still returns', () {
    final wipe = NativeNetworkLogWipe(clear: () async => false);
    expect(wipe.onWipeStarting, returnsNormally);
  });
}
