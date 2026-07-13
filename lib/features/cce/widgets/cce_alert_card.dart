import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/constants/app_strings.dart';
import '../cce_alert.dart';

/// CCE alert card — wireframe v14 design.
///
/// Layout:
///   • Header row: donut-ring timer | patient name + facility·condition | mini action icons
///   • Progress bar + status labels (delegated to [journey] widget)
///   • Follow-up banner (completed cards with a [CceAlert.followUpDate] only)
///
/// Pure presentation — callbacks and journey widget are injected by the drawer.
class CceAlertCard extends StatelessWidget {
  const CceAlertCard({
    super.key,
    required this.alert,
    required this.journey,
    required this.onUpdateStatus,
    required this.onCall,
    required this.onLocate,
    this.onWhatsapp,
  });

  final CceAlert alert;
  final Widget journey;
  final VoidCallback onUpdateStatus;
  final VoidCallback onCall;
  final VoidCallback onLocate;

  /// WhatsApp action — shown on warning-severity cards when the patient has a
  /// phone number. Optional; if null the WhatsApp button is hidden.
  final VoidCallback? onWhatsapp;

  @override
  Widget build(BuildContext context) {
    final accent = _accent(alert.severity);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderColor(alert.severity), width: 1.5),
        boxShadow: AppShadows.card,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(accent),
            const SizedBox(height: 12),
            journey,
            if (alert.severity == CceSeverity.completed &&
                alert.followUpDate != null)
              _followUpBanner(),
          ],
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────

  Widget _header(Color accent) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _ring(accent),
        const SizedBox(width: 12),
        Expanded(child: _nameBlock()),
        const SizedBox(width: 8),
        _actionIcons(),
      ],
    );
  }

  Widget _ring(Color accent) {
    if (alert.severity == CceSeverity.completed) {
      return Container(
        width: 52,
        height: 52,
        decoration: const BoxDecoration(
          color: AppColors.statusSuccess,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check_rounded, color: Colors.white, size: 26),
      );
    }

    final fill = alert.severity == CceSeverity.breached ? 0.75 : 0.55;

    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(52, 52),
            painter: _DonutPainter(
              fill: fill,
              color: accent,
              trackColor: accent.withValues(alpha: 0.12),
              strokeWidth: 5.5,
            ),
          ),
          Text(
            alert.ringLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _nameBlock() {
    final nameParts = <String>[alert.patientName];
    if (alert.patientAge != null) nameParts.add('${alert.patientAge}');
    final subtitle = _subtitle();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          nameParts.join(', '),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  /// Strips "Referred: date · " prefix from [CceAlert.referredMeta] to produce
  /// "UHC Manikganj · Severe pneumonia" for the card subtitle.
  String _subtitle() {
    final meta = alert.referredMeta;
    final idx = meta.indexOf(' · ');
    return idx != -1 ? meta.substring(idx + 3) : meta;
  }

  // ── Action icons ─────────────────────────────────────────────────────────

  Widget _actionIcons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (alert.severity != CceSeverity.completed && alert.hasPhone) ...[
          _miniIcon(
            Icons.phone_rounded,
            const Color(0xFFEC4899),
            const Color(0x1FEC4899),
            onCall,
          ),
          const SizedBox(width: 6),
        ],
        if (alert.severity == CceSeverity.warning &&
            alert.hasPhone &&
            onWhatsapp != null) ...[
          _miniIcon(
            Icons.chat_rounded,
            AppColors.whatsapp,
            const Color(0x1F25D366),
            onWhatsapp!,
          ),
          const SizedBox(width: 6),
        ],
        if (alert.severity == CceSeverity.completed)
          _miniIcon(
            Icons.calendar_today_rounded,
            AppColors.aiPurple,
            const Color(0x1F6B63D4),
            onUpdateStatus,
          )
        else
          _miniIcon(
            Icons.refresh_rounded,
            AppColors.aiPurple,
            const Color(0x1F6B63D4),
            onUpdateStatus,
          ),
      ],
    );
  }

  Widget _miniIcon(
    IconData icon,
    Color iconColor,
    Color bgColor,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
        child: Icon(icon, size: 16, color: iconColor),
      ),
    );
  }

  // ── Follow-up banner ─────────────────────────────────────────────────────

  Widget _followUpBanner() {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: GestureDetector(
        onTap: onUpdateStatus,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.calendar_today_rounded,
                size: 16,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  CceStrings.followUpDueBanner(alert.followUpDate),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  // ── Color helpers ────────────────────────────────────────────────────────

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

  static Color _borderColor(CceSeverity s) {
    switch (s) {
      case CceSeverity.breached:
        return AppColors.statusCriticalBorder;
      case CceSeverity.warning:
        return AppColors.statusWarningBorder;
      case CceSeverity.onTrack:
        return AppColors.border;
      case CceSeverity.completed:
        return AppColors.statusSuccessBorder;
    }
  }
}

// ── Donut ring painter ───────────────────────────────────────────────────────

class _DonutPainter extends CustomPainter {
  const _DonutPainter({
    required this.fill,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  final double fill;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Track
    paint.color = trackColor;
    canvas.drawCircle(center, radius, paint);

    // Fill arc — starts at top (−π/2) and sweeps clockwise
    if (fill > 0) {
      paint.color = color;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * fill,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.fill != fill || old.color != color || old.trackColor != trackColor;
}
