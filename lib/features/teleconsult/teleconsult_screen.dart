/// Real Shukhee teleconsult flow: auto-books an instant video consultation,
/// embeds the call in-page via `shukhee_sdk`'s [ShukheeCallView] (a genuine
/// top-level WebView navigation -- never an iframe, which breaks the join),
/// polls for completion in the background, and shows the resulting
/// prescription/invoice or a "not available" state.
///
/// No manual booking form: [patientPhone]/[reason]/[patientDob]/
/// [patientGender] are derived by the caller (Visit flow Step 3) from data
/// already on hand. The only manual input this screen ever asks for is the
/// patient's phone number, and only when the caller didn't have one.
///
/// UI matches design mockup `design/v16.html` screen `s17` as closely as the
/// real data allows -- see that file's "Doctor's Conclusion"/Rx-ID/structured
/// prescription line items, which are deliberately NOT built here: no such
/// data exists anywhere in Shukhee's real API contract (confirmed against
/// their sandbox API doc and Postman collection), so building them would be
/// fabricated content. Everything else in `s17` (colors, video-in-a-card
/// layout, doctor identity, the "record shared" banner, the counselling CTA)
/// is real and matched.
///
/// Engineering Design Standards:
///   - All Shukhee-specific I/O lives in `shukhee_sdk`; this file only
///     translates its `ShukheeException`s into this app's own
///     [DomainException] subclasses and renders state.
///   - All strings from [TeleconsultStrings].
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:provider/provider.dart';
import 'package:shukhee_sdk/shukhee_sdk.dart';

import '../../core/api/api_client.dart';
import '../../core/config/app_config.dart';
import '../../core/constants/app_strings.dart';
import '../../core/errors/domain_exceptions.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/counselling_launcher.dart';
import 'pdf_viewer_screen.dart';

enum _Stage { booking, connected, wrapUp, notCompleted, error, notProvisioned }

class TeleconsultScreen extends StatefulWidget {
  const TeleconsultScreen({
    super.key,
    required this.patientLabel,
    required this.patientId,
    this.visitId,
    this.patientPhone,
    this.reason,
    this.patientDob,
    this.patientGender,
    this.visitNumber,
    this.gestationalWeeks,
    this.clinicalContextSummary,
    this.whatsappMessage,
    @visibleForTesting this.client,
  });

  final String patientLabel;
  final String patientId;

  /// Threaded through as `encounter_id` when booking.
  final String? visitId;

  /// The patient's contact number, if already known. When null/empty, the
  /// screen asks for it once via a one-field bottom sheet before booking.
  final String? patientPhone;

  /// Pre-derived reason text (from the visit's AI recommendation) — already
  /// includes [clinicalContextSummary] when applicable. See
  /// `_deriveTeleconsultReason` in `visit_flow_screen.dart`.
  final String? reason;

  final String? patientDob;
  final String? patientGender;

  /// ANC/PNC visit number (1-based) — for the "record shared" banner's
  /// "ANC Visit N notes" phrasing. Null for non-ANC/PNC visits.
  final int? visitNumber;

  /// For the "N weeks pregnant" header subtitle.
  final int? gestationalWeeks;

  /// The real BP-trend/urine-protein summary already folded into [reason] --
  /// rendered verbatim in the "record shared with Sukhee" banner so the UI
  /// never claims to have shared something that wasn't actually sent.
  final String? clinicalContextSummary;

  /// The same NABA-derived WhatsApp message used by the visit flow's inline
  /// counselling card — powers this screen's "Send counselling to family"
  /// button. Null/empty hides the button.
  final String? whatsappMessage;

  /// Test-only injection point — real callers never pass this; the screen
  /// builds its own client from [AppConfig] otherwise.
  final ShukheeClient? client;

  @override
  State<TeleconsultScreen> createState() => _TeleconsultScreenState();
}

class _TeleconsultScreenState extends State<TeleconsultScreen> {
  late final ShukheeClient _client;
  final _callViewKey = GlobalKey();

