import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/models/programme.dart';

/// Leapfrog brand palette. Single home for every raw color literal — widgets
/// must reach for [LeapfrogColors], [ProgrammeColors], or [UrgencyTheme]
/// via `Theme.of(context).extension<…>()`, never `AppColors.*` directly.
abstract final class AppColors {
  AppColors._();

  // ─── Brand ───
  static const Color navy = Color(0xFF1B2B5E);
  static const Color navyDark = Color(0xFF142050);
  static const Color navyDeepDark = Color(0xFF0E173F);
  static const Color navyOnDark = Color(0xFF3D4B85);

  static const Color pink = Color(0xFFE8356D);
  static const Color pinkDark = Color(0xFFC42B5A);
  static const Color pinkLight = Color(0xFFFF5A87);

  static const Color aiPurple = Color(0xFF6B63D4);
  static const Color aiPurpleDark = Color(0xFF3D3599);
  static const Color aiPurpleLight = Color(0xFF9890E8);
  static const Color aiSurfaceStart = Color(0xFFEEF0FF);
  static const Color aiSurfaceEnd = Color(0xFFE8EAFF);
  static const Color aiSurfaceStartDark = Color(0xFF1F1B3D);
  static const Color aiSurfaceEndDark = Color(0xFF2A2558);
  static const Color aiBorder = Color(0xFFD4D8FF);
  static const Color aiBorderDark = Color(0xFF3D3599);

  // ─── Canvas / neutrals (light) ───
  static const Color canvas = Color(0xFFF0F2F8);
  static const Color cardSurface = Color(0xFFFFFFFF);
  static const Color cardSurfaceMuted = Color(0xFFF8F9FC);
  static const Color textPrimary = Color(0xFF1A1A2E);
  static const Color textMuted = Color(0xFF6B7280);
  static const Color textOnNavy = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE5E7EB);
  static const Color borderSoft = Color(0x14000000); // rgba(0,0,0,0.08)

  // ─── Canvas / neutrals (dark) ───
  static const Color canvasDark = Color(0xFF0F172A);
  static const Color cardSurfaceDark = Color(0xFF1E293B);
  static const Color cardSurfaceMutedDark = Color(0xFF1A2333);
  static const Color textPrimaryDark = Color(0xFFF8FAFC);
  static const Color textMutedDark = Color(0xFF94A3B8);
  static const Color borderDark = Color(0xFF334155);
  static const Color borderSoftDark = Color(0x14FFFFFF);

  // ─── Status (light) ───
  static const Color statusSuccess = Color(0xFF10B981);
  static const Color statusSuccessSurface = Color(0xFFD1FAE5);
  static const Color statusWarning = Color(0xFFF59E0B);
  static const Color statusWarningSurface = Color(0xFFFEF3C7);
  static const Color statusCritical = Color(0xFFEF4444);
  static const Color statusCriticalSurface = Color(0xFFFEE2E2);
  static const Color statusInfo = Color(0xFF0EA5E9);
  static const Color statusInfoSurface = Color(0xFFE0F2FE);

  // ─── Status (dark) ───
  static const Color statusSuccessDark = Color(0xFF34D399);
  static const Color statusSuccessSurfaceDark = Color(0xFF064E3B);
  static const Color statusWarningDark = Color(0xFFFBBF24);
  static const Color statusWarningSurfaceDark = Color(0xFF92400E);
  static const Color statusCriticalDark = Color(0xFFF87171);
  static const Color statusCriticalSurfaceDark = Color(0xFF7F1D1D);
  static const Color statusInfoDark = Color(0xFF38BDF8);
  static const Color statusInfoSurfaceDark = Color(0xFF0C4A6E);

  // ─── Programme tokens (light) ───
  // ANC pink family
  static const Color ancText = Color(0xFF9D174D);
  static const Color ancBorder = Color(0xFFF9A8D4);
  static const Color ancSurface = Color(0xFFFDF2F8);
  // IMCI red family
  static const Color imciText = Color(0xFF991B1B);
  static const Color imciBorder = Color(0xFFFCA5A5);
  static const Color imciSurface = Color(0xFFFEF2F2);
  // NCD amber family
  static const Color ncdText = Color(0xFF92400E);
  static const Color ncdBorder = Color(0xFFFCD34D);
  static const Color ncdSurface = Color(0xFFFFF7ED);
  // TB green family
  static const Color tbText = Color(0xFF065F46);
  static const Color tbBorder = Color(0xFF6EE7B7);
  static const Color tbSurface = Color(0xFFF0FDF4);
  // Postpartum / PNC purple family
  static const Color pncText = Color(0xFF4C1D95);
  static const Color pncBorder = Color(0xFFC4B5FD);
  static const Color pncSurface = Color(0xFFF5F3FF);

  // ─── Programme tokens (dark) ───
  static const Color ancTextDark = Color(0xFFF9A8D4);
  static const Color ancSurfaceDark = Color(0xFF500724);
  static const Color imciTextDark = Color(0xFFFCA5A5);
  static const Color imciSurfaceDark = Color(0xFF450A0A);
  static const Color ncdTextDark = Color(0xFFFCD34D);
  static const Color ncdSurfaceDark = Color(0xFF451A03);
  static const Color tbTextDark = Color(0xFF6EE7B7);
  static const Color tbSurfaceDark = Color(0xFF052E16);
  static const Color pncTextDark = Color(0xFFC4B5FD);
  static const Color pncSurfaceDark = Color(0xFF2E1065);

  // ─── External integrations ───
  static const Color whatsapp = Color(0xFF25D366);
  static const Color sukheeStart = Color(0xFF00BFA5);
  static const Color sukheeEnd = Color(0xFF0288D1);
}

