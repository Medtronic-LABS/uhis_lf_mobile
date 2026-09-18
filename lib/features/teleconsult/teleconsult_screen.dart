/// Real Shukhee teleconsult flow: a booking form (specialty, contact number,
/// document type + up to 3 photographed documents) books an instant video
/// consultation, shows a native "Connecting to doctor…" screen while the
/// call's `shukhee_sdk` [ShukheeCallView] (a genuine top-level WebView
/// navigation -- never an iframe, which breaks the join) loads off-screen,
/// then presents the call fullscreen, polls for completion in the
/// background, shows a "Generating prescription…" gate while the resulting
/// documents are prefetched, and finally the wrap-up screen with inline
/// prescription/invoice previews (or a "not available" state).
///
/// UI matches design mockups for this flow as closely as the real data
/// allows -- the wrap-up screen deliberately does NOT build a "Doctor's
/// Conclusion" card, Rx ID, or structured prescription line items: no such
/// data exists anywhere in Shukhee's real API contract (confirmed against
/// their sandbox API doc and Postman collection), so building them would be
/// fabricated content. The live call screen likewise renders no custom
/// mic/camera/end-call controls -- that's Shukhee's own web page inside the
/// WebView, which exposes no control-surface hook to the host app.
///
/// Engineering Design Standards:
///   - All Shukhee-specific I/O lives in `shukhee_sdk`; this file only
///     translates its `ShukheeException`s into this app's own
///     [DomainException] subclasses and renders state.
///   - All strings from [TeleconsultStrings].
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdfx/pdfx.dart';
import 'package:provider/provider.dart';
import 'package:shukhee_sdk/shukhee_sdk.dart';

import '../../core/api/api_client.dart';
import '../../core/config/app_config.dart';
import '../../core/constants/app_strings.dart';
import '../../core/db/teleconsult_prescription_dao.dart';
import '../../core/debug/console_log.dart';
import '../../core/errors/domain_exceptions.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/counselling_launcher.dart';
import 'pdf_viewer_screen.dart';
import 'teleconsult_permission_service.dart';

/// The fixed, live-confirmed set of Shukhee specialities offered on the
/// booking form (verified against the sandbox's own
/// `GET /patient/emergency-request-specialities`, in this exact order).
/// These are the literal values sent as `requestedSpeciality` -- never
/// substitute a translated label here, only the *displayed* text is
/// translated (see `_BookingFormViewState._specialityLabel`).
const List<String> kTeleconsultSpecialities = [
  'General Physician',
  'Sexual Wellness',
  'Diabetic Coach',
  'Maternity Coach',
];

enum _Stage {
  booking,
  connecting,
  connected,
  generatingPrescription,
  wrapUp,
  notCompleted,
  error,
  notProvisioned,
}

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
    @visibleForTesting this.permissionService,
    @visibleForTesting this.prescriptionDao,
  });

  final String patientLabel;
  final String patientId;

  /// Threaded through as `encounter_id` when booking.
  final String? visitId;

  /// The patient's contact number, if already known -- pre-fills the
  /// booking form's contact-number field (still editable, still required).
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

  /// Test-only injection points — real callers never pass these; the screen
  /// builds its own instances from [AppConfig]/the widget tree's [Provider]s
  /// otherwise.
  final ShukheeClient? client;
  final TeleconsultPermissionService? permissionService;
  final TeleconsultPrescriptionDao? prescriptionDao;

  @override
  State<TeleconsultScreen> createState() => _TeleconsultScreenState();
}

class _TeleconsultScreenState extends State<TeleconsultScreen> {
  late final ShukheeClient _client;
  late final TeleconsultPermissionService _permissionService;
  // Resolved once, up front, while context is still valid -- the SK can leave
  // this screen (back button, `_confirmLeaveCall`) while a call is still
  // being polled in the background, and the poll/save below must keep
  // running and be able to persist the result after this widget is disposed,
  // when `context`/`context.read` are no longer safe to use.
  late final TeleconsultPrescriptionDao _prescriptionDao;
  final _callViewKey = GlobalKey();

  _Stage _stage = _Stage.booking;
  DomainException? _error;
  ShukheeBooking? _booking;
  ShukheeStatus? _status;
  Widget? _cachedCallView;
  bool _webViewReady = false;
  bool _minDurationElapsed = false;
  DateTime? _callStartedAt;
  Duration _liveElapsed = Duration.zero;
  Timer? _liveTimer;
  Uint8List? _prescriptionBytes;
  Uint8List? _invoiceBytes;

