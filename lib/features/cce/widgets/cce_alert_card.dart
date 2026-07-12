import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/constants/app_strings.dart';
import '../cce_alert.dart';

/// A single CCE alert card: patient header, SLA badge, status line, intel
/// tags, the 4-step journey strip, and severity-driven action buttons.
/// Pure presentation — all timing text is pre-computed on the [CceAlert]; all
/// actions are delegated to the callbacks the drawer supplies.
class CceAlertCard extends StatelessWidget {
  const CceAlertCard({
    super.key,
    required this.alert,
    required this.journey,
    required this.onUpdateStatus,
    required this.onCall,
    required this.onLocate,
  });

  final CceAlert alert;

  /// The journey strip widget is injected so this file needn't import the
  /// strip directly — keeps the card a pure layout container.
  final Widget journey;

  final VoidCallback onUpdateStatus;
  final VoidCallback onCall;
  final VoidCallback onLocate;

  @override
  Widget build(BuildContext context) {
    final accent = _accent(alert.severity);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent, width: 1.4),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(accent),
            const SizedBox(height: 6),
            Text(alert.referredMeta,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 6),
            Text(
              alert.statusLine,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _statusColor(alert.severity),
              ),
            ),
            if (alert.intelTags.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: alert.intelTags.map(_intelChip).toList(),
              ),
            ],
            const SizedBox(height: 14),
            journey,
            if (_actions.isNotEmpty) ...[
              const SizedBox(height: 14),
              Row(children: _actions),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header(Color accent) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: accent.withValues(alpha: 0.15),
          child: Text(
            _initials(alert.patientName),
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: accent),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _headerTitle(),
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _slaBadge(accent),
      ],
    );
  }

  Widget _slaBadge(Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        alert.slaBadge,
        style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white),
      ),
    );
  }

  Widget _intelChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  /// Action set is severity-driven, mirroring the wireframe:
  /// breached → Call / Update / Locate; warning → Call / Update;
  /// on-track → Update; completed → none.
  List<Widget> get _actions {
    switch (alert.severity) {
      case CceSeverity.breached:
        return [
          _actionButton(CceStrings.actionCallFamily, Icons.phone,
              AppColors.statusCritical, onCall,
              filled: true),
          const SizedBox(width: 8),
          _actionButton(CceStrings.actionUpdateStatus, Icons.edit_outlined,
              AppColors.navy, onUpdateStatus),
          const SizedBox(width: 8),
          _actionButton(CceStrings.actionLocate, Icons.location_on_outlined,
              AppColors.statusWarning, onLocate),
        ];
      case CceSeverity.warning:
        return [
          _actionButton(CceStrings.actionCallFamily, Icons.phone,
              AppColors.navy, onCall, filled: true),
          const SizedBox(width: 8),
          _actionButton(CceStrings.actionUpdateStatus, Icons.edit_outlined,
              AppColors.navy, onUpdateStatus),
        ];
      case CceSeverity.onTrack:
        return [
          _actionButton(CceStrings.actionUpdateStatus, Icons.edit_outlined,
              AppColors.navy, onUpdateStatus),
        ];
      case CceSeverity.completed:
        return const [];
    }
  }

  Widget _actionButton(
      String label, IconData icon, Color color, VoidCallback onTap,
      {bool filled = false}) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 15, color: filled ? Colors.white : color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: filled ? Colors.white : color,
            ),
          ),
        ),
      ],
    );
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: filled ? color : color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: filled ? null : Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: child,
        ),
      ),
    );
  }

  String _headerTitle() {
    final parts = <String>[alert.patientName];
    if (alert.patientAge != null) parts.add('${alert.patientAge}y');
    final g = _genderInitial(alert.patientGender);
    if (g != null) parts.add(g);
    return parts.join(' · ');
  }

  static String? _genderInitial(String? gender) {
    if (gender == null || gender.isEmpty) return null;
    final g = gender[0].toUpperCase();
    return (g == 'M' || g == 'F') ? g : null;
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  static Color _accent(CceSeverity s) {
    switch (s) {
      case CceSeverity.breached:
        return AppColors.statusCritical;
      case CceSeverity.warning:
        return AppColors.statusWarning;
      case CceSeverity.onTrack:
        return AppColors.navy;
      case CceSeverity.completed:
        return AppColors.statusSuccess;
    }
  }

  static Color _statusColor(CceSeverity s) {
    switch (s) {
      case CceSeverity.breached:
        return AppColors.statusCriticalText;
      case CceSeverity.warning:
        return AppColors.statusWarningText;
      case CceSeverity.onTrack:
        return AppColors.textPrimary;
      case CceSeverity.completed:
        return AppColors.statusSuccessText;
    }
  }
}
