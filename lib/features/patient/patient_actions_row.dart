import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/programme.dart';
import '../visit/visit_landing_screen.dart';

/// Row of action buttons for patient context screen.
class PatientActionsRow extends StatelessWidget {
  const PatientActionsRow({
    super.key,
    required this.patientId,
    this.patientName,
    this.patientAge,
    this.patientGender,
    this.householdId,
    this.programmes = const {},
  });

  final String patientId;
  final String? patientName;
  final int? patientAge;
  final String? patientGender;
  final String? householdId;
  final Set<Programme> programmes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Determine primary programme for the visit
    Programme? primaryProgramme;
    if (programmes.contains(Programme.anc)) {
      primaryProgramme = Programme.anc;
    } else if (programmes.contains(Programme.pnc)) {
      primaryProgramme = Programme.pnc;
    } else if (programmes.contains(Programme.imci)) {
      primaryProgramme = Programme.imci;
    } else if (programmes.contains(Programme.ncd)) {
      primaryProgramme = Programme.ncd;
    } else if (programmes.contains(Programme.tb)) {
      primaryProgramme = Programme.tb;
    } else if (programmes.isNotEmpty) {
      primaryProgramme = programmes.first;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Actions',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () {
                  final data = VisitLandingData(
                    patientId: patientId,
                    patientName: patientName,
                    patientAge: patientAge,
                    patientGender: patientGender,
                    householdId: householdId,
                    programme: primaryProgramme,
                  );
                  context.push(
                    '/patients/visit/$patientId/start',
                    extra: data,
                  );
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start Visit'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  // TODO: Implement referral creation
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Referral creation coming soon'),
                    ),
                  );
                },
                icon: const Icon(Icons.send),
                label: const Text('Open Referral'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  // TODO: Implement call household
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Call household coming soon'),
                    ),
                  );
                },
                icon: const Icon(Icons.phone),
                label: const Text('Call'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