  _Stage _stage = _Stage.booking;
  DomainException? _error;
  ShukheeBooking? _booking;
  ShukheeStatus? _status;
  String? _phoneOverride;
  bool _isFullscreen = false;
  DateTime? _callStartedAt;
  Duration _liveElapsed = Duration.zero;
  Timer? _liveTimer;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? _buildDefaultClient();
    // _start() can show a modal bottom sheet (the phone-number fallback),
    // which needs an inherited Localizations/Theme lookup that isn't safe to
    // perform until after the first frame -- deferring avoids a "called
    // before initState() completed" assertion whenever patientPhone is null.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }

  ShukheeClient _buildDefaultClient() {
    final apiClient = context.read<ApiClient>();
    return ShukheeClient(
      ShukheeConfig(
        baseUrl: AppConfig.shukheeApiBaseUrl,
        // ApiClient.exportAuthToken() returns the full "Bearer <token>" string
        // verbatim (its own request interceptor uses it as-is, with no scheme
        // prepended -- see api_client.dart's onRequest handlers) -- but
        // shukhee_sdk's authTokenProvider contract expects just the raw token
        // and prepends "Bearer " itself. Strip it here so the two don't stack
        // into "Bearer Bearer <token>", which the real auth-service rejects
        // with 400 (confirmed live against the sandbox this session).
        authTokenProvider: () async {
          final raw = apiClient.exportAuthToken();
          if (raw == null) return null;
          const prefix = 'Bearer ';
          return raw.startsWith(prefix) ? raw.substring(prefix.length) : raw;
        },
        // The backend's real (Phase 2) auth validation needs this to call the
        // legacy platform's own /authenticate endpoint -- see shukhee_sdk's
        // ShukheeConfig.tenantIdProvider doc for why.
        tenantIdProvider: () async => apiClient.tenantId,
      ),
    );
  }

  Future<void> _start() async {
    if (!mounted) return;
    setState(() {
      _stage = _Stage.booking;
      _error = null;
    });

    var phone = _phoneOverride ?? widget.patientPhone;
    if (phone == null || phone.trim().isEmpty) {
      final entered = await _promptForPhone();
      if (!mounted) return;
      if (entered == null || entered.trim().isEmpty) {
        Navigator.of(context).pop();
        return;
      }
      phone = entered.trim();
      _phoneOverride = phone;
    }

    try {
      final booking = await _client.startConsultation(
        contactNumber: phone,
        reason: (widget.reason?.trim().isNotEmpty ?? false)
            ? widget.reason!.trim()
            : 'Teleconsult requested for ${widget.patientLabel}',
        encounterId: widget.visitId,
        patientName: widget.patientLabel,
        patientDob: widget.patientDob,
        patientGender: widget.patientGender,
      );
      if (!mounted) return;
      setState(() {
        _booking = booking;
        _stage = _Stage.connected;
        _status = null;
        _isFullscreen = false;
        _callStartedAt = DateTime.now();
        _liveElapsed = Duration.zero;
      });
      _startLiveTimer();
      unawaited(_pollInBackground(booking.callLog));
    } on ShukheeException catch (e) {
      if (mounted) _handleError(e);
    }
  }

