import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/locale_provider.dart';
import '../../app/theme_provider.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/auth/auth_state.dart';
import '../../core/constants/app_strings.dart';
import '../../core/device/battery_optimization_gate.dart';
import '../../core/device/battery_optimization_service.dart';
import '../../core/i18n/app_locale.dart';
import '../../core/preferences/ai_feature_toggles_notifier.dart';
import '../../core/preferences/vad_tuning_notifier.dart';
import '../../core/theme/app_theme.dart';
import '../debug/db_viewer_screen.dart';
import 'settings_actions.dart';
import 'widgets/profile_card.dart';
import 'widgets/settings_row.dart';

/// Settings — account/device controls (device unlock, PIN, appearance,
/// language, offline database) plus the AI Widgets toggles. Consolidates
/// what used to be spread across this page (AI-only) and the dashboard's
/// popup Settings menu; the popup menu still exposes Language/Offline Sync/
/// Sign out directly, with everything else routed through this page via the
/// shared functions in `settings_actions.dart` and [SettingsRow].
///
/// The VAD (voice-activity-gate) tuning UI below is intentionally hidden —
/// [_showVadTuning] — the underlying [VadTuningNotifier]/tuning sliders stay
/// in the codebase; the plan is to drive visibility from a remote config/API
/// flag rather than exposing it as a raw UI knob for now.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  UserProfileSummary? _summary;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSummary());
  }

  Future<void> _loadSummary() async {
    if (!mounted) return;
    final auth = context.read<AuthState>();
    final s = await auth.userProfileSummary();
    if (!mounted) return;
    setState(() => _summary = s);
  }

  Future<void> _confirmReset(BuildContext context) async {
    final togglesNotifier = context.read<AiFeatureTogglesNotifier>();
    await togglesNotifier.resetToDefaults();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AiSettingsStrings.resetConfirmation)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 60,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '⚙️ ${SettingsStrings.settings}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            ),
            Text(
              SettingsStrings.settingsSubtitle,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.restore),
            tooltip: AiSettingsStrings.resetToDefaults,
            onPressed: () => _confirmReset(context),
          ),
        ],
      ),
      body: _SettingsBody(summary: _summary),
    );
  }
}

class _SettingsBody extends StatelessWidget {
  const _SettingsBody({required this.summary});

  final UserProfileSummary? summary;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final theme = context.watch<ThemeProvider>();
    final locale = context.watch<LocaleProvider>();

    final String appearanceSubtitle;
    if (theme.isDark) {
      appearanceSubtitle = SettingsStrings.darkMode;
    } else if (theme.isSystem) {
      appearanceSubtitle = SettingsStrings.systemMode;
    } else {
      appearanceSubtitle = SettingsStrings.lightMode;
    }
    final languageSubtitle = locale.isBangla
        ? SettingsStrings.bangla
        : SettingsStrings.english;

