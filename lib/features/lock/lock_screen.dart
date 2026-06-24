import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/auth/auth_state.dart';
import '../../core/config/app_config.dart';
import '../../core/constants/app_strings.dart';
import 'lock_header.dart';

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
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      if (!mounted) return;
      setState(
          () => _isOnline = result.isNotEmpty && result[0].rawAddress.isNotEmpty);
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
      context.go('/dashboard');
    } else if (!auth.biometricEnabled) {
      context.go('/login?from=lock');
    } else {
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.select<AuthState, bool>((a) => a.busy);
    final biometricEnabled = context.select<AuthState, bool>((a) => a.biometricEnabled);
    final biometricAvailable = context.select<AuthState, bool>((a) => a.biometricAvailable);
    final pinEnabled = context.select<AuthState, bool>((a) => a.pinEnabled);

    final programTitle = _summary?.area ?? LockStrings.programName;

    return Scaffold(
      backgroundColor: AppColors.cardSurface,
      body: Column(
        children: [
          LockProgramHeader(title: programTitle, pageCount: 8),
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
                    onPassword: () => context.go('/login?from=lock'),
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
    required this.onPassword,
  });

  final UserProfileSummary? summary;
  final bool busy;
  final bool failed;
  final bool biometricEnabled;
  final bool pinEnabled;
  final bool isOnline;
  final VoidCallback onUnlock;
  final VoidCallback onPinUnlock;
  final VoidCallback onPassword;

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
      duration: const Duration(milliseconds: 500),
    )..forward();
    // 6 slots: stagger step = 60 ms, each slot animates for 200 ms.
    // Total window = 5 × 60 + 200 = 500 ms.
    _slots = List.generate(
      6,
      (i) => CurvedAnimation(
        parent: _entranceCtrl,
        curve: Interval(
          (i * 60) / 500,
          ((i * 60) + 200) / 500,
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

  Widget _enter(int index, Widget child) {
    final anim = _slots[index];
    return AnimatedBuilder(
      animation: anim,
      child: child,
      builder: (_, c) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
          offset: Offset(0, 6 * (1 - anim.value)),
          child: c,
        ),
      ),
    );
  }

  void _showOfflineMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(LockStrings.offlinePasswordDisabled),
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _enter(0, const _UserAvatar()),
          const SizedBox(height: 18),
          _enter(
            1,
            Text(
              LockStrings.welcomeBack,
              style: Theme.of(context)
                  .textTheme
                  .headlineLarge
                  ?.copyWith(fontWeight: FontWeight.w900, color: AppColors.navy),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 4),
          _enter(
            2,
            Text(
              LockStrings.signInToStartYourDay,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: AppColors.textMuted),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 20),
          if (s != null) ...[
            _enter(3, _UserProfileCard(summary: s)),
            const SizedBox(height: 16),
          ],
          ..._actionWidgets(context),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  List<Widget> _actionWidgets(BuildContext context) {
    return [
      if (widget.failed) ...[
        Center(
          child: Text(
            LockStrings.biometricCancelled,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: 8),
      ],
      _enter(
        4,
        _FingerprintCard(
          onTap: widget.busy ? () {} : widget.onUnlock,
          busy: widget.busy,
          failed: widget.failed,
        ),
      ),
      if (widget.pinEnabled && !widget.busy) ...[
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: widget.onPinUnlock,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textMuted,
              textStyle: const TextStyle(
                fontFamily: 'NunitoSans',
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
            child: Text(LockStrings.orUsePin(AppConfig.pinLength)),
          ),
        ),
      ],
      if (!widget.busy) ...[
        const SizedBox(height: 4),
        Center(
          child: TextButton.icon(
            onPressed: widget.isOnline
                ? widget.onPassword
                : () => _showOfflineMessage(context),
            icon: const Icon(Icons.lock_outline, size: 16),
            label: Text(CommonStrings.usePassword),
            style: TextButton.styleFrom(
              foregroundColor: widget.isOnline
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : Theme.of(context).disabledColor,
            ),
          ),
        ),
      ],
    ];
  }
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: AppColors.pink,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.pinkIcon,
      ),
      child: const Icon(Icons.person_rounded, color: Colors.white, size: 34),
    );
  }
}

class _UserProfileCard extends StatelessWidget {
  const _UserProfileCard({required this.summary});

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

  String _idLine() {
    final parts = <String>[];
    if (summary.skId != null) parts.add(summary.skId!);
    if (summary.ward != null) parts.add(summary.ward!);
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    // ignore: avoid_print
    print('[ProfileCard] firstName=${summary.firstName} lastName=${summary.lastName} '
        'fullName=${_fullName()} nidOrPhone=${summary.nidOrPhone} '
        'upazila=${summary.upazila} skId=${summary.skId}');
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.navy, AppColors.navyMid],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          // Decorative ghost circles
          Positioned(
            right: -20,
            top: -20,
            child: Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: Color(0x0DFFFFFF),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            right: 10,
            bottom: -10,
            child: Container(
              width: 50,
              height: 50,
              decoration: const BoxDecoration(
                color: Color(0x0AFFFFFF),
                shape: BoxShape.circle,
              ),
            ),
          ),
          // Card content
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LockStrings.shasthyaKormi,
                  style: const TextStyle(
                    fontFamily: 'NunitoSans',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0x80FFFFFF),
                    letterSpacing: 0.80,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _InitialsAvatar(initials: _initials()),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _fullName().isNotEmpty ? _fullName() : LockStrings.profileLoading,
                            style: const TextStyle(
                              fontFamily: 'Nunito',
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          if (_idLine().isNotEmpty)
                            Text(
                              _idLine(),
                              style: TextStyle(
                                fontFamily: 'NunitoSans',
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.60),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _InfoPanel(
                        label: LockStrings.nidLabel,
                        value: summary.nidOrPhone ?? '—',
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _InfoPanel(
                        label: LockStrings.upazilaLabel,
                        value: summary.upazila?.toUpperCase() ?? '—',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: const BoxDecoration(
        color: Color(0x26FFFFFF), // rgba(255,255,255,0.15)
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          fontFamily: 'Nunito',
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF), // rgba(255,255,255,0.10)
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'NunitoSans',
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: Color(0x80FFFFFF),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'NunitoSans',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

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
  static const _iconBoxIdle   = Color(0x1FFFFFFF); // white 12%
  static const _iconBoxScan   = Color(0x33E8356D); // pink 20%
  static const _iconBoxVerify = Color(0x3310B981); // green 20%
  static const _verifyGreen   = Color(0xFF10B981);

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(vsync: this, duration: AppAnimations.idleGlow)
      ..repeat(reverse: true);
    _scanCtrl  = AnimationController(vsync: this, duration: AppAnimations.scanPulse);
    _verifyCtrl = AnimationController(vsync: this, duration: AppAnimations.verifyBounce);
    _springAnim = CurvedAnimation(parent: _verifyCtrl, curve: AppAnimations.spring);
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
        final Color iconColor = _verified
            ? _verifyGreen
            : Colors.white;
        final double glowSpread = widget.busy
            ? 4 * _scanCtrl.value
            : 3 * _glowCtrl.value;
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
        final double opacity = widget.busy ? 0.5 + 0.5 * _scanCtrl.value : 1.0;
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
    );
  }
}
