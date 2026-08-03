import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uhis_next/core/widgets/app_version_label.dart';

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'LEAPWELL',
      packageName: 'com.medtroniclabs.uhis_next',
      version: '1.0.2',
      buildNumber: '2',
      buildSignature: '',
    );
  });

  testWidgets('shows v{versionName} once package info resolves', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppVersionLabel())),
    );

    expect(find.text('v1.0.2'), findsNothing);
    await tester.pump();

    expect(find.text('v1.0.2'), findsOneWidget);
  });
}
