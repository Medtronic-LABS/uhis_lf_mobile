import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_strings.dart';
import '../../core/preferences/ai_feature_toggles_notifier.dart';
import '../../core/preferences/vad_tuning_notifier.dart';
import '../../core/theme/app_theme.dart';

/// AI Settings — realtime-ASR VAD gate tuning. Field-adjustable without a
/// rebuild so the entry/sustain/floor/timing thresholds can be dialed in
/// against real device + environment conditions (rural, variable vocal
/// volume, unpredictable ambient noise) rather than guessed at in code.
///
/// Changes take effect on the next recording session — [RealtimeAsrController]
/// reads the current [VadTuningNotifier] value each time [start] is called,
/// not just once at construction.
class AiSettingsScreen extends StatelessWidget {
  const AiSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 60,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '🤖 ${AiSettingsStrings.title}',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            ),
            Text(
              AiSettingsStrings.appBarSubtitle,
              style: TextStyle(
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
      body: const _VadTuningBody(),
    );
  }

  Future<void> _confirmReset(BuildContext context) async {
    final vadNotifier = context.read<VadTuningNotifier>();
    final togglesNotifier = context.read<AiFeatureTogglesNotifier>();
    await Future.wait([
      vadNotifier.resetToDefaults(),
      togglesNotifier.resetToDefaults(),
    ]);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(AiSettingsStrings.resetConfirmation)),
    );
  }
}

class _VadTuningBody extends StatelessWidget {
  const _VadTuningBody();

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<VadTuningNotifier>();
    final cfg = notifier.config;

    void save(VadTuningConfig next) {
      notifier.update(next);
    }

    return ListView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        const _WhiteCard(
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
        _WhiteCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                AiSettingsStrings.sectionHeader,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                  letterSpacing: 0.8,
                ),
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
        ),
        const SizedBox(height: 14),
        const _AiWidgetTogglesCard(),
      ],
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

    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            AiSettingsStrings.widgetsSectionHeader,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            AiSettingsStrings.widgetsSectionDescription,
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.textMuted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          const _StepHeader(AiSettingsStrings.step1Header),
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
          const _StepHeader(AiSettingsStrings.step2Header),
          _ToggleRow(
            label: AiSettingsStrings.step2AsrLabel,
            description: AiSettingsStrings.step2AsrDesc,
            value: t.step2AsrEnabled,
            onChanged: (v) => save(t.copyWith(step2AsrEnabled: v)),
          ),
          const _StepHeader(AiSettingsStrings.step3Header),
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
  });

  final String label;
  final String description;
  final bool value;
  final bool isLast;
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
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
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