    return ListView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (summary != null) ...[
          ProfileCard(summary: summary!, username: auth.username),
          const SizedBox(height: 14),
        ],
        _WhiteCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SettingsTapRow(
                row: SettingsRow(
                  emoji: auth.biometricEnabled ? '🔒' : '🔓',
                  chipColor: AppColors.aiSurfaceStart,
                  title: auth.biometricEnabled
                      ? DashboardStrings.disableDeviceUnlock
                      : DashboardStrings.enableDeviceUnlock,
                ),
                onTap: () => auth.biometricEnabled
                    ? disableDeviceUnlock(context, auth)
                    : offerDeviceUnlock(context),
              ),
              const Divider(height: 20),
              _SettingsTapRow(
                row: SettingsRow(
                  emoji: '🔢',
                  chipColor: AppColors.ancSurface,
                  title: auth.pinEnabled
                      ? PinStrings.disablePin
                      : PinStrings.enablePin,
                ),
                onTap: () => auth.pinEnabled
                    ? removePin(context, auth)
                    : context.go('/pin-setup'),
              ),
              const Divider(height: 20),
              _SettingsTapRow(
                row: SettingsRow(
                  emoji: '🌓',
                  chipColor: AppColors.catChildSurface,
                  title: SettingsStrings.appearance,
                  subtitle: appearanceSubtitle,
                ),
                onTap: () async {
                  final chosen = await showOptionPicker<ThemeMode>(
                    context: context,
                    title: SettingsStrings.appearance,
                    current: theme.mode,
                    options: [
                      (ThemeMode.light, SettingsStrings.lightMode),
                      (ThemeMode.dark, SettingsStrings.darkMode),
                      (ThemeMode.system, SettingsStrings.systemMode),
                    ],
                  );
                  if (chosen != null) await theme.setMode(chosen);
                },
              ),
              const Divider(height: 20),
              _SettingsTapRow(
                row: SettingsRow(
                  emoji: '🔋',
                  chipColor: AppColors.catHomeSurface,
                  title: BatteryOptimizationStrings.settingsRowTitle,
                  subtitle: BatteryOptimizationStrings.settingsRowSubtitle,
                ),
                // Lives here rather than in onboarding: the destination is a
                // vendor battery screen a frontline SK cannot realistically
                // navigate, and the sync foreground service already survives
                // Doze without it. This is the escape hatch for a supervisor
                // troubleshooting a handset that kills background work.
                onTap: () => BatteryOptimizationGate(
                  service: const MethodChannelBatteryOptimizationService(),
                ).openBestSettingsScreen(),
              ),
              const Divider(height: 20),
              _SettingsTapRow(
                row: SettingsRow(
                  emoji: '🌐',
                  chipColor: AppColors.catHomeSurface,
                  title: SettingsStrings.language,
                  subtitle: languageSubtitle,
                ),
                onTap: () async {
                  final chosen = await showOptionPicker<AppLanguage>(
                    context: context,
                    title: SettingsStrings.language,
                    current: locale.language,
                    options: [
                      (AppLanguage.english, SettingsStrings.english),
                      (AppLanguage.bangla, SettingsStrings.bangla),
                    ],
                  );
                  if (chosen != null) await locale.setLanguage(chosen);
                },
              ),
              if (kDebugMode) ...[
                const Divider(height: 20),
                _SettingsTapRow(
                  row: SettingsRow(
                    emoji: '🗄️',
                    chipColor: AppColors.catChildSurface,
                    title: SettingsStrings.debugDbViewer,
                    subtitle: SettingsStrings.debugDbViewerSubtitle,
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DebugDbViewerScreen(),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_showVadTuning) ...[
          _WhiteCard(
            child: Text(
              AiSettingsStrings.sectionDescription,
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.textMuted,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const _VadTuningCard(),
          const SizedBox(height: 14),
        ],
        const _AiWidgetTogglesCard(),
      ],
    );
  }
}

/// Makes a [SettingsRow] fully tappable — used on this page (unlike the
/// popup menu, where `PopupMenuItem.onSelected` already handles the tap).
class _SettingsTapRow extends StatelessWidget {
  const _SettingsTapRow({required this.row, required this.onTap});

  final SettingsRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: row,
      ),
    );
  }
}

// Future: drive from a remote config/API flag instead of a compile-time
// const — feature/notifier stay intact, only the UI is hidden for now.
const bool _showVadTuning = false;

class _VadTuningCard extends StatelessWidget {
  const _VadTuningCard();

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<VadTuningNotifier>();
    final cfg = notifier.config;

