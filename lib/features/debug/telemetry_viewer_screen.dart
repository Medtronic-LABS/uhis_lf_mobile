/// Dev-only report screen for AI Scribe / counselling telemetry.
///
/// Pick a date range, generate, read the five metric groups, download. Stands
/// in for the server dashboard until the AI-service endpoint exists — and
/// afterwards remains the on-device way to confirm what this handset actually
/// captured, independent of what reached the server.
///
/// All aggregation lives in [TelemetryReportBuilder]; this file only renders.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_strings.dart';
import '../../core/telemetry/telemetry_dao.dart';
import '../../core/telemetry/telemetry_report.dart';
import '../../core/theme/app_theme.dart';

class TelemetryViewerScreen extends StatefulWidget {
  const TelemetryViewerScreen({super.key});

  @override
  State<TelemetryViewerScreen> createState() => _TelemetryViewerScreenState();
}

class _TelemetryViewerScreenState extends State<TelemetryViewerScreen> {
  late DateTime _from;
  late DateTime _to;
  TelemetryReport? _report;
  ({int total, int pending})? _counts;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _to = DateTime(now.year, now.month, now.day);
    _from = _to.subtract(const Duration(days: 6)); // a week, inclusive
    _generate();
  }

  Future<void> _pick({required bool isFrom}) async {
    final initial = isFrom ? _from : _to;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2026),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        // Keep the range coherent rather than silently returning nothing.
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = picked;
        if (_to.isBefore(_from)) _from = _to;
      }
    });
    await _generate();
  }

  Future<void> _generate() async {
    setState(() => _busy = true);
    try {
      final dao = context.read<TelemetryDao>();
      final events = await dao.inRange(_from, _to);
      final counts = await dao.counts();
      if (!mounted) return;
      setState(() {
        _report = TelemetryReportBuilder.build(
          from: _from,
          to: _to,
          events: events,
        );
        _counts = counts;
      });
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, dynamic> _asJson(TelemetryReport r) => {
        'from': _dateOnly(r.from),
        'to': _dateOnly(r.to),
        'adoption': {
          'visits': r.visitCount,
          'scribeVisits': r.scribeVisitCount,
          'manualVisits': r.manualVisitCount,
          'usersUsingScribe': r.usersUsingScribe,
          'usersManualOnly': r.usersManualOnly,
        },
        'timeToComplete': {
          'scribeMedianMs': r.scribeMedianDurationMs,
          'manualMedianMs': r.manualMedianDurationMs,
          'scribeSamples': r.scribeDurationSampleCount,
          'manualSamples': r.manualDurationSampleCount,
          'caveat': TelemetryStrings.durationCaveat,
        },
        'fieldsCaptured': {
          'totalAiFields': r.totalAiFields,
          'avgPerScribeVisit': r.avgAiFieldsPerScribeVisit,
          'captureRatePct': r.captureRatePct,
          'denominators': {
            'extractableVisible': r.totalExtractableVisible,
            'rendered': r.totalRendered,
            'library': r.totalLibrary,
          },
        },
        'provenance': {
          'manual': r.manualFieldTotal,
          'prefilled': r.prefilledTotal,
          'derived': r.derivedTotal,
          'aiOverridden': r.aiOverriddenTotal,
          'disagreementRatePct': r.disagreementRatePct,
          'caveat': TelemetryStrings.provenanceCaveat,
        },
        'correction': {
          'aiFilled': r.aiFilledTotal,
          'corrected': r.aiCorrectedTotal,
          'unchanged': r.aiAcceptedUnchangedTotal,
          'ratePct': r.manualCorrectionRatePct,
          'caveat': TelemetryStrings.correctionCaveat,
          'perField': [
            for (final f in r.fieldAccuracy)
              {
                'fieldId': f.fieldId,
                'filled': f.filled,
                'corrected': f.corrected,
                'ratePct': f.correctionRatePct,
              }
          ],
        },
        'counselling': {
          'smsComposeOpened': r.smsComposeOpened,
          'whatsappComposeOpened': r.whatsappComposeOpened,
          'contactSmsOpened': r.contactSmsOpened,
          'contactWhatsappOpened': r.contactWhatsappOpened,
          'caveat': TelemetryStrings.composeCaveat,
        },
      };

  /// Per-field CSV — the shape a spreadsheet or the future dashboard wants.
  String _asCsv(TelemetryReport r) {
    final rows = <String>['field_id,filled,corrected,correction_rate_pct'];
    for (final f in r.fieldAccuracy) {
      rows.add('${f.fieldId},${f.filled},${f.corrected},'
          '${f.correctionRatePct?.toStringAsFixed(1) ?? ''}');
    }
    return rows.join('\n');
  }

  Future<void> _download() async {
    final report = _report;
    if (report == null) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final stamp = '${_dateOnly(report.from)}_${_dateOnly(report.to)}';
      final jsonFile = File('${dir.path}/ai_scribe_report_$stamp.json');
      final csvFile = File('${dir.path}/ai_scribe_fields_$stamp.csv');
      await jsonFile.writeAsString(
          const JsonEncoder.withIndent('  ').convert(_asJson(report)));
      await csvFile.writeAsString(_asCsv(report));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(TelemetryStrings.savedTo(dir.path))),
      );
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _copyJson() async {
    final report = _report;
    if (report == null) return;
    await Clipboard.setData(ClipboardData(
        text: const JsonEncoder.withIndent('  ').convert(_asJson(report))));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(TelemetryStrings.copyJson)));
  }

  static String _dateOnly(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// `null` renders as an em dash, never 0% — a rate with no denominator is
  /// unknown, not zero.
  static String _pct(double? v) =>
      v == null ? TelemetryStrings.notAvailable : '${v.toStringAsFixed(1)}%';

  static String _num(num? v) => v == null
      ? TelemetryStrings.notAvailable
      : (v is int ? '$v' : v.toStringAsFixed(1));

  static String _duration(int? ms) {
    if (ms == null) return TelemetryStrings.notAvailable;
    final total = Duration(milliseconds: ms);
    final m = total.inMinutes;
    final s = total.inSeconds % 60;
    return m > 0 ? '${m}m ${s}s' : '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(title: Text(TelemetryStrings.title)),
      body: Column(
        children: [
          _rangeBar(),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: report == null
                ? const SizedBox.shrink()
                : ListView(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    children: [
                      if (report.visitCount == 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                          child: Text(TelemetryStrings.noData),
                        ),
                      _section(TelemetryStrings.adoption, [
                        _row(TelemetryStrings.scribeUsers,
                            '${report.usersUsingScribe}'),
                        _row(TelemetryStrings.manualUsers,
                            '${report.usersManualOnly}'),
                        _row(TelemetryStrings.scribeVisits,
                            '${report.scribeVisitCount}'),
                        _row(TelemetryStrings.manualVisits,
                            '${report.manualVisitCount}'),
                      ]),
                      _section(
                        TelemetryStrings.timeToComplete,
                        [
                          _row(TelemetryStrings.medianWithScribe,
                              _duration(report.scribeMedianDurationMs)),
                          _row(TelemetryStrings.medianManual,
                              _duration(report.manualMedianDurationMs)),
                        ],
                        caveat: TelemetryStrings.durationCaveat,
                      ),
                      _section(TelemetryStrings.fieldsCaptured, [
                        _row(TelemetryStrings.totalAiFields,
                            '${report.totalAiFields}'),
                        _row(TelemetryStrings.avgAiFields,
                            _num(report.avgAiFieldsPerScribeVisit)),
                        _row(TelemetryStrings.captureRate,
                            _pct(report.captureRatePct)),
                        _row(TelemetryStrings.fieldsVisible,
                            '${report.totalExtractableVisible}'),
                        _row(TelemetryStrings.fieldsRendered,
                            '${report.totalRendered}'),
                        _row(TelemetryStrings.fieldsInForm,
                            '${report.totalLibrary}'),
                      ]),
                      _section(
                        TelemetryStrings.accuracy,
                        [
                          _row(TelemetryStrings.aiFilled,
                              '${report.aiFilledTotal}'),
                          _row(TelemetryStrings.aiCorrected,
                              '${report.aiCorrectedTotal}'),
                          _row(TelemetryStrings.aiUnchanged,
                              '${report.aiAcceptedUnchangedTotal}'),
                          _row(TelemetryStrings.correctionRate,
                              _pct(report.manualCorrectionRatePct)),
                        ],
                        caveat: TelemetryStrings.correctionCaveat,
                      ),
                      _section(
                        TelemetryStrings.provenance,
                        [
                          _row(TelemetryStrings.manualFields,
                              '${report.manualFieldTotal}'),
                          _row(TelemetryStrings.prefilledFields,
                              '${report.prefilledTotal}'),
                          _row(TelemetryStrings.derivedFields,
                              '${report.derivedTotal}'),
                          _row(TelemetryStrings.aiOverridden,
                              '${report.aiOverriddenTotal}'),
                          _row(TelemetryStrings.disagreementRate,
                              _pct(report.disagreementRatePct)),
                        ],
                        caveat: TelemetryStrings.provenanceCaveat,
                      ),
                      if (report.fieldAccuracy.isNotEmpty)
                        _section(
                          TelemetryStrings.worstFields,
                          [
                            for (final f in report.fieldAccuracy.take(15))
                              _row('${f.fieldId}  (${f.corrected}/${f.filled})',
                                  _pct(f.correctionRatePct)),
                          ],
                        ),
                      _section(
                        TelemetryStrings.counselling,
                        [
                          _row(TelemetryStrings.smsOpened,
                              '${report.smsComposeOpened}'),
                          _row(TelemetryStrings.whatsappOpened,
                              '${report.whatsappComposeOpened}'),
                        ],
                        caveat: TelemetryStrings.composeCaveat,
                      ),
                      _section(
                        TelemetryStrings.contactShares,
                        [
                          _row(TelemetryStrings.contactSms,
                              '${report.contactSmsOpened}'),
                          _row(TelemetryStrings.contactWhatsapp,
                              '${report.contactWhatsappOpened}'),
                        ],
                        caveat: TelemetryStrings.contactCaveat,
                      ),
                      if (_counts != null)
                        _section(TelemetryStrings.eventCount, [
                          _row(TelemetryStrings.eventCount,
                              '${_counts!.total}'),
                          _row(TelemetryStrings.pendingUpload,
                              '${_counts!.pending}'),
                        ]),
                    ],
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _report == null ? null : _copyJson,
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: Text(TelemetryStrings.copyJson),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _report == null ? null : _download,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text(TelemetryStrings.download),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rangeBar() => Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl, vertical: AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: _dateButton(
                  TelemetryStrings.from, _from, () => _pick(isFrom: true)),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _dateButton(
                  TelemetryStrings.to, _to, () => _pick(isFrom: false)),
            ),
            const SizedBox(width: AppSpacing.md),
            FilledButton(
              onPressed: _busy ? null : _generate,
              child: Text(TelemetryStrings.generate),
            ),
          ],
        ),
      );

  Widget _dateButton(String label, DateTime value, VoidCallback onTap) =>
      OutlinedButton(
        onPressed: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            Text(_dateOnly(value)),
          ],
        ),
      );

  Widget _section(String title, List<Widget> rows, {String? caveat}) => Card(
        margin: const EdgeInsets.only(bottom: AppSpacing.xl),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: AppSpacing.md),
              ...rows,
              if (caveat != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(caveat,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: Theme.of(context).hintColor)),
              ],
            ],
          ),
        ),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(value,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );
}
