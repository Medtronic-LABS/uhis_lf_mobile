import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/models/referral.dart';
import '../../../core/models/sla.dart';

/// Section 6 — Action Layer
/// Sticky bottom action area with dynamic actions based on referral state.
class ActionLayer extends StatelessWidget {
  const ActionLayer({
    super.key,
    required this.referral,
    required this.priority,
    this.onCallFamily,
    this.onUpdateStatus,
    this.onLocate,
    this.onEscalate,
    this.onCallFacility,
    this.onUpdateQueue,
    this.onOpenReferral,
    this.onViewPrescription,
    this.onScheduleFollowUp,
    this.onSendReminder,
    this.onCloseCase,
  });

  final Referral referral;
  final SlaPriority priority;

  // Critical case actions
  final VoidCallback? onCallFamily;
  final VoidCallback? onUpdateStatus;
  final VoidCallback? onLocate;
  final VoidCallback? onEscalate;

  // Facility delay actions
  final VoidCallback? onCallFacility;
  final VoidCallback? onUpdateQueue;
  final VoidCallback? onOpenReferral;

  // Completed case actions
  final VoidCallback? onViewPrescription;
  final VoidCallback? onScheduleFollowUp;
  final VoidCallback? onSendReminder;
  final VoidCallback? onCloseCase;

  @override
  Widget build(BuildContext context) {
    final actions = _determineActions();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 1,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < actions.length; i++) ...[
              _ActionButton(action: actions[i]),
              if (i < actions.length - 1) const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }

  List<_ActionData> _determineActions() {
    final isBreached = referral.breachedSince != null;
    final isCritical = priority == SlaPriority.critical;
    final isCompleted = referral.state.isClosed;
    final isAtFacility = referral.state == ReferralStatus.arrived ||
        referral.state == ReferralStatus.treatmentStarted;

    // Completed case actions
    if (isCompleted) {
      return [
        _ActionData(
          label: ReferralStrings.actionViewPrescription,
          icon: Icons.description_outlined,
          type: _ActionType.primary,
          onPressed: onViewPrescription,
        ),
        _ActionData(
          label: ReferralStrings.actionScheduleFollowUp,
          icon: Icons.event_outlined,
          type: _ActionType.secondary,
          onPressed: onScheduleFollowUp,
        ),
        _ActionData(
          label: ReferralStrings.actionSendReminder,
          icon: Icons.notifications_outlined,
          type: _ActionType.secondary,
          onPressed: onSendReminder,
        ),
        _ActionData(
          label: ReferralStrings.actionCloseCase,
          icon: Icons.check_circle_outline,
          type: _ActionType.tertiary,
          onPressed: onCloseCase,
        ),
      ];
    }

    // Facility delay actions (at facility but waiting)
    if (isAtFacility) {
      return [
        _ActionData(
          label: ReferralStrings.actionCallFacility,
          icon: Icons.phone_outlined,
          type: isBreached ? _ActionType.urgent : _ActionType.primary,
          onPressed: onCallFacility,
        ),
        _ActionData(
          label: ReferralStrings.actionUpdateQueue,
          icon: Icons.update_outlined,
          type: _ActionType.secondary,
          onPressed: onUpdateQueue,
        ),
        if (isBreached || isCritical)
          _ActionData(
            label: ReferralStrings.actionEscalate,
            icon: Icons.arrow_upward_rounded,
            type: _ActionType.urgent,
            onPressed: onEscalate,
          ),
        _ActionData(
          label: ReferralStrings.actionOpenReferral,
          icon: Icons.open_in_new_rounded,
          type: _ActionType.tertiary,
          onPressed: onOpenReferral,
        ),
      ];
    }

    // Critical / breached case actions (not arrived or delayed)
    if (isBreached || isCritical) {
      return [
        _ActionData(
          label: ReferralStrings.actionCallFamily,
          icon: Icons.phone_outlined,
          type: _ActionType.urgent,
          onPressed: onCallFamily,
        ),
        _ActionData(
          label: ReferralStrings.actionUpdateStatus,
          icon: Icons.edit_note_outlined,
          type: _ActionType.primary,
          onPressed: onUpdateStatus,
        ),
        _ActionData(
          label: ReferralStrings.actionLocate,
          icon: Icons.location_on_outlined,
          type: _ActionType.secondary,
          onPressed: onLocate,
        ),
        _ActionData(
          label: ReferralStrings.actionEscalate,
          icon: Icons.arrow_upward_rounded,
          type: _ActionType.urgent,
          onPressed: onEscalate,
        ),
      ];
    }

    // Default actions for non-critical active cases
    return [
      _ActionData(
        label: ReferralStrings.actionCallFamily,
        icon: Icons.phone_outlined,
        type: _ActionType.primary,
        onPressed: onCallFamily,
      ),
      _ActionData(
        label: ReferralStrings.actionUpdateStatus,
        icon: Icons.edit_note_outlined,
        type: _ActionType.secondary,
        onPressed: onUpdateStatus,
      ),
      _ActionData(
        label: ReferralStrings.actionOpenReferral,
        icon: Icons.open_in_new_rounded,
        type: _ActionType.tertiary,
        onPressed: onOpenReferral,
      ),
    ];
  }
}

enum _ActionType {
  urgent,
  primary,
  secondary,
  tertiary,
}

class _ActionData {
  const _ActionData({
    required this.label,
    required this.icon,
    required this.type,
    this.onPressed,
  });

  final String label;
  final IconData icon;
  final _ActionType type;
  final VoidCallback? onPressed;
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.action});

  final _ActionData action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    switch (action.type) {
      case _ActionType.urgent:
        return _buildFilledButton(context, scheme.error, scheme.onError);
      case _ActionType.primary:
        return _buildFilledButton(context, scheme.primary, scheme.onPrimary);
      case _ActionType.secondary:
        return _buildOutlinedButton(context, scheme);
      case _ActionType.tertiary:
        return _buildTextButton(context, scheme);
    }
  }

  Widget _buildFilledButton(
      BuildContext context, Color bgColor, Color fgColor) {
    return FilledButton.icon(
      onPressed: action.onPressed,
      icon: Icon(action.icon, size: 18),
      label: Text(action.label),
      style: FilledButton.styleFrom(
        backgroundColor: bgColor,
        foregroundColor: fgColor,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
        minimumSize: const Size(0, 36),
      ),
    );
  }

  Widget _buildOutlinedButton(BuildContext context, ColorScheme scheme) {
    return OutlinedButton.icon(
      onPressed: action.onPressed,
      icon: Icon(action.icon, size: 18),
      label: Text(action.label),
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.primary,
        side: BorderSide(color: scheme.outline),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
        minimumSize: const Size(0, 36),
      ),
    );
  }

  Widget _buildTextButton(BuildContext context, ColorScheme scheme) {
    return TextButton.icon(
      onPressed: action.onPressed,
      icon: Icon(action.icon, size: 18),
      label: Text(action.label),
      style: TextButton.styleFrom(
        foregroundColor: scheme.onSurfaceVariant,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
        minimumSize: const Size(0, 36),
      ),
    );
  }
}
