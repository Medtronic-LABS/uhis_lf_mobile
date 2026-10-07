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
/// Returns a [TeleconsultConsentDecision] via [GoRouter.pop] -- `agreed:
/// false` when declined. The caller only proceeds to `/teleconsult` on
/// `agreed: true`, threading `version`/`versionId`/`lng`/`itemsChecked`
/// through to the booking call so it can embed them directly onto the
/// resulting Call Logs row in the same request (see
/// `TeleconsultScreen._submitBooking`) -- there is no separate consent
/// doctype or later linking step for an Agreed decision. A Decline is
/// recorded immediately, here, via [ShukheeConsentClient.recordDecline] --
/// see [_decide]'s own doc comment for why that's the only place it can be.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/auth/user_hierarchy_service.dart';
import '../../core/constants/app_strings.dart';
import '../../core/i18n/app_locale.dart';
import '../../core/theme/app_theme.dart';
import 'consent_template_filler.dart';
import 'shukhee_consent_client.dart';

/// The result popped by [TeleconsultConsentScreen] -- carries the accepted
/// consent version/language/items forward so the booking call can embed them
/// directly onto the resulting Call Logs row, not just the bare Agree/Decline
/// bit.
class TeleconsultConsentDecision {
  const TeleconsultConsentDecision({
    required this.agreed,
    required this.version,
    required this.versionId,
    required this.lng,
    this.itemsChecked,
  });

  final bool agreed;
  final String? version;

  /// The exact Shukhee Consent Version snapshot the patient saw -- must be
  /// carried forward unchanged (see `ShukheeConsentContent.versionId`'s own
  /// doc comment).
  final String? versionId;
  final String lng;

  /// One entry per `ShukheeConsentContent.items`, positional -- null when
  /// that list was empty (nothing to tick, nothing to echo back).
  final List<bool>? itemsChecked;
}

/// CHW display name for the `{{chw_name}}` token (purely cosmetic -- see
/// `fillConsentTemplate`'s own doc comment), tolerating a missing
/// [UserHierarchyService] provider rather than requiring every widget test
/// of this screen to wire up a full fake auth stack just for one display
/// field. Production always has this provider registered at the app root
/// (see `main.dart`); only test harnesses that don't need CHW-name coverage
/// skip it.
String? _watchChwName(BuildContext context) {
  try {
    return context.watch<UserHierarchyService>().skProfile?.name;
  } on Object {
    return null;
  }
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

  /// Who the consent decision is about -- sent to [ShukheeConsentClient.recordDecline] on
  /// Decline, or threaded through to `TeleconsultScreen`/`start_consultation` on Agree
  /// (never sent to the `get_consent` fetch itself).
  final String patientId;

  /// The visit/encounter the consent was captured during, if any.
  final String? visitId;

  /// The patient's date of birth (ISO 8601), if known -- recorded alongside the
  /// decision so age is visible in the audit trail (raw fact, not a derived
  /// "is minor" flag).
  final String? patientDob;

  /// Shown for display context only -- never sent to the consent endpoint.
  final String? patientLabel;

  /// Test seam overriding how the [ShukheeConsentClient] is built, mirroring
  /// `TeleconsultScreen`'s injected `client` param. Production always uses
  /// the default ([buildShukheeConsentClient]).
  @visibleForTesting
  final ShukheeConsentClient Function(BuildContext)? consentClientBuilder;

  @override
  State<TeleconsultConsentScreen> createState() => _TeleconsultConsentScreenState();
}

class _TeleconsultConsentScreenState extends State<TeleconsultConsentScreen> {
  late Future<ShukheeConsentContent> _future;

  /// One entry per [ShukheeConsentContent.items], positional -- initialized
  /// once content loads (see [_onContentLoaded]), reset on retry.
  List<bool> _itemChecked = const [];

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<ShukheeConsentContent> _fetch() {
    final client = (widget.consentClientBuilder ?? buildShukheeConsentClient)(context);
    return client.fetchConsent(lng: AppLocale.isBangla ? 'bn' : 'en');
  }

  /// Runs once per successful fetch (including after a retry) -- sizes the
  /// per-item checkbox state to match this response's own `items` list,
  /// since a retry could in principle return a different-length list than
  /// the previous attempt.
  void _onContentLoaded(ShukheeConsentContent content) {
    if (_itemChecked.length != content.items.length) {
      _itemChecked = List<bool>.filled(content.items.length, false);
    }
  }

