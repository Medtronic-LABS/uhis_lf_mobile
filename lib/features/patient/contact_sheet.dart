import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_strings.dart';
import '../../core/db/member_dao.dart';
import 'patient_context_screen.dart' show PatientOrMemberData;

// ── Resolution model ──────────────────────────────────────────────────────────

class ContactResolution {
  const ContactResolution({
    required this.phone,
    required this.recipientName,
    this.relationship,
    required this.patientName,
  });

  final String phone;
  final String recipientName;
  // null = patient's own number; set = fallback contact
  final String? relationship;
  final String patientName;

  bool get isOwnNumber => relationship == null;
}

// ── Resolver ──────────────────────────────────────────────────────────────────

Future<ContactResolution?> resolvePatientContact(
  PatientOrMemberData d,
  MemberDao dao,
) async {
  final patientName = d.name ?? ContactSheetStrings.unknownPatient;

  // 1. Patient's own phone
  final own = d.phoneNumber?.trim();
  if (own != null && own.isNotEmpty) {
    return ContactResolution(
      phone: own,
      recipientName: patientName,
      patientName: patientName,
    );
  }

  // 2. Household member fallback
  final householdId = d.householdId;
  if (householdId == null || householdId.isEmpty) return null;

  final members = await dao.getByHouseholdId(householdId);
  final withPhone = members
      .where((m) => (m.phone?.trim() ?? '').isNotEmpty)
      .toList();
  if (withPhone.isEmpty) return null;

  // Prefer household head, then first member with a number
  final candidate = withPhone.firstWhere(
    (m) => m.isHouseholdHead,
    orElse: () => withPhone.first,
  );

  return ContactResolution(
    phone: candidate.phone!.trim(),
    recipientName: candidate.name ?? ContactSheetStrings.familyMember,
    relationship: candidate.isHouseholdHead
        ? ContactSheetStrings.householdHead
        : ContactSheetStrings.familyMember,
    patientName: patientName,
  );
}

// ── Helpers ───────────────────────────────────────────────────────────────────

// Normalise to E.164 digits (no +) for wa.me — handles Bangladeshi 01X format.
String _toE164(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.startsWith('0')) return '880${digits.substring(1)}';
  return digits;
}

String _prefilledMessage(String patientName) =>
    '${ReferralStrings.msgGreeting(patientName)}'
    '${ReferralStrings.msgIntro}'
    '${ReferralStrings.msgGenericOutreach}';

void _snack(BuildContext ctx, String msg) =>
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg)));

Future<void> _call(BuildContext ctx, String phone) async {
  final uri = Uri(scheme: 'tel', path: phone);
  try {
    if (!await launchUrl(uri) && ctx.mounted) {
      _snack(ctx, PatientProfileStrings.dialFailed);
    }
  } catch (_) {
    if (ctx.mounted) _snack(ctx, PatientProfileStrings.dialFailed);
  }
}

Future<void> _whatsApp(
    BuildContext ctx, String phone, String patientName) async {
  final e164 = _toE164(phone);
  final msg = Uri.encodeComponent(_prefilledMessage(patientName));
  final uri = Uri.parse('https://wa.me/$e164?text=$msg');
  try {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        ctx.mounted) {
      _snack(ctx, ContactSheetStrings.whatsAppFailed);
    }
  } catch (_) {
    if (ctx.mounted) _snack(ctx, ContactSheetStrings.whatsAppFailed);
  }
}

Future<void> _sms(BuildContext ctx, String phone, String patientName) async {
  final msg = Uri.encodeComponent(_prefilledMessage(patientName));
  final uri = Uri.parse('sms:$phone?body=$msg');
  try {
    if (!await launchUrl(uri) && ctx.mounted) {
      _snack(ctx, ContactSheetStrings.smsFailed);
    }
  } catch (_) {
    if (ctx.mounted) _snack(ctx, ContactSheetStrings.smsFailed);
  }
}

// ── Entry point ───────────────────────────────────────────────────────────────

Future<void> showContactSheet(
  BuildContext context,
  PatientOrMemberData d,
) async {
  final dao = context.read<MemberDao>();

  ContactResolution? resolution;
  try {
    resolution = await resolvePatientContact(d, dao);
  } catch (_) {
    resolution = null;
  }

  if (!context.mounted) return;

  if (resolution == null) {
    _snack(context, ContactSheetStrings.noContactAvailable);
    return;
  }

  final captured = resolution;
  final outerCtx = context;
  await showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ContactSheet(resolution: captured, outerCtx: outerCtx),
  );
}

// ── Sheet ─────────────────────────────────────────────────────────────────────

class _ContactSheet extends StatelessWidget {
  const _ContactSheet({required this.resolution, required this.outerCtx});
  final ContactResolution resolution;
  final BuildContext outerCtx;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Title + phone number
            Text(
              ReferralStrings.contactSheetTitle(resolution.recipientName),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              resolution.phone,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),

            // Fallback banner
            if (!resolution.isOwnNumber) ...[
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3CD),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFFFFCC44).withValues(alpha: 0.5)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 16, color: Color(0xFF856404)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ContactSheetStrings.fallbackBanner(
                          resolution.patientName,
                          resolution.recipientName,
                          resolution.relationship!,
                        ),
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF664D00), height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Actions
            Row(
              children: [
                _ActionButton(
                  icon: Icons.phone_rounded,
                  label: ReferralStrings.contactCall,
                  subtitle: ReferralStrings.contactCallSubtitle,
                  color: const Color(0xFF2E7D32),
                  onTap: () {
                    Navigator.of(context).pop();
                    _call(outerCtx, resolution.phone);
                  },
                ),
                const SizedBox(width: 10),
                _ActionButton(
                  icon: Icons.chat_rounded,
                  label: ReferralStrings.contactWhatsApp,
                  subtitle: ReferralStrings.contactWhatsAppSubtitle,
                  color: const Color(0xFF25D366),
                  onTap: () {
                    Navigator.of(context).pop();
                    _whatsApp(outerCtx, resolution.phone, resolution.patientName);
                  },
                ),
                const SizedBox(width: 10),
                _ActionButton(
                  icon: Icons.sms_rounded,
                  label: ReferralStrings.contactSms,
                  subtitle: ReferralStrings.contactSmsSubtitle,
                  color: const Color(0xFF1565C0),
                  onTap: () {
                    Navigator.of(context).pop();
                    _sms(outerCtx, resolution.phone, resolution.patientName);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  color: color.withValues(alpha: 0.7),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
