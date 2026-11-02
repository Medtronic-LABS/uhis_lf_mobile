import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/db/immunisation_dao.dart';
import '../../../core/models/patient.dart';
import '../../../core/theme/app_theme.dart';
import '../assessment_repository.dart';
import 'child_immunization_dto.dart';
import 'epi_card_scanner.dart';
import 'epi_date_validator.dart';
import 'epi_schedule_engine.dart';

/// Confidence tier for one scanned dose row — drives the badge shown next to
/// the vaccine name and whether the row is checked by default.
enum _DoseConfidence {
  /// Online (Gemini) path with model confidence at/above [_clearThreshold],
  /// or an offline-matched code with no finer-grained signal available.
  readClearly,

  /// Has a date but confidence is low — ask the SK to double check it.
  toConfirm,

  /// No legible date for this code at all (explicit `unmatchedRows` entry,
  /// or a target code the scan never matched).
  notOnCard,
}

const double _clearThreshold = 0.7;

/// One reviewable row in the scan-review sheet — one vaccine dose, grouped
/// under its milestone section.
class _ReviewRow {
  _ReviewRow({
    required this.milestoneLabel,
    required this.vaccine,
    required this.confidence,
    DateTime? date,
    bool? checked,
  })  : date = date,
        checked = checked ?? confidence != _DoseConfidence.notOnCard;

  final String milestoneLabel;
  final VaccineEntry vaccine;
  final _DoseConfidence confidence;
  DateTime? date;
  bool checked;
  String? dateError;
}

/// Consolidated post-scan review sheet — replaces opening one
/// [_UpdateStatusSheet] per matched milestone. Shows every scanned dose
/// across all due milestones in one scrollable sheet, grouped by milestone,
/// each with its own checkbox + confidence badge + editable date, and a
/// single bulk "Update N doses" action that saves everything in one
/// CHILD_IMMUNIZATION assessment.
///
/// Returns `true` from [Navigator.pop] when the SK chose "Retake photo", so
/// the caller can relaunch the scan screen; returns nothing (null) after a
/// successful save or a plain dismiss.
class EpiScanReviewSheet extends StatefulWidget {
  const EpiScanReviewSheet({
    super.key,
    required this.milestones,
    required this.scanResult,
    required this.patient,
    required this.patientId,
    required this.patientName,
    required this.ageLabel,
    this.dob,
    this.encounterId,
    this.memberId,
    this.householdId,
    this.householdMemberLocalId,
    required this.onSaved,
  });

  /// Only the milestones with at least one matched, not-yet-recorded dose —
  /// same filter [ImmunisationTimelineScreen._reviewMatchedMilestones] used.
  final List<VaccineMilestone> milestones;
  final EpiScanResult scanResult;
  final Patient? patient;
  final String patientId;
  final String patientName;
  final String ageLabel;
  final DateTime? dob;
  final String? encounterId;
  final String? memberId;
  final String? householdId;
  final int? householdMemberLocalId;

  /// Invoked after a successful bulk save so the caller can refresh the
  /// timeline (mirrors [_UpdateStatusSheet.onRecorded]).
  final VoidCallback onSaved;

  @override
  State<EpiScanReviewSheet> createState() => _EpiScanReviewSheetState();
}

class _EpiScanReviewSheetState extends State<EpiScanReviewSheet> {
  late final List<_ReviewRow> _rows = _buildRows();
  bool _saving = false;

  List<_ReviewRow> _buildRows() {
    final result = widget.scanResult;
    final matched = result.matchedCodes.toSet();
    final notOnCardCodes = result.unmatchedRows.map((r) => r.vaccineCode).toSet();
    final rows = <_ReviewRow>[];
    for (final milestone in widget.milestones) {
      for (final v in milestone.vaccines) {
        // Only a dose actually eligible today (dueNow) or missed — a
        // training card can carry every milestone up to 9 months regardless
        // of this child's real age, so an OCR match alone doesn't mean the
        // dose belongs in this review (the caller pre-filters milestones the
        // same way, but a milestone can mix per-vaccine scheduledDates).
        if (v.status != VaccineStatus.dueNow && v.status != VaccineStatus.missed) {
          continue;
        }
        final isMatched = matched.contains(v.code);
        final isNotOnCard = notOnCardCodes.contains(v.code);
        if (!isMatched && !isNotOnCard) continue; // not part of this scan

        DateTime? date = result.dateByCode[v.code] ?? result.extractedDate;
        final confidenceValue = result.confidenceByCode[v.code];

        final _DoseConfidence tier;
        if (isNotOnCard || date == null) {
          tier = _DoseConfidence.notOnCard;
          date = null;
        } else if (confidenceValue == null) {
          // Offline path (no per-dose confidence) — a global regex date
          // applied uniformly is a best-effort read, not a confirmed one.
          tier = result.engine == EpiScanEngine.geminiVision
              ? _DoseConfidence.readClearly
              : _DoseConfidence.toConfirm;
        } else {
          tier = confidenceValue >= _clearThreshold
              ? _DoseConfidence.readClearly
              : _DoseConfidence.toConfirm;
        }

        final row = _ReviewRow(
          milestoneLabel: milestone.label,
          vaccine: v,
          confidence: tier,
          // Null only for notOnCard rows — renders the "+ Add date" prompt
          // instead of a pre-filled box; never silently default to today.
          date: date,
        );
        // Flag a scan-prefilled date against DOB / this dose's minimum
        // eligible age immediately, not only after the SK touches the row —
        // a false-positive card match (e.g. a 9-month dose on a 3-month-old)
        // should read as wrong on first sight.
        if (date != null) {
          row.dateError = validateVaccinationDate(
            date,
            dob: widget.dob,
            earliestEligibleDate: v.scheduledDate,
          );
        }
        rows.add(row);
      }
    }
    return rows;
  }

