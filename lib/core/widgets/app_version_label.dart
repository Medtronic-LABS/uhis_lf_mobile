import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../constants/app_strings.dart';
import '../theme/app_theme.dart';

/// Small muted "v{versionName}" label. Reads the running build's version
/// from the platform package info — pubspec.yaml's `version:` field is the
/// single source of truth, so this never drifts from what's installed.
class AppVersionLabel extends StatefulWidget {
  const AppVersionLabel({super.key});

  @override
  State<AppVersionLabel> createState() => _AppVersionLabelState();
}

class _AppVersionLabelState extends State<AppVersionLabel> {
  String? _version;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = info.version);
    });
  }

  @override
  Widget build(BuildContext context) {
    final version = _version;
    if (version == null) return const SizedBox.shrink();
    return Text(
      CommonStrings.versionLabel(version),
      style: TextStyle(
        fontFamily: AppFonts.body,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColors.textDisabled,
      ),
    );
  }
}