    void save(VadTuningConfig next) {
      notifier.update(next);
    }

    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AiSettingsStrings.sectionHeader,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
              GestureDetector(
                onTap: () => notifier.resetToDefaults(),
                child: Text(
                  AiSettingsStrings.widgetsResetToDefaults,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.aiPurpleDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _TuningSlider(
            label: AiSettingsStrings.enterMarginLabel,
            description: AiSettingsStrings.enterMarginDesc,
            value: cfg.enterMarginDb,
            min: 3,
            max: 20,
            divisions: 34,
            unit: 'dB',
            onChangeEnd: (v) => save(cfg.copyWith(enterMarginDb: v)),
          ),
          _TuningSlider(
            label: AiSettingsStrings.sustainMarginLabel,
            description: AiSettingsStrings.sustainMarginDesc,
            value: cfg.sustainMarginDb,
            min: 2,
            max: 15,
            divisions: 26,
            unit: 'dB',
            onChangeEnd: (v) => save(cfg.copyWith(sustainMarginDb: v)),
          ),
          _TuningSlider(
            label: AiSettingsStrings.floorCeilingLabel,
            description: AiSettingsStrings.floorCeilingDesc,
            value: cfg.floorCeilingDbfs,
            min: -60,
            max: -10,
            divisions: 50,
            unit: 'dBFS',
            onChangeEnd: (v) => save(cfg.copyWith(floorCeilingDbfs: v)),
          ),
          _TuningSlider(
            label: AiSettingsStrings.floorAlphaLabel,
            description: AiSettingsStrings.floorAlphaDesc,
            value: cfg.floorAlpha,
            min: 0.01,
            max: 0.3,
            divisions: 29,
            unit: '',
            valueFractionDigits: 2,
            onChangeEnd: (v) => save(cfg.copyWith(floorAlpha: v)),
          ),
          _TuningSlider(
            label: AiSettingsStrings.bootstrapLabel,
            description: AiSettingsStrings.bootstrapDesc,
            value: cfg.bootstrapMs.toDouble(),
            min: 100,
            max: 1500,
            divisions: 28,
            unit: 'ms',
            onChangeEnd: (v) => save(cfg.copyWith(bootstrapMs: v.round())),
          ),
          _TuningSlider(
            label: AiSettingsStrings.debounceLabel,
            description: AiSettingsStrings.debounceDesc,
            value: cfg.debounceMs.toDouble(),
            min: 50,
            max: 500,
            divisions: 45,
            unit: 'ms',
            onChangeEnd: (v) => save(cfg.copyWith(debounceMs: v.round())),
          ),
          _TuningSlider(
            label: AiSettingsStrings.hangoverLabel,
            description: AiSettingsStrings.hangoverDesc,
            value: cfg.hangoverMs.toDouble(),
            min: 200,
            max: 2000,
            divisions: 36,
            unit: 'ms',
            onChangeEnd: (v) => save(cfg.copyWith(hangoverMs: v.round())),
          ),
          _TuningSlider(
            label: AiSettingsStrings.preRollLabel,
            description: AiSettingsStrings.preRollDesc,
            value: cfg.preRollMs.toDouble(),
            min: 100,
            max: 800,
            divisions: 28,
            unit: 'ms',
            isLast: true,
            onChangeEnd: (v) => save(cfg.copyWith(preRollMs: v.round())),
          ),
        ],
      ),
    );
  }
}

class _AiWidgetTogglesCard extends StatelessWidget {
  const _AiWidgetTogglesCard();

  @override
  Widget build(BuildContext context) {
    final togglesNotifier = context.watch<AiFeatureTogglesNotifier>();
    final t = togglesNotifier.toggles;

    void save(AiFeatureToggles next) => togglesNotifier.update(next);
    final allEnabled = t.step1SummaryEnabled &&
        t.step1AsrEnabled &&
        t.step2AsrEnabled &&
        t.step3SummaryEnabled &&
        t.step3ReferralAlertEnabled &&
        t.step3WhatsAppEnabled;

    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AiSettingsStrings.widgetsSectionHeader,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
              GestureDetector(
                onTap: () => togglesNotifier.resetToDefaults(),
                child: Text(
                  AiSettingsStrings.widgetsResetToDefaults,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.aiPurpleDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            AiSettingsStrings.widgetsSectionDescription,
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.textMuted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          _ToggleRow(
            label: AiSettingsStrings.selectAllLabel,
            description: AiSettingsStrings.selectAllDesc,
            value: allEnabled,
            bold: true,
            onChanged: (v) => save(AiFeatureToggles(
              step1SummaryEnabled: v,
              step1AsrEnabled: v,
              step2AsrEnabled: v,
              step3SummaryEnabled: v,
              step3ReferralAlertEnabled: v,
              step3WhatsAppEnabled: v,
            )),
          ),
          const Divider(height: 18),
          _StepHeader(AiSettingsStrings.step1Header),
          _ToggleRow(
            label: AiSettingsStrings.step1SummaryLabel,
            description: AiSettingsStrings.step1SummaryDesc,
            value: t.step1SummaryEnabled,
            onChanged: (v) => save(t.copyWith(step1SummaryEnabled: v)),
          ),
          _ToggleRow(
            label: AiSettingsStrings.step1AsrLabel,
            description: AiSettingsStrings.step1AsrDesc,
            value: t.step1AsrEnabled,
            onChanged: (v) => save(t.copyWith(step1AsrEnabled: v)),
          ),
          _StepHeader(AiSettingsStrings.step2Header),
          _ToggleRow(
            label: AiSettingsStrings.step2AsrLabel,
            description: AiSettingsStrings.step2AsrDesc,
            value: t.step2AsrEnabled,
            onChanged: (v) => save(t.copyWith(step2AsrEnabled: v)),
          ),
          _StepHeader(AiSettingsStrings.step3Header),
          _ToggleRow(
            label: AiSettingsStrings.step3SummaryLabel,
            description: AiSettingsStrings.step3SummaryDesc,
            value: t.step3SummaryEnabled,
            onChanged: (v) => save(t.copyWith(step3SummaryEnabled: v)),
          ),
          _ToggleRow(
            label: AiSettingsStrings.step3ReferralAlertLabel,
            description: AiSettingsStrings.step3ReferralAlertDesc,
            value: t.step3ReferralAlertEnabled,
            onChanged: (v) => save(t.copyWith(step3ReferralAlertEnabled: v)),
          ),
          _ToggleRow(
            label: AiSettingsStrings.step3WhatsAppLabel,
            description: AiSettingsStrings.step3WhatsAppDesc,
            value: t.step3WhatsAppEnabled,
            onChanged: (v) => save(t.copyWith(step3WhatsAppEnabled: v)),
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 2),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: AppColors.navy,
        ),
      ),
    );
  }
}

