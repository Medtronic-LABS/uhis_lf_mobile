/// Read-only detail view of one historical Shukhee teleconsult call, synced
/// in from Frappe (`CallLogHistoryRow`, via `CallLogSyncService`). Deliberately
/// not `_WrapUpView` reused -- that screen is bound to an in-progress
/// `TeleconsultScreen`'s live state machine (polling, prefetching bytes the
/// moment a call completes); this is a plain, stateless-data screen showing
/// whatever a past sync already captured, with documents fetched live, on
/// tap (see [DocumentDownloadButton]) rather than eagerly.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shukhee_sdk/shukhee_sdk.dart';

import '../../core/constants/app_strings.dart';
import '../../core/db/call_log_history_dao.dart';
import '../../core/theme/app_theme.dart';
import 'clinical_data_card.dart';
import 'document_download_button.dart';
import 'shukhee_client_factory.dart';

class TeleconsultCallDetailScreen extends StatelessWidget {
  const TeleconsultCallDetailScreen({super.key, required this.row});

  final CallLogHistoryRow row;

  @override
  Widget build(BuildContext context) {
    final clinicalDataJson = row.clinicalDataJson;
    final clinicalData = clinicalDataJson == null
        ? null
        : ShukheeClinicalData.fromJson(jsonDecode(clinicalDataJson) as Map<String, dynamic>);
    final client = (row.hasPrescription || row.hasInvoice) ? buildShukheeClient(context) : null;

    return Scaffold(
      appBar: AppBar(title: Text(TeleconsultStrings.historyDetailTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(
            row.doctorName == null
                ? TeleconsultStrings.historyDetailTitle
                : 'Dr. ${row.doctorName}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          if (row.doctorSpeciality != null || row.doctorFacility != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                [row.doctorSpeciality, row.doctorFacility].whereType<String>().join(' · '),
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
            ),
          if (row.callDate != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${row.callDate}',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ),
          const SizedBox(height: AppSpacing.h6xl),
          if (row.reason != null && row.reason!.isNotEmpty) ...[
            Text(
              TeleconsultStrings.historyReasonLabel,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted),
            ),
            const SizedBox(height: 2),
            Text(row.reason!),
            const SizedBox(height: AppSpacing.h6xl),
          ],
          if (clinicalData != null) ...[
            ClinicalDataCard(data: clinicalData),
            const SizedBox(height: AppSpacing.h6xl),
          ],
          if (row.hasPrescription || row.hasInvoice)
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (row.hasPrescription)
                  DocumentDownloadButton(
                    client: client!,
                    callLog: row.id,
                    docType: 'prescription',
                    title: TeleconsultStrings.viewPrescription,
                    buttonLabel: TeleconsultStrings.viewPrescription,
                    icon: Icons.description_outlined,
                  ),
                if (row.hasInvoice)
                  DocumentDownloadButton(
                    client: client!,
                    callLog: row.id,
                    docType: 'invoice',
                    title: TeleconsultStrings.viewInvoice,
                    buttonLabel: TeleconsultStrings.viewInvoice,
                    icon: Icons.receipt_long_outlined,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
