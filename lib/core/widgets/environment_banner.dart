import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../constants/app_strings.dart';
import '../theme/app_theme.dart';

/// Persistent top-of-screen warning shown on every route of the "LW
/// Training" build (AppConfig.isTrainingBuild) so it's never mistaken for
/// production — wired into MaterialApp.router's `builder:` in `main.dart`
/// so it wraps every screen with a single insertion point.
///
/// Renders nothing on the production build.
class EnvironmentBanner extends StatelessWidget {
  const EnvironmentBanner({super.key});

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.showEnvironmentBanner) return const SizedBox.shrink();

    return SafeArea(
      bottom: false,
      // Material, not Container: the banner sits above every route (outside any
      // Scaffold), and Text without a Material ancestor renders with Flutter's
      // yellow "missing Material" underline.
      child: Material(
        color: AppColors.trainingBanner,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Text(
            CommonStrings.trainingBannerMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.trainingBannerText,
              fontSize: 11,
              height: 1.2,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}
