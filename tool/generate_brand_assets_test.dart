// One-off asset generator, not part of the regular test suite (lives outside
// test/ so a plain `flutter test` run skips it). Rasterizes the LEAPWELL logo
// SVGs to every PNG the Android launcher icon and Play Store listing need.
// Re-run with `flutter test tool/generate_brand_assets_test.dart` whenever
// the source SVGs in assets/images/ change.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/core/theme/app_theme.dart';

// flutter_test renders every Text widget with a placeholder tofu-box glyph
// unless the real font is registered via FontLoader first — needed for the
// feature graphic, the only capture with real text on it.
Future<void> _loadFont(String family, String assetPath) async {
  final loader = FontLoader(family);
  loader.addFont(rootBundle.load(assetPath));
  await loader.load();
}

// Mirrors _SplashScreenState._badges in lib/app/router.dart — duplicated here
// because that list is private to the splash screen; this is a build-time-only
// tool, not shipped app code.
const _badges = [
  'AI Triage', 'On-device CDSS', 'Teleconsult', 'Offline-first', 'WhatsApp',
];

class _CaptureJob {
  _CaptureJob(this.outPath, this.width, this.height, this.builder);
  final String outPath;
  final double width;
  final double height;
  final Widget Function() builder;
}

Widget _icon() =>
    SvgPicture.asset('assets/images/leapwell-icon.svg', fit: BoxFit.contain);

Widget _iconForeground() => SvgPicture.asset(
  'assets/images/leapwell-icon-foreground.svg',
  fit: BoxFit.contain,
);

Widget _badge(String label) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
  decoration: BoxDecoration(
    border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
    borderRadius: BorderRadius.circular(20),
  ),
  child: Text(
    label,
    style: TextStyle(
      fontFamily: AppFonts.body,
      fontSize: 14,
      fontWeight: FontWeight.w800,
      color: Colors.white.withValues(alpha: 0.85),
    ),
  ),
);

Widget _featureGraphic() => Container(
  color: AppColors.navy,
  padding: const EdgeInsets.all(48),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Container(
        width: 176,
        height: 176,
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(36),
          boxShadow: [
            BoxShadow(
              color: AppColors.pink.withValues(alpha: 0.45),
              blurRadius: 40,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Padding(padding: const EdgeInsets.all(22), child: _icon()),
      ),
      const SizedBox(width: 40),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'LEAPWELL',
              style: TextStyle(
                fontFamily: AppFonts.display,
                fontSize: 56,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Apon Sushashthya',
              style: TextStyle(
                fontFamily: AppFonts.body,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.pink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'আপন সুস্বাস্থ্য',
              style: TextStyle(
                fontFamily: 'NotoSansBengali',
                fontSize: 18,
                color: Colors.white.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: 560,
              child: Text(
                'AI-powered community health for every household in Bangladesh',
                style: TextStyle(
                  fontFamily: AppFonts.body,
                  fontSize: 16,
                  color: Colors.white.withValues(alpha: 0.65),
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: _badges.map(_badge).toList(),
            ),
          ],
        ),
      ),
    ],
  ),
);

List<_CaptureJob> _buildJobs() {
  const androidRes = 'android/app/src/main/res';
  final jobs = <_CaptureJob>[];

  // Legacy flat launcher icon (pre-Android-8 devices without adaptive icon
  // support). The native pre-engine splash bitmap is no longer generated
  // here — Android 12+ ignores a custom windowBackground drawable for the
  // cold-start splash, so that's now handled by the AndroidX SplashScreen
  // API (see android/app/src/main/res/values/styles.xml), which reuses
  // @mipmap/ic_launcher_foreground generated below instead of its own asset.
  for (final entry in <String, double>{
    '$androidRes/mipmap-mdpi/ic_launcher.png': 48,
    '$androidRes/mipmap-hdpi/ic_launcher.png': 72,
    '$androidRes/mipmap-xhdpi/ic_launcher.png': 96,
    '$androidRes/mipmap-xxhdpi/ic_launcher.png': 144,
    '$androidRes/mipmap-xxxhdpi/ic_launcher.png': 192,
  }.entries) {
    jobs.add(_CaptureJob(entry.key, entry.value, entry.value, _icon));
  }

  // Adaptive icon foreground — mark only, padded to Android's ~66% safe
  // zone within the standard 108dp-equivalent adaptive icon canvas.
  for (final entry in <String, double>{
    '$androidRes/mipmap-mdpi/ic_launcher_foreground.png': 108,
    '$androidRes/mipmap-hdpi/ic_launcher_foreground.png': 162,
    '$androidRes/mipmap-xhdpi/ic_launcher_foreground.png': 216,
    '$androidRes/mipmap-xxhdpi/ic_launcher_foreground.png': 324,
    '$androidRes/mipmap-xxxhdpi/ic_launcher_foreground.png': 432,
  }.entries) {
    final canvas = entry.value;
    final safeZone = canvas * 0.66;
    jobs.add(
      _CaptureJob(
        entry.key,
        canvas,
        canvas,
        () => Center(
          child: SizedBox(
            width: safeZone,
            height: safeZone,
            child: _iconForeground(),
          ),
        ),
      ),
    );
  }

  // Play Store listing assets.
  jobs.add(_CaptureJob('store_assets/hi_res_icon.png', 512, 512, _icon));
  jobs.add(
    _CaptureJob(
      'store_assets/feature_graphic.png',
      1024,
      500,
      _featureGraphic,
    ),
  );

  return jobs;
}

void main() {
  // Each capture gets its own testWidgets — reusing one WidgetTester across
  // multiple pumpWidget calls in a single test body hangs (flutter_svg's
  // internal picture cache/listenable teardown from the previous pumpWidget
  // never resolves under flutter_test's fake-async clock), so a fresh test
  // lifecycle per asset sidesteps it entirely.
  setUpAll(() async {
    await _loadFont('Nunito', 'assets/fonts/Nunito-Variable.ttf');
    await _loadFont('NunitoSans', 'assets/fonts/NunitoSans-Variable.ttf');
    await _loadFont('NotoSansBengali', 'assets/fonts/NotoSansBengali-Variable.ttf');
  });

  for (final job in _buildJobs()) {
    testWidgets('generate ${job.outPath}', (tester) async {
      // flutter_test's default test view is only 800x600 — Center gives its
      // child loose constraints, but "loose" still caps at the view size, so
      // any job bigger than 800x600 was silently clamped (feature_graphic.png
      // came out 800x500 instead of 1024x500). Match the view to the job.
      tester.view.physicalSize = Size(job.width, job.height);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: job.width,
                height: job.height,
                child: job.builder(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(job.outPath);
      // Sync I/O, not async: flutter_test's fake-async zone never drives
      // real dart:io async completion callbacks, so awaited
      // File.create/writeAsBytes hang forever — the sync variants block
      // the isolate directly instead of depending on that event loop.
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(byteData!.buffer.asUint8List());
      // ignore: avoid_print
      print(
        'wrote ${job.outPath} (${job.width.toInt()}x${job.height.toInt()})',
      );
    }, timeout: const Timeout(Duration(seconds: 30)));
  }

  // The SVG decoder leaves a lingering isolate that keeps flutter_test's
  // teardown from completing — all files are already written by this point,
  // so hard-exit rather than hang waiting for a clean shutdown.
  tearDownAll(() => exit(0));
}
