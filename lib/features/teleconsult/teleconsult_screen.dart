/// Teleconsult placeholder screen.
///
/// Video consultation with a doctor will be available here. The SK can
/// initiate a call directly from a completed visit. This screen is a
/// functional scaffold — no API calls until the feature is wired.
///
/// Engineering Design Standards:
///   - Pure UI — no I/O, no business logic.
///   - All strings from [TeleconsultStrings].
library;

import 'package:flutter/material.dart';

import '../../core/constants/app_strings.dart';
import '../../core/theme/app_theme.dart';

class TeleconsultScreen extends StatelessWidget {
  const TeleconsultScreen({
    super.key,
    required this.patientLabel,
    required this.patientId,
  });

  final String patientLabel;
  final String patientId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text(TeleconsultStrings.title),
        backgroundColor: AppColors.navyDark,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.h6xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ── Video icon ────────────────────────────────────────────
                const Icon(
                  Icons.video_call_rounded,
                  size: 80,
                  color: AppColors.statusInfo,
                ),
                const SizedBox(height: AppSpacing.h6xl),

                // ── Patient label ─────────────────────────────────────────
                Text(
                  patientLabel,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.md),

                // ── Coming soon chip ──────────────────────────────────────
                Chip(
                  label: const Text(TeleconsultStrings.comingSoon),
                  backgroundColor:
                      AppColors.statusInfo.withValues(alpha: 0.15),
                  side: BorderSide.none,
                ),
                const SizedBox(height: AppSpacing.h6xl),

                // ── Placeholder description ───────────────────────────────
                Text(
                  TeleconsultStrings.placeholder,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: AppSpacing.h8xl),

                // ── Disabled action buttons ───────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    // Disabled — API not wired yet.
                    // ignore: avoid_redundant_argument_values
                    onPressed: null,
                    icon: const Icon(Icons.phone_outlined),
                    label: const Text(TeleconsultStrings.callAction),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    // Disabled — API not wired yet.
                    // ignore: avoid_redundant_argument_values
                    onPressed: null,
                    icon: const Icon(Icons.message_outlined),
                    label: const Text(TeleconsultStrings.smsAction),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