  void _startLiveTimer() {
    _liveTimer?.cancel();
    _liveTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final start = _callStartedAt;
      if (!mounted || start == null) return;
      setState(() => _liveElapsed = DateTime.now().difference(start));
    });
  }

  Future<void> _pollInBackground(String callLog) async {
    final status = await _client.pollStatus(
      callLog: callLog,
      maxAttempts: AppConfig.teleconsultPollMaxAttempts,
      delayBetween: Duration(seconds: AppConfig.teleconsultPollDelaySeconds),
      // Fires on every attempt (not just the terminal one) so the connected
      // screen can show the assigned doctor as soon as Shukhee has one,
      // rather than waiting for the whole call to finish.
      onUpdate: (update) {
        if (mounted) setState(() => _status = update);
      },
    );
    if (!mounted) return;
    _liveTimer?.cancel();
    setState(() {
      _status = status;
      _stage = status.isCompleted ? _Stage.wrapUp : _Stage.notCompleted;
      _isFullscreen = false;
    });
  }

  void _handleError(ShukheeException e) {
    setState(() {
      switch (e) {
        case ShukheeNotProvisionedException():
          _stage = _Stage.notProvisioned;
          _error = TeleconsultNotProvisionedException(e.message);
        case ShukheeUnauthorizedException():
          _stage = _Stage.error;
          _error = TeleconsultUnauthorizedException(e.message);
        case ShukheeBookingException():
          _stage = _Stage.error;
          _error = TeleconsultBookingException(e.message);
      }
    });
  }

  Future<String?> _promptForPhone() {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _PhonePromptSheet(patientLabel: widget.patientLabel),
    );
  }

  void _toggleFullscreen() => setState(() => _isFullscreen = !_isFullscreen);

  Future<void> _confirmLeaveCall() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(TeleconsultStrings.leaveCallTitle),
        content: Text(TeleconsultStrings.leaveCallBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(TeleconsultStrings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(TeleconsultStrings.leaveCallConfirm),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop();
  }

  String get _liveElapsedLabel {
    final m = _liveElapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _liveElapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_stage == _Stage.connected && _booking != null) {
      return _buildConnectedScaffold(context);
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(TeleconsultStrings.title),
        backgroundColor: AppColors.navyDark,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildConnectedScaffold(BuildContext context) {
    final callView = ShukheeCallView(key: _callViewKey, callUrl: _booking!.callUrl);

    if (_isFullscreen) {
      // Same-keyed callView as the non-fullscreen branch below -- Flutter
      // reuses the State (and therefore the underlying WebViewController)
      // across this rebuild, so toggling fullscreen never reloads the call.
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              _FullscreenBar(elapsedLabel: _liveElapsedLabel, onCollapse: _toggleFullscreen),
              Expanded(child: callView),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.ancHeader,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _confirmLeaveCall,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(TeleconsultStrings.callTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Text(
              widget.gestationalWeeks != null
                  ? TeleconsultStrings.viaSukheeWithPatient(widget.patientLabel) +
                      TeleconsultStrings.weeksPregnantSuffix(widget.gestationalWeeks!)
                  : TeleconsultStrings.viaSukheeWithPatient(widget.patientLabel),
              style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.85)),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _VideoCard(
                callView: callView,
                elapsedLabel: _liveElapsedLabel,
                onExpand: _toggleFullscreen,
              ),
              const SizedBox(height: AppSpacing.md),
              _DoctorIdentityLine(status: _status),
              const SizedBox(height: AppSpacing.md),
              _RecordSharedBanner(
                clinicalContextSummary: widget.clinicalContextSummary,
                visitNumber: widget.visitNumber,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_stage) {
      case _Stage.booking:
        return _CenteredMessage(
          icon: Icons.video_call_rounded,
          iconColor: AppColors.statusInfo,
          title: TeleconsultStrings.connecting,
          body: TeleconsultStrings.connectingHint,
          showSpinner: true,
        );
      case _Stage.wrapUp:
        return _WrapUpView(
          client: _client,
          callLog: _booking?.callLog,
          status: _status,
          visitNumber: widget.visitNumber,
          clinicalContextSummary: widget.clinicalContextSummary,
          whatsappMessage: widget.whatsappMessage,
          patientPhone: widget.patientPhone,
          onDone: () => Navigator.of(context).pop(),
        );
      case _Stage.notCompleted:
        return _CenteredMessage(
          icon: Icons.phone_disabled_rounded,
          iconColor: AppColors.rangeCritical,
          title: TeleconsultStrings.notCompletedTitle,
          body: TeleconsultStrings.notCompletedBody,
          primaryLabel: TeleconsultStrings.tryAgain,
          onPrimary: _start,
          secondaryLabel: TeleconsultStrings.continueWithoutCall,
          onSecondary: () => Navigator.of(context).pop(),
        );
      case _Stage.notProvisioned:
        return _CenteredMessage(
          icon: Icons.block_rounded,
          iconColor: AppColors.rangeCritical,
          title: TeleconsultStrings.notProvisionedTitle,
          body: _error?.localizedMessage ?? TeleconsultStrings.notProvisionedBody,
          primaryLabel: TeleconsultStrings.doneButton,
          onPrimary: () => Navigator.of(context).pop(),
        );
      case _Stage.error:
        return _CenteredMessage(
          icon: Icons.error_outline_rounded,
          iconColor: AppColors.rangeCritical,
          title: TeleconsultStrings.notCompletedTitle,
          body: _error?.localizedMessage ?? TeleconsultStrings.notCompletedBody,
          primaryLabel: CommonStrings.retry,
          onPrimary: _start,
          secondaryLabel: TeleconsultStrings.continueWithoutCall,
          onSecondary: () => Navigator.of(context).pop(),
        );
      case _Stage.connected:
        return const SizedBox.shrink(); // handled in build() above
    }
  }
}

/// The live call rendered in a card (not full-bleed), with a "LIVE mm:ss"
/// badge and an expand-to-fullscreen control — matches the design mockup's
/// video tile treatment while keeping the summary sections below reachable
/// without leaving the page.
class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.callView, required this.elapsedLabel, required this.onExpand});

  final Widget callView;
  final String elapsedLabel;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final partner = Theme.of(context).extension<PartnerColors>()!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        height: 220,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [partner.ancTeleVideoStart, partner.ancTeleVideoEnd],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            callView,
            Positioned(
              top: AppSpacing.sm,
              left: AppSpacing.sm,
              child: _LiveBadge(elapsedLabel: elapsedLabel),
            ),
            Positioned(
              top: AppSpacing.sm,
              right: AppSpacing.sm,
              child: _RoundIconButton(
                icon: Icons.open_in_full_rounded,
                onTap: onExpand,
                tooltip: TeleconsultStrings.expandTooltip,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Slim top bar shown instead of the full header while [ShukheeCallView] is
/// expanded to fill the screen.
class _FullscreenBar extends StatelessWidget {
  const _FullscreenBar({required this.elapsedLabel, required this.onCollapse});

  final String elapsedLabel;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          _RoundIconButton(
            icon: Icons.close_fullscreen_rounded,
            onTap: onCollapse,
            tooltip: TeleconsultStrings.collapseTooltip,
          ),
          const Spacer(),
          _LiveBadge(elapsedLabel: elapsedLabel),
        ],
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.elapsedLabel});

  final String elapsedLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            '${TeleconsultStrings.liveLabel} · $elapsedLabel',
            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap, required this.tooltip});

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 16),
        ),
      ),
    );
  }
}