  // Cached from the most recent submit -- lets "Retry" re-book with the same
  // values instead of sending the SK back to a blank form.
  String? _lastContactNumber;
  String? _lastSpeciality;
  Map<String, List<ShukheeMediaFile>> _lastMediaGroups = const {};

  static const _minConnectingDuration = Duration(seconds: 2);
  Timer? _connectingMinDurationTimer;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? _buildDefaultClient();
    _permissionService = widget.permissionService ?? TeleconsultPermissionService();
    _prescriptionDao = widget.prescriptionDao ?? context.read<TeleconsultPrescriptionDao>();
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _connectingMinDurationTimer?.cancel();
    super.dispose();
  }

  ShukheeClient _buildDefaultClient() {
    final apiClient = context.read<ApiClient>();
    final config = ShukheeConfig(
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
    );
    return ShukheeClient(
      config,
      // Debug-only: shukhee_sdk builds its own internal Dio with no logging
      // (it has no dependency on this app's ConsoleLog/[PayloadDebug]
      // convention), so every Shukhee HTTP call is otherwise invisible on
      // device. Injecting our own Dio here (same BaseOptions the SDK would
      // have built itself) lets _shukheeDebugInterceptor observe exactly
      // what's sent/received without touching the shared SDK package.
      dio: kDebugMode ? _buildDebugDio(config) : null,
    );
  }

  /// Debug-only Dio, mirroring the BaseOptions shukhee_sdk would have built
  /// internally, plus a request/response/error logging interceptor -- see
  /// [_buildDefaultClient]. `[ShukheeDebug]` tag, visible via `adb logcat`.
  static Dio _buildDebugDio(ShukheeConfig config) {
    final dio = Dio(BaseOptions(
      baseUrl: config.baseUrl,
      connectTimeout: config.connectTimeout,
      receiveTimeout: config.receiveTimeout,
    ));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final data = options.data;
          String bodyDesc;
          if (data is FormData) {
            final fields = {for (final f in data.fields) f.key: f.value};
            final files = {
              for (final f in data.files) f.key: '${f.value.filename} (${f.value.length}b)',
            };
            bodyDesc = 'fields=$fields'
                '${files.isNotEmpty ? ' files=$files' : ''}';
          } else {
            bodyDesc = data?.toString() ?? '(none)';
          }
          ConsoleLog.banner(
            '[ShukheeDebug] --> ${options.method} ${options.path}\n'
            'headers: ${options.headers}\n'
            'body: $bodyDesc',
          );
          handler.next(options);
        },
        onResponse: (response, handler) {
          ConsoleLog.success(
            '[ShukheeDebug] <-- ${response.statusCode} ${response.requestOptions.path}',
          );
          ConsoleLog.json('[ShukheeDebug] response body', response.data);
          handler.next(response);
        },
        onError: (e, handler) {
          ConsoleLog.warn(
            '[ShukheeDebug] <-- ERROR ${e.response?.statusCode} ${e.requestOptions.path}: '
            '${e.response?.data ?? e.message}',
          );
          handler.next(e);
        },
      ),
    );
    return dio;
  }

  Future<void> _submitBooking({
    required String contactNumber,
    required String speciality,
    required Map<String, List<ShukheeMediaFile>> mediaGroups,
  }) async {
    _lastContactNumber = contactNumber;
    _lastSpeciality = speciality;
    _lastMediaGroups = mediaGroups;

    final permitted = await _permissionService.ensureCameraAndMicPermission(context);
    if (!mounted) return;
    if (!permitted) {
      setState(() {
        _stage = _Stage.error;
        _error = TeleconsultCameraMicRequiredException(TeleconsultStrings.cameraMicRequiredBody);
      });
      return;
    }

    setState(() {
      _stage = _Stage.connecting;
      _error = null;
      _booking = null;
      _status = null;
      _cachedCallView = null;
      _webViewReady = false;
      _minDurationElapsed = false;
    });
    _connectingMinDurationTimer?.cancel();
    _connectingMinDurationTimer = Timer(_minConnectingDuration, () {
      if (!mounted) return;
      _minDurationElapsed = true;
      _maybeEnterConnected();
    });

    try {
      final booking = await _client.startConsultation(
        contactNumber: contactNumber,
        reason: (widget.reason?.trim().isNotEmpty ?? false)
            ? widget.reason!.trim()
            : 'Teleconsult requested for ${widget.patientLabel}',
        requestedSpeciality: speciality,
        encounterId: widget.visitId,
        patientName: widget.patientLabel,
        patientDob: widget.patientDob,
        patientGender: widget.patientGender,
        mediaGroups: mediaGroups,
      );
      if (!mounted) return;
      setState(() => _booking = booking);
      unawaited(_pollInBackground(booking.callLog));
    } on ShukheeException catch (e) {
      if (mounted) _handleError(e);
    }
  }

  /// Re-submits with the values from the most recent attempt -- used by the
  /// error/not-completed states' "Retry"/"Try again" buttons so a transient
  /// failure doesn't send the SK back to a blank form.
  void _retryBooking() {
    final contactNumber = _lastContactNumber;
    final speciality = _lastSpeciality;
    if (contactNumber == null || speciality == null) {
      setState(() => _stage = _Stage.booking);
      return;
    }
    unawaited(
      _submitBooking(
        contactNumber: contactNumber,
        speciality: speciality,
        mediaGroups: _lastMediaGroups,
      ),
    );
  }

  Widget _callViewFor(String url) {
    return _cachedCallView ??= ShukheeCallView(
      key: _callViewKey,
      callUrl: url,
      onPageFinished: () {
        _webViewReady = true;
        _maybeEnterConnected();
      },
    );
  }

  void _maybeEnterConnected() {
    if (!mounted || _stage != _Stage.connecting) return;
    if (_webViewReady && _minDurationElapsed) {
      setState(() {
        _stage = _Stage.connected;
        _callStartedAt = DateTime.now();
        _liveElapsed = Duration.zero;
      });
      _startLiveTimer();
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

  /// Polls until the call reaches a terminal status, then (if completed)
  /// downloads and saves the prescription/invoice. Deliberately keeps running
  /// to completion even if the SK backs out of this screen mid-call --
  /// `unawaited` in [_submitBooking] means nothing cancels this Future on
  /// dispose, so only the *UI-facing* `setState` calls below are guarded by
  /// [mounted]; the download/save side-effects are not, so a call that
  /// finishes after the SK has already left still ends up in the patient's
  /// visit timeline instead of being silently dropped.
  Future<void> _pollInBackground(String callLog) async {
    final status = await _client.pollStatus(
      callLog: callLog,
      maxAttempts: AppConfig.teleconsultPollMaxAttempts,
      delayBetween: Duration(seconds: AppConfig.teleconsultPollDelaySeconds),
      // Fires on every attempt (not just the terminal one) so the connecting
      // screen can show the assigned doctor as soon as Shukhee has one,
      // rather than waiting for the whole call to finish.
      onUpdate: (update) {
        if (mounted) setState(() => _status = update);
      },
    );
    _liveTimer?.cancel();
    if (!status.isCompleted) {
      if (mounted) {
        setState(() {
          _status = status;
          _stage = _Stage.notCompleted;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _status = status;
        _stage = _Stage.generatingPrescription;
      });
    }
    await _prefetchDocuments(status);
    if (mounted) setState(() => _stage = _Stage.wrapUp);
  }

  /// Eagerly downloads whatever documents the completed call produced so the
  /// wrap-up screen's [_DocumentPreviewCard]s render immediately. A failure
  /// here is swallowed -- each card's own lazy fetch is the fallback path
  /// (see [_DocumentPreviewCard.initialBytes]), so a prefetch bug degrades to
  /// today's already-shipped per-card spinner rather than a dead screen.
  Future<void> _prefetchDocuments(ShukheeStatus status) async {
    final log = _booking?.callLog;
    if (log == null) return;
    try {
      if (status.prescriptionLink != null) {
        final doc = await _client.downloadDocument(callLog: log, docType: 'prescription');
        _prescriptionBytes = Uint8List.fromList(doc.bytes);
      }
      if (status.invoiceLink != null) {
        final doc = await _client.downloadDocument(callLog: log, docType: 'invoice');
        _invoiceBytes = Uint8List.fromList(doc.bytes);
      }
    } catch (_) {
      // Swallowed by design -- see doc comment above.
    }
    await _savePrescriptionToVisit(callLog: log, status: status);
  }

  /// Persists the prescription/invoice against the visit that requested the
  /// call so the patient timeline can show a "view prescription" icon later
  /// (see `PatientContextScreen`'s `_TimelineEntryCard`) without a network
  /// re-fetch. No-op when the call wasn't launched from a real visit
  /// ([TeleconsultScreen.visitId] null -- nothing to attach it to) or when
  /// neither document downloaded (nothing worth persisting).
  ///
  /// Deliberately does NOT check [mounted] -- this can run after the SK has
  /// already left the screen (see [_pollInBackground]), and the save must
  /// still happen so the timeline picks it up next time the visit is opened.
  /// [_prescriptionDao] is resolved once in [initState] for exactly this
  /// reason: `context.read` here would be unsafe once this widget is
  /// disposed.
  Future<void> _savePrescriptionToVisit({
    required String callLog,
    required ShukheeStatus status,
  }) async {
    final visitId = widget.visitId;
    if (visitId == null || visitId.isEmpty) {
      ConsoleLog.warn('[TeleconsultPrescription] skip save: no visitId (callLog=$callLog) '
          '-- this call wasn\'t launched from a visit, so there\'s nothing to attach it to.');
      return;
    }
    if (_prescriptionBytes == null && _invoiceBytes == null) {
      ConsoleLog.warn('[TeleconsultPrescription] skip save: neither prescription nor invoice '
          'bytes downloaded (visitId=$visitId callLog=$callLog).');
      return;
    }
    try {
      await _prescriptionDao.upsert(TeleconsultPrescriptionRow(
        visitId: visitId,
        callLog: callLog,
        doctorName: status.doctorName,
        prescriptionBytes: _prescriptionBytes,
        invoiceBytes: _invoiceBytes,
        createdAt: DateTime.now(),
      ));
      ConsoleLog.success('[TeleconsultPrescription] saved visitId=$visitId callLog=$callLog '
          'hasPrescription=${_prescriptionBytes != null} hasInvoice=${_invoiceBytes != null}');
    } catch (e) {
      // Best-effort -- the wrap-up screen already has the bytes in memory
      // and works regardless; only the timeline icon would be missing.
      ConsoleLog.warn('[TeleconsultPrescription] save FAILED visitId=$visitId callLog=$callLog: $e');
    }
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
    switch (_stage) {
      case _Stage.booking:
        return _BookingFormView(
          client: _client,
          initialPhone: widget.patientPhone,
          onSubmit: _submitBooking,
        );
      case _Stage.connecting:
        return _buildConnectingScaffold(context);
      case _Stage.connected:
        return _buildConnectedScaffold(context);
      case _Stage.generatingPrescription:
        return Scaffold(
          appBar: AppBar(
            title: Text(TeleconsultStrings.prescriptionHeaderTitle),
            backgroundColor: AppColors.ancHeader,
            foregroundColor: Colors.white,
          ),
          body: SafeArea(
            child: _CenteredMessage(
              icon: Icons.description_outlined,
              iconColor: AppColors.ancHeader,
              title: TeleconsultStrings.generatingPrescriptionTitle,
              body: TeleconsultStrings.generatingPrescriptionBody,
              showSpinner: true,
              spinnerColor: AppColors.ancHeader,
            ),
          ),
        );
      case _Stage.wrapUp:
      case _Stage.notCompleted:
      case _Stage.error:
      case _Stage.notProvisioned:
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
  }

  Widget _buildConnectingScaffold(BuildContext context) {
    final booking = _booking;
    final callView = booking != null ? _callViewFor(booking.callUrl) : null;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(TeleconsultStrings.connectingHeaderTitle),
        backgroundColor: AppColors.ancHeader,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            _ConnectingView(
              status: _status,
              clinicalContextSummary: widget.clinicalContextSummary,
              visitNumber: widget.visitNumber,
              onCancel: () => Navigator.of(context).pop(),
            ),
            // Loads the real call page off-screen so it's already ready by
            // the time we transition to the fullscreen `connected` stage --
            // see `_callViewFor`'s onPageFinished callback / `_maybeEnterConnected`.
            if (callView != null) Offstage(child: callView),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectedScaffold(BuildContext context) {
    final booking = _booking;
    if (booking == null) return _buildConnectingScaffold(context);
    // Same-keyed callView as the connecting stage's Offstage-mounted instance
    // -- Flutter reuses the State (and therefore the underlying
    // WebViewController) across this rebuild, so entering fullscreen never
    // reloads the call.
    final callView = _callViewFor(booking.callUrl);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _FullscreenBar(elapsedLabel: _liveElapsedLabel, onBack: _confirmLeaveCall),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  callView,
                  Positioned(
                    left: AppSpacing.md,
                    right: AppSpacing.md,
                    bottom: AppSpacing.md,
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: _CallOverlayIdentityStrip(status: _status),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_stage) {
      case _Stage.wrapUp:
        return _WrapUpView(
          client: _client,
          callLog: _booking?.callLog,
          status: _status,
          visitNumber: widget.visitNumber,
          clinicalContextSummary: widget.clinicalContextSummary,
          whatsappMessage: widget.whatsappMessage,
          patientPhone: widget.patientPhone,
          prescriptionBytes: _prescriptionBytes,
          invoiceBytes: _invoiceBytes,
          onDone: () => Navigator.of(context).pop(),
        );
      case _Stage.notCompleted:
        return _CenteredMessage(
          icon: Icons.phone_disabled_rounded,
          iconColor: AppColors.rangeCritical,
          title: TeleconsultStrings.notCompletedTitle,
          body: TeleconsultStrings.notCompletedBody,
          primaryLabel: TeleconsultStrings.tryAgain,
          onPrimary: _retryBooking,
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
          onPrimary: _retryBooking,
          secondaryLabel: TeleconsultStrings.continueWithoutCall,
          onSecondary: () => Navigator.of(context).pop(),
        );
      case _Stage.booking:
      case _Stage.connecting:
      case _Stage.connected:
      case _Stage.generatingPrescription:
        return const SizedBox.shrink(); // handled directly in build() above
    }
  }
}

/// Formats "Dr. {name}" / "Dr. {name} · {speciality}" /
/// "Dr. {name} · {speciality} · {facility}" depending on what Shukhee has
/// assigned so far. Shared by [_DoctorIdentityLine] and [_ConnectingView].
String _formatDoctorLine(String name, String? speciality, String? facility) {
  final hasSpeciality = speciality != null && speciality.isNotEmpty;
  final hasFacility = facility != null && facility.isNotEmpty;
  if (hasSpeciality && hasFacility) {
    return TeleconsultStrings.doctorNameSpecialityFacility(name, speciality, facility);
  }
  if (hasSpeciality) return TeleconsultStrings.doctorNameSpeciality(name, speciality);
  return TeleconsultStrings.doctorNameOnly(name);
}

/// "{speciality} · {facility}" (no name) — used under the doctor's name on
/// the connecting screen once at least one of the two fields is known.
String? _specialityFacilityLine(ShukheeStatus? status) {
  final speciality = status?.doctorSpeciality;
  final facility = status?.doctorFacility;
  final hasSpeciality = speciality != null && speciality.isNotEmpty;
  final hasFacility = facility != null && facility.isNotEmpty;
  if (hasSpeciality && hasFacility) return '$speciality · $facility';
  if (hasSpeciality) return speciality;
  if (hasFacility) return facility;
  return null;
}

/// Derives display initials from a doctor's full name (e.g. "Farzana Kabir"
/// → "FK") for the connecting screen's placeholder avatar. Shukhee has no
/// photo field, so this is the only avatar content available.
String _avatarInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1).toUpperCase();
  }
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

/// Booking form: specialty, contact number, document type, and up to 3
/// photographed documents. The only screen in this flow with manual input --
/// everything else (reason, patient name/dob/gender) was already derived by
/// the caller (Visit flow Step 3) from data on hand.
class _BookingFormView extends StatefulWidget {
  const _BookingFormView({required this.client, required this.initialPhone, required this.onSubmit});

  final ShukheeClient client;
  final String? initialPhone;
  final Future<void> Function({
    required String contactNumber,
    required String speciality,
    required Map<String, List<ShukheeMediaFile>> mediaGroups,
  }) onSubmit;

  @override
  State<_BookingFormView> createState() => _BookingFormViewState();
}

/// One document-type bucket on the booking form -- e.g. "Prescription" with its own
/// photographed files, kept separate from "Lab Report"'s so a single booking can carry
/// both, each correctly tagged (see [ShukheeClient.startConsultation]'s `mediaGroups`).
class _MediaGroup {
  _MediaGroup({required this.type, required this.label});

  final String type; // 'prescription' | 'lab_report' -- the literal API value.
  final String label; // Translated display label for this bucket's header.
  final List<XFile> files = [];
}

class _BookingFormViewState extends State<_BookingFormView> {
  static const _maxDocuments = 3;

  // Downscale/compress picked documents before upload -- an uncompressed
  // camera photo is commonly several MB, and up to 3 of them are relayed
  // synchronously through the backend to Shukhee within a single request
  // (see shukhee_client.py's 10s per-call timeout) -- on the poor rural
  // connectivity this app is built for, that combination routinely times
  // out. 1600px is comfortably legible for a photographed prescription or
  // lab slip; quality 70 cuts typical camera output by roughly 5-10x with
  // no visible loss of readability for text/handwriting.
  static const _maxDocumentDimension = 1600.0;
  static const _documentImageQuality = 70;

  late final TextEditingController _phoneController =
      TextEditingController(text: widget.initialPhone ?? '');

  /// Null while loading. Falls back to [kTeleconsultSpecialities] (as
  /// synthetic entries keyed by their own title) if the live fetch fails, so
  /// the form stays usable rather than dead-ending on a network error.
  List<ShukheeSpeciality>? _specialities;
  String? _selectedTitle;
  final List<_MediaGroup> _mediaGroups = [
    _MediaGroup(type: 'prescription', label: TeleconsultStrings.documentTypePrescription),
    _MediaGroup(type: 'lab_report', label: TeleconsultStrings.documentTypeLabReports),
  ];
  String? _phoneError;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadSpecialities();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadSpecialities() async {
    List<ShukheeSpeciality> fetched;
    try {
      fetched = await widget.client.getSpecialities();
    } on ShukheeException {
      fetched = const [];
    }
    if (fetched.isEmpty) {
      // Live fetch failed or returned nothing -- fall back to the
      // last-known-good list rather than leaving the form with no options.
      fetched = kTeleconsultSpecialities
          .map((title) => ShukheeSpeciality(specialityId: title, title: title))
          .toList();
    }
    if (!mounted) return;
    final defaultEntry = fetched.firstWhere(
      (s) => s.title.trim().toLowerCase() == 'general physician',
      orElse: () => fetched.first,
    );
    setState(() {
      _specialities = fetched;
      _selectedTitle = defaultEntry.title;
    });
  }

  // Selection is tracked by [ShukheeSpeciality.title], not .specialityId --
  // confirmed live against the Shukhee sandbox that every speciality in the
  // real list currently shares the *same* specialityId ("9"), so using it as
  // a selection key made every card compare equal and appear selected at
  // once. title is the field that's actually distinct per entry (and is
  // also the exact value submitted as requestedSpeciality, so there's no
  // separate "key" to keep in sync with it).
  ShukheeSpeciality? get _selectedSpeciality {
    final specialities = _specialities;
    if (specialities == null) return null;
    for (final s in specialities) {
      if (s.title == _selectedTitle) return s;
    }
    return specialities.isNotEmpty ? specialities.first : null;
  }

  /// Known specialities get a translated label; anything else (a speciality
  /// Shukhee adds later that this app hasn't localized yet) falls back to
  /// displaying the API's own title text as-is rather than hiding the option.
  String _specialityLabel(String title) {
    switch (title) {
      case 'General Physician':
        return TeleconsultStrings.specialityGeneralPhysician;
      case 'Sexual Wellness':
        return TeleconsultStrings.specialitySexualWellness;
      case 'Diabetic Coach':
        return TeleconsultStrings.specialityDiabeticCoach;
      case 'Maternity Coach':
        return TeleconsultStrings.specialityMaternityCoach;
      default:
        return title;
    }
  }

  Future<void> _pickFilesForGroup(_MediaGroup group) async {
    // Capped per group, not shared across groups -- Prescription filling up to
    // _maxDocuments must not hide/disable the independent Lab Report dropzone.
    final remaining = _maxDocuments - group.files.length;
    if (remaining <= 0) return;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(TeleconsultStrings.takePhoto),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(TeleconsultStrings.chooseFromGallery),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final picker = ImagePicker();
    if (source == ImageSource.camera) {
      final file = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: _maxDocumentDimension,
        maxHeight: _maxDocumentDimension,
        imageQuality: _documentImageQuality,
      );
      if (file != null && mounted) setState(() => group.files.add(file));
    } else {
      final files = await picker.pickMultiImage(
        limit: remaining,
        maxWidth: _maxDocumentDimension,
        maxHeight: _maxDocumentDimension,
        imageQuality: _documentImageQuality,
      );
      if (files.isNotEmpty && mounted) {
        setState(() => group.files.addAll(files.take(remaining)));
      }
    }
  }

  void _removeFile(_MediaGroup group, int index) => setState(() => group.files.removeAt(index));

  Future<void> _submit() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _phoneError = TeleconsultStrings.contactNumberRequired);
      return;
    }
    setState(() {
      _phoneError = null;
      _submitting = true;
    });

    // One key per non-empty group -- e.g. {'prescription': [...], 'lab_report': [...]} --
    // lets a single booking carry both a prescription and a lab report photo, each
    // correctly tagged (see ShukheeClient.startConsultation's mediaGroups doc comment).
    final mediaGroups = <String, List<ShukheeMediaFile>>{};
    for (final group in _mediaGroups) {
      if (group.files.isEmpty) continue;
      final medias = <ShukheeMediaFile>[];
      for (final file in group.files) {
        final bytes = await file.readAsBytes();
        medias.add(ShukheeMediaFile(filename: file.name, bytes: bytes, mimeType: file.mimeType));
      }
      mediaGroups[group.type] = medias;
    }
    if (!mounted) return;

    // .title -- the exact API field value -- is what's sent, never a
    // translated display label; .specialityId only tracks selection above.
    await widget.onSubmit(
      contactNumber: phone,
      speciality: _selectedSpeciality?.title ?? kTeleconsultSpecialities.first,
      mediaGroups: mediaGroups,
    );
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(TeleconsultStrings.bookingTitle),
        backgroundColor: AppColors.ancHeader,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      TeleconsultStrings.availableSpecialityLabel,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (_specialities == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    else
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: AppSpacing.sm,
                        crossAxisSpacing: AppSpacing.sm,
                        childAspectRatio: 2.4,
                        children: _specialities!.map((s) {
                          return _SpecialityChip(
                            label: _specialityLabel(s.title),
                            selected: s.title == _selectedTitle,
                            onTap: () => setState(() => _selectedTitle = s.title),
                          );
                        }).toList(),
                      ),
                    const SizedBox(height: AppSpacing.xl),
                    Row(
                      children: [
                        Text(
                          TeleconsultStrings.contactNumberLabel,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 3),
                        const Text(
                          '*',
                          style: TextStyle(color: AppColors.statusCritical, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        hintText: '+880 17XX XXX XXX',
                        errorText: _phoneError,
                        border: const OutlineInputBorder(),
                        focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.catFacilityBorder, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      TeleconsultStrings.selectDocumentsLabel,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    for (final group in _mediaGroups) ...[
                      Text(
                        group.label,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      if (group.files.isNotEmpty) ...[
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: List.generate(group.files.length, (i) {
                            return _PickedDocumentThumbnail(
                              file: group.files[i],
                              onRemove: () => _removeFile(group, i),
                            );
                          }),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      if (group.files.length < _maxDocuments)
                        _MediaPickerDropzone(onTap: () => _pickFilesForGroup(group)),
                      const SizedBox(height: AppSpacing.md),
                    ],
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: (_submitting || _specialities == null) ? null : _submit,
                    style: FilledButton.styleFrom(backgroundColor: AppColors.pinkWorklist),
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(TeleconsultStrings.startConsultationButton),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpecialityChip extends StatelessWidget {
  const _SpecialityChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.field),
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.catFacilitySurface : Colors.white,
          border: Border.all(color: selected ? AppColors.catFacilityBorder : AppColors.border, width: selected ? 1.5 : 1),
          borderRadius: BorderRadius.circular(AppRadius.field),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.navy : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _PickedDocumentThumbnail extends StatelessWidget {
  const _PickedDocumentThumbnail({required this.file, required this.onRemove});

  final XFile file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(File(file.path), width: 72, height: 72, fit: BoxFit.cover),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: Tooltip(
            message: CommonStrings.remove,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onRemove,
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(color: AppColors.rangeCritical, shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded, color: Colors.white, size: 14),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Dashed-border drop-zone for picking up to 3 photographed documents. No
/// dependency added for this: a small [CustomPainter] draws the dashed
/// outline instead of pulling in a dedicated package for one box.
class _MediaPickerDropzone extends StatelessWidget {
  const _MediaPickerDropzone({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.card),
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedBorderPainter(color: AppColors.catFacilityBorder),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl, horizontal: AppSpacing.md),
          child: Column(
            children: [
              const Icon(Icons.add_circle_outline_rounded, color: AppColors.catFacilityBorder, size: 28),
              const SizedBox(height: AppSpacing.sm),
              Text(
                TeleconsultStrings.selectDocumentsMax,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.75, 0.75, size.width - 1.5, size.height - 1.5),
      Radius.circular(AppRadius.card),
    );
    const dashWidth = 6.0;
    const dashGap = 4.0;
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + dashWidth), paint);
        distance += dashWidth + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) => oldDelegate.color != color;
}

/// Native "Connecting to doctor…" screen shown between a successful booking
/// and the fullscreen call — while `shukhee_sdk`'s [ShukheeCallView] loads
/// off-screen (see `_TeleconsultScreenState._buildConnectingScaffold`).
class _ConnectingView extends StatelessWidget {
  const _ConnectingView({
    required this.status,
    required this.clinicalContextSummary,
    required this.visitNumber,
    required this.onCancel,
  });

  final ShukheeStatus? status;
  final String? clinicalContextSummary;
  final int? visitNumber;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final name = status?.doctorName;
    final hasDoctor = name != null && name.isNotEmpty;
    final subtitle = _specialityFacilityLine(status);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.h6xl),
                Container(
                  width: 96,
                  height: 96,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.statusWarningSurface,
                    shape: BoxShape.circle,
                  ),
                  child: hasDoctor
                      ? Text(
                          _avatarInitials(name),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: AppColors.statusWarningText,
                          ),
                        )
                      : const Icon(Icons.medical_services_rounded, size: 40, color: AppColors.statusWarning),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  hasDoctor ? TeleconsultStrings.doctorNameOnly(name) : TeleconsultStrings.lookingForDoctor,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.statusWarningSurface,
                    border: Border.all(color: AppColors.statusWarningBorder),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(color: AppColors.statusWarning, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        TeleconsultStrings.connectingToDoctorPill,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.statusWarningText),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.h6xl),
                _RecordSharedBanner(
                  clinicalContextSummary: clinicalContextSummary,
                  visitNumber: visitNumber,
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(onPressed: onCancel, child: Text(TeleconsultStrings.cancel)),
          ),
        ),
      ],
    );
  }
}

