/// AI-generated health counselling WhatsApp screen.
///
/// Displays the AI-generated WhatsApp message from [NabaResponse.whatsappSummary]
/// and allows the SK to send it to the patient's family via WhatsApp or SMS.
///
/// Engineering Design Standards:
///   - All strings from [CounsellingStrings].
///   - No business logic — pure send/copy actions via [url_launcher].
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_strings.dart';
import '../../core/theme/app_theme.dart';

/// WhatsApp brand green header — mimics the real WhatsApp app chrome,
/// deliberately distinct from AppColors.whatsapp/waHeader (the in-app accent).
const Color _waHeaderColor = AppColors.whatsappPreviewHeader;

/// WhatsApp sent-bubble green.
const Color _waBubbleColor = AppColors.whatsappPreviewBubble;

/// WhatsApp accent green (send button, avatar).
const Color _waAccentColor = AppColors.whatsapp;

class CounsellingScreen extends StatefulWidget {
  const CounsellingScreen({
    super.key,
    required this.patientLabel,
    required this.patientId,
    this.whatsappMessage,
    this.patientPhone,
  });

  final String patientLabel;
  final String patientId;

  /// AI-generated counselling message (Bangla). From [NabaResponse.whatsappSummary].
  final String? whatsappMessage;

  /// Pre-fills the WhatsApp / SMS recipient. Normalised to E.164 digits on send.
  final String? patientPhone;

  @override
  State<CounsellingScreen> createState() => _CounsellingScreenState();
}

class _CounsellingScreenState extends State<CounsellingScreen> {
  bool _copied = false;

  bool get _hasMessage =>
      widget.whatsappMessage != null && widget.whatsappMessage!.isNotEmpty;

  Future<void> _copy() async {
    if (!_hasMessage) return;
    await Clipboard.setData(ClipboardData(text: widget.whatsappMessage!));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  Future<void> _sendWhatsApp() async {
    if (!_hasMessage) return;
    final encoded = Uri.encodeComponent(widget.whatsappMessage!);
    final rawPhone =
        widget.patientPhone?.replaceAll(RegExp(r'[^\d]'), '') ?? '';
    final phoneParam = rawPhone.isNotEmpty ? 'phone=$rawPhone&' : '';
    final nativeUri =
        Uri.parse('whatsapp://send?${phoneParam}text=$encoded');
    if (await canLaunchUrl(nativeUri)) {
      await launchUrl(nativeUri);
      return;
    }
    // Fallback: wa.me universal link.
    final webUri = Uri.parse(
        'https://wa.me/${rawPhone.isNotEmpty ? rawPhone : ''}?text=$encoded');
    if (await canLaunchUrl(webUri)) {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(CounsellingStrings.whatsAppNotInstalled)),
      );
    }
  }

  Future<void> _sendSms() async {
    if (!_hasMessage) return;
    final encoded = Uri.encodeComponent(widget.whatsappMessage!);
    final phone = widget.patientPhone ?? '';
    final uri = Uri.parse('sms:$phone?body=$encoded');
    if (!await canLaunchUrl(uri)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(CounsellingStrings.smsNotAvailable)),
        );
      }
      return;
    }
    await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(CounsellingStrings.title),
        backgroundColor: _waHeaderColor,
        foregroundColor: Colors.white,
        actions: _hasMessage
            ? [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _copied
                      ? const Icon(
                          Icons.check_rounded,
                          key: ValueKey('copied'),
                          color: Colors.white,
                        )
                      : IconButton(
                          key: const ValueKey('copy'),
                          icon: const Icon(Icons.copy_rounded),
                          tooltip: CounsellingStrings.copyMessage,
                          onPressed: _copy,
                        ),
                ),
              ]
            : null,
      ),
      body: Column(
        children: [
          // ── Patient header ──────────────────────────────────────────────
          ListTile(
            tileColor: Theme.of(context).colorScheme.surface,
            leading: const CircleAvatar(
              backgroundColor: _waAccentColor,
              child: Icon(Icons.person, color: Colors.white),
            ),
            title: Text(
              widget.patientLabel,
              style: theme.textTheme.titleSmall,
            ),
            subtitle: Text(CounsellingStrings.subtitle),
          ),
          const Divider(height: 1),

          // ── Message area ────────────────────────────────────────────────
          Expanded(
            child: _hasMessage
                ? ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xxxl,
                      vertical: AppSpacing.md,
                    ),
                    children: [
                      _OutgoingBubble(text: widget.whatsappMessage!),
                    ],
                  )
                : const Center(
                    child: Text(
                      CounsellingStrings.noMessage,
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ),
          ),

          // ── Send actions ────────────────────────────────────────────────
          if (_hasMessage)
            SafeArea(
              child: Container(
                color: Theme.of(context).colorScheme.surface,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.md,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _sendWhatsApp,
                        icon: const Icon(Icons.chat_rounded, size: 18),
                        label: Text(CounsellingStrings.sendWhatsApp),
                        style: FilledButton.styleFrom(
                          backgroundColor: _waAccentColor,
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    IconButton(
                      onPressed: _sendSms,
                      icon: const Icon(Icons.sms_rounded),
                      tooltip: CounsellingStrings.sendSms,
                      style: IconButton.styleFrom(
                        foregroundColor: _waAccentColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A right-aligned WhatsApp-style sent message bubble.
class _OutgoingBubble extends StatelessWidget {
  const _OutgoingBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxxl,
          vertical: AppSpacing.xl,
        ),
        decoration: const BoxDecoration(
          color: _waBubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(AppRadius.card),
            topRight: Radius.circular(AppRadius.card),
            bottomLeft: Radius.circular(AppRadius.card),
            bottomRight: Radius.circular(AppRadius.rxIcon),
          ),
        ),
        child: Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textStrong,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}