/// Shows who the SK is actually talking to, from Shukhee's real
/// `doctor`/`specialty`/`working_at` fields once assigned — a generic
/// "connecting" placeholder before then, since Shukhee assigns a doctor
/// asynchronously and there's no earlier signal for it.
class _DoctorIdentityLine extends StatelessWidget {
  const _DoctorIdentityLine({required this.status});

  final ShukheeStatus? status;

  @override
  Widget build(BuildContext context) {
    final name = status?.doctorName;
    final text = (name == null || name.isEmpty)
        ? TeleconsultStrings.connectingToDoctor
        : _formatLine(name, status?.doctorSpeciality, status?.doctorFacility);
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
    );
  }

  static String _formatLine(String name, String? speciality, String? facility) {
    final hasSpeciality = speciality != null && speciality.isNotEmpty;
    final hasFacility = facility != null && facility.isNotEmpty;
    if (hasSpeciality && hasFacility) {
      return TeleconsultStrings.doctorNameSpecialityFacility(name, speciality, facility);
    }
    if (hasSpeciality) return TeleconsultStrings.doctorNameSpeciality(name, speciality);
    return TeleconsultStrings.doctorNameOnly(name);
  }
}

/// "Apon Sushashthya shared the full record with Sukhee" banner. Renders
/// [clinicalContextSummary] verbatim — the exact same string already folded
/// into the booking `reason` — so this never claims to have shared a detail
/// that wasn't actually sent. Falls back to a generic line when there's no
/// qualifying trend (non-ANC visits, or fewer than 2 prior visits).
class _RecordSharedBanner extends StatelessWidget {
  const _RecordSharedBanner({this.clinicalContextSummary, this.visitNumber});

