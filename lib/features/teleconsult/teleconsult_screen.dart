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
/// Engineering Design Standards:
///   - All Shukhee-specific I/O lives in `shukhee_sdk`; this file only
///     translates its `ShukheeException`s into this app's own
///     [DomainException] subclasses and renders state.
///   - All strings from [TeleconsultStrings].
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shukhee_sdk/shukhee_sdk.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client.dart';
import '../../core/config/app_config.dart';
import '../../core/constants/app_strings.dart';
import '../../core/errors/domain_exceptions.dart';
import '../../core/theme/app_theme.dart';

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
    @visibleForTesting this.client,
  });

  final String patientLabel;
  final String patientId;

  /// Threaded through as `encounter_id` when booking.
  final String? visitId;

  /// The patient's contact number, if already known. When null/empty, the
  /// screen asks for it once via a one-field bottom sheet before booking.
  final String? patientPhone;

  /// Pre-derived reason text (from the visit's AI recommendation) — see
  /// `_TeleconsultButton` in `visit_flow_screen.dart` for how this is built.
  final String? reason;

  final String? patientDob;
  final String? patientGender;

  /// Test-only injection point — real callers never pass this; the screen
  /// builds its own client from [AppConfig] otherwise.
  final ShukheeClient? client;

  @override
  State<TeleconsultScreen> createState() => _TeleconsultScreenState();
}

class _TeleconsultScreenState extends State<TeleconsultScreen> {
  late final ShukheeClient _client;

  _Stage _stage = _Stage.booking;
  DomainException? _error;
  ShukheeBooking? _booking;
  ShukheeStatus? _status;
  String? _phoneOverride;

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

  ShukheeClient _buildDefaultClient() {
    final apiClient = context.read<ApiClient>();
    return ShukheeClient(
      ShukheeConfig(
        baseUrl: AppConfig.shukheeApiBaseUrl,
        authTokenProvider: () async => apiClient.exportAuthToken(),
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
      });
      unawaited(_pollInBackground(booking.callLog));
    } on ShukheeException catch (e) {
      if (mounted) _handleError(e);
    }
  }

  Future<void> _pollInBackground(String callLog) async {
    final status = await _client.pollStatus(
      callLog: callLog,
      maxAttempts: AppConfig.teleconsultPollMaxAttempts,
      delayBetween: Duration(seconds: AppConfig.teleconsultPollDelaySeconds),
    );
    if (!mounted) return;
    setState(() {
      _status = status;
      _stage = status.isCompleted ? _Stage.wrapUp : _Stage.notCompleted;
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

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
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

  @override
  Widget build(BuildContext context) {
    if (_stage == _Stage.connected && _booking != null) {
      // No standard AppBar here — the branded strip below is the header,
      // and every remaining pixel goes to the call itself.
      return Scaffold(
        backgroundColor: AppColors.partnerSukheeCardStart,
        body: SafeArea(
          child: Column(
            children: [
              _ConnectedHeader(onBack: _confirmLeaveCall),
              Expanded(child: ShukheeCallView(callUrl: _booking!.callUrl)),
            ],
          ),
        ),
      );
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
        return _WrapUpView(status: _status, onOpenLink: _openLink, onDone: () => Navigator.of(context).pop());
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

/// Branded header shown above [ShukheeCallView] — styled from the design
/// mockup's Sukhee partner tokens. Everything below this strip is Shukhee's
/// own real webpage content, not rebuilt here.
class _ConnectedHeader extends StatelessWidget {
  const _ConnectedHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.partnerSukheeBar,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  TeleconsultStrings.title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                ),
                Text(
                  TeleconsultStrings.viaSukhee,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              color: AppColors.sukheeStart.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: AppColors.sukheeStart, shape: BoxShape.circle),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  TeleconsultStrings.statusConnected,
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Prescription/invoice summary shown once the call reaches `completed`.
/// Only renders what the backend actually returns (file links) — the
/// mockup's "Doctor's conclusion" card is not built here: the backend
/// contract has no structured diagnosis field, only prescription/invoice
/// file links.
class _WrapUpView extends StatelessWidget {
  const _WrapUpView({required this.status, required this.onOpenLink, required this.onDone});

  final ShukheeStatus? status;
  final Future<void> Function(String url) onOpenLink;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final prescriptionLink = status?.prescriptionLink;
    final invoiceLink = status?.invoiceLink;

    return Padding(
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
          const SizedBox(height: AppSpacing.h6xl),
          FilledButton.icon(
            onPressed: prescriptionLink == null ? null : () => onOpenLink(prescriptionLink),
            icon: const Icon(Icons.description_outlined),
            label: Text(TeleconsultStrings.viewPrescription),
          ),
          const SizedBox(height: AppSpacing.xl),
          if (invoiceLink != null)
            OutlinedButton.icon(
              onPressed: () => onOpenLink(invoiceLink),
              icon: const Icon(Icons.receipt_long_outlined),
              label: Text(TeleconsultStrings.viewInvoice),
            ),
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
  final _controller = TextEditingController();

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