  bool _mandatoryUnmet(ShukheeConsentContent content) {
    for (var i = 0; i < content.items.length; i++) {
      final checked = i < _itemChecked.length && _itemChecked[i];
      if (content.items[i].mandatory && !checked) return true;
    }
    return false;
  }

  /// On Agree, never calls the network here at all -- the decision (including
  /// which items were ticked) is carried forward via the popped
  /// [TeleconsultConsentDecision] and sent as part of the booking call itself
  /// (`start_consultation`), which embeds it directly onto the Call Logs row
  /// it creates. There is no Call Logs row to embed anything on for a
  /// Decline, so that's the one case recorded here instead -- fired
  /// immediately, fire-and-forget (never awaited, never blocks this
  /// navigation), via [ShukheeConsentClient.recordDecline], which never
  /// throws on its own.
  void _decide(ShukheeConsentContent content, {required bool agreed}) {
    final itemsChecked = content.items.isEmpty ? null : List<bool>.of(_itemChecked);
    if (!agreed) {
      final client = (widget.consentClientBuilder ?? buildShukheeConsentClient)(context);
      unawaited(
        client.recordDecline(
          patientId: widget.patientId,
          visitId: widget.visitId,
          lng: content.lng,
          versionId: content.versionId,
          patientDob: widget.patientDob,
        ),
      );
    }
    context.pop(TeleconsultConsentDecision(
      agreed: agreed,
      version: content.version,
      versionId: content.versionId,
      lng: content.lng,
      itemsChecked: itemsChecked,
    ));
  }

  void _retry() {
    setState(() {
      _itemChecked = const [];
      _future = _fetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    final chwName = _watchChwName(context);
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
            final content = snapshot.data!;
            _onContentLoaded(content);
            final filledHtml = fillConsentTemplate(
              content.html,
              participantName: widget.patientLabel ?? widget.patientId,
              participantId: widget.patientId,
              dateTime: DateTime.now(),
              lng: content.lng,
              chwName: chwName,
              consentVersion: content.version,
            );
            return _LoadedState(
              content: content,
              html: filledHtml,
              patientLabel: widget.patientLabel,
              itemChecked: _itemChecked,
              onItemToggled: (index, value) => setState(() {
                _itemChecked = List<bool>.of(_itemChecked)..[index] = value;
              }),
              canAgree: content.items.isEmpty || !_mandatoryUnmet(content),
              onAgree: () => _decide(content, agreed: true),
              onDecline: () => _decide(content, agreed: false),
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
    required this.html,
    required this.itemChecked,
    required this.onItemToggled,
    required this.canAgree,
    required this.onAgree,
    required this.onDecline,
    this.patientLabel,
  });

  final ShukheeConsentContent content;

  /// [content.html] with `{{token}}` placeholders already substituted for
  /// live display (see `fillConsentTemplate`) -- rendered as-is, never
  /// [content.html] directly.
  final String html;
  final String? patientLabel;

  /// One entry per [ShukheeConsentContent.items], positional.
  final List<bool> itemChecked;
  final void Function(int index, bool value) onItemToggled;

  /// False while any mandatory item (see [ConsentItem.mandatory]) is
  /// unchecked -- optional items never block proceeding.
  final bool canAgree;
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
                Html(data: html),
                const SizedBox(height: 20),
                for (var i = 0; i < content.items.length; i++) ...[
                  _ConsentItemCheckbox(
                    item: content.items[i],
                    value: i < itemChecked.length && itemChecked[i],
                    onChanged: (v) => onItemToggled(i, v ?? false),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
        _ActionBar(canAgree: canAgree, onAgree: onAgree, onDecline: onDecline),
      ],
    );
  }
}

class _ConsentItemCheckbox extends StatelessWidget {
  const _ConsentItemCheckbox({
    required this.item,
    required this.value,
    required this.onChanged,
  });

  final ConsentItem item;
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
              child: Text.rich(
                TextSpan(
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    color: value ? AppColors.navy : AppColors.textPrimary,
                    fontWeight: value ? FontWeight.w600 : FontWeight.normal,
                  ),
                  children: [
                    // A bare "*" needs no translation, unlike a "Required"
                    // word would -- same convention as a required
                    // form-field marker.
                    if (item.mandatory)
                      const TextSpan(
                        text: '* ',
                        style: TextStyle(
                          color: AppColors.statusCritical,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    TextSpan(text: item.description),
                  ],
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
    required this.canAgree,
    required this.onAgree,
    required this.onDecline,
  });

  final bool canAgree;
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
              onPressed: canAgree ? onAgree : null,
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
