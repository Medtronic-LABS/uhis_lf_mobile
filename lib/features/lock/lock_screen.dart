import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/auth/auth_state.dart';
import '../../core/config/app_config.dart';
import '../../core/constants/app_strings.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _failed = false;
  UserProfileSummary? _summary;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSummary();
      _checkConnectivity();
    });
  }

  Future<void> _checkConnectivity() async {
    try {
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 3));
      if (!mounted) return;
      setState(
        () => _isOnline = result.isNotEmpty && result[0].rawAddress.isNotEmpty,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isOnline = false);
    }
  }

  Future<void> _loadSummary() async {
    if (!mounted) return;
    final auth = context.read<AuthState>();
    final s = await auth.userProfileSummary();
    if (!mounted) return;
    setState(() => _summary = s);
  }

  Future<void> _trigger() async {
    final auth = context.read<AuthState>();
    setState(() => _failed = false);
    final ok = await auth.biometricUnlock();
    if (!mounted) return;
    if (ok) {
      context.go('/home');
    } else if (!auth.biometricEnabled || !auth.biometricAvailable) {
      context.go('/login?from=lock');
    } else {
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.select<AuthState, bool>((a) => a.busy);
    final biometricEnabled = context.select<AuthState, bool>(
      (a) => a.biometricEnabled,
    );
    final biometricAvailable = context.select<AuthState, bool>(
      (a) => a.biometricAvailable,
    );
    final pinEnabled = context.select<AuthState, bool>((a) => a.pinEnabled);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Column(
        children: [
          // ── Dark navy header ────────────────────────────────────────────
          _LockHeader(),
          // ── Scrollable body ─────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: LockContent(
                    summary: _summary,
                    busy: busy,
                    failed: _failed,
                    biometricEnabled: biometricEnabled && biometricAvailable,
                    pinEnabled: pinEnabled,
                    isOnline: _isOnline,
                    onUnlock: _trigger,
                    onPinUnlock: () => context.go('/pin-unlock'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Main content ──────────────────────────────────────────────────────────────

class LockContent extends StatefulWidget {
  const LockContent({
    super.key,
    required this.summary,
    required this.busy,
    required this.failed,
    required this.biometricEnabled,
    required this.pinEnabled,
    required this.isOnline,
    required this.onUnlock,
    required this.onPinUnlock,
  });

  final UserProfileSummary? summary;
  final bool busy;
  final bool failed;
  final bool biometricEnabled;
  final bool pinEnabled;
  final bool isOnline;
  final VoidCallback onUnlock;
  final VoidCallback onPinUnlock;

  @override
  State<LockContent> createState() => _LockContentState();
}

class _LockContentState extends State<LockContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceCtrl;
  late final List<Animation<double>> _slots;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _slots = List.generate(
      6,
      (i) => CurvedAnimation(
        parent: _entranceCtrl,
        curve: Interval(
          (i * 60) / 600,
          ((i * 60) + 240) / 600,
          curve: AppAnimations.standard,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    super.dispose();
  }

  Widget _enter(int slot, Widget child) {
    final anim = _slots[slot];
    return AnimatedBuilder(
      animation: anim,
      child: child,
      builder: (_, c) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - anim.value)),
          child: c,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Pink avatar ────────────────────────────────────────────────
          _enter(
            0,
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.pink,
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.pink.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(Icons.person, size: 54, color: Colors.white),
            ),
          ),
          const SizedBox(height: 28),

          // ── Welcome copy ───────────────────────────────────────────────
          _enter(
            1,
            Column(
              children: [
                Text(
                  LockStrings.welcomeBack,
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: Theme.of(context).colorScheme.onSurface,
                    letterSpacing: -0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  LockStrings.signInToStartYourDay,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── Profile card ───────────────────────────────────────────────
          if (s != null) ...[
            _enter(2, _ProfileCard(summary: s)),
            const SizedBox(height: 20),
          ] else ...[
            const SizedBox(height: 20),
          ],

          // ── Biometric verify button ────────────────────────────────────
          if (widget.biometricEnabled) ...[
            _enter(
              3,
              _FingerprintCard(
                onTap: widget.busy ? () {} : widget.onUnlock,
                busy: widget.busy,
                failed: widget.failed,
              ),
            ),
          ],

          // ── OR + PIN ───────────────────────────────────────────────────
          if (widget.pinEnabled) ...[
            const SizedBox(height: 20),
            _enter(4, const _OrDivider()),
            const SizedBox(height: 16),
            _enter(
              5,
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: widget.onPinUnlock,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.navy,
                    backgroundColor: Colors.white,
                    side: BorderSide(
                      color: AppColors.navy.withValues(alpha: 0.2),
                      width: 1.2,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: 'NunitoSans',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🔢 ', style: TextStyle(fontSize: 16)),
                      Text(LockStrings.orUsePin(AppConfig.pinLength)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Dark navy header (app branding + stepper dots) ────────────────────────────

class _LockHeader extends StatelessWidget {
  const _LockHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.navy,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 20,
        left: 24,
        right: 24,
        bottom: 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            LockStrings.aponSushashthya,
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            LockStrings.programSubtitle,
            style: TextStyle(
              fontFamily: 'NunitoSans',
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 16),
          // Stepper dots
          Row(
            children: List.generate(7, (i) {
              final active = i == 0;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: active ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ── Simplified profile card ───────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.summary});

  final UserProfileSummary summary;

  String _initials() {
    final f = summary.firstName?.trim() ?? '';
    final l = summary.lastName?.trim() ?? '';
    final fi = f.isNotEmpty ? f[0].toUpperCase() : '';
    final li = l.isNotEmpty ? l[0].toUpperCase() : '';
    final result = '$fi$li';
    return result.isNotEmpty ? result : '?';
  }

  String _fullName() {
    final f = summary.firstName?.trim() ?? '';
    final l = summary.lastName?.trim() ?? '';
    return [f, l].where((e) => e.isNotEmpty).join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.07),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Initials avatar — pink background
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.pink.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              _initials(),
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.pink,
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Name + role
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LockStrings.shasthyaKormi,
                  style: TextStyle(
                    fontFamily: 'NunitoSans',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy.withValues(alpha: 0.45),
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _fullName().isNotEmpty
                      ? _fullName()
                      : LockStrings.profileLoading,
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                    letterSpacing: -0.2,
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

// ── OR divider ────────────────────────────────────────────────────────────────

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Divider(
            color: Theme.of(context).colorScheme.outlineVariant,
            thickness: 1,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'OR',
            style: TextStyle(
              fontFamily: 'NunitoSans',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 1.0,
            ),
          ),
        ),
        Expanded(
          child: Divider(
            color: Theme.of(context).colorScheme.outlineVariant,
            thickness: 1,
          ),
        ),
      ],
    );
  }
}

// ── Fingerprint / biometric card (unchanged from original) ────────────────────

class _FingerprintCard extends StatefulWidget {
  const _FingerprintCard({
    required this.onTap,
    this.busy = false,
    this.failed = false,
  });

  final VoidCallback onTap;
  final bool busy;
  final bool failed;

  @override
  State<_FingerprintCard> createState() => _FingerprintCardState();
}

class _FingerprintCardState extends State<_FingerprintCard>
    with TickerProviderStateMixin {
  late final AnimationController _glowCtrl;
  late final AnimationController _scanCtrl;
  late final AnimationController _verifyCtrl;
  late final Animation<double> _springAnim;
  bool _isPressed = false;
  bool _verified = false;

  static const _navy = AppColors.navy;
  static const _iconBoxIdle = Color(0x1FFFFFFF);
  static const _iconBoxScan = Color(0x33E8356D);
  static const _iconBoxVerify = Color(0x3310B981);

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: AppAnimations.idleGlow,
    )..repeat(reverse: true);
    _scanCtrl = AnimationController(
      vsync: this,
      duration: AppAnimations.scanPulse,
    );
    _verifyCtrl = AnimationController(
      vsync: this,
      duration: AppAnimations.verifyBounce,
    );
    _springAnim = CurvedAnimation(
      parent: _verifyCtrl,
      curve: AppAnimations.spring,
    );
  }

  @override
  void didUpdateWidget(_FingerprintCard old) {
    super.didUpdateWidget(old);
    if (widget.busy && !old.busy) {
      _verified = false;
      _glowCtrl.stop();
      _scanCtrl.repeat(reverse: true);
    }
    if (!widget.busy && old.busy) {
      _scanCtrl.stop();
      _scanCtrl.animateTo(0);
      if (!widget.failed) {
        _verified = true;
        _verifyCtrl.forward(from: 0);
        Future.delayed(AppAnimations.verifyBounce, () {
          if (mounted) _glowCtrl.repeat(reverse: true);
        });
      } else {
        _glowCtrl.repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    _scanCtrl.dispose();
    _verifyCtrl.dispose();
    super.dispose();
  }

  Widget _buildIconBox() {
    return AnimatedBuilder(
      animation: Listenable.merge([_glowCtrl, _scanCtrl]),
      builder: (context, _) {
        final Color boxColor = _verified
            ? _iconBoxVerify
            : widget.busy
            ? _iconBoxScan
            : _iconBoxIdle;
        final Color iconColor =
            _verified ? AppColors.statusSuccess : Colors.white;
        final double glowSpread =
            widget.busy ? 4 * _scanCtrl.value : 3 * _glowCtrl.value;
        final Color glowColor = widget.busy
            ? AppColors.pink.withValues(alpha: 0.35 * _scanCtrl.value)
            : Colors.white.withValues(alpha: 0.15 * _glowCtrl.value);

        return AnimatedBuilder(
          animation: _springAnim,
          builder: (_, child) => Transform.scale(
            scale: 1.0 + 0.08 * _springAnim.value,
            child: child,
          ),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: boxColor,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: glowColor,
                  blurRadius: 12,
                  spreadRadius: glowSpread,
                ),
              ],
            ),
            child: Icon(Icons.fingerprint, size: 26, color: iconColor),
          ),
        );
      },
    );
  }

  Widget _buildLabels() {
    return AnimatedBuilder(
      animation: _scanCtrl,
      builder: (context, _) {
        final String title = _verified
            ? LockStrings.fingerprintVerified
            : widget.busy
            ? LockStrings.readingFingerprint
            : LockStrings.verifyFingerprint;
        final String subtitle = _verified
            ? ''
            : widget.busy
            ? LockStrings.tapToPlaceFinger
            : LockStrings.tapToPlaceFingerSubtitle;
        final double opacity =
            widget.busy ? 0.5 + 0.5 * _scanCtrl.value : 1.0;
        return Opacity(
          opacity: opacity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _isPressed ? 0.97 : 1.0,
      duration: AppAnimations.pressFeedback,
      child: Semantics(
        label: 'Authenticate with fingerprint',
        button: true,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) {
            setState(() => _isPressed = false);
            if (!widget.busy) widget.onTap();
          },
          onTapCancel: () => setState(() => _isPressed = false),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: _navy,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: _navy.withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                _buildIconBox(),
                const SizedBox(width: 14),
                Expanded(child: _buildLabels()),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
