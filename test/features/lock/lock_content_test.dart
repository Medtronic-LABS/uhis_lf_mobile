import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/config/app_config.dart';
import 'package:uhis_next/core/constants/app_strings.dart';
import 'package:uhis_next/features/lock/lock_screen.dart';

void main() {
  Widget buildLockContent({
    required bool biometricEnabled,
    required bool pinEnabled,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: LockContent(
          summary: null,
          busy: false,
          failed: false,
          biometricEnabled: biometricEnabled,
          pinEnabled: pinEnabled,
          isOnline: true,
          onUnlock: () {},
          onPinUnlock: () {},
        ),
      ),
    );
  }

  testWidgets('PIN-only lock screen does not show fingerprint action', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildLockContent(biometricEnabled: false, pinEnabled: true),
    );

    expect(find.byIcon(Icons.fingerprint), findsNothing);
    expect(
      find.text(LockStrings.orUsePin(AppConfig.pinLength)),
      findsOneWidget,
    );
  });

  testWidgets('biometric lock screen shows fingerprint action', (tester) async {
    await tester.pumpWidget(
      buildLockContent(biometricEnabled: true, pinEnabled: true),
    );

    expect(find.byIcon(Icons.fingerprint), findsOneWidget);
    expect(find.text(LockStrings.verifyFingerprint), findsOneWidget);
  });
}
