import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_state.dart';
import '../../core/config/app_config.dart';
import '../../core/constants/app_strings.dart';

/// First-login onboarding screen that asks the user whether they want to
/// enable biometric authentication and set up a fallback PIN.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _busy = false;

  Future<void> _setupSecurity() async {
    setState(() => _busy = true);
    final auth = context.read<AuthState>();

    // Try to enable biometric if available and supported
    if (auth.biometricAvailable) {
      try {
        await auth.enrolBiometric();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(DashboardStrings.deviceUnlockEnabled),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(OnboardingStrings.biometricSetupFailed),
            ),
          );
        }
      }
    }

    // Mark onboarding as complete and go to PIN setup
    await auth.markOnboardingComplete();
    if (!mounted) return;

    // Navigate to PIN setup (mandatory step)
    context.go('/pin-setup');
  }

  Future<void> _skipSetup() async {
    // Show confirmation alert
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(OnboardingStrings.skipConfirmTitle),
        content: const Text(OnboardingStrings.skipConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(OnboardingStrings.cancelButton),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(OnboardingStrings.skipAnywayButton),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final auth = context.read<AuthState>();
    setState(() => _busy = true);

    // Mark onboarding as complete, skip biometric and PIN
    await auth.markOnboardingComplete();
    await auth.markBiometricOffered();

    if (!mounted) return;

    // Go directly to home (sync already done before onboarding)
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final biometricAvailable = context.select<AuthState, bool>((a) => a.biometricAvailable);

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxHeight < 550;

              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: isCompact ? 16 : 32,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight -
                        (isCompact ? 32 : 64), // Account for padding
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/images/app-logo-name.png',
                        height: isCompact ? 48 : 64,
                        fit: BoxFit.contain,
                        semanticLabel: 'UHIS logo',
                      ),
                      SizedBox(height: isCompact ? 24 : 40),
                      Icon(
                        Icons.security_rounded,
                        size: isCompact ? 56 : 72,
                        color: scheme.primary,
                      ),
                      SizedBox(height: isCompact ? 16 : 24),
                      Text(
                        OnboardingStrings.title,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        OnboardingStrings.subtitle,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: isCompact ? 24 : 32),
                      _FeatureCard(
                        icon: Icons.fingerprint,
                        title: OnboardingStrings.biometricFeatureTitle,
                        description: biometricAvailable
                            ? OnboardingStrings.biometricFeatureDesc
                            : OnboardingStrings.biometricNotAvailable,
                        available: biometricAvailable,
                      ),
                      const SizedBox(height: 12),
                      _FeatureCard(
                        icon: Icons.pin_outlined,
                        title: OnboardingStrings.pinFeatureTitle(
                            AppConfig.pinLength),
                        description: OnboardingStrings.pinFeatureDesc,
                        available: true,
                      ),
                      SizedBox(height: isCompact ? 24 : 40),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _setupSecurity,
                          icon: _busy
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.shield_outlined),
                          label: Text(OnboardingStrings.setupButton),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: _busy ? null : _skipSetup,
                          child: Text(OnboardingStrings.skipButton),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        OnboardingStrings.pinRequiredNote,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.available,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool available;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: available ? scheme.outlineVariant : scheme.outline,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: available
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: available ? scheme.onPrimaryContainer : scheme.outline,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: available ? null : scheme.outline,
                            ),
                      ),
                    ),
                    if (!available)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          OnboardingStrings.notAvailable,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: scheme.outline,
                                  ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
