// Live on-device OCR check for the NID scanner against real card photos.
//
// Not part of the normal suite — a manual harness. Push sample cards first:
//   adb shell mkdir -p /sdcard/Android/data/com.medtroniclabs.uhis_next/files/nid_samples
//   adb push "<card>.jpg" /sdcard/Android/data/com.medtroniclabs.uhis_next/files/nid_samples/
// then run:
//   flutter test integration_test/nid_ocr_live_test.dart -d <device>
//
// It runs the real ML Kit pipeline (extractNidFromImage) on each pushed image
// and prints the extracted fields so we can eyeball accuracy on genuine cards.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uhis_next/features/household/enrollment/nid_ocr_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('OCR every pushed NID sample and print the extracted fields', () async {
    final base = await getExternalStorageDirectory();
    final dir = Directory('${base!.path}/nid_samples');
    // Opt-in harness: skip cleanly (never fail CI) when no samples were pushed.
    // `flutter test` reinstalls the app and wipes this dir, so push the cards
    // AFTER install and run this test without a rebuild.
    if (!dir.existsSync()) {
      markTestSkipped('no nid_samples pushed to ${dir.path}');
      return;
    }
    final images = dir
        .listSync()
        .whereType<File>()
        .where((f) => RegExp(r'\.(jpe?g|png)$', caseSensitive: false)
            .hasMatch(f.path))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    if (images.isEmpty) {
      markTestSkipped('no images in ${dir.path}');
      return;
    }

    final ocr = NidOcrService();
    for (final img in images) {
      final result = await ocr.extractNidFromImage(img.path);
      final d = result.data;
      // ignore: avoid_print
      print('── ${img.uri.pathSegments.last}\n'
          '   status : ${result.status.name}\n'
          '   name   : ${d?.name ?? '(none)'}\n'
          '   dob    : ${d?.dateOfBirth ?? '(none)'}\n'
          '   nid    : ${d?.nidNumber ?? '(none)'}\n'
          '   gender : ${d?.gender?.label ?? '(none)'}');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