/// Semantic Leapfrog tokens — the only color surface widgets should consume.
///
/// Use via `Theme.of(context).extension<LeapfrogColors>()!`. Mirrors the HTML
/// reference (`Leapfrog .html`) palette: navy + pink core, AI purple, soft
/// lavender canvas, status quadrant, external-integration brand colors.
@immutable
class LeapfrogColors extends ThemeExtension<LeapfrogColors> {
  const LeapfrogColors({
    required this.brandNavy,
    required this.brandNavyDark,
    required this.brandPink,
    required this.brandPinkDark,
    required this.aiPurple,
    required this.aiPurpleDark,
    required this.aiSurfaceStart,
    required this.aiSurfaceEnd,
    required this.aiBorder,
    required this.canvas,
    required this.cardSurface,
    required this.cardSurfaceMuted,
    required this.textPrimary,
    required this.textMuted,
    required this.divider,
    required this.statusSuccess,
    required this.statusSuccessSurface,
    required this.statusWarning,
    required this.statusWarningSurface,
    required this.statusCritical,
    required this.statusCriticalSurface,
    required this.statusInfo,
    required this.statusInfoSurface,
    required this.whatsapp,
    required this.sukheeGradientStart,
    required this.sukheeGradientEnd,
  });

  final Color brandNavy;
  final Color brandNavyDark;
  final Color brandPink;
  final Color brandPinkDark;
  final Color aiPurple;
  final Color aiPurpleDark;
  final Color aiSurfaceStart;
  final Color aiSurfaceEnd;
  final Color aiBorder;
  final Color canvas;
  final Color cardSurface;
  final Color cardSurfaceMuted;
  final Color textPrimary;
  final Color textMuted;
  final Color divider;
  final Color statusSuccess;
  final Color statusSuccessSurface;
  final Color statusWarning;
  final Color statusWarningSurface;
  final Color statusCritical;
  final Color statusCriticalSurface;
  final Color statusInfo;
  final Color statusInfoSurface;
  final Color whatsapp;
  final Color sukheeGradientStart;
  final Color sukheeGradientEnd;

  /// Border-radius scale. Constants because rounded-rectangle shape is shared
  /// across the system and we don't want each call site reinventing it.
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 24;

