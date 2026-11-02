/// Shared WhatsApp/SMS send logic for AI-generated counselling messages.
///
/// Extracted so `CounsellingScreen`, `_AiCounsellingCard` (visit flow Step 3),
/// and the teleconsult wrap-up screen's "Send counselling to family" button
/// all share one implementation instead of three near-identical copies.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens WhatsApp (native app, falling back to the wa.me web link) with
/// [message] pre-filled, addressed to [phone] when given. Shows
/// [notInstalledMessage] via a [SnackBar] if neither can be launched.
Future<void> sendCounsellingWhatsApp({
  required BuildContext context,
  required String message,
  String? phone,
  required String notInstalledMessage,
}) async {
  final encoded = Uri.encodeComponent(message);
  final rawPhone = phone?.replaceAll(RegExp(r'[^\d]'), '') ?? '';
  final phoneParam = rawPhone.isNotEmpty ? 'phone=$rawPhone&' : '';
  final nativeUri = Uri.parse('whatsapp://send?${phoneParam}text=$encoded');
  if (await canLaunchUrl(nativeUri)) {
    await launchUrl(nativeUri);
    return;
  }
  final webUri = Uri.parse(
      'https://wa.me/${rawPhone.isNotEmpty ? rawPhone : ''}?text=$encoded');
  if (await canLaunchUrl(webUri)) {
    await launchUrl(webUri, mode: LaunchMode.externalApplication);
    return;
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(notInstalledMessage)));
  }
}

/// Opens the SMS composer with [message] pre-filled, addressed to [phone].
/// Shows [notAvailableMessage] via a [SnackBar] if SMS can't be launched.
Future<void> sendCounsellingSms({
  required BuildContext context,
  required String message,
  String? phone,
  required String notAvailableMessage,
}) async {
  final encoded = Uri.encodeComponent(message);
  final uri = Uri.parse('sms:${phone ?? ''}?body=$encoded');
  if (!await canLaunchUrl(uri)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(notAvailableMessage)));
    }
    return;
  }
  await launchUrl(uri);
}
