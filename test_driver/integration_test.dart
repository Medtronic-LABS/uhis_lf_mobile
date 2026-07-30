import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

const _outDir = 'store_assets/screenshots';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final dir = Directory(_outDir)..createSync(recursive: true);
      File('${dir.path}/$name.png').writeAsBytesSync(bytes);
      return true;
    },
  );
}