/// Slim top bar shown above the fullscreen call — a back arrow (through the
/// existing leave-call confirmation) plus the live elapsed-time badge.
class _FullscreenBar extends StatelessWidget {
  const _FullscreenBar({required this.elapsedLabel, required this.onBack});

  final String elapsedLabel;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          _RoundIconButton(
            icon: Icons.arrow_back_rounded,
            onTap: onBack,
            tooltip: TeleconsultStrings.leaveCallConfirm,
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
            decoration: const BoxDecoration(color: AppColors.statusSuccess, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            '${TeleconsultStrings.connectedLabel} · $elapsedLabel',
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

/// Bottom-left translucent overlay on top of the live fullscreen call,
/// showing who the SK is actually talking to — the only Flutter-owned chrome
/// over Shukhee's own web page content (see file header: no custom
/// mic/camera/end-call controls are built here, that's Shukhee's page).
class _CallOverlayIdentityStrip extends StatelessWidget {
  const _CallOverlayIdentityStrip({required this.status});

  final ShukheeStatus? status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: _DoctorIdentityLine(status: status, dark: true),
    );
  }
}

/// Shows who the SK is actually talking to, from Shukhee's real
/// `doctor`/`specialty`/`working_at` fields once assigned — a generic
/// "connecting" placeholder before then, since Shukhee assigns a doctor
/// asynchronously and there's no earlier signal for it.
class _DoctorIdentityLine extends StatelessWidget {
  const _DoctorIdentityLine({required this.status, this.dark = false});

