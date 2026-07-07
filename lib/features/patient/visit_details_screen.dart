import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_theme.dart';
import 'member_detail_repository.dart';

/// Screen to display detailed information about a patient visit.
/// Based on Spice 2.0 MemberSummaryActivity pattern.
/// 
/// Fetches detailed visit information from medical-review/history endpoint
/// using the encounterId to get diagnosis, vitals, presenting complaints, etc.
class VisitDetailsScreen extends StatefulWidget {
  const VisitDetailsScreen({
    super.key,
    required this.visit,
    this.patientName,
  });

  final PatientVisit visit;
  final String? patientName;

  @override
  State<VisitDetailsScreen> createState() => _VisitDetailsScreenState();
}

class _VisitDetailsScreenState extends State<VisitDetailsScreen> {
  Future<VisitDetails?>? _detailsFuture;
  bool _loadedDetails = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loadedDetails) {
      _loadedDetails = true;
      _fetchDetails();
    }
  }

  void _fetchDetails() {
    final repo = context.read<MemberDetailRepository>();
    final encounterId = widget.visit.id;
    final patientRef = widget.visit.rawJson['patientReference']?.toString();
    final memberRef = widget.visit.rawJson['memberReference']?.toString() ??
        widget.visit.rawJson['memberId']?.toString();
    final type = widget.visit.rawJson['type']?.toString();
    
    // ignore: avoid_print
    print('[VisitDetailsScreen] Fetching details for encounterId=$encounterId, memberRef=$memberRef');
    
    setState(() {
      _detailsFuture = repo.getVisitDetails(
        encounterId,
        patientReference: patientRef,
        memberReference: memberRef,
        type: type,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dateFormat = DateFormat('MMMM d, yyyy');
    final timeFormat = DateFormat('h:mm a');

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.visit.serviceProvided ??
            widget.visit.encounterType ??
            VisitDetailsStrings.fallbackTitle),
        elevation: 0,
      ),
      body: FutureBuilder<VisitDetails?>(
        future: _detailsFuture,
        builder: (context, snapshot) {
          final details = snapshot.data;
          final isLoading = snapshot.connectionState == ConnectionState.waiting;
          
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Visit header card
                _buildHeaderCard(context, scheme, dateFormat, timeFormat),
                
                const SizedBox(height: 16),
                
                // Loading indicator
                if (isLoading)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                
                // Visit details section
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSection(
                        context,
                        title: VisitDetailsStrings.sectionVisitInformation,
                        icon: Icons.calendar_today_outlined,
                        children: [
                          _buildDetailRow(
                            context,
                            label: VisitDetailsStrings.labelService,
                            value: details?.visitType ??
                                   widget.visit.serviceProvided ??
                                   widget.visit.encounterType ??
                                   VisitDetailsStrings.generalVisitFallback,
                          ),
                          _buildDetailRow(
                            context,
                            label: VisitDetailsStrings.labelVisitDate,
                            value: dateFormat.format(widget.visit.visitDate),
                          ),
                          if (details?.dateOfReview != null)
                            _buildDetailRow(
                              context,
                              label: VisitDetailsStrings.labelReviewDate,
                              value: _formatDate(details!.dateOfReview!),
                            ),
                          if (widget.visit.visitNumber != null || 
                              details?.reviewDetails?.visitNumber != null)
                            _buildDetailRow(
                              context,
                              label: VisitDetailsStrings.labelVisitNumber,
                              value: (details?.reviewDetails?.visitNumber ?? 
                                     widget.visit.visitNumber).toString(),
                            ),
                          if (widget.visit.status != null)
                            _buildDetailRow(
                              context,
                              label: VisitDetailsStrings.labelStatus,
                              value: widget.visit.status!,
                              valueColor: _getStatusColor(widget.visit.status!, scheme),
                            ),
                          if (details?.visitType != null)
                            _buildDetailRow(
                              context,
                              label: VisitDetailsStrings.labelVisitType,
                              value: _formatVisitType(details!.visitType!),
                            ),
                          if (details?.reviewDetails?.patientStatus != null)
                            _buildDetailRow(
                              context,
                              label: VisitDetailsStrings.labelPatientStatus,
                              value: details!.reviewDetails!.patientStatus!,
                            ),
                          if (details?.id != null)
                            _buildDetailRow(
                              context,
                              label: VisitDetailsStrings.labelEncounterId,
                              value: details!.id!,
                            ),
                        ],
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Diagnosis section (from detailed response)
                      if (details?.reviewDetails?.diagnosis != null &&
                          details!.reviewDetails!.diagnosis!.isNotEmpty)
                        _buildDiagnosisSection(context, details.reviewDetails!.diagnosis!),
                      
                      if (details?.reviewDetails?.diagnosis != null &&
                          details!.reviewDetails!.diagnosis!.isNotEmpty)
                        const SizedBox(height: 16),
                      
                      // Presenting Complaints section
                      if (details?.reviewDetails?.presentingComplaints != null &&
                          details!.reviewDetails!.presentingComplaints!.isNotEmpty)
                        _buildListSection(
                          context,
                          title: VisitDetailsStrings.sectionPresentingComplaints,
                          icon: Icons.medical_information_outlined,
                          items: details.reviewDetails!.presentingComplaints!,
                          notes: details.reviewDetails!.presentingComplaintsNotes,
                        ),
                      
                      if (details?.reviewDetails?.presentingComplaints != null &&
                          details!.reviewDetails!.presentingComplaints!.isNotEmpty)
                        const SizedBox(height: 16),
                      
                      // Systemic Examinations section
                      if (details?.reviewDetails?.systemicExaminations != null &&
                          details!.reviewDetails!.systemicExaminations!.isNotEmpty)
                        _buildListSection(
                          context,
                          title: VisitDetailsStrings.sectionSystemicExaminations,
                          icon: Icons.health_and_safety_outlined,
                          items: details.reviewDetails!.systemicExaminations!,
                          notes: details.reviewDetails!.systemicExaminationsNotes,
                        ),
                      
                      if (details?.reviewDetails?.systemicExaminations != null &&
                          details!.reviewDetails!.systemicExaminations!.isNotEmpty)
                        const SizedBox(height: 16),
                      
                      // Obstetric Examinations section
                      if (details?.reviewDetails?.obstetricExaminations != null &&
                          details!.reviewDetails!.obstetricExaminations!.isNotEmpty)
                        _buildListSection(
                          context,
                          title:
                              VisitDetailsStrings.sectionObstetricExaminations,
                          icon: Icons.pregnant_woman,
                          items: details.reviewDetails!.obstetricExaminations!,
                          notes: details.reviewDetails!.obstetricExaminationsNotes,
                        ),
                      
                      if (details?.reviewDetails?.obstetricExaminations != null &&
                          details!.reviewDetails!.obstetricExaminations!.isNotEmpty)
                        const SizedBox(height: 16),
                      
                      // Labour/Delivery section
                      if (details?.reviewDetails?.labourDTO != null)
                        _buildLabourSection(context, details!.reviewDetails!.labourDTO!),
                      
                      if (details?.reviewDetails?.labourDTO != null)
                        const SizedBox(height: 16),
                      
                      // Neonate/Baby section
                      if (_hasNeonateInfo(details?.reviewDetails))
                        _buildNeonateSection(context, details!.reviewDetails!),
                      
                      if (_hasNeonateInfo(details?.reviewDetails))
                        const SizedBox(height: 16),
                      
                      // Type-specific details sections (NCD, Mental Health, etc.)
                      if (details?.hasTypeSpecificDetails == true) ...[
                        // Complaints section
                        if (details!.complaints.isNotEmpty)
                          _buildSimpleListSection(
                            context,
                            title: VisitDetailsStrings.sectionComplaints,
                            icon: Icons.healing,
                            items: details.complaints,
                          ),
                        if (details.complaints.isNotEmpty)
                          const SizedBox(height: 16),
                        
                        // Physical Exams section
                        if (details.physicalExams.isNotEmpty)
                          _buildSimpleListSection(
                            context,
                            title:
                                VisitDetailsStrings.sectionPhysicalExaminations,
                            icon: Icons.medical_services,
                            items: details.physicalExams,
                          ),
                        if (details.physicalExams.isNotEmpty)
                          const SizedBox(height: 16),
                        
                        // Comorbidities section
                        if (details.comorbidities.isNotEmpty)
                          _buildSimpleListSection(
                            context,
                            title: VisitDetailsStrings.sectionComorbidities,
                            icon: Icons.health_and_safety,
                            items: details.comorbidities,
                          ),
                        if (details.comorbidities.isNotEmpty)
                          const SizedBox(height: 16),
                        
                        // Complications section
                        if (details.complications.isNotEmpty)
                          _buildSimpleListSection(
                            context,
                            title: VisitDetailsStrings.sectionComplications,
                            icon: Icons.warning_amber,
                            items: details.complications,
                          ),
                        if (details.complications.isNotEmpty)
                          const SizedBox(height: 16),
                        
                        // Investigations section
                        if (details.investigations.isNotEmpty)
                          _buildSimpleListSection(
                            context,
                            title: VisitDetailsStrings.sectionInvestigations,
                            icon: Icons.science,
                            items: details.investigations,
                          ),
                        if (details.investigations.isNotEmpty)
                          const SizedBox(height: 16),
                        
                        // Prescriptions section
                        if (details.prescriptions.isNotEmpty)
                          _buildPrescriptionsSection(context, details.prescriptions),
                        if (details.prescriptions.isNotEmpty)
                          const SizedBox(height: 16),
                        
                        // Clinical Note (from type-specific details)
                        if (details.clinicalNote != null && details.clinicalNote!.isNotEmpty)
                          _buildSection(
                            context,
                            title: VisitDetailsStrings.sectionClinicalNotes,
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
                                  details.clinicalNote!,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        if (details.clinicalNote != null && details.clinicalNote!.isNotEmpty)
                          const SizedBox(height: 16),
                      ],
                      
                      // History section (when reviewDetails is null but history exists)
                      if (details?.history != null && details!.history!.isNotEmpty)
                        _buildHistorySection(context, details.history!),
                      
                      if (details?.history != null && details!.history!.isNotEmpty)
                        const SizedBox(height: 16),
                      
                      // Provider information
                      if (widget.visit.providerName != null)
                        _buildSection(
                          context,
                          title: VisitDetailsStrings.sectionProviderInformation,
                          icon: Icons.person_outline,
                          children: [
                            _buildDetailRow(
                              context,
                              label: VisitDetailsStrings.labelProvider,
                              value: widget.visit.providerName!,
                            ),
                            // Check for facility from rawJson
                            if (widget.visit.rawJson['facilityName'] != null)
                              _buildDetailRow(
                                context,
                                label: VisitDetailsStrings.labelFacility,
                                value: widget.visit.rawJson['facilityName'].toString(),
                              ),
                          ],
                        ),
                      
                      if (widget.visit.providerName != null) const SizedBox(height: 16),
                      
                      // Clinical notes
                      if ((widget.visit.notes != null && widget.visit.notes!.isNotEmpty) ||
                          (details?.reviewDetails?.clinicalNotes != null && 
                           details!.reviewDetails!.clinicalNotes!.isNotEmpty))
                        _buildSection(
                          context,
                          title: VisitDetailsStrings.sectionClinicalNotes,
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
                                details?.reviewDetails?.clinicalNotes ?? widget.visit.notes ?? '',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      
                      if ((widget.visit.notes != null && widget.visit.notes!.isNotEmpty) ||
                          (details?.reviewDetails?.clinicalNotes != null && 
                           details!.reviewDetails!.clinicalNotes!.isNotEmpty))
                        const SizedBox(height: 16),
                      
                      // Additional details from rawJson
                      _buildAdditionalDetails(context, scheme),
                      
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHistorySection(BuildContext context, List<Map<String, dynamic>> history) {
    final scheme = Theme.of(context).colorScheme;
    
    return _buildSection(
      context,
      title: VisitDetailsStrings.sectionVisitHistory,
      icon: Icons.history,
      children: history.map((item) {
        final rawType =
            item['type']?.toString() ?? VisitDetailsStrings.unknownVisitType;
        final formattedType = _formatVisitType(rawType);
        final date = item['date']?.toString();
        final id = item['id']?.toString();
        
        DateTime? parsedDate;
        if (date != null) {
          parsedDate = DateTime.tryParse(date);
        }
        
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.secondaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.secondaryContainer),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.medical_services_outlined, 
                    size: 18, 
                    color: scheme.secondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      formattedType,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (parsedDate != null) ...[
                const SizedBox(height: 4),
                Text(
                  DateFormat('MMMM d, yyyy h:mm a').format(parsedDate),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (id != null) ...[
                const SizedBox(height: 2),
                Text(
                  VisitDetailsStrings.encounterIdLine(id),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.outline,
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  bool _hasNeonateInfo(ReviewDetails? details) {
    if (details == null) return false;
    return details.neonateOutcome != null ||
           details.stateOfBaby != null ||
           details.birthWeight != null ||
           details.isMotherAlive != null;
  }

  /// Format visit type for display (convert SNAKE_CASE to Title Case)
  String _formatVisitType(String type) {
    // Convert SNAKE_CASE to Title Case
    return type
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isEmpty 
            ? word 
            : word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' ');
  }

  /// Format ISO date string to readable format
  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('MMMM d, yyyy h:mm a').format(date);
    } catch (_) {
      return dateStr;
    }
  }

  /// Build a simple list section with chips (used for type-specific details)
  Widget _buildSimpleListSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<String> items,
  }) {
    return _buildListSection(context, title: title, icon: icon, items: items);
  }

  /// Build prescriptions section with medication details
  Widget _buildPrescriptionsSection(BuildContext context, List<Map<String, dynamic>> prescriptions) {
    final scheme = Theme.of(context).colorScheme;
    
    return _buildSection(
      context,
      title: VisitDetailsStrings.sectionPrescriptions,
      icon: Icons.medication,
      children: prescriptions.map((rx) {
        final drugName = rx['drugName']?.toString() ??
            rx['name']?.toString() ??
            VisitDetailsStrings.unknownMedication;
        final dosage = rx['dosage']?.toString();
        final frequency = rx['frequency']?.toString();
        final duration = rx['duration']?.toString();
        final instructions = rx['instructions']?.toString();
        
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.tertiaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.tertiaryContainer),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.medication_outlined, size: 18, color: scheme.tertiary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      drugName,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (dosage != null)
                _buildDetailRow(context,
                    label: VisitDetailsStrings.labelDosage, value: dosage),
              if (frequency != null)
                _buildDetailRow(context,
                    label: VisitDetailsStrings.labelFrequency,
                    value: frequency),
              if (duration != null)
                _buildDetailRow(context,
                    label: VisitDetailsStrings.labelDuration, value: duration),
              if (instructions != null && instructions.isNotEmpty)
                _buildDetailRow(context,
                    label: VisitDetailsStrings.labelInstructions,
                    value: instructions),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDiagnosisSection(BuildContext context, List<DiagnosisInfo> diagnosis) {
    final scheme = Theme.of(context).colorScheme;
    
    return _buildSection(
      context,
      title: RealtimeAsrStrings.diagnosis,
      icon: Icons.medical_services_outlined,
      children: [
        ...diagnosis.map((d) => _buildDiagnosisItem(context, d, scheme)),
      ],
    );
  }

  Widget _buildDiagnosisItem(BuildContext context, DiagnosisInfo diagnosis, ColorScheme scheme) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.primaryContainer),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (diagnosis.diseaseCategory != null)
            Text(
              diagnosis.diseaseCategory!,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (diagnosis.diseaseCondition != null)
            Text(
              diagnosis.diseaseCondition!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          if (diagnosis.notes != null && diagnosis.notes!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              diagnosis.notes!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildListSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<String> items,
    String? notes,
  }) {
    final scheme = Theme.of(context).colorScheme;
    
    return _buildSection(
      context,
      title: title,
      icon: icon,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items.map((item) => Chip(
            label: Text(item),
            backgroundColor: scheme.secondaryContainer,
            labelStyle: TextStyle(color: scheme.onSecondaryContainer),
            side: BorderSide.none,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          )).toList(),
        ),
        if (notes != null && notes.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  VisitDetailsStrings.notesLabel,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(notes),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLabourSection(BuildContext context, LabourDetails labour) {
    return _buildSection(
      context,
      title: VisitDetailsStrings.sectionLabourDelivery,
      icon: Icons.child_friendly,
      children: [
        if (labour.deliveryType != null)
          _buildDetailRow(context,
              label: VisitDetailsStrings.labelDeliveryType,
              value: labour.deliveryType!),
        if (labour.deliveryAt != null)
          _buildDetailRow(context,
              label: VisitDetailsStrings.labelDeliveryAt,
              value: labour.deliveryAt!),
        if (labour.deliveryBy != null)
          _buildDetailRow(context,
              label: VisitDetailsStrings.labelDeliveryBy,
              value: labour.deliveryBy!),
        if (labour.deliveryStatus != null)
          _buildDetailRow(context,
              label: VisitDetailsStrings.labelDeliveryStatus,
              value: labour.deliveryStatus!),
        if (labour.dateAndTimeOfDelivery != null)
          _buildDetailRow(context,
              label: VisitDetailsStrings.labelDeliveryDateTime,
              value: labour.dateAndTimeOfDelivery!),
        if (labour.dateAndTimeOfLabourOnset != null)
          _buildDetailRow(context,
              label: VisitDetailsStrings.labelLabourOnset,
              value: labour.dateAndTimeOfLabourOnset!),
      ],
    );
  }

  Widget _buildNeonateSection(BuildContext context, ReviewDetails details) {
    return _buildSection(
      context,
      title: VisitDetailsStrings.sectionNeonate,
      icon: Icons.child_care,
      children: [
        if (details.isMotherAlive != null)
          _buildDetailRow(
            context,
            label: VisitDetailsStrings.labelMotherAlive,
            value: details.isMotherAlive!
                ? VisitDetailsStrings.yes
                : VisitDetailsStrings.no,
          ),
        if (details.neonateOutcome != null)
          _buildDetailRow(context,
              label: VisitDetailsStrings.labelNeonateOutcome,
              value: details.neonateOutcome!),
        if (details.stateOfBaby != null)
          _buildDetailRow(context,
              label: VisitDetailsStrings.labelStateOfBaby,
              value: details.stateOfBaby!),
        if (details.birthWeight != null)
          _buildDetailRow(context,
              label: VisitDetailsStrings.labelBirthWeight,
              value: details.birthWeight!),
        if (details.breastCondition != null)
          _buildDetailRow(context,
              label: VisitDetailsStrings.labelBreastCondition,
              value: details.breastCondition!),
        if (details.breastConditionNotes != null)
          _buildDetailRow(context,
              label: VisitDetailsStrings.labelBreastNotes,
              value: details.breastConditionNotes!),
        if (details.involutionsOfTheUterus != null)
          _buildDetailRow(context,
              label: VisitDetailsStrings.labelInvolutionOfUterus,
              value: details.involutionsOfTheUterus!),
        if (details.signs != null && details.signs!.isNotEmpty)
          _buildDetailRow(context,
              label: VisitDetailsStrings.labelSigns,
              value: details.signs!.join(', ')),
      ],
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
            scheme.primary.withValues(alpha: 0.8),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.patientName != null) ...[
            Text(
              widget.patientName!,
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
                  color: scheme.onPrimary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getServiceIcon(widget.visit.serviceProvided ?? widget.visit.encounterType),
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
                      widget.visit.serviceProvided ??
                          widget.visit.encounterType ??
                          VisitDetailsStrings.headerVisitFallback,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: scheme.onPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateFormat.format(widget.visit.visitDate),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onPrimary.withValues(alpha: 0.9),
                          ),
                    ),
                  ],
                ),
              ),
              if (widget.visit.status != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.onPrimary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    widget.visit.status!,
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
    final rawJson = widget.visit.rawJson;
    
    // Extract additional fields that might be useful
    const fieldsToShow = VisitDetailsStrings.additionalDetailLabels;

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
      title: VisitDetailsStrings.sectionAdditionalDetails,
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
      return AppColors.statusSuccess;
    } else if (statusLower.contains('pending') || statusLower.contains('in-progress')) {
      return AppColors.statusWarning;
    } else if (statusLower.contains('cancel') || statusLower.contains('rejected')) {
      return AppColors.statusCritical;
    }
    return scheme.onSurface;
  }
}