  /// Subtle card shadow matching the HTML reference.
  static const List<BoxShadow> cardShadow = <BoxShadow>[
    BoxShadow(
      color: Color(0x0F000000),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  static const LeapfrogColors light = LeapfrogColors(
    brandNavy: AppColors.navy,
    brandNavyDark: AppColors.navyDark,
    brandPink: AppColors.pink,
    brandPinkDark: AppColors.pinkDark,
    aiPurple: AppColors.aiPurple,
    aiPurpleDark: AppColors.aiPurpleDark,
    aiSurfaceStart: AppColors.aiSurfaceStart,
    aiSurfaceEnd: AppColors.aiSurfaceEnd,
    aiBorder: AppColors.aiBorder,
    canvas: AppColors.canvas,
    cardSurface: AppColors.cardSurface,
    cardSurfaceMuted: AppColors.cardSurfaceMuted,
    textPrimary: AppColors.textPrimary,
    textMuted: AppColors.textMuted,
    divider: AppColors.borderSoft,
    statusSuccess: AppColors.statusSuccess,
    statusSuccessSurface: AppColors.statusSuccessSurface,
    statusWarning: AppColors.statusWarning,
    statusWarningSurface: AppColors.statusWarningSurface,
    statusCritical: AppColors.statusCritical,
    statusCriticalSurface: AppColors.statusCriticalSurface,
    statusInfo: AppColors.statusInfo,
    statusInfoSurface: AppColors.statusInfoSurface,
    whatsapp: AppColors.whatsapp,
    sukheeGradientStart: AppColors.sukheeStart,
    sukheeGradientEnd: AppColors.sukheeEnd,
  );

  static const LeapfrogColors dark = LeapfrogColors(
    brandNavy: AppColors.navy,
    brandNavyDark: AppColors.navyDeepDark,
    brandPink: AppColors.pinkLight,
    brandPinkDark: AppColors.pink,
    aiPurple: AppColors.aiPurpleLight,
    aiPurpleDark: AppColors.aiPurple,
    aiSurfaceStart: AppColors.aiSurfaceStartDark,
    aiSurfaceEnd: AppColors.aiSurfaceEndDark,
    aiBorder: AppColors.aiBorderDark,
    canvas: AppColors.canvasDark,
    cardSurface: AppColors.cardSurfaceDark,
    cardSurfaceMuted: AppColors.cardSurfaceMutedDark,
    textPrimary: AppColors.textPrimaryDark,
    textMuted: AppColors.textMutedDark,
    divider: AppColors.borderSoftDark,
    statusSuccess: AppColors.statusSuccessDark,
    statusSuccessSurface: AppColors.statusSuccessSurfaceDark,
    statusWarning: AppColors.statusWarningDark,
    statusWarningSurface: AppColors.statusWarningSurfaceDark,
    statusCritical: AppColors.statusCriticalDark,
    statusCriticalSurface: AppColors.statusCriticalSurfaceDark,
    statusInfo: AppColors.statusInfoDark,
    statusInfoSurface: AppColors.statusInfoSurfaceDark,
    whatsapp: AppColors.whatsapp,
    sukheeGradientStart: AppColors.sukheeStart,
    sukheeGradientEnd: AppColors.sukheeEnd,
  );

  @override
  LeapfrogColors copyWith({
    Color? brandNavy,
    Color? brandNavyDark,
    Color? brandPink,
    Color? brandPinkDark,
    Color? aiPurple,
    Color? aiPurpleDark,
    Color? aiSurfaceStart,
    Color? aiSurfaceEnd,
    Color? aiBorder,
    Color? canvas,
    Color? cardSurface,
    Color? cardSurfaceMuted,
    Color? textPrimary,
    Color? textMuted,
    Color? divider,
    Color? statusSuccess,
    Color? statusSuccessSurface,
    Color? statusWarning,
    Color? statusWarningSurface,
    Color? statusCritical,
    Color? statusCriticalSurface,
    Color? statusInfo,
    Color? statusInfoSurface,
    Color? whatsapp,
    Color? sukheeGradientStart,
    Color? sukheeGradientEnd,
  }) =>
      LeapfrogColors(
        brandNavy: brandNavy ?? this.brandNavy,
        brandNavyDark: brandNavyDark ?? this.brandNavyDark,
        brandPink: brandPink ?? this.brandPink,
        brandPinkDark: brandPinkDark ?? this.brandPinkDark,
        aiPurple: aiPurple ?? this.aiPurple,
        aiPurpleDark: aiPurpleDark ?? this.aiPurpleDark,
        aiSurfaceStart: aiSurfaceStart ?? this.aiSurfaceStart,
        aiSurfaceEnd: aiSurfaceEnd ?? this.aiSurfaceEnd,
        aiBorder: aiBorder ?? this.aiBorder,
        canvas: canvas ?? this.canvas,
        cardSurface: cardSurface ?? this.cardSurface,
        cardSurfaceMuted: cardSurfaceMuted ?? this.cardSurfaceMuted,
        textPrimary: textPrimary ?? this.textPrimary,
        textMuted: textMuted ?? this.textMuted,
        divider: divider ?? this.divider,
        statusSuccess: statusSuccess ?? this.statusSuccess,
        statusSuccessSurface: statusSuccessSurface ?? this.statusSuccessSurface,
        statusWarning: statusWarning ?? this.statusWarning,
        statusWarningSurface: statusWarningSurface ?? this.statusWarningSurface,
        statusCritical: statusCritical ?? this.statusCritical,
        statusCriticalSurface:
            statusCriticalSurface ?? this.statusCriticalSurface,
        statusInfo: statusInfo ?? this.statusInfo,
        statusInfoSurface: statusInfoSurface ?? this.statusInfoSurface,
        whatsapp: whatsapp ?? this.whatsapp,
        sukheeGradientStart: sukheeGradientStart ?? this.sukheeGradientStart,
        sukheeGradientEnd: sukheeGradientEnd ?? this.sukheeGradientEnd,
      );

  @override
  LeapfrogColors lerp(ThemeExtension<LeapfrogColors>? other, double t) {
    if (other is! LeapfrogColors) return this;
    return LeapfrogColors(
      brandNavy: Color.lerp(brandNavy, other.brandNavy, t)!,
      brandNavyDark: Color.lerp(brandNavyDark, other.brandNavyDark, t)!,
      brandPink: Color.lerp(brandPink, other.brandPink, t)!,
      brandPinkDark: Color.lerp(brandPinkDark, other.brandPinkDark, t)!,
      aiPurple: Color.lerp(aiPurple, other.aiPurple, t)!,
      aiPurpleDark: Color.lerp(aiPurpleDark, other.aiPurpleDark, t)!,
      aiSurfaceStart: Color.lerp(aiSurfaceStart, other.aiSurfaceStart, t)!,
      aiSurfaceEnd: Color.lerp(aiSurfaceEnd, other.aiSurfaceEnd, t)!,
      aiBorder: Color.lerp(aiBorder, other.aiBorder, t)!,
      canvas: Color.lerp(canvas, other.canvas, t)!,
      cardSurface: Color.lerp(cardSurface, other.cardSurface, t)!,
      cardSurfaceMuted:
          Color.lerp(cardSurfaceMuted, other.cardSurfaceMuted, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      statusSuccess: Color.lerp(statusSuccess, other.statusSuccess, t)!,
      statusSuccessSurface:
          Color.lerp(statusSuccessSurface, other.statusSuccessSurface, t)!,
      statusWarning: Color.lerp(statusWarning, other.statusWarning, t)!,
      statusWarningSurface:
          Color.lerp(statusWarningSurface, other.statusWarningSurface, t)!,
      statusCritical: Color.lerp(statusCritical, other.statusCritical, t)!,
      statusCriticalSurface:
          Color.lerp(statusCriticalSurface, other.statusCriticalSurface, t)!,
      statusInfo: Color.lerp(statusInfo, other.statusInfo, t)!,
      statusInfoSurface:
          Color.lerp(statusInfoSurface, other.statusInfoSurface, t)!,
      whatsapp: Color.lerp(whatsapp, other.whatsapp, t)!,
      sukheeGradientStart:
          Color.lerp(sukheeGradientStart, other.sukheeGradientStart, t)!,
      sukheeGradientEnd:
          Color.lerp(sukheeGradientEnd, other.sukheeGradientEnd, t)!,
    );
  }
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
    required this.pnc,
    required this.pncContainer,
  });

  final Color imci;
  final Color imciContainer;
  final Color anc;
  final Color ancContainer;
  final Color ncd;
  final Color ncdContainer;
  final Color tb;
  final Color tbContainer;
  final Color pnc;
  final Color pncContainer;

  Color of(Programme p) {
    switch (p) {
      case Programme.imci:
        return imci;
      case Programme.anc:
        return anc;
      case Programme.pnc:
        return pnc;
      case Programme.ncd:
        return ncd;
      case Programme.tb:
        return tb;
      case Programme.unknown:
        return ncd;
    }
  }

  Color containerOf(Programme p) {
    switch (p) {
      case Programme.imci:
        return imciContainer;
      case Programme.anc:
        return ancContainer;
      case Programme.pnc:
        return pncContainer;
      case Programme.ncd:
        return ncdContainer;
      case Programme.tb:
        return tbContainer;
      case Programme.unknown:
        return ncdContainer;
    }
  }

  static const ProgrammeColors light = ProgrammeColors(
    imci: AppColors.imciText,
    imciContainer: AppColors.imciSurface,
    anc: AppColors.ancText,
    ancContainer: AppColors.ancSurface,
    ncd: AppColors.ncdText,
    ncdContainer: AppColors.ncdSurface,
    tb: AppColors.tbText,
    tbContainer: AppColors.tbSurface,
    pnc: AppColors.pncText,
    pncContainer: AppColors.pncSurface,
  );

  static const ProgrammeColors dark = ProgrammeColors(
    imci: AppColors.imciTextDark,
    imciContainer: AppColors.imciSurfaceDark,
    anc: AppColors.ancTextDark,
    ancContainer: AppColors.ancSurfaceDark,
    ncd: AppColors.ncdTextDark,
    ncdContainer: AppColors.ncdSurfaceDark,
    tb: AppColors.tbTextDark,
    tbContainer: AppColors.tbSurfaceDark,
    pnc: AppColors.pncTextDark,
    pncContainer: AppColors.pncSurfaceDark,
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
    Color? pnc,
    Color? pncContainer,
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
        pnc: pnc ?? this.pnc,
        pncContainer: pncContainer ?? this.pncContainer,
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
      pnc: Color.lerp(pnc, other.pnc, t)!,
      pncContainer: Color.lerp(pncContainer, other.pncContainer, t)!,
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

  final Color visitNow;
  final Color visitNowContainer;
  final Color today;
  final Color todayContainer;
  final Color thisWeek;
  final Color thisWeekContainer;
  final Color routine;
  final Color routineContainer;
  final Color urgent;
  final Color urgentContainer;

  static const UrgencyTheme light = UrgencyTheme(
    visitNow: AppColors.statusCritical,
    visitNowContainer: AppColors.statusCriticalSurface,
    today: AppColors.statusWarning,
    todayContainer: AppColors.statusWarningSurface,
    thisWeek: AppColors.statusInfo,
    thisWeekContainer: AppColors.statusInfoSurface,
    routine: AppColors.textMuted,
    routineContainer: AppColors.cardSurfaceMuted,
    urgent: AppColors.statusCritical,
    urgentContainer: AppColors.statusCriticalSurface,
  );

  static const UrgencyTheme dark = UrgencyTheme(
    visitNow: AppColors.statusCriticalDark,
    visitNowContainer: AppColors.statusCriticalSurfaceDark,
    today: AppColors.statusWarningDark,
    todayContainer: AppColors.statusWarningSurfaceDark,
    thisWeek: AppColors.statusInfoDark,
    thisWeekContainer: AppColors.statusInfoSurfaceDark,
    routine: AppColors.textMutedDark,
    routineContainer: AppColors.cardSurfaceMutedDark,
    urgent: AppColors.statusCriticalDark,
    urgentContainer: AppColors.statusCriticalSurfaceDark,
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
      visitNowContainer:
          Color.lerp(visitNowContainer, other.visitNowContainer, t)!,
      today: Color.lerp(today, other.today, t)!,
      todayContainer: Color.lerp(todayContainer, other.todayContainer, t)!,
      thisWeek: Color.lerp(thisWeek, other.thisWeek, t)!,
      thisWeekContainer:
          Color.lerp(thisWeekContainer, other.thisWeekContainer, t)!,
      routine: Color.lerp(routine, other.routine, t)!,
      routineContainer: Color.lerp(routineContainer, other.routineContainer, t)!,
      urgent: Color.lerp(urgent, other.urgent, t)!,
      urgentContainer: Color.lerp(urgentContainer, other.urgentContainer, t)!,
    );
  }
}

/// Builds the Nunito + Nunito Sans text theme for the given brightness.
/// Headings use Nunito (700/800/900); body and labels use Nunito Sans
/// (400/600/700), matching the HTML reference type scale.
TextTheme _buildTextTheme(Brightness brightness) {
  final base = brightness == Brightness.light
      ? Typography.material2021().black
      : Typography.material2021().white;

  final heading = GoogleFonts.nunitoTextTheme(base);
  final body = GoogleFonts.nunitoSansTextTheme(base);

  return base.copyWith(
    displayLarge: heading.displayLarge?.copyWith(fontWeight: FontWeight.w800),
    displayMedium: heading.displayMedium?.copyWith(fontWeight: FontWeight.w800),
    displaySmall: heading.displaySmall?.copyWith(fontWeight: FontWeight.w800),
    headlineLarge: heading.headlineLarge?.copyWith(fontWeight: FontWeight.w800),
    headlineMedium:
        heading.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
    headlineSmall: heading.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
    titleLarge: heading.titleLarge?.copyWith(fontWeight: FontWeight.w800),
    titleMedium: heading.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    titleSmall: heading.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    bodyLarge: body.bodyLarge?.copyWith(fontWeight: FontWeight.w400),
    bodyMedium: body.bodyMedium?.copyWith(fontWeight: FontWeight.w400),
    bodySmall: body.bodySmall?.copyWith(fontWeight: FontWeight.w400),
    labelLarge: body.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    labelMedium: body.labelMedium?.copyWith(fontWeight: FontWeight.w600),
    labelSmall: body.labelSmall?.copyWith(fontWeight: FontWeight.w700),
  );
}

ThemeData buildAppTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.navy,
    onPrimary: AppColors.textOnNavy,
    primaryContainer: AppColors.aiSurfaceStart,
    onPrimaryContainer: AppColors.navy,
    secondary: AppColors.pink,
    onSecondary: AppColors.textOnNavy,
    secondaryContainer: AppColors.statusCriticalSurface,
    onSecondaryContainer: AppColors.pinkDark,
    tertiary: AppColors.aiPurple,
    onTertiary: AppColors.textOnNavy,
    tertiaryContainer: AppColors.aiSurfaceEnd,
    onTertiaryContainer: AppColors.aiPurpleDark,
    error: AppColors.statusCritical,
    onError: AppColors.textOnNavy,
    errorContainer: AppColors.statusCriticalSurface,
    onErrorContainer: AppColors.imciText,
    surface: AppColors.cardSurface,
    onSurface: AppColors.textPrimary,
    onSurfaceVariant: AppColors.textMuted,
    outline: AppColors.border,
    outlineVariant: AppColors.borderSoft,
    shadow: Color(0x1A000000),
    scrim: Color(0x80000000),
    inverseSurface: AppColors.navy,
    onInverseSurface: AppColors.textOnNavy,
    inversePrimary: AppColors.aiSurfaceStart,
    surfaceTint: AppColors.navy,
    surfaceContainerLowest: AppColors.cardSurface,
    surfaceContainerLow: AppColors.cardSurfaceMuted,
    surfaceContainer: AppColors.canvas,
    surfaceContainerHigh: Color(0xFFE6E9F2),
    surfaceContainerHighest: Color(0xFFD9DDEA),
  );

  final textTheme = _buildTextTheme(Brightness.light);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    extensions: const <ThemeExtension<dynamic>>[
      LeapfrogColors.light,
      ProgrammeColors.light,
      UrgencyTheme.light,
    ],
    scaffoldBackgroundColor: AppColors.canvas,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.navy,
      foregroundColor: AppColors.textOnNavy,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: GoogleFonts.nunito(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: AppColors.textOnNavy,
      ),
      iconTheme: const IconThemeData(color: AppColors.textOnNavy),
      actionsIconTheme: const IconThemeData(color: AppColors.textOnNavy),
    ),
    cardTheme: CardThemeData(
      color: AppColors.cardSurface,
      elevation: 0,
      shadowColor: const Color(0x0F000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusLg),
      ),
      margin: EdgeInsets.zero,
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.borderSoft,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.cardSurface,
      hintStyle: GoogleFonts.nunitoSans(
        color: AppColors.textMuted,
        fontSize: 14,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusMd),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusMd),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusMd),
        borderSide: const BorderSide(color: AppColors.aiPurple, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusMd),
        borderSide: const BorderSide(color: AppColors.statusCritical),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.pink,
        foregroundColor: AppColors.textOnNavy,
        elevation: 0,
        shadowColor: const Color(0x66E8356D),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LeapfrogColors.radiusMd),
        ),
        textStyle: GoogleFonts.nunito(
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.navy,
        foregroundColor: AppColors.textOnNavy,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LeapfrogColors.radiusMd),
        ),
        textStyle: GoogleFonts.nunito(
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.navy,
        side: const BorderSide(color: AppColors.navy, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LeapfrogColors.radiusMd),
        ),
        textStyle: GoogleFonts.nunito(
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.aiPurple,
        textStyle: GoogleFonts.nunito(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.pink,
      foregroundColor: AppColors.textOnNavy,
      elevation: 4,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.cardSurface,
      selectedColor: AppColors.navy,
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      labelStyle: GoogleFonts.nunitoSans(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      secondaryLabelStyle: GoogleFonts.nunitoSans(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppColors.textOnNavy,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.cardSurface,
      indicatorColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return GoogleFonts.nunitoSans(
          fontSize: 11,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          color: selected ? AppColors.navy : AppColors.textMuted,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? AppColors.navy : AppColors.textMuted,
          size: 24,
        );
      }),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.cardSurface,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusMd),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.cardSurface,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusLg),
      ),
      titleTextStyle: GoogleFonts.nunito(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColors.cardSurface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(LeapfrogColors.radiusXl)),
      ),
      modalBackgroundColor: AppColors.cardSurface,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.navy,
      contentTextStyle: GoogleFonts.nunitoSans(
        color: AppColors.textOnNavy,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusMd),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    iconTheme: const IconThemeData(color: AppColors.textPrimary),
  );
}

