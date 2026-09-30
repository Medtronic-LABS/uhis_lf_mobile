/// Full-screen patient-consent gate shown every time the SK taps "Call a
/// doctor now" -- before the real Shukhee booking flow
/// ([TeleconsultScreen]) is ever reached. See `_TeleconsultButtonState._onTap`
/// in `visit_flow_screen.dart` for the single call site that pushes this
/// screen (`/teleconsult/consent`).
///
/// The consent body is HTML fetched live from the backend
/// ([ShukheeConsentClient]) in the app's current language, with a
/// server-side fallback to English -- never cached, and never replaced by a
/// hardcoded fallback on failure (this is a compliance-sensitive gate: a
/// fetch failure blocks the call entirely and offers only a retry).
///
/// Returns `true` via [GoRouter.pop] when the SK confirms consent, `false`
/// when declined. The caller only proceeds to `/teleconsult` on `true`.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/config/app_config.dart';
import '../../core/constants/app_strings.dart';
import '../../core/i18n/app_locale.dart';
import '../../core/telemetry/teleconsult_consent_log_service.dart';
import '../../core/theme/app_theme.dart';
import 'shukhee_consent_client.dart';

/// Builds a [ShukheeConsentClient] wired to this app's own authenticated
/// session ([ApiClient]) -- same token-stripping/tenantId convention as
/// `shukhee_client_factory.dart`'s `buildShukheeClient`, kept local here
/// (rather than added to that file) since that file's own doc comment scopes
/// it to building "the app's one real `ShukheeClient`" (the `shukhee_sdk`
/// client specifically), not every Shukhee-family client.
ShukheeConsentClient _buildConsentClient(BuildContext context) {
  final apiClient = context.read<ApiClient>();
  return ShukheeConsentClient(
    baseUrl: AppConfig.shukheeApiBaseUrl,
    authTokenProvider: () async {
      final raw = apiClient.exportAuthToken();
      if (raw == null) return null;
      const prefix = 'Bearer ';
      return raw.startsWith(prefix) ? raw.substring(prefix.length) : raw;
    },
    tenantIdProvider: () async => apiClient.tenantId,
  );
}

class TeleconsultConsentScreen extends StatefulWidget {
  const TeleconsultConsentScreen({
    super.key,
    required this.patientId,
    this.visitId,
    this.patientDob,
    this.patientLabel,
    @visibleForTesting this.consentClientBuilder,
  });

  /// Who the consent decision is about -- logged by
  /// [TeleconsultConsentLogService], never sent to the `get_consent` fetch
  /// itself.
  final String patientId;

  /// The visit/encounter the consent was captured during, if any.
  final String? visitId;

  /// The patient's date of birth (ISO 8601), if known -- logged alongside the
  /// decision so age is visible in the audit trail (see
  /// `TeleconsultConsentLogEntry.patientDob`'s doc comment for why this is
  /// the raw fact and not a derived flag).
  final String? patientDob;

  /// Shown for display context only -- never sent to the consent endpoint.
  final String? patientLabel;

  /// Test seam overriding how the [ShukheeConsentClient] is built, mirroring
  /// `TeleconsultScreen`'s injected `client` param. Production always uses
  /// the default ([_buildConsentClient]).
  @visibleForTesting
  final ShukheeConsentClient Function(BuildContext)? consentClientBuilder;

  @override
  State<TeleconsultConsentScreen> createState() => _TeleconsultConsentScreenState();
}

class _TeleconsultConsentScreenState extends State<TeleconsultConsentScreen> {
  late Future<ShukheeConsentContent> _future;
  bool _agreed = false;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<ShukheeConsentContent> _fetch() {
    final client = (widget.consentClientBuilder ?? _buildConsentClient)(context);
    return client.fetchConsent(lng: AppLocale.isBangla ? 'bn' : 'en');
  }

  /// Fires the fire-and-forget consent-decision log, then pops with the
  /// decision -- log failure must never delay or block this navigation (see
  /// [TeleconsultConsentLogService.record]'s own "never throws" contract).
  void _decide(ShukheeConsentContent content, {required bool agreed}) {
    unawaited(
      context.read<TeleconsultConsentLogService>().record(
            patientId: widget.patientId,
            visitId: widget.visitId,
            agreed: agreed,
            lng: content.lng,
            consentVersion: content.version,
            patientDob: widget.patientDob,
          ),
    );
    context.pop(agreed);
  }

  void _retry() {
    setState(() {
      _agreed = false;
      _future = _fetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        title: Text(
          TeleconsultConsentStrings.title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: FutureBuilder<ShukheeConsentContent>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return _LoadingState();
            }
            if (snapshot.hasError) {
              return _ErrorState(onRetry: _retry);
            }
            return _LoadedState(
              content: snapshot.data!,
              patientLabel: widget.patientLabel,
              agreed: _agreed,
              onAgreedChanged: (v) => setState(() => _agreed = v ?? false),
              onAgree: () => _decide(snapshot.data!, agreed: true),
              onDecline: () => _decide(snapshot.data!, agreed: false),
            );
          },
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppColors.navy),
          const SizedBox(height: 16),
          Text(
            TeleconsultConsentStrings.loadingMessage,
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 40, color: AppColors.statusCritical),
            const SizedBox(height: 16),
            Text(
              TeleconsultConsentStrings.errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.5),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
              child: Text(TeleconsultConsentStrings.retryButton),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadedState extends StatelessWidget {
  const _LoadedState({
    required this.content,
    required this.agreed,
    required this.onAgreedChanged,
    required this.onAgree,
    required this.onDecline,
    this.patientLabel,
  });

  final ShukheeConsentContent content;
  final String? patientLabel;
  final bool agreed;
  final ValueChanged<bool?> onAgreedChanged;
  final VoidCallback onAgree;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (patientLabel != null && patientLabel!.isNotEmpty) ...[
                  Text(
                    TeleconsultConsentStrings.patientContextLabel(patientLabel!),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Html(data: content.html),
                const SizedBox(height: 20),
                _AgreementCheckbox(value: agreed, onChanged: onAgreedChanged),
              ],
            ),
          ),
        ),
        _ActionBar(agreed: agreed, onAgree: onAgree, onDecline: onDecline),
      ],
    );
  }
}

class _AgreementCheckbox extends StatelessWidget {
  const _AgreementCheckbox({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: value ? AppColors.cardSurfaceMuted : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: value ? AppColors.navy : AppColors.border,
            width: value ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: value,
                onChanged: onChanged,
                activeColor: AppColors.navy,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                TeleconsultConsentStrings.checkboxLabel,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: value ? AppColors.navy : AppColors.textPrimary,
                  fontWeight: value ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.agreed,
    required this.onAgree,
    required this.onDecline,
  });

  final bool agreed;
  final VoidCallback onAgree;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: onDecline,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(TeleconsultConsentStrings.declineButton),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: agreed ? onAgree : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.navy,
                disabledBackgroundColor: AppColors.border,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(TeleconsultConsentStrings.agreeButton),
            ),
          ),
        ],
      ),
    );
  }
}
