import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_state.dart';
import '../../core/config/app_config.dart';
import '../../core/constants/app_strings.dart';
import '../../core/sync/offline_sync_service.dart';
import '../../core/sync/sync_connectivity_service.dart';
import '../../core/sync/sync_report.dart';
import '../../core/auth/user_hierarchy_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_version_label.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.fromLock = false});

  final bool fromLock;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _userCtl = TextEditingController();
  final _passCtl = TextEditingController();
  bool _obscurePassword = true;
  String? _bannerMessage;

  @override
  void initState() {
    debugPrint('[_LoginScreenState] initState');
    super.initState();
    final auth = context.read<AuthState>();
    final last = auth.username;
    if (last != null) {
      _userCtl.text = last;
    }
    debugPrint(
      '[_LoginScreenState] cachedUsername=${last == null ? 'null (field editable)' : '"$last" (field locked)'}',
    );
    // Capture and clear any pending auth error (e.g. session expired) so it
    // shows as a persistent banner rather than a dismissible snackbar.
    final pending = auth.error;
    if (pending != null) {
      _bannerMessage = pending;
      auth.clearError();
    }
  }

  @override
  void dispose() {
    debugPrint('[_LoginScreenState] dispose');
    _userCtl.dispose();
    _passCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    debugPrint('[_LoginScreenState] _submit username=${_userCtl.text.trim()}');
    if (!_formKey.currentState!.validate()) {
      debugPrint('[_LoginScreenState] _submit: form validation failed');
      return;
    }
    final username = _userCtl.text.trim();
    if (!mounted) return;

    final auth = context.read<AuthState>();
    debugPrint('[_LoginScreenState] _submit: calling auth.login…');
    final ok = await auth.login(username, _passCtl.text);
    debugPrint('[_LoginScreenState] _submit: auth.login → ok=$ok error=${auth.error}');
    if (!mounted) return;
    if (ok) {
      final sync = context.read<OfflineSyncService>();
      final skipLoginSync =
          auth.sameUserRelogin && await sync.lastSyncedAt() != null;

      // Prefetch user hierarchy (saves upazila + durable SS/village cache) so
      // enrollment dropdowns work offline after process death / PIN unlock.
      context
          .read<UserHierarchyService>()
          .prefetch(forceRefresh: true)
          .ignore();
      debugPrint('[_LoginScreenState] post-login: onboardingComplete=${auth.onboardingComplete} pinEnabled=${auth.pinEnabled} biometricEnabled=${auth.biometricEnabled} sameUserRelogin=${auth.sameUserRelogin} skipLoginSync=$skipLoginSync');
      if (skipLoginSync) {
        // UHIS parity: ResourceLoadingScreen skips download when
        // SERVER_LAST_SYNCED exists — go straight to home; LandingActivity
        // then runs ScheduledSyncWork (push + delta fetch). Mirror that here.
        debugPrint('[_LoginScreenState] returning user with sync cursor → /home');
        context.read<SyncConnectivityService>().syncIfSessionReady();
        context.go('/home');
      } else if (!auth.onboardingComplete && !auth.pinEnabled) {
        // New user — kick off sync in background immediately so data arrives
        // while they complete PIN setup, then go to onboarding. A wiping
        // full sync is only correct for a genuinely new device/user; if this
        // is actually the same SK re-authenticating (e.g. onboarding was
        // interrupted after a session-expiry relogin), defer to /sync's own
        // push-then-incremental-delta sequence instead — see the else-if
        // below for why that path isn't safe to shortcut in the background.
        debugPrint(
          '[_LoginScreenState] new user → background sync + /onboarding '
          '(sameUserRelogin=${auth.sameUserRelogin})',
        );
        if (!auth.sameUserRelogin) {
          _startBackgroundColdSync(context, sameUser: false);
        }
        context.go('/onboarding');
      } else if (!auth.pinEnabled && !auth.biometricEnabled) {
        // Returning user with no security enrolled (e.g. pre-PIN-mandate accounts).
        // Re-enter onboarding so user sees the "Set up security / Skip" choice.
        //
        // Only fire the background head start for a genuinely new
        // device/user. If this is the same SK re-authenticating after a
        // session-expiry sign-out (auth.sameUserRelogin), a wiping
        // coldSync() here would discard local data and force a full resync
        // for what should be an incremental change sync — SyncProgressScreen
        // already does the correct push-pending-work-then-reloginSync()
        // sequence once /sync is reached (sync_progress_screen.dart:136-170);
        // let that run in the foreground rather than racing it with a
        // background call that skips the push step.
        debugPrint(
          '[_LoginScreenState] returning user, no security → /onboarding '
          '(sameUserRelogin=${auth.sameUserRelogin})',
        );
        if (!auth.sameUserRelogin) {
          _startBackgroundColdSync(context, sameUser: false);
        }
        context.go('/onboarding');
      } else {
        // Returning user with PIN or biometric — go to sync screen as normal.
        debugPrint('[_LoginScreenState] returning user → /sync');
        context.go('/sync');
      }
    } else {
      final msg = auth.error ?? LoginStrings.loginFailed;
      final isOffline = msg.contains('internet') || msg.contains('timed out');
      final hasPinOrBio =
          auth.pinEnabled || (auth.biometricEnabled && auth.biometricAvailable);
      final isSessionExpired = _bannerMessage?.contains('expired') ?? false;
      if (isOffline && hasPinOrBio && !isSessionExpired) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LoginStrings.offlineUsePinHint),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: auth.pinEnabled
                  ? PinStrings.usePinShort
                  : LoginStrings.useDeviceUnlock,
              onPressed: () {
                if (auth.pinEnabled) {
                  context.go('/pin-unlock');
                } else {
                  context.go('/lock');
                }
              },
            ),
          ),
        );
      } else if (isOffline && isSessionExpired) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LoginStrings.sessionExpiredNeedOnline),
            duration: const Duration(seconds: 6),
          ),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  /// Fire-and-forget sync started right after login so data arrives while the
  /// user completes onboarding/PIN setup. Deliberately not awaited — callers
  /// attach to this in-flight sync on [SyncProgressScreen] instead of
  /// restarting it. Uses incremental sync for a returning SK (UHIS parity).
  void _startBackgroundColdSync(BuildContext context, {required bool sameUser}) {
    final sync = context.read<OfflineSyncService>();
    final Future<SyncReport> future = sameUser
        ? sync.reloginSync()
        : sync.coldSync(wipeBeforeSync: true);
    future.then((report) {
      debugPrint(
        '[_LoginScreenState] background coldSync done: '
        'households=${report.households} members=${report.members} '
        'patients=${report.patients} errors=${report.errors}',
      );
    }).catchError((Object e) {
      debugPrint('[_LoginScreenState] background coldSync failed: $e');
    });
  }

  @override
  Widget build(BuildContext context) {
    // Use select to only rebuild on specific field changes
    final showBio = context.select<AuthState, bool>(
      (a) => a.biometricEnabled && a.biometricAvailable,
    );
    final showPin = context.select<AuthState, bool>((a) => a.pinEnabled);
    final busy = context.select<AuthState, bool>((a) => a.busy);
    // A cached username means this device is bound to one SK (UHIS parity —
    // username field locked after first login). Explicit logout keeps
    // lastUsername on disk so the field stays prefilled and offline login
    // continues to work.
    final cachedUsername = context.select<AuthState, String?>((a) => a.username);
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 32),
                        Center(
                          child: SvgPicture.asset(
                            // Foreground-only layer (no card/background fill,
                            // unlike leapwell-icon.svg) — bare mark for the
                            // login header.
                            'assets/images/leapwell-icon-foreground.svg',
                            width: 88,
                            height: 88,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            AppStrings.appName,
                            style: AppTextStyles.brandWordmark.copyWith(
                              fontSize:
                                  27.2, // 32 * 0.85 — brief asked for -15%
                              color: AppColors.pink,
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        if (_bannerMessage != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .errorContainer
                                  .withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 18,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onErrorContainer,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _bannerMessage!,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onErrorContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (widget.fromLock && _bannerMessage == null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .secondaryContainer
                                  .withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              LoginStrings.fromLockBanner,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        if (showBio || showPin) ...[
                          if (showBio)
                            OutlinedButton.icon(
                              onPressed: busy
                                  ? null
                                  : () => context.go('/lock'),
                              icon: const Icon(Icons.fingerprint),
                              label: Text(LoginStrings.useDeviceUnlock),
                            ),
                          if (showPin) ...[
                            if (showBio) const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: busy
                                  ? null
                                  : () => context.go('/pin-unlock'),
                              icon: const Icon(Icons.pin_outlined),
                              label: Text(
                                PinStrings.usePin(AppConfig.pinLength),
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Expanded(child: Divider()),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: Text(CommonStrings.or),
                              ),
                              const Expanded(child: Divider()),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextFormField(
                          controller: _userCtl,
                          enabled: cachedUsername == null,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText: LoginStrings.usernameLabel,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AppRadius.field,
                              ),
                            ),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? CommonStrings.required
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passCtl,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: LoginStrings.passwordLabel,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AppRadius.field,
                              ),
                            ),
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword
                                  ? LoginStrings.showPasswordTooltip
                                  : LoginStrings.hidePasswordTooltip,
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                          ),
                          validator: (v) => (v == null || v.isEmpty)
                              ? CommonStrings.required
                              : null,
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: busy ? null : _submit,
                          child: busy
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(LoginStrings.signIn),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: busy
                                ? null
                                : () => context.push('/forgot-password'),
                            child: Text(LoginStrings.forgotPassword),
                          ),
                        ),
                        // Medtronic Labs branding + logo temporarily hidden.
                        // const SizedBox(height: 48),
                        // Column(
                        //   children: [
                        //     Text(
                        //       AppStrings.poweredBy,
                        //       style: Theme.of(context).textTheme.bodySmall
                        //           ?.copyWith(
                        //             color: Theme.of(
                        //               context,
                        //             ).colorScheme.onSurfaceVariant,
                        //           ),
                        //       textAlign: TextAlign.center,
                        //     ),
                        //     const SizedBox(height: 8),
                        //     Image.asset(
                        //       'assets/images/medtronic-labs-logo.png',
                        //       height: 32,
                        //       fit: BoxFit.contain,
                        //       semanticLabel: 'Medtronic Labs logo',
                        //     ),
                        //   ],
                        // ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: AppSpacing.h6xl,
            bottom: AppSpacing.md,
            child: SafeArea(top: false, child: const AppVersionLabel()),
          ),
        ],
      ),
    );
  }
}