  int get _readClearlyCount =>
      _rows.where((r) => r.confidence == _DoseConfidence.readClearly).length;
  int get _toConfirmCount =>
      _rows.where((r) => r.confidence == _DoseConfidence.toConfirm).length;
  int get _notOnCardCount =>
      _rows.where((r) => r.confidence == _DoseConfidence.notOnCard).length;
  int get _checkedCount => _rows.where((r) => r.checked).length;

  List<String> get _milestoneOrder {
    final seen = <String>{};
    final order = <String>[];
    for (final r in _rows) {
      if (seen.add(r.milestoneLabel)) order.add(r.milestoneLabel);
    }
    return order;
  }

  Future<void> _pickDate(_ReviewRow row) async {
    final firstDate = widget.dob ?? DateTime(2020);
    final wanted = row.date ?? DateTime.now();
    // showDatePicker asserts firstDate <= initialDate — a scan-prefilled
    // date can be before DOB (the exact violation this sheet flags), so
    // clamp instead of passing it straight through and crashing on open.
    final initialDate = wanted.isBefore(firstDate) ? firstDate : wanted;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      row.date = picked;
      row.checked = true;
      row.dateError = validateVaccinationDate(
        picked,
        dob: widget.dob,
        earliestEligibleDate: row.vaccine.scheduledDate,
      );
    });
  }

  Future<void> _save() async {
    final toSave = _rows.where((r) => r.checked).toList();
    if (toSave.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    var hasError = false;
    setState(() {
      for (final row in toSave) {
        final date = row.date;
        row.dateError = date == null
            ? EpiStrings.scanNoDateFound
            : validateVaccinationDate(
                date,
                dob: widget.dob,
                earliestEligibleDate: row.vaccine.scheduledDate,
              );
        if (row.dateError != null) hasError = true;
      }
    });
    if (hasError) return;

    setState(() => _saving = true);
    final immunisationDao = context.read<ImmunisationDao>();
    final assessmentRepo = context.read<AssessmentRepository>();

    try {
      final immunisationRows = toSave
          .map((r) => ImmunisationRow(
                id: '${widget.patientId}_${r.vaccine.code}',
                patientId: widget.patientId,
                vaccineCode: r.vaccine.code,
                dueAt: r.vaccine.scheduledDate.millisecondsSinceEpoch,
                givenAt: r.date!.millisecondsSinceEpoch,
                status: 'Vaccinated',
                rawJson: '{"vaccineName":"${r.vaccine.display}"'
                    ',"milestone":"${r.milestoneLabel}"}',
              ))
          .toList();
      await immunisationDao.upsertMany(immunisationRows);

      final records = toSave
          .map((r) => ChildImmunizationVaccinationRecord(
                vaccineName: r.vaccine.display,
                status: 'Vaccinated',
                vaccinatedDate: ChildImmunizationVaccinationRecord.dateWire(r.date!),
              ))
          .toList();

      await assessmentRepo.saveAssessment(
        assessmentType: 'CHILD_IMMUNIZATION',
        assessmentDetails: {
          'vaccinations': records.map((r) => r.toJson()).toList(),
        },
        householdMemberLocalId: widget.householdMemberLocalId ?? 0,
        memberId: widget.memberId,
        householdId: widget.householdId,
        patientId: widget.patientId,
        villageId: widget.patient?.villageId,
        encounterId: widget.encounterId,
      );
      unawaited(assessmentRepo.syncPendingAssessments());

      if (mounted) {
        Navigator.of(context).pop();
        widget.onSaved();
      }
    } on Object catch (e) {
      debugPrint('[EpiScanReviewSheet] save error: $e');
      if (mounted) setState(() => _saving = false);
    }
  }

  void _retake() => Navigator.of(context).pop(true);

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(0, 0, 0, bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD1D5DB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        EpiStrings.scanReviewTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: AppColors.navy,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.dob != null
                            ? '${widget.patientName} · ${EpiStrings.scanReviewDobLabel} '
                                '${DateFormat('d MMM yyyy').format(widget.dob!)}'
                            : widget.patientName,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF3F4F6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_readClearlyCount > 0)
                  _SummaryChip(
                    label: EpiStrings.scanReviewDosesRead(_readClearlyCount),
                    background: const Color(0xFFEEF2FF),
                    foreground: const Color(0xFF4338CA),
                  ),
                if (_toConfirmCount > 0)
                  _SummaryChip(
                    label: EpiStrings.scanReviewToConfirm(_toConfirmCount),
                    background: const Color(0xFFFEF3C7),
                    foreground: const Color(0xFF92400E),
                  ),
                if (_notOnCardCount > 0)
                  _SummaryChip(
                    label: EpiStrings.scanReviewNotOnCard(_notOnCardCount),
                    background: const Color(0xFFF3F4F6),
                    foreground: const Color(0xFF4B5563),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                EpiStrings.scanReviewInstructions,
                style: const TextStyle(fontSize: 12.5, color: AppColors.navy, height: 1.4),
              ),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              children: [
                for (final label in _milestoneOrder) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 4),
                    child: Text(
                      label.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                  for (final row in _rows.where((r) => r.milestoneLabel == label))
                    _ReviewRowTile(
                      row: row,
                      onCheckedChanged: (v) => setState(() => row.checked = v),
                      onTapDate: () => _pickDate(row),
                    ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving || _checkedCount == 0 ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : Text(
                            EpiStrings.scanReviewUpdateCta(_checkedCount),
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _saving ? null : _retake,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textMuted,
                      side: const BorderSide(color: Color(0xFFE5E7EB), width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      EpiStrings.scanReviewRetakePhoto,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const _kGreen = Color(0xFF059669);

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.background, required this.foreground});
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: foreground),
      ),
    );
  }
}

