import 'package:flutter/material.dart';

import '../core/models/programme.dart';

/// High-contrast UI Foundation color palette (Tailwind Slate).
abstract final class AppColors {
  AppColors._();

  // ─────────────────────────────────────────────────────────────────────────────
  // LIGHT MODE
  // ─────────────────────────────────────────────────────────────────────────────

  // Backgrounds
  static const Color background = Color(0xFFFFFFFF); // White
  static const Color surface = Color(0xFFF8FAFC); // Off-White / slate-50

  // Text
  static const Color textPrimary = Color(0xFF0F172A); // Dark Slate / slate-900
  static const Color textSecondary = Color(0xFF64748B); // Cool Gray / slate-500

  // Borders / Dividers
  static const Color border = Color(0xFFE2E8F0); // Light Gray / slate-200

  // Surface container variants (Material 3)
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF); // white
  static const Color surfaceContainerLow = Color(0xFFF8FAFC); // slate-50
  static const Color surfaceContainer = Color(0xFFF1F5F9); // slate-100
  static const Color surfaceContainerHigh = Color(0xFFE2E8F0); // slate-200
  static const Color surfaceContainerHighest = Color(0xFFCBD5E1); // slate-300

  // Brand accent — Apon teal (primary actions)
  static const Color primary = Color(0xFF0E8E80); // Apon teal
  static const Color primaryContainer = Color(0xFFD0F5F1); // Light teal
  static const Color onPrimary = Color(0xFFFFFFFF);

  // Semantic colors
  static const Color error = Color(0xFFDC2626); // red-600
  static const Color errorContainer = Color(0xFFFEE2E2); // red-100
  static const Color success = Color(0xFF16A34A); // green-600
  static const Color warning = Color(0xFFD97706); // amber-600

  // Programme accent: ANC (pink). IMCI/NCD/TB reuse error/warning/success
  // semantics so they stay consistent across the system.
  static const Color ancPink = Color(0xFFEC4899); // pink-500
  static const Color ancPinkContainer = Color(0xFFFCE7F3); // pink-100

  // ─────────────────────────────────────────────────────────────────────────────
  // DARK MODE
  // ─────────────────────────────────────────────────────────────────────────────

  // Backgrounds
  static const Color backgroundDark = Color(0xFF0F172A); // slate-900
  static const Color surfaceDark = Color(0xFF1E293B); // slate-800

  // Text
  static const Color textPrimaryDark = Color(0xFFF8FAFC); // slate-50
  static const Color textSecondaryDark = Color(0xFF94A3B8); // slate-400

  // Borders / Dividers
  static const Color borderDark = Color(0xFF334155); // slate-700

  // Surface container variants (Material 3, dark)
  static const Color surfaceContainerLowestDark = Color(0xFF0F172A); // slate-900
  static const Color surfaceContainerLowDark = Color(0xFF1E293B); // slate-800
  static const Color surfaceContainerDark = Color(0xFF334155); // slate-700
  static const Color surfaceContainerHighDark = Color(0xFF475569); // slate-600
  static const Color surfaceContainerHighestDark = Color(0xFF64748B); // slate-500

  // Brand accent — Apon teal (adjusted for dark)
  static const Color primaryDark = Color(0xFF5EC4B8); // Lighter teal for dark mode
  static const Color primaryContainerDark = Color(0xFF0A4F47); // Darker teal

  // Semantic colors (dark)
  static const Color errorDark = Color(0xFFF87171); // red-400
  static const Color errorContainerDark = Color(0xFF7F1D1D); // red-900
  static const Color successDark = Color(0xFF4ADE80); // green-400
  static const Color warningDark = Color(0xFFFBBF24); // amber-400

  // Programme accent (dark)
  static const Color ancPinkDark = Color(0xFFF472B6); // pink-400
  static const Color ancPinkContainerDark = Color(0xFF831843); // pink-900
}