  final String? clinicalContextSummary;
  final int? visitNumber;

  @override
  Widget build(BuildContext context) {
    final partner = Theme.of(context).extension<PartnerColors>()!;
    final summary = clinicalContextSummary;
    final body = (summary == null || summary.isEmpty)
        ? TeleconsultStrings.dataSharedGenericBody
        : TeleconsultStrings.ancRecordSharedBody(
            visitNumber != null
                ? PatientContextStrings.timelineAncVisitN(visitNumber!)
                : TeleconsultStrings.thisVisitLabel,
            summary,
          );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: partner.ancTeleBannerBg,
        border: Border.all(color: partner.ancTeleBannerBorder),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: AppColors.ancHeader, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 16),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  TeleconsultStrings.dataSharedTitle,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: partner.ancTeleBannerTitle),
                ),
                const SizedBox(height: 2),
                Text(body, style: TextStyle(fontSize: 11, color: partner.ancTeleBannerBody)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown once the call reaches `completed`. Only renders what the backend
/// actually returns — doctor identity, the retrospective "record shared"
/// banner, and inline prescription/invoice previews. The mockup's "Doctor's
/// Conclusion" card, Rx ID, and structured line items are deliberately not
/// built: no such data exists in Shukhee's contract.
class _WrapUpView extends StatelessWidget {
  const _WrapUpView({
    required this.client,
    required this.callLog,
    required this.status,
    required this.visitNumber,
    required this.clinicalContextSummary,
    required this.whatsappMessage,
    required this.patientPhone,
    required this.onDone,
  });

  final ShukheeClient client;
  final String? callLog;
  final ShukheeStatus? status;
  final int? visitNumber;
  final String? clinicalContextSummary;
  final String? whatsappMessage;
  final String? patientPhone;
  final VoidCallback onDone;

  bool get _hasMessage => whatsappMessage != null && whatsappMessage!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final hasPrescription = status?.prescriptionLink != null;
    final hasInvoice = status?.invoiceLink != null;
    final log = callLog;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.h6xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.check_circle_rounded, size: 56, color: AppColors.statusSuccess),
          const SizedBox(height: AppSpacing.xxxl),
          Text(
            TeleconsultStrings.prescriptionTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.md),
          Center(child: _DoctorIdentityLine(status: status)),
          const SizedBox(height: AppSpacing.h6xl),
          _RecordSharedBanner(clinicalContextSummary: clinicalContextSummary, visitNumber: visitNumber),
          const SizedBox(height: AppSpacing.h6xl),
          if (hasPrescription && log != null)
            _DocumentPreviewCard(
              client: client,
              callLog: log,
              docType: 'prescription',
              title: TeleconsultStrings.viewPrescription,
              buttonLabel: TeleconsultStrings.viewFullDocument,
              icon: Icons.description_outlined,
            ),
          if (hasInvoice && log != null) ...[
            const SizedBox(height: AppSpacing.xl),
            _DocumentPreviewCard(
              client: client,
              callLog: log,
              docType: 'invoice',
              title: TeleconsultStrings.viewInvoice,
              buttonLabel: TeleconsultStrings.viewFullDocument,
              icon: Icons.receipt_long_outlined,
            ),
          ],
          if (_hasMessage) ...[
            const SizedBox(height: AppSpacing.h6xl),
            FilledButton(
              onPressed: () => sendCounsellingWhatsApp(
                context: context,
                message: whatsappMessage!,
                phone: patientPhone,
                notInstalledMessage: NabaStrings.whatsAppNotInstalled,
              ),
              style: FilledButton.styleFrom(backgroundColor: AppColors.pinkWorklist),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(TeleconsultStrings.sendCounsellingToFamily),
                  Text(
                    TeleconsultStrings.sendCounsellingToFamilyBn,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.h6xl),
          FilledButton(
            onPressed: onDone,
            style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
            child: Text(TeleconsultStrings.doneButton),
          ),
        ],
      ),
    );
  }
}