class _ReviewRowTile extends StatelessWidget {
  const _ReviewRowTile({required this.row, required this.onCheckedChanged, required this.onTapDate});
  final _ReviewRow row;
  final ValueChanged<bool> onCheckedChanged;
  final VoidCallback onTapDate;

  @override
  Widget build(BuildContext context) {
    final hasError = row.dateError != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Checkbox(
                  value: row.checked,
                  activeColor: _kGreen,
                  onChanged: (v) => onCheckedChanged(v ?? false),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      EpiVaccineStrings.display(row.vaccine.code, row.vaccine.display),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.navy),
                    ),
                    const SizedBox(height: 4),
                    _ConfidenceBadge(confidence: row.confidence),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 130,
                child: row.confidence == _DoseConfidence.notOnCard && row.date == null
                    ? _AddDateButton(onTap: onTapDate)
                    : _InlineDateField(date: row.date!, onTap: onTapDate, hasError: hasError),
              ),
            ],
          ),
          if (hasError)
            Padding(
              padding: const EdgeInsets.only(left: 44, top: 2),
              child: Text(
                row.dateError!,
                style: const TextStyle(fontSize: 11, color: Color(0xFFEF4444)),
              ),
            ),
        ],
      ),
    );
  }
}

class _ConfidenceBadge extends StatelessWidget {
  const _ConfidenceBadge({required this.confidence});
  final _DoseConfidence confidence;

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color background;
    final Color foreground;
    switch (confidence) {
      case _DoseConfidence.readClearly:
        label = EpiStrings.scanReviewReadClearly;
        background = const Color(0xFFD1FAE5);
        foreground = const Color(0xFF065F46);
        break;
      case _DoseConfidence.toConfirm:
        label = EpiStrings.scanReviewConfirmDate;
        background = const Color(0xFFFEF3C7);
        foreground = const Color(0xFF92400E);
        break;
      case _DoseConfidence.notOnCard:
        label = EpiStrings.scanReviewNotOnCardBadge;
        background = const Color(0xFFF3F4F6);
        foreground = const Color(0xFF4B5563);
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: foreground),
      ),
    );
  }
}

class _InlineDateField extends StatelessWidget {
  const _InlineDateField({required this.date, required this.onTap, required this.hasError});
  final DateTime date;
  final VoidCallback onTap;
  final bool hasError;

  String _format(DateTime d) {
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    return '$day/$month/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: hasError ? const Color(0xFFEF4444) : const Color(0xFFE5E7EB), width: 1.5),
        ),
        child: Text(
          _format(date),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: AppColors.navy, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _AddDateButton extends StatelessWidget {
  const _AddDateButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5, style: BorderStyle.solid),
        ),
        child: Text(
          EpiStrings.scanReviewAddDate,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