/// One AI-widget on/off row — same label + description shell as
/// [_TuningSlider], with a themed [Switch] instead of a slider. Persists
/// immediately on toggle (no drag-release semantics needed for a switch).
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
    this.isLast = false,
    this.bold = false,
  });

  final String label;
  final String description;
  final bool value;
  final bool isLast;
  final bool bold;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: 10, bottom: isLast ? 0 : 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: bold ? 14.5 : 13.5,
                    fontWeight: FontWeight.w800,
                    color: bold ? AppColors.navy : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppColors.aiPurple,
            inactiveTrackColor: AppColors.progressTrack,
          ),
        ],
      ),
    );
  }
}

/// Stateful only for smooth drag feedback — [onChangeEnd] (the only thing
/// that persists) fires exactly once per gesture, on release. The parent's
/// [value] (the persisted config) re-syncs [_dragValue] via [didUpdateWidget]
/// so an external reset (e.g. "Reset to defaults") is reflected immediately.
class _TuningSlider extends StatefulWidget {
  const _TuningSlider({
    required this.label,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.unit,
    required this.onChangeEnd,
    this.valueFractionDigits = 1,
    this.isLast = false,
  });

  final String label;
  final String description;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String unit;
  final int valueFractionDigits;
  final bool isLast;
  final ValueChanged<double> onChangeEnd;

  @override
  State<_TuningSlider> createState() => _TuningSliderState();
}

class _TuningSliderState extends State<_TuningSlider> {
  late double _dragValue = widget.value;

  @override
  void didUpdateWidget(_TuningSlider old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _dragValue = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    final displayValue = _dragValue.toStringAsFixed(widget.valueFractionDigits);
    return Padding(
      padding: EdgeInsets.only(top: 14, bottom: widget.isLast ? 0 : 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.aiSurfaceStart,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  widget.unit.isEmpty
                      ? displayValue
                      : '$displayValue ${widget.unit}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.aiPurpleDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            widget.description,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textMuted,
              height: 1.3,
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.aiPurple,
              thumbColor: AppColors.navy,
              overlayColor: AppColors.aiPurple.withValues(alpha: 0.15),
              inactiveTrackColor: AppColors.progressTrack,
            ),
            child: Slider(
              value: _dragValue.clamp(widget.min, widget.max),
              min: widget.min,
              max: widget.max,
              divisions: widget.divisions,
              onChanged: (v) => setState(() => _dragValue = v),
              onChangeEnd: widget.onChangeEnd,
            ),
          ),
        ],
      ),
    );
  }
}

class _WhiteCard extends StatelessWidget {
  const _WhiteCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 6,
            offset: Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: child,
    );
  }
}