/// Downloads a completed consultation's prescription/invoice bytes, renders
/// the first page inline as a preview, and opens the full multi-page
/// document in an in-app [PdfViewerScreen] on tap — never hands the PDF to
/// an external app (the file is a private Frappe attachment with no
/// unauthenticated web access; see [ShukheeClient.downloadDocument]).
class _DocumentPreviewCard extends StatefulWidget {
  const _DocumentPreviewCard({
    required this.client,
    required this.callLog,
    required this.docType,
    required this.title,
    required this.buttonLabel,
    required this.icon,
  });

  final ShukheeClient client;
  final String callLog;
  final String docType;
  final String title;
  final String buttonLabel;
  final IconData icon;

  @override
  State<_DocumentPreviewCard> createState() => _DocumentPreviewCardState();
}

class _DocumentPreviewCardState extends State<_DocumentPreviewCard> {
  Uint8List? _bytes;
  Uint8List? _thumbnail;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final document = await widget.client.downloadDocument(
        callLog: widget.callLog,
        docType: widget.docType,
      );
      final bytes = Uint8List.fromList(document.bytes);
      final pdf = await PdfDocument.openData(bytes);
      final page = await pdf.getPage(1);
      final image = await page.render(
        width: page.width * 2,
        height: page.height * 2,
        format: PdfPageImageFormat.png,
      );
      await page.close();
      await pdf.close();
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _thumbnail = image?.bytes;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _openFull() {
    final bytes = _bytes;
    if (bytes == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PdfViewerScreen(title: widget.title, bytes: bytes)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(widget.icon, size: 18, color: AppColors.ancHeader),
              const SizedBox(width: AppSpacing.sm),
              Text(widget.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: AppSpacing.sm),
                    Text(TeleconsultStrings.loadingPreview, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            )
          else if (_failed || _bytes == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(TeleconsultStrings.previewUnavailable, style: Theme.of(context).textTheme.bodySmall),
            )
          else ...[
            GestureDetector(
              onTap: _openFull,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _thumbnail != null
                    ? Image.memory(_thumbnail!, fit: BoxFit.contain)
                    : Container(height: 160, color: AppColors.canvas),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: _openFull,
              icon: const Icon(Icons.open_in_full_rounded, size: 16),
              label: Text(widget.buttonLabel),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shared layout for the booking/error/not-completed/not-provisioned states.
class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    this.showSpinner = false,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  final bool showSpinner;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.h6xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (showSpinner)
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.h6xl),
                child: CircularProgressIndicator(),
              )
            else
              Icon(icon, size: 56, color: iconColor),
            const SizedBox(height: AppSpacing.xxxl),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.md),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5),
            ),
            if (primaryLabel != null) ...[
              const SizedBox(height: AppSpacing.h6xl),
              SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: onPrimary, child: Text(primaryLabel!)),
              ),
            ],
            if (secondaryLabel != null) ...[
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One-field fallback sheet — the only manual input in this flow, shown
/// only when the caller didn't already have the patient's phone number.
class _PhonePromptSheet extends StatefulWidget {
  const _PhonePromptSheet({required this.patientLabel});

  final String patientLabel;

  @override
  State<_PhonePromptSheet> createState() => _PhonePromptSheetState();
}

class _PhonePromptSheetState extends State<_PhonePromptSheet> {
  // Pre-filled, not silently applied -- the SK still sees and can edit it
  // before confirming. Empty AppConfig.teleconsultDefaultPhone (the default
  // outside dev) just means no pre-fill, same as before this existed.
  late final _controller = TextEditingController(text: AppConfig.teleconsultDefaultPhone);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.h6xl,
        right: AppSpacing.h6xl,
        top: AppSpacing.h6xl,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.h6xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(TeleconsultStrings.phonePromptTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.md),
          Text(TeleconsultStrings.phonePromptHint, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.xl),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.phone,
            autofocus: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: AppSpacing.h6xl),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_controller.text),
            child: Text(TeleconsultStrings.phonePromptSubmit),
          ),
        ],
      ),
    );
  }
}
