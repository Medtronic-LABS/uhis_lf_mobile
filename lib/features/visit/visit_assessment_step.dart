import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'assessment_repository.dart';
import 'forms/anc_assessment_form.dart';
import 'forms/iccm_assessment_form.dart';
import 'forms/ncd_assessment_form.dart';
import 'forms/tb_assessment_form.dart';
import 'models/anc_assessment.dart';
import 'models/iccm_assessment.dart';
import 'models/ncd_assessment.dart';
import 'models/tb_assessment.dart';

/// Assessment step screen that displays the appropriate form based on programme.
class VisitAssessmentStep extends StatefulWidget {
  const VisitAssessmentStep({
    super.key,
    required this.visitId,
    required this.programme,
    this.patientId,
    this.memberId,
    this.householdId,
    this.villageId,
    this.householdMemberLocalId,
    this.patientAge,
    this.gestationalWeeks,
  });

  final String visitId;
  final String programme;
  final String? patientId;
  final String? memberId;
  final String? householdId;
  final String? villageId;
  final int? householdMemberLocalId;
  final int? patientAge;
  final int? gestationalWeeks;

  @override
  State<VisitAssessmentStep> createState() => _VisitAssessmentStepState();
}

class _VisitAssessmentStepState extends State<VisitAssessmentStep> {
  // Form data
  NcdAssessment? _ncdData;
  TbAssessment? _tbData;
  AncAssessment? _ancData;
  IccmAssessment? _iccmData;

  bool _isSubmitting = false;

  String get _programmeTitle {
    switch (widget.programme.toUpperCase()) {
      case 'NCD':
        return 'NCD Assessment';
      case 'TB':
        return 'TB Screening';
      case 'ANC':
        return 'ANC Assessment';
      case 'ICCM':
      case 'IMCI':
        return 'ICCM Assessment';
      default:
        return 'Assessment';
    }
  }

  bool get _referralRecommended {
    switch (widget.programme.toUpperCase()) {
      case 'TB':
        return _tbData?.referralRecommended ?? false;
      case 'ANC':
        return _ancData?.referralRecommended ?? false;
      case 'ICCM':
      case 'IMCI':
        return _iccmData?.referralRecommended ?? false;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_programmeTitle),
        actions: [
          if (_referralRecommended)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                label: const Text('Referral'),
                avatar: const Icon(Icons.warning, size: 16),
                backgroundColor: theme.colorScheme.errorContainer,
                labelStyle: TextStyle(
                  color: theme.colorScheme.onErrorContainer,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
      body: _buildForm(),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _isSubmitting ? null : _onSubmit,
            child: _isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Complete Assessment'),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    switch (widget.programme.toUpperCase()) {
      case 'NCD':
        return NcdAssessmentForm(
          initialData: _ncdData,
          patientAge: widget.patientAge,
          onChanged: (data) => _ncdData = data,
        );
      case 'TB':
        return TbAssessmentForm(
          initialData: _tbData,
          onChanged: (data) {
            _tbData = data;
            setState(() {}); // Rebuild to update referral chip
          },
        );
      case 'ANC':
        return AncAssessmentForm(
          initialData: _ancData,
          gestationalWeeks: widget.gestationalWeeks,
          onChanged: (data) {
            _ancData = data;
            setState(() {}); // Rebuild to update referral chip
          },
        );
      case 'ICCM':
      case 'IMCI':
        final ageInMonths = widget.patientAge != null
            ? widget.patientAge! * 12
            : null; // Convert years to months
        return IccmAssessmentForm(
          initialData: _iccmData,
          ageInMonths: ageInMonths,
          onChanged: (data) {
            _iccmData = data;
            setState(() {}); // Rebuild to update referral chip
          },
        );
      default:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.construction, size: 64),
              const SizedBox(height: 16),
              Text(
                'Unknown programme: ${widget.programme}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        );
    }
  }

  Future<void> _onSubmit() async {
    setState(() => _isSubmitting = true);

    try {
      // Get form data as JSON
      final Map<String, dynamic> assessmentData;
      final List<String>? referredReasons;
      
      switch (widget.programme.toUpperCase()) {
        case 'NCD':
          assessmentData = _ncdData?.toJson() ?? {};
          referredReasons = null;
          break;
        case 'TB':
          assessmentData = _tbData?.toJson() ?? {};
          referredReasons = _tbData?.isPositive == true 
              ? ['Positive TB Screen'] 
              : null;
          break;
        case 'ANC':
          assessmentData = _ancData?.toJson() ?? {};
          referredReasons = _ancData?.referralRecommended == true
              ? ['ANC Danger Signs']
              : null;
          break;
        case 'ICCM':
        case 'IMCI':
          assessmentData = _iccmData?.toJson() ?? {};
          referredReasons = _iccmData?.referralRecommended == true
              ? _iccmData!.conditionsSummary
              : null;
          break;
        default:
          assessmentData = {};
          referredReasons = null;
      }

      // Save to local DB via AssessmentRepository (offline-first)
      final repo = context.read<AssessmentRepository>();
      final localId = await repo.saveAssessment(
        assessmentType: widget.programme,
        assessmentDetails: assessmentData,
        householdMemberLocalId: widget.householdMemberLocalId ?? 0,
        memberId: widget.memberId,
        householdId: widget.householdId,
        patientId: widget.patientId,
        villageId: widget.villageId,
        isReferred: _referralRecommended,
        referralStatus: _referralRecommended ? 'Referred' : 'Recovered',
        referredReasons: referredReasons,
      );

      debugPrint('Assessment saved locally with ID: $localId');
      debugPrint('Referral recommended: $_referralRecommended');

      // Navigate to completion screen
      if (mounted) {
        _showCompletionDialog();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save assessment: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showCompletionDialog() {
    final theme = Theme.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              _referralRecommended ? Icons.warning : Icons.check_circle,
              color: _referralRecommended
                  ? theme.colorScheme.error
                  : Colors.green,
            ),
            const SizedBox(width: 12),
            const Text('Assessment Complete'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$_programmeTitle has been saved.'),
            if (_referralRecommended) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning,
                        color: theme.colorScheme.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Referral is recommended based on findings.',
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (_referralRecommended)
            OutlinedButton(
              onPressed: () {
                Navigator.pop(ctx);
                // TODO: Navigate to create referral
                context.go('/patients');
              },
              child: const Text('Create Referral'),
            ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/patients');
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
