import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_strings.dart';
import '../../core/theme/app_theme.dart';

/// Informed consent screen shown before household registration.
///
/// Returns `true` via [GoRouter.pop] when the SK confirms consent,
/// `false` (or null via back gesture) when declined.
///
/// Usage:
/// ```dart
/// final consented = await context.push<bool>('/household/enrollment/consent');
/// if (consented == true) { /* proceed */ }
/// ```
class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _agreed = false;

  void _onConfirm() {
    debugPrint('[_ConsentScreenState] _onConfirm');
    context.pop(true);
  }

  Future<void> _onDecline() async {
    debugPrint('[_ConsentScreenState] _onDecline');
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(ConsentStrings.declineButton),
        content: const Text(ConsentStrings.declineWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(ConsentStrings.declineCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.statusCritical),
            child: const Text(ConsentStrings.declineConfirm),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      context.pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        title: const Text(
          ConsentStrings.title,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ProgrammeHeader(),
                    const SizedBox(height: 20),
                    Text(
                      ConsentStrings.introText,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const _ConsentSection(
                      title: ConsentStrings.section1Title,
                      body: ConsentStrings.section1Body,
                    ),
                    const _ConsentSection(
                      title: ConsentStrings.section2Title,
                      body: ConsentStrings.section2Body,
                    ),
                    const _ConsentSection(
                      title: ConsentStrings.section3Title,
                      body: ConsentStrings.section3Body,
                    ),
                    const SizedBox(height: 28),
                    _AgreementCheckbox(
                      value: _agreed,
                      onChanged: (v) => setState(() => _agreed = v ?? false),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            _ActionBar(
              agreed: _agreed,
              onConfirm: _onConfirm,
              onDecline: _onDecline,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgrammeHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardSurfaceMuted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.health_and_safety_outlined, color: AppColors.navy, size: 22),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              ConsentStrings.subtitle,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.navy,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsentSection extends StatelessWidget {
  const _ConsentSection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              fontSize: 13,
              height: 1.65,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
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
                ConsentStrings.checkboxLabel,
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
    required this.onConfirm,
    required this.onDecline,
  });

  final bool agreed;
  final VoidCallback onConfirm;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
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
                side: BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text(ConsentStrings.declineButton),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: agreed ? onConfirm : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.navy,
                disabledBackgroundColor: AppColors.border,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text(ConsentStrings.confirmButton),
            ),
          ),
        ],
      ),
    );
  }
}
