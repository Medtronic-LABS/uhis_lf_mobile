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

  test('a failing clear does not throw into the wipe', () async {
    final wipe = NativeNetworkLogWipe(clear: () async => false);
    wipe.onWipeStarting();
    await Future<void>.delayed(Duration.zero);
  });
}