/// Programme→color mapping. Single home — widgets call
/// `Theme.of(context).extension<ProgrammeColors>()!.of(programme)`.
@immutable
class ProgrammeColors extends ThemeExtension<ProgrammeColors> {
  const ProgrammeColors({
    required this.imci,
    required this.imciContainer,
    required this.anc,
    required this.ancContainer,
    required this.ncd,
    required this.ncdContainer,
    required this.tb,
    required this.tbContainer,
  });

  final Color imci;
  final Color imciContainer;
  final Color anc;
  final Color ancContainer;
  final Color ncd;
  final Color ncdContainer;
  final Color tb;
  final Color tbContainer;

  Color of(Programme p) {
    switch (p) {
      case Programme.imci:
        return imci;
      case Programme.anc:
        return anc;
      case Programme.ncd:
        return ncd;
      case Programme.tb:
        return tb;
    }
  }

  Color containerOf(Programme p) {
    switch (p) {
      case Programme.imci:
        return imciContainer;
      case Programme.anc:
        return ancContainer;
      case Programme.ncd:
        return ncdContainer;
      case Programme.tb:
        return tbContainer;
    }
  }

  static const ProgrammeColors light = ProgrammeColors(
    imci: AppColors.error,
    imciContainer: AppColors.errorContainer,
    anc: AppColors.ancPink,
    ancContainer: AppColors.ancPinkContainer,
    ncd: AppColors.warning,
    ncdContainer: Color(0xFFFEF3C7), // amber-100
    tb: AppColors.success,
    tbContainer: Color(0xFFDCFCE7), // green-100
  );

  static const ProgrammeColors dark = ProgrammeColors(
    imci: AppColors.errorDark,
    imciContainer: AppColors.errorContainerDark,
    anc: AppColors.ancPinkDark,
    ancContainer: AppColors.ancPinkContainerDark,
    ncd: AppColors.warningDark,
    ncdContainer: Color(0xFF78350F), // amber-900
    tb: AppColors.successDark,
    tbContainer: Color(0xFF166534), // green-800
  );

  @override
  ProgrammeColors copyWith({
    Color? imci,
    Color? imciContainer,
    Color? anc,
    Color? ancContainer,
    Color? ncd,
    Color? ncdContainer,
    Color? tb,
    Color? tbContainer,
  }) =>
      ProgrammeColors(
        imci: imci ?? this.imci,
        imciContainer: imciContainer ?? this.imciContainer,
        anc: anc ?? this.anc,
        ancContainer: ancContainer ?? this.ancContainer,
        ncd: ncd ?? this.ncd,
        ncdContainer: ncdContainer ?? this.ncdContainer,
        tb: tb ?? this.tb,
        tbContainer: tbContainer ?? this.tbContainer,
      );

  @override
  ProgrammeColors lerp(ThemeExtension<ProgrammeColors>? other, double t) {
    if (other is! ProgrammeColors) return this;
    return ProgrammeColors(
      imci: Color.lerp(imci, other.imci, t)!,
      imciContainer: Color.lerp(imciContainer, other.imciContainer, t)!,
      anc: Color.lerp(anc, other.anc, t)!,
      ancContainer: Color.lerp(ancContainer, other.ancContainer, t)!,
      ncd: Color.lerp(ncd, other.ncd, t)!,
      ncdContainer: Color.lerp(ncdContainer, other.ncdContainer, t)!,
      tb: Color.lerp(tb, other.tb, t)!,
      tbContainer: Color.lerp(tbContainer, other.tbContainer, t)!,
    );
  }
}

/// Urgency-based color roles for visit prioritization.
/// Use via `Theme.of(context).extension<UrgencyTheme>()!`.
@immutable
class UrgencyTheme extends ThemeExtension<UrgencyTheme> {
  const UrgencyTheme({
    required this.visitNow,
    required this.visitNowContainer,
    required this.today,
    required this.todayContainer,
    required this.thisWeek,
    required this.thisWeekContainer,
    required this.routine,
    required this.routineContainer,
    required this.urgent,
    required this.urgentContainer,
  });

  /// Immediate action required
  final Color visitNow;
  final Color visitNowContainer;

  /// Due today
  final Color today;
  final Color todayContainer;

  /// Due this week
  final Color thisWeek;
  final Color thisWeekContainer;