/// Builds the dark theme for the app.
ThemeData buildDarkTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.pinkLight,
    onPrimary: AppColors.canvasDark,
    primaryContainer: AppColors.aiSurfaceStartDark,
    onPrimaryContainer: AppColors.textPrimaryDark,
    secondary: AppColors.aiPurpleLight,
    onSecondary: AppColors.canvasDark,
    secondaryContainer: AppColors.aiSurfaceEndDark,
    onSecondaryContainer: AppColors.textPrimaryDark,
    tertiary: AppColors.aiPurpleLight,
    onTertiary: AppColors.canvasDark,
    tertiaryContainer: AppColors.aiSurfaceEndDark,
    onTertiaryContainer: AppColors.textPrimaryDark,
    error: AppColors.statusCriticalDark,
    onError: AppColors.canvasDark,
    errorContainer: AppColors.statusCriticalSurfaceDark,
    onErrorContainer: AppColors.textPrimaryDark,
    surface: AppColors.cardSurfaceDark,
    onSurface: AppColors.textPrimaryDark,
    onSurfaceVariant: AppColors.textMutedDark,
    outline: AppColors.borderDark,
    outlineVariant: AppColors.borderSoftDark,
    shadow: Color(0x66000000),
    scrim: Color(0xCC000000),
    inverseSurface: AppColors.textPrimaryDark,
    onInverseSurface: AppColors.canvasDark,
    inversePrimary: AppColors.pink,
    surfaceTint: AppColors.pinkLight,
    surfaceContainerLowest: AppColors.canvasDark,
    surfaceContainerLow: AppColors.cardSurfaceMutedDark,
    surfaceContainer: AppColors.cardSurfaceDark,
    surfaceContainerHigh: Color(0xFF2B3548),
    surfaceContainerHighest: Color(0xFF36405A),
  );

  final textTheme = _buildTextTheme(Brightness.dark);

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    extensions: const <ThemeExtension<dynamic>>[
      LeapfrogColors.dark,
      ProgrammeColors.dark,
      UrgencyTheme.dark,
    ],
    scaffoldBackgroundColor: AppColors.canvasDark,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.navyDeepDark,
      foregroundColor: AppColors.textPrimaryDark,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: GoogleFonts.nunito(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimaryDark,
      ),
      iconTheme: const IconThemeData(color: AppColors.textPrimaryDark),
      actionsIconTheme: const IconThemeData(color: AppColors.textPrimaryDark),
    ),
    cardTheme: CardThemeData(
      color: AppColors.cardSurfaceDark,
      elevation: 0,
      shadowColor: const Color(0x66000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusLg),
      ),
      margin: EdgeInsets.zero,
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.borderSoftDark,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.cardSurfaceDark,
      hintStyle: GoogleFonts.nunitoSans(
        color: AppColors.textMutedDark,
        fontSize: 14,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusMd),
        borderSide: const BorderSide(color: AppColors.borderDark),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusMd),
        borderSide: const BorderSide(color: AppColors.borderDark),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusMd),
        borderSide:
            const BorderSide(color: AppColors.aiPurpleLight, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusMd),
        borderSide: const BorderSide(color: AppColors.statusCriticalDark),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.pinkLight,
        foregroundColor: AppColors.canvasDark,
        elevation: 0,
        shadowColor: const Color(0x66FF5A87),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LeapfrogColors.radiusMd),
        ),
        textStyle: GoogleFonts.nunito(
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.navy,
        foregroundColor: AppColors.textPrimaryDark,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LeapfrogColors.radiusMd),
        ),
        textStyle: GoogleFonts.nunito(
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimaryDark,
        side: const BorderSide(color: AppColors.aiPurpleLight, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LeapfrogColors.radiusMd),
        ),
        textStyle: GoogleFonts.nunito(
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.aiPurpleLight,
        textStyle: GoogleFonts.nunito(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.pinkLight,
      foregroundColor: AppColors.canvasDark,
      elevation: 4,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.cardSurfaceDark,
      selectedColor: AppColors.aiPurple,
      side: const BorderSide(color: AppColors.borderDark),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      labelStyle: GoogleFonts.nunitoSans(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimaryDark,
      ),
      secondaryLabelStyle: GoogleFonts.nunitoSans(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimaryDark,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.cardSurfaceDark,
      indicatorColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return GoogleFonts.nunitoSans(
          fontSize: 11,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          color: selected ? AppColors.pinkLight : AppColors.textMutedDark,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? AppColors.pinkLight : AppColors.textMutedDark,
          size: 24,
        );
      }),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.cardSurfaceDark,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusMd),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.cardSurfaceDark,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusLg),
      ),
      titleTextStyle: GoogleFonts.nunito(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimaryDark,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColors.cardSurfaceDark,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(LeapfrogColors.radiusXl)),
      ),
      modalBackgroundColor: AppColors.cardSurfaceDark,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.cardSurfaceMutedDark,
      contentTextStyle: GoogleFonts.nunitoSans(
        color: AppColors.textPrimaryDark,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusMd),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.textMutedDark,
    ),
    iconTheme: const IconThemeData(color: AppColors.textPrimaryDark),
  );
}
