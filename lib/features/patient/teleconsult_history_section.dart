/// A patient's full Shukhee teleconsult history, synced in from Frappe's
/// `Call Logs` doctype (see `CallLogSyncService`) -- distinct from the
/// existing `_CombinedTimeline`'s single prescription-icon-per-visit model:
/// a patient can have many historical calls (including ones made from a
/// different device), so this renders as its own section rather than
/// folding into that per-visit-day row model.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shukhee_sdk/shukhee_sdk.dart';

import '../../core/config/app_config.dart';
import '../../core/constants/app_strings.dart';
import '../../core/db/call_log_history_dao.dart';
import '../../core/db/encounter_dao.dart';
import '../../core/theme/app_theme.dart';
import '../teleconsult/teleconsult_call_detail_screen.dart';

class TeleconsultHistorySection extends StatefulWidget {
  const TeleconsultHistorySection({super.key, required this.patientId});

  final String patientId;

  @override
  State<TeleconsultHistorySection> createState() => _TeleconsultHistorySectionState();
}

class _TeleconsultHistorySectionState extends State<TeleconsultHistorySection> {
  List<CallLogHistoryRow>? _rows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TeleconsultHistorySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.patientId != widget.patientId) _load();
  }

  /// Strips a FHIR-style `Resource/id` prefix -- `encounters.patient_id` is
  /// queried with the bare id elsewhere on this screen (see
  /// `VitalsRepository._bareId`); mirrored here so `EncounterDao.idsForPatient`
  /// resolves against the same value regardless of which form
  /// `widget.patientId` arrives in.
  static String _bareId(String id) {
    final slash = id.lastIndexOf('/');
    return slash < 0 ? id : id.substring(slash + 1);
  }

  Future<void> _load() async {
    final encounterDao = context.read<EncounterDao>();
    final callDao = context.read<CallLogHistoryDao>();
    final encounterIds = await encounterDao.idsForPatient(_bareId(widget.patientId));
    final rows = encounterIds.isEmpty
        ? const <CallLogHistoryRow>[]
        : await callDao.getForEncounters(encounterIds);
    if (mounted) setState(() => _rows = rows);
  }

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.teleconsultEnabled) return const SizedBox.shrink();
    final rows = _rows;
    if (rows == null || rows.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            TeleconsultStrings.historyTitle,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final row in rows) _HistoryEntryRow(row: row),
        ],
      ),
    );
  }
}

class _HistoryEntryRow extends StatelessWidget {
  const _HistoryEntryRow({required this.row});

  final CallLogHistoryRow row;

  String? _clinicalSummary() {
    final json = row.clinicalDataJson;
    if (json == null) return null;
    final data = ShukheeClinicalData.fromJson(jsonDecode(json) as Map<String, dynamic>);
    final parts = <String>[];
    if (data.chiefComplaints.isNotEmpty) {
      parts.add(data.chiefComplaints.take(2).join(', '));
    }
    if (data.medicine.isNotEmpty) {
      parts.add('${data.medicine.length} medicine(s)');
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final summary = _clinicalSummary();
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => TeleconsultCallDetailScreen(row: row)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    row.doctorName == null
                        ? TeleconsultStrings.historyDetailTitle
                        : 'Dr. ${row.doctorName}'
                            '${row.doctorSpeciality != null ? ' · ${row.doctorSpeciality}' : ''}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                if (row.callDate != null)
                  Text(
                    DateFormat.yMMMd().format(row.callDate!),
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
              ],
            ),
            if (summary != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  summary,
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