  /// Routine / scheduled
  final Color routine;
  final Color routineContainer;

  /// Urgent / critical
  final Color urgent;
  final Color urgentContainer;

  static const UrgencyTheme light = UrgencyTheme(
    visitNow: Color(0xFFDC2626), // red-600
    visitNowContainer: Color(0xFFFEE2E2), // red-100
    today: Color(0xFFD97706), // amber-600
    todayContainer: Color(0xFFFEF3C7), // amber-100
    thisWeek: Color(0xFF0E8E80), // Apon teal
    thisWeekContainer: Color(0xFFD0F5F1), // Light teal
    routine: Color(0xFF64748B), // slate-500
    routineContainer: Color(0xFFF1F5F9), // slate-100
    urgent: Color(0xFFDC2626), // red-600
    urgentContainer: Color(0xFFFEE2E2), // red-100
  );

  static const UrgencyTheme dark = UrgencyTheme(
    visitNow: Color(0xFFF87171), // red-400
    visitNowContainer: Color(0xFF7F1D1D), // red-900
    today: Color(0xFFFBBF24), // amber-400
    todayContainer: Color(0xFF78350F), // amber-900
    thisWeek: Color(0xFF5EC4B8), // Light teal
    thisWeekContainer: Color(0xFF0A4F47), // Dark teal
    routine: Color(0xFF94A3B8), // slate-400
    routineContainer: Color(0xFF334155), // slate-700
    urgent: Color(0xFFF87171), // red-400
    urgentContainer: Color(0xFF7F1D1D), // red-900
  );

  @override
  UrgencyTheme copyWith({
    Color? visitNow,
    Color? visitNowContainer,
    Color? today,
    Color? todayContainer,
    Color? thisWeek,
    Color? thisWeekContainer,
    Color? routine,
    Color? routineContainer,
    Color? urgent,
    Color? urgentContainer,
  }) =>
      UrgencyTheme(
        visitNow: visitNow ?? this.visitNow,
        visitNowContainer: visitNowContainer ?? this.visitNowContainer,
        today: today ?? this.today,
        todayContainer: todayContainer ?? this.todayContainer,
        thisWeek: thisWeek ?? this.thisWeek,
        thisWeekContainer: thisWeekContainer ?? this.thisWeekContainer,
        routine: routine ?? this.routine,
        routineContainer: routineContainer ?? this.routineContainer,
        urgent: urgent ?? this.urgent,
        urgentContainer: urgentContainer ?? this.urgentContainer,
      );

  @override
  UrgencyTheme lerp(ThemeExtension<UrgencyTheme>? other, double t) {
    if (other is! UrgencyTheme) return this;
    return UrgencyTheme(
      visitNow: Color.lerp(visitNow, other.visitNow, t)!,
      visitNowContainer: Color.lerp(visitNowContainer, other.visitNowContainer, t)!,
      today: Color.lerp(today, other.today, t)!,
      todayContainer: Color.lerp(todayContainer, other.todayContainer, t)!,
      thisWeek: Color.lerp(thisWeek, other.thisWeek, t)!,
      thisWeekContainer: Color.lerp(thisWeekContainer, other.thisWeekContainer, t)!,
      routine: Color.lerp(routine, other.routine, t)!,
      routineContainer: Color.lerp(routineContainer, other.routineContainer, t)!,
      urgent: Color.lerp(urgent, other.urgent, t)!,
      urgentContainer: Color.lerp(urgentContainer, other.urgentContainer, t)!,
    );
  }
}

