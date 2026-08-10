import 'package:flutter/material.dart';

import '../constants/app_strings.dart';
import 'battery_optimization_gate.dart';

/// Shows the one-time battery-optimisation prompt, at most once ever.
///
/// A prompt, never a gate: an SK who declines keeps a fully working app. The
/// "asked" flag is written whichever button is pressed, so declining is
/// respected permanently rather than re-asked on the next launch.
Future<void> maybeShowBatteryOptimizationPrompt(
  BuildContext context,
  BatteryOptimizationGate gate,
) async {
  if (!await gate.shouldPrompt()) return;
  if (!context.mounted) return;

  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(BatteryOptimizationStrings.title),
      content: Text(BatteryOptimizationStrings.body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(BatteryOptimizationStrings.notNow),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(BatteryOptimizationStrings.openSettings),
        ),
      ],
    ),
  );

  // Written for both answers — see the note above about not re-asking.
  await gate.markAsked();

  if (accepted != true) return;

  final opened = await gate.openBestSettingsScreen();
  if (opened || !context.mounted) return;

  // Some vendor ROMs have neither screen. Say so rather than leaving the SK
  // looking at a button that appeared to do nothing.
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(BatteryOptimizationStrings.couldNotOpen)),
  );
}
