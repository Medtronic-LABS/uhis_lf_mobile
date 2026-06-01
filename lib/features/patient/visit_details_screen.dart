import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'member_detail_repository.dart';

/// Screen to display detailed information about a patient visit.
/// Based on Spice 2.0 MemberSummaryActivity pattern.
class VisitDetailsScreen extends StatelessWidget {
  const VisitDetailsScreen({
    super.key,
    required this.visit,
    this.patientName,
  });

  final PatientVisit visit;
  final String? patientName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dateFormat = DateFormat('MMMM d, yyyy');
    final timeFormat = DateFormat('h:mm a');

    return Scaffold(
      appBar: AppBar(
        title: Text(visit.serviceProvided ?? visit.encounterType ?? 'Visit Details'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Visit header card
            _buildHeaderCard(context, scheme, dateFormat, timeFormat),
            
            const SizedBox(height: 16),
            
            // Visit details section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSection(
                    context,
                    title: 'Visit Information',
                    icon: Icons.calendar_today_outlined,
                    children: [
                      _buildDetailRow(
                        context,
                        label: 'Service',
                        value: visit.serviceProvided ?? 
                               visit.encounterType ?? 
                               'General Visit',
                      ),
                      _buildDetailRow(
                        context,
                        label: 'Visit Date',
                        value: dateFormat.format(visit.visitDate),
                      ),
                      if (visit.visitNumber != null)
                        _buildDetailRow(
                          context,
                          label: 'Visit Number',
                          value: visit.visitNumber.toString(),
                        ),
                      if (visit.status != null)
                        _buildDetailRow(
                          context,
                          label: 'Status',
                          value: visit.status!,
                          valueColor: _getStatusColor(visit.status!, scheme),
                        ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Provider information
                  if (visit.providerName != null)
                    _buildSection(
                      context,
                      title: 'Provider Information',
                      icon: Icons.person_outline,
                      children: [
                        _buildDetailRow(
                          context,
                          label: 'Provider',
                          value: visit.providerName!,
                        ),
                        // Check for facility from rawJson
                        if (visit.rawJson['facilityName'] != null)
                          _buildDetailRow(
                            context,
                            label: 'Facility',
                            value: visit.rawJson['facilityName'].toString(),
                          ),
                      ],
                    ),
                  
                  if (visit.providerName != null) const SizedBox(height: 16),
                  
                  // Clinical notes
                  if (visit.notes != null && visit.notes!.isNotEmpty)
                    _buildSection(
                      context,
                      title: 'Clinical Notes',
                      icon: Icons.note_outlined,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            visit.notes!,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  
                  if (visit.notes != null && visit.notes!.isNotEmpty)
                    const SizedBox(height: 16),
                  
                  // Additional details from rawJson
                  _buildAdditionalDetails(context, scheme),
                  
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(
    BuildContext context,
    ColorScheme scheme,
    DateFormat dateFormat,
    DateFormat timeFormat,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary,
            scheme.primary.withOpacity(0.8),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (patientName != null) ...[
            Text(
              patientName!,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
          ],
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.onPrimary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getServiceIcon(visit.serviceProvided ?? visit.encounterType),
                  size: 32,
                  color: scheme.onPrimary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      visit.serviceProvided ?? visit.encounterType ?? 'Visit',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: scheme.onPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateFormat.format(visit.visitDate),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onPrimary.withOpacity(0.9),
                          ),
                    ),
                  ],
                ),
              ),
              if (visit.status != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.onPrimary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    visit.status!,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.onPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final scheme = Theme.of(context).colorScheme;
    
    return Card(
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    BuildContext context, {
    required String label,
    required String value,
    Color? valueColor,
  }) {
    final scheme = Theme.of(context).colorScheme;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: valueColor,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdditionalDetails(BuildContext context, ColorScheme scheme) {
    final additionalDetails = <Widget>[];
    final rawJson = visit.rawJson;
    
    // Extract additional fields that might be useful
    final fieldsToShow = {
      'referralStatus': 'Referral Status',
      'referralReason': 'Referral Reason',
      'nextFollowUpDate': 'Next Follow-up',
      'diagnosis': 'Diagnosis',
      'prescription': 'Prescription',
      'labTests': 'Lab Tests',
      'symptoms': 'Symptoms',
      'riskLevel': 'Risk Level',
      'programType': 'Program Type',
      'encounterClass': 'Encounter Type',
      'reasonCode': 'Reason',
      'bloodPressureSystolic': 'BP Systolic',
      'bloodPressureDiastolic': 'BP Diastolic',
      'weight': 'Weight',
      'height': 'Height',
      'bmi': 'BMI',
      'temperature': 'Temperature',
      'pulseRate': 'Pulse Rate',
      'respiratoryRate': 'Respiratory Rate',
    };
    
    for (final entry in fieldsToShow.entries) {
      final value = rawJson[entry.key];
      if (value != null && value.toString().isNotEmpty) {
        String displayValue = value.toString();
        
        // Format date fields
        if (entry.key.toLowerCase().contains('date')) {
          try {
            final date = DateTime.parse(displayValue);
            displayValue = DateFormat('MMMM d, yyyy').format(date);
          } catch (_) {
            // Keep original value if parsing fails
          }
        }
        
        additionalDetails.add(
          _buildDetailRow(
            context,
            label: entry.value,
            value: displayValue,
          ),
        );
      }
    }
    
    // Check for vital signs in nested structure
    final vitalSigns = rawJson['vitalSigns'] ?? rawJson['vitals'];
    if (vitalSigns is Map<String, dynamic>) {
      for (final vitalEntry in vitalSigns.entries) {
        if (vitalEntry.value != null) {
          additionalDetails.add(
            _buildDetailRow(
              context,
              label: _formatLabel(vitalEntry.key),
              value: vitalEntry.value.toString(),
            ),
          );
        }
      }
    }
    
    if (additionalDetails.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return _buildSection(
      context,
      title: 'Additional Details',
      icon: Icons.info_outline,
      children: additionalDetails,
    );
  }

  String _formatLabel(String key) {
    // Convert camelCase to Title Case
    final result = key.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (match) => ' ${match.group(1)}',
    );
    return result[0].toUpperCase() + result.substring(1);
  }

  IconData _getServiceIcon(String? service) {
    if (service == null) return Icons.local_hospital_outlined;
    
    final serviceLower = service.toLowerCase();
    if (serviceLower.contains('anc') || serviceLower.contains('antenatal')) {
      return Icons.pregnant_woman;
    } else if (serviceLower.contains('pnc') || serviceLower.contains('postnatal')) {
      return Icons.child_friendly;
    } else if (serviceLower.contains('immunization') || serviceLower.contains('vaccine')) {
      return Icons.vaccines;
    } else if (serviceLower.contains('ncd') || serviceLower.contains('chronic')) {
      return Icons.monitor_heart_outlined;
    } else if (serviceLower.contains('tb') || serviceLower.contains('tuberculosis')) {
      return Icons.air;
    } else if (serviceLower.contains('mental') || serviceLower.contains('mh')) {
      return Icons.psychology_outlined;
    } else if (serviceLower.contains('screening')) {
      return Icons.health_and_safety;
    } else if (serviceLower.contains('referral')) {
      return Icons.send_outlined;
    } else if (serviceLower.contains('follow')) {
      return Icons.repeat;
    }
    return Icons.local_hospital_outlined;
  }

  Color _getStatusColor(String status, ColorScheme scheme) {
    final statusLower = status.toLowerCase();
    if (statusLower.contains('complete') || statusLower.contains('finished')) {
      return Colors.green;
    } else if (statusLower.contains('pending') || statusLower.contains('in-progress')) {
      return Colors.orange;
    } else if (statusLower.contains('cancel') || statusLower.contains('rejected')) {
      return Colors.red;
    }
    return scheme.onSurface;
  }
}