ThemeData buildAppTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.primary,
    onPrimary: AppColors.onPrimary,
    primaryContainer: AppColors.primaryContainer,
    onPrimaryContainer: AppColors.textPrimary,
    secondary: AppColors.textSecondary,
    onSecondary: AppColors.onPrimary,
    secondaryContainer: AppColors.surface,
    onSecondaryContainer: AppColors.textPrimary,
    tertiary: AppColors.success,
    onTertiary: AppColors.onPrimary,
    tertiaryContainer: Color(0xFFDCFCE7), // green-100
    onTertiaryContainer: AppColors.textPrimary,
    error: AppColors.error,
    onError: AppColors.onPrimary,
    errorContainer: AppColors.errorContainer,
    onErrorContainer: AppColors.textPrimary,
    surface: AppColors.background,
    onSurface: AppColors.textPrimary,
    onSurfaceVariant: AppColors.textSecondary,
    outline: AppColors.border,
    outlineVariant: AppColors.border,
    shadow: Color(0x1A000000),
    scrim: Color(0x80000000),
    inverseSurface: AppColors.textPrimary,
    onInverseSurface: AppColors.background,
    inversePrimary: AppColors.primaryContainer,
    surfaceTint: AppColors.primary,
    // Surface container variants for proper text contrast
    surfaceContainerLowest: AppColors.surfaceContainerLowest,
    surfaceContainerLow: AppColors.surfaceContainerLow,
    surfaceContainer: AppColors.surfaceContainer,
    surfaceContainerHigh: AppColors.surfaceContainerHigh,
    surfaceContainerHighest: AppColors.surfaceContainerHighest,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    extensions: const <ThemeExtension<dynamic>>[
      ProgrammeColors.light,
      UrgencyTheme.light,
    ],
    scaffoldBackgroundColor: AppColors.surface,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: AppColors.background,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.primaryContainer,
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.background,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.background,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.textPrimary,
      contentTextStyle: const TextStyle(color: AppColors.background),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// Builds the dark theme for the app.
ThemeData buildDarkTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.primaryDark,
    onPrimary: AppColors.backgroundDark,
    primaryContainer: AppColors.primaryContainerDark,
    onPrimaryContainer: AppColors.textPrimaryDark,
    secondary: AppColors.textSecondaryDark,
    onSecondary: AppColors.backgroundDark,
    secondaryContainer: AppColors.surfaceDark,
    onSecondaryContainer: AppColors.textPrimaryDark,
    tertiary: AppColors.successDark,
    onTertiary: AppColors.backgroundDark,
    tertiaryContainer: Color(0xFF166534), // green-800
    onTertiaryContainer: AppColors.textPrimaryDark,
    error: AppColors.errorDark,
    onError: AppColors.backgroundDark,
    errorContainer: AppColors.errorContainerDark,
    onErrorContainer: AppColors.textPrimaryDark,
    surface: AppColors.backgroundDark,
    onSurface: AppColors.textPrimaryDark,
    onSurfaceVariant: AppColors.textSecondaryDark,
    outline: AppColors.borderDark,
    outlineVariant: AppColors.borderDark,
    shadow: Color(0x40000000),
    scrim: Color(0xCC000000),
    inverseSurface: AppColors.textPrimaryDark,
    onInverseSurface: AppColors.backgroundDark,
    inversePrimary: AppColors.primary,
    surfaceTint: AppColors.primaryDark,
    // Surface container variants for proper text contrast
    surfaceContainerLowest: AppColors.surfaceContainerLowestDark,
    surfaceContainerLow: AppColors.surfaceContainerLowDark,
    surfaceContainer: AppColors.surfaceContainerDark,
    surfaceContainerHigh: AppColors.surfaceContainerHighDark,
    surfaceContainerHighest: AppColors.surfaceContainerHighestDark,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    extensions: const <ThemeExtension<dynamic>>[
      ProgrammeColors.dark,
      UrgencyTheme.dark,
    ],
    scaffoldBackgroundColor: AppColors.surfaceDark,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.backgroundDark,
      foregroundColor: AppColors.textPrimaryDark,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: AppColors.surfaceDark,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.borderDark),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.borderDark,
      thickness: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceDark,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.borderDark),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.borderDark),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primaryDark, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surfaceDark,
      selectedColor: AppColors.primaryContainerDark,
      side: const BorderSide(color: AppColors.borderDark),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surfaceDark,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.borderDark),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surfaceDark,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.textPrimaryDark,
      contentTextStyle: const TextStyle(color: AppColors.backgroundDark),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      behavior: SnackBarBehavior.floating,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surfaceDark,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.textSecondaryDark,
    ),
  );
}
