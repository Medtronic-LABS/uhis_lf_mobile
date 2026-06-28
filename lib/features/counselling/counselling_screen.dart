/// AI-generated health counselling message placeholder screen.
///
/// Displays a WhatsApp-style chat interface scaffold. No messages are sent
/// or received — this is a functional UI scaffold awaiting the counselling
/// AI API wiring.
///
/// Engineering Design Standards:
///   - Pure UI — no I/O, no API calls.
///   - All strings from [CounsellingStrings].
library;

import 'package:flutter/material.dart';

import '../../core/constants/app_strings.dart';
import '../../core/theme/app_theme.dart';

/// WhatsApp brand green header.
const Color _waHeaderColor = Color(0xFF075E54);

/// WhatsApp sent-bubble green.
const Color _waBubbleColor = Color(0xFFDCF8C6);

/// WhatsApp accent green (send button, avatar).
const Color _waAccentColor = Color(0xFF25D366);

class CounsellingScreen extends StatelessWidget {
  const CounsellingScreen({
    super.key,
    required this.patientLabel,
    required this.patientId,
  });

  final String patientLabel;
  final String patientId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text(CounsellingStrings.title),
        backgroundColor: _waHeaderColor,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // ── Patient header ──────────────────────────────────────────────
          ListTile(
            tileColor: AppColors.cardSurface,
            leading: const CircleAvatar(
              backgroundColor: _waAccentColor,
              child: Icon(Icons.person, color: Colors.white),
            ),
            title: Text(
              patientLabel,
              style: theme.textTheme.titleSmall,
            ),
            subtitle: const Text(CounsellingStrings.subtitle),
          ),
          const Divider(height: 1),

          // ── Coming soon chip ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Chip(
              label: const Text(CounsellingStrings.comingSoon),
              backgroundColor:
                  AppColors.statusSuccess.withValues(alpha: 0.12),
              side: BorderSide.none,
            ),
          ),

          // ── Placeholder message bubbles ─────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xxxl,
                vertical: AppSpacing.md,
              ),
              children: const [
                _OutgoingBubble(
                  text: CounsellingStrings.messagePlaceholder1,
                ),
                SizedBox(height: AppSpacing.md),
                _OutgoingBubble(
                  text: CounsellingStrings.messagePlaceholder2,
                ),
                SizedBox(height: AppSpacing.md),
                _OutgoingBubble(
                  text: CounsellingStrings.messagePlaceholder3,
                ),
              ],
            ),
          ),

          // ── Disabled message input bar ──────────────────────────────────
          SafeArea(
            child: Container(
              color: AppColors.cardSurface,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      enabled: false,
                      decoration: InputDecoration(
                        hintText: CounsellingStrings.typeMessage,
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppRadius.full),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: AppColors.canvas,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xxxl,
                          vertical: AppSpacing.md,
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  IconButton(
                    onPressed: null,
                    icon: const Icon(
                      Icons.send,
                      color: _waAccentColor,
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
        decoration: BoxDecoration(
          color: _waBubbleColor,
          borderRadius: const BorderRadius.only(
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
