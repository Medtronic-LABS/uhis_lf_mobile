import 'package:flutter/material.dart';

import '../../../core/models/patient.dart';
import '../../../core/models/referral.dart';
import '../../../core/models/sla.dart';
import 'action_layer.dart';
import 'horizontal_timeline.dart';
import 'identity_strip.dart';
import 'operational_status.dart';
import 'referral_metadata.dart';
import 'sla_status_banner.dart';

/// Comprehensive Triage Referral Card with 6 visual sections:
/// 1. Identity Strip — Patient name, age, priority badge
/// 2. SLA Status Banner — Largest visual element showing breach/warning/completion
/// 3. Referral Metadata — Structured metadata (date, facility, condition, etc.)
/// 4. Operational Status — Current operational context with status hints
/// 5. Timeline Progress — Horizontal compact timeline
/// 6. Action Layer — Dynamic actions based on state
class TriageReferralCard extends StatelessWidget {
  const TriageReferralCard({
    super.key,
    required this.referral,
    required this.patient,
    this.events = const [],
    this.facilityName,
    this.programmeName,
    this.assignedDoctor,
    this.followUpDueAt,
    this.prescriptionShared = false,
    this.onTap,
    // Action callbacks
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
  final Patient? patient;
  final List<ReferralStatusEventRow> events;
  final String? facilityName;
  final String? programmeName;
  final String? assignedDoctor;
  final int? followUpDueAt;
  final bool prescriptionShared;
  final VoidCallback? onTap;

  // Action callbacks
  final VoidCallback? onCallFamily;
  final VoidCallback? onUpdateStatus;
  final VoidCallback? onLocate;
  final VoidCallback? onEscalate;
  final VoidCallback? onCallFacility;
  final VoidCallback? onUpdateQueue;
  final VoidCallback? onOpenReferral;
  final VoidCallback? onViewPrescription;
  final VoidCallback? onScheduleFollowUp;
  final VoidCallback? onSendReminder;
  final VoidCallback? onCloseCase;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final priority = SlaPriority.fromWireTag(referral.priorityLevel);
    final isCompleted = referral.state.isClosed;
    final isBreached = referral.breachedSince != null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      elevation: isBreached ? 3 : 1,
      shadowColor: isBreached 
          ? scheme.error.withValues(alpha: 0.3)
          : scheme.shadow.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: _cardBorderColor(scheme, priority, isBreached, isCompleted),
          width: isBreached ? 2 : 1,
        ),
      ),
      child: Semantics(
        label: 'View referral for ${patient?.name ?? referral.patientId}',
        button: true,
        child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Main content area
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Section 1: Identity Strip
                  IdentityStrip(
                    patientName: patient?.name ?? referral.patientId,
                    patientAge: patient?.age,
                    priority: priority,
                    isCompleted: isCompleted,
                  ),
                  const SizedBox(height: 10),

                  // Section 2: SLA Status Banner
                  SlaStatusBanner(
                    referral: referral,
                    priority: priority,
                  ),
                  const SizedBox(height: 10),

                  // Section 3: Referral Metadata
                  ReferralMetadata(
                    referral: referral,
                    facilityName: facilityName,
                    programmeName: programmeName,
                    assignedDoctor: assignedDoctor,
                  ),
                  const SizedBox(height: 10),

                  // Section 4: Operational Status
                  OperationalStatus(
                    referral: referral,
                    followUpDueAt: followUpDueAt,
                    prescriptionShared: prescriptionShared,
                  ),
                  const SizedBox(height: 10),

                  // Section 5: Timeline Progress
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: HorizontalTimeline(
                      events: events,
                      currentState: referral.state,
                      isBreached: isBreached,
                    ),
                  ),
                ],
              ),
            ),

            // Section 6: Action Layer (sticky bottom)
            ActionLayer(
              referral: referral,
              priority: priority,
              onCallFamily: onCallFamily,
              onUpdateStatus: onUpdateStatus,
              onLocate: onLocate,
              onEscalate: onEscalate,
              onCallFacility: onCallFacility,
              onUpdateQueue: onUpdateQueue,
              onOpenReferral: onOpenReferral,
              onViewPrescription: onViewPrescription,
              onScheduleFollowUp: onScheduleFollowUp,
              onSendReminder: onSendReminder,
              onCloseCase: onCloseCase,
            ),
          ],
        ),
        ),
      ),
    );
  }

  Color _cardBorderColor(
    ColorScheme scheme,
    SlaPriority priority,
    bool isBreached,
    bool isCompleted,
  ) {
    if (isCompleted) return scheme.primary.withValues(alpha: 0.3);
    if (isBreached) return scheme.error;
    
    switch (priority) {
      case SlaPriority.critical:
        return scheme.error.withValues(alpha: 0.6);
      case SlaPriority.high:
        return scheme.tertiary.withValues(alpha: 0.5);
      case SlaPriority.medium:
        return scheme.primary.withValues(alpha: 0.4);
      case SlaPriority.low:
        return scheme.outlineVariant;
    }
  }
}