  final ShukheeStatus? status;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final name = status?.doctorName;
    final text = (name == null || name.isEmpty)
        ? TeleconsultStrings.connectingToDoctor
        : _formatDoctorLine(name, status?.doctorSpeciality, status?.doctorFacility);
    return Text(
      text,
      style: TextStyle(
        fontWeight: FontWeight.w700,
        color: dark ? Colors.white : null,
        fontSize: dark ? 13 : null,
      ),
    );
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
    required this.prescriptionBytes,
    required this.invoiceBytes,
    required this.onDone,
  });

  final ShukheeClient client;
  final String? callLog;
  final ShukheeStatus? status;
  final int? visitNumber;
  final String? clinicalContextSummary;
  final String? whatsappMessage;
  final String? patientPhone;
  final Uint8List? prescriptionBytes;
  final Uint8List? invoiceBytes;
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
              initialBytes: prescriptionBytes,
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
              initialBytes: invoiceBytes,
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

/// Renders a completed consultation's prescription/invoice bytes as an
/// inline first-page preview, and opens the full multi-page document in an
/// in-app [PdfViewerScreen] on tap — never hands the PDF to an external app
/// (the file is a private Frappe attachment with no unauthenticated web
/// access; see [ShukheeClient.downloadDocument]).
///
/// When [initialBytes] is given (the parent screen already prefetched it via
/// its own "Generating prescription…" gate), rendering starts from those
/// bytes immediately with no network call. When null (prefetch failed or was
/// skipped), falls back to fetching the bytes itself — today's original
/// behavior — so a prefetch bug degrades gracefully rather than breaking.
class _DocumentPreviewCard extends StatefulWidget {
  const _DocumentPreviewCard({
    required this.client,
    required this.callLog,
    required this.docType,
    required this.title,
    required this.buttonLabel,
    required this.icon,
    this.initialBytes,
  });

  final ShukheeClient client;
  final String callLog;
  final String docType;
  final String title;
  final String buttonLabel;
  final IconData icon;
  final Uint8List? initialBytes;

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
      final bytes = widget.initialBytes ??
          Uint8List.fromList(
            (await widget.client.downloadDocument(callLog: widget.callLog, docType: widget.docType)).bytes,
          );
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

/// Shared layout for the error/not-completed/not-provisioned/
/// generating-prescription states.
class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    this.showSpinner = false,
    this.spinnerColor,
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
  final Color? spinnerColor;
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
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.h6xl),
                child: spinnerColor != null
                    ? CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(spinnerColor))
                    : const CircularProgressIndicator(),
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
