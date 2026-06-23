import 'package:flutter/material.dart';

import '../../core/constants/app_strings.dart';

/// Presentation-only PIN entry: title/subtitle + progress dots + numeric
/// keypad. Carries NO business logic — the parent owns the entered [value] and
/// reacts in [onChanged]. Reused by PIN setup (create + confirm) and PIN
/// unlock so the "collect N digits" UI lives in exactly one place.
class PinEntryView extends StatelessWidget {
  const PinEntryView({
    super.key,
    required this.length,
    required this.value,
    required this.onChanged,
    required this.title,
    this.subtitle,
    this.errorText,
    this.busy = false,
  });

  final int length;
  final String value;
  final ValueChanged<String> onChanged;
  final String title;
  final String? subtitle;
  final String? errorText;
  final bool busy;

  void _digit(String d) {
    if (busy || value.length >= length) return;
    onChanged(value + d);
  }

  void _delete() {
    if (busy || value.isEmpty) return;
    onChanged(value.substring(0, value.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 28),
          _Dots(length: length, filled: value.length, error: errorText != null),
          const SizedBox(height: 12),
          SizedBox(
            height: 20,
            child: errorText == null
                ? null
                : Text(
                    errorText!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
          ),
          const SizedBox(height: 16),
          _Keypad(onDigit: _digit, onDelete: _delete, enabled: !busy),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.length, required this.filled, required this.error});

  final int length;
  final int filled;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(length, (i) {
        final on = i < filled;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on
                ? (error ? scheme.error : scheme.primary)
                : Colors.transparent,
            border: Border.all(
              color: error ? scheme.error : scheme.outline,
              width: 1.5,
            ),
          ),
        );
      }),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.onDigit,
    required this.onDelete,
    required this.enabled,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    Widget key(String d) =>
        _KeyButton(label: d, onTap: enabled ? () => onDigit(d) : null);
    Widget row(List<Widget> kids) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: kids,
        );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row([key('1'), key('2'), key('3')]),
          const SizedBox(height: 12),
          row([key('4'), key('5'), key('6')]),
          const SizedBox(height: 12),
          row([key('7'), key('8'), key('9')]),
          const SizedBox(height: 12),
          row([
            const SizedBox(width: 64),
            key('0'),
            _DeleteButton(onTap: enabled ? onDelete : null),
          ]),
        ],
      ),
    );
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
        ),
        child: Text(label, style: Theme.of(context).textTheme.headlineSmall),
      ),
    );
  }
}

class _DeleteButton extends StatelessWidget {
  const _DeleteButton({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: IconButton(
        onPressed: onTap,
        tooltip: PinStrings.deleteKey,
        icon: const Icon(Icons.backspace_outlined),
      ),
    );
  }
}
