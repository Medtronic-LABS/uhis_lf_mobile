import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_state.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_theme.dart';

/// Shared settings actions — called identically from the dashboard's
/// popup Settings menu and the [SettingsScreen] page, so both surfaces stay
/// in sync with a single source of truth rather than two copies of the
/// same confirm-dialog/business logic.

/// Offers to enable device unlock (biometric) if not already enabled.
Future<void> offerDeviceUnlock(BuildContext context) async {
  final auth = context.read<AuthState>();
  if (auth.biometricEnabled) return;
  if (!context.mounted) return;
  final supported = auth.biometricAvailable;
  final ans = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(DashboardStrings.useDeviceUnlockTitle),
      content: Text(
        supported
            ? DashboardStrings.biometricOfferSupported
            : DashboardStrings.biometricOfferUnsupported,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(DashboardStrings.notNow),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(DashboardStrings.enable),
        ),
      ],
    ),
  );
  if (ans != true || !context.mounted) return;
  if (!supported) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(DashboardStrings.setUpScreenLock)));
    return;
  }
  try {
    await auth.enrolBiometric();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(DashboardStrings.deviceUnlockEnabled)),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(DashboardStrings.couldNotEnable(e))));
  }
}

/// Confirms and disables device unlock (biometric) if currently enabled.
Future<void> disableDeviceUnlock(BuildContext context, AuthState auth) async {
  final confirmBio = await showDialog<bool>(
    context: context,
    builder: (dlgCtx) => AlertDialog(
      title: Text(DashboardStrings.confirmDisableDeviceUnlock),
      content: Text(DashboardStrings.confirmDisableDeviceUnlockBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dlgCtx).pop(false),
          child: Text(DashboardStrings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dlgCtx).pop(true),
          child: Text(DashboardStrings.disable),
        ),
      ],
    ),
  );
  if (confirmBio != true) return;
  await auth.disableBiometric();
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(DashboardStrings.deviceUnlockDisabled)),
    );
  }
}

/// Confirms and removes the PIN if currently enabled.
Future<void> removePin(BuildContext context, AuthState auth) async {
  final confirmPin = await showDialog<bool>(
    context: context,
    builder: (dlgCtx) => AlertDialog(
      title: Text(PinStrings.confirmRemovePin),
      content: Text(PinStrings.confirmRemovePinBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dlgCtx).pop(false),
          child: Text(DashboardStrings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dlgCtx).pop(true),
          child: Text(CommonStrings.remove),
        ),
      ],
    ),
  );
  if (confirmPin != true) return;
  await auth.disablePin();
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(PinStrings.disabledSnack)));
  }
}

/// "Pick one of N" dialog shared by the Appearance and Language rows — a
/// list of options with a check mark next to whichever is current.
Future<T?> showOptionPicker<T>({
  required BuildContext context,
  required String title,
  required T current,
  required List<(T value, String label)> options,
}) {
  return showDialog<T>(
    context: context,
    builder: (dlgCtx) => SimpleDialog(
      title: Text(title),
      children: [
        for (final (value, label) in options)
          SimpleDialogOption(
            onPressed: () => Navigator.of(dlgCtx).pop(value),
            child: Row(
              children: [
                Expanded(child: Text(label)),
                if (value == current)
                  const Icon(
                    Icons.check,
                    size: 18,
                    color: AppColors.aiPurpleDark,
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}
