// Design tokens extracted from apon_sushashthya_v5 1.html.
// This is the single source of truth for all visual constants in the app.
// Widgets must consume [AppColors], [AppSpacing], [AppRadius], [AppShadows],
// or theme extension values — never hardcoded literals.
//
// lib/app/theme.dart re-exports this file so existing imports keep working.

import 'package:flutter/material.dart';

import '../models/programme.dart';

// ═══════════════════════════════════════════════════════════════
// COLORS
// Source: :root CSS variables + inline styles in the HTML prototype
// ═══════════════════════════════════════════════════════════════

abstract final class AppColors {
  AppColors._();

  // ─── Brand — primary palette ───────────────────────────────
  // HTML: --navy, --navy-dark; s1 gradient uses #2D3F7A as mid-stop
  static const Color navy         = Color(0xFF1B2B5E);
  static const Color navyDark     = Color(0xFF142050);
  static const Color navyDeepDark = Color(0xFF0E173F);
  static const Color navyMid      = Color(0xFF2D3F7A); // SK identity card gradient end
  static const Color navyOnDark   = Color(0xFF3D4B85); // initials avatar bg on navy cards

  // HTML: --pink, --pink-dark
  static const Color pink         = Color(0xFFE8356D);
  static const Color pinkDark     = Color(0xFFC42B5A);
  static const Color pinkLight    = Color(0xFFFF5A87);

  // HTML: --purple, --purple-dark, --lavender, --lavender-mid
  static const Color aiPurple        = Color(0xFF6B63D4);
  static const Color aiPurpleDark    = Color(0xFF3D3599);
  static const Color aiPurpleLight   = Color(0xFF9890E8);
  static const Color aiSurfaceStart  = Color(0xFFEEF0FF); // --lavender
  static const Color aiSurfaceEnd    = Color(0xFFE8EAFF);
  static const Color aiBorder        = Color(0xFFD4D8FF); // --lavender-mid
  static const Color aiSurfaceStartDark = Color(0xFF1F1B3D);
  static const Color aiSurfaceEndDark   = Color(0xFF2A2558);
  static const Color aiBorderDark       = Color(0xFF3D3599);

  // ─── Canvas / neutrals ─────────────────────────────────────
  // HTML: --bg, --card, --text, --muted, --border
  static const Color canvas           = Color(0xFFF0F2F8); // --bg
  static const Color pageBackground   = Color(0xFFF5F6FB); // enrollment/form page canvas
  static const Color cardSurface      = Color(0xFFFFFFFF); // --card / --white
  static const Color cardSurfaceMuted = Color(0xFFF8F9FC);
  static const Color chatBg           = Color(0xFFF9FAFB); // .chat-area background
  static const Color textPrimary      = Color(0xFF1A1A2E); // --text
  static const Color textStrong       = Color(0xFF1F2937); // wa-body, stronger than primary
  static const Color textMid          = Color(0xFF4B5563); // diag body — between primary & muted
  static const Color textMuted        = Color(0xFF6B7280); // --muted
  static const Color textOnNavy       = Color(0xFFFFFFFF);
  static const Color border           = Color(0xFFE5E7EB); // explicit #E5E7EB from chips/inputs
  static const Color borderSoft       = Color(0x14000000); // --border: rgba(0,0,0,0.08)
  static const Color progressTrack    = Color(0xFFF3F4F6); // score-track bg

  // dark-mode canvas
  static const Color canvasDark           = Color(0xFF0F172A);
  static const Color cardSurfaceDark      = Color(0xFF1E293B);
  static const Color cardSurfaceMutedDark = Color(0xFF1A2333);
  static const Color textPrimaryDark      = Color(0xFFF8FAFC);
  static const Color textMutedDark        = Color(0xFF94A3B8);
  static const Color borderDark           = Color(0xFF334155);
  static const Color borderSoftDark       = Color(0x14FFFFFF);

  // ─── Status — surfaces and text ────────────────────────────
  // HTML: --green, --amber, --red, --teal; score / flag / tag / diag-box tokens
  static const Color statusSuccess        = Color(0xFF10B981); // --green
  static const Color statusSuccessSurface = Color(0xFFD1FAE5); // .score-green bg / .tag-green bg
  static const Color statusSuccessText    = Color(0xFF064E3B); // .score-green text / .tag-green text
  static const Color statusSuccessAction  = Color(0xFF059669); // .btn-green (darker CTA)
  static const Color statusSuccessActionDark = Color(0xFF047857);

  static const Color statusWarning        = Color(0xFFF59E0B); // --amber
  static const Color statusWarningSurface = Color(0xFFFEF3C7); // .score-amber bg
  static const Color statusWarningText    = Color(0xFF92400E); // .score-amber text / .diag-title.amber

  static const Color statusCritical        = Color(0xFFEF4444); // --red
  static const Color statusCriticalSurface = Color(0xFFFEE2E2); // .score-red bg / .diag-box.red bg
  static const Color statusCriticalBorder  = Color(0xFFFECACA); // .diag-box.red border
  static const Color statusCriticalText    = Color(0xFF991B1B); // .score-red text / .tag-red text

  static const Color statusInfo        = Color(0xFF0EA5E9); // --teal
  static const Color statusInfoSurface = Color(0xFFE0F2FE); // .score-teal bg
  static const Color statusInfoText    = Color(0xFF0C4A6E); // .score-teal text

  // dark-mode status
  static const Color statusSuccessDark        = Color(0xFF34D399);
  static const Color statusSuccessSurfaceDark = Color(0xFF064E3B);
  static const Color statusWarningDark        = Color(0xFFFBBF24);
  static const Color statusWarningSurfaceDark = Color(0xFF92400E);
  static const Color statusCriticalDark        = Color(0xFFF87171);
  static const Color statusCriticalSurfaceDark = Color(0xFF7F1D1D);
  static const Color statusInfoDark        = Color(0xFF38BDF8);
  static const Color statusInfoSurfaceDark = Color(0xFF0C4A6E);

  // ─── Programme tokens ──────────────────────────────────────
  // ANC pink family
  static const Color ancText      = Color(0xFF9D174D);
  static const Color ancBorder    = Color(0xFFF9A8D4);
  static const Color ancSurface   = Color(0xFFFDF2F8);
  // IMCI red family
  static const Color imciText     = Color(0xFF991B1B); // same as statusCriticalText
  static const Color imciBorder   = Color(0xFFFCA5A5);
  static const Color imciSurface  = Color(0xFFFEF2F2);
  // NCD amber family
  static const Color ncdText      = Color(0xFF92400E); // same as statusWarningText
  static const Color ncdBorder    = Color(0xFFFCD34D);
  static const Color ncdSurface   = Color(0xFFFFF7ED);
  // TB green family
  static const Color tbText       = Color(0xFF065F46);
  static const Color tbBorder     = Color(0xFF6EE7B7);
  static const Color tbSurface    = Color(0xFFF0FDF4);
  // PNC / Postpartum purple family
  static const Color pncText      = Color(0xFF4C1D95);
  static const Color pncBorder    = Color(0xFFC4B5FD);
  static const Color pncSurface   = Color(0xFFF5F3FF);

  // dark-mode programme
  static const Color ancTextDark  = Color(0xFFF9A8D4);
  static const Color ancSurfaceDark  = Color(0xFF500724);
  static const Color imciTextDark = Color(0xFFFCA5A5);
  static const Color imciSurfaceDark = Color(0xFF450A0A);
  static const Color ncdTextDark  = Color(0xFFFCD34D);
  static const Color ncdSurfaceDark  = Color(0xFF451A03);
  static const Color tbTextDark   = Color(0xFF6EE7B7);
  static const Color tbSurfaceDark   = Color(0xFF052E16);
  static const Color pncTextDark  = Color(0xFFC4B5FD);
  static const Color pncSurfaceDark  = Color(0xFF2E1065);

  // ─── Tag colours (from .tag-* in HTML) ─────────────────────
  // red / amber / green reuse status surfaces above
  static const Color tagBlueSurface = Color(0xFFDBEAFE); // .tag-blue, .rx-icon bg
  static const Color tagBlueText    = Color(0xFF1E40AF); // .tag-blue text
  static const Color tagTealSurface = Color(0xFFCFFAFE); // .tag-teal bg
  static const Color tagTealText    = Color(0xFF155E75); // .tag-teal text

  // ─── External integrations ─────────────────────────────────
  static const Color whatsapp      = Color(0xFF25D366);
  static const Color waBg          = Color(0xFFECF8EB); // .wa-box background
  static const Color waBorder      = Color(0xFFA7D9A2); // .wa-box border
  static const Color sukheeStart   = Color(0xFF00BFA5);
  static const Color sukheeEnd     = Color(0xFF0288D1);

  // ─── Programme screen header colours (v10) ─────────────────
  // Dark background for programme-specific visit screen headers.
  static const Color ancHeader    = Color(0xFF831843); // s11/s13/s14/s18 ANC visit headers
  static const Color ncdHeader    = Color(0xFF854F0B); // s10/s12/s15 NCD visit headers
  static const Color imciHeader   = Color(0xFF991B1B); // s4/s5/s16 IMCI/Child visit headers
  static const Color tbHeader     = Color(0xFF085041); // TB visit completion headers
  static const Color sukheeHeader = Color(0xFF0F766E); // s17 Sukhee teleconsult header
  static const Color waHeader     = Color(0xFF064E3B); // s7/s18 WhatsApp counselling header

  // ─── SLA status text ───────────────────────────────────────
  // Surfaces reuse existing status tokens:
  //   overdue surface  = statusCriticalSurface (0xFEE2E2)
  //   dueSoon surface  = statusWarningSurface  (0xFEF3C7)
  //   onTrack surface  = tbSurface             (0xF0FDF4)
  //   onTrack text     = tbText                (0x065F46)
  static const Color slaOverdueText = Color(0xFFDC2626); // brighter than statusCritical
  static const Color slaDueSoonText = Color(0xFFD97706); // matches amber-700

  // ─── Healthcare range palette ──────────────────────────
  // Exact hex values from HTML prototype — distinct from status palette
  static const Color rangeNormal   = Color(0xFF16A34A); // green-600
  static const Color rangeElevated = Color(0xFFCA8A04); // amber-600
  static const Color rangeAbnormal = Color(0xFFEA580C); // orange-600 (Stage 1)
  static const Color rangeCritical = Color(0xFFDC2626); // red-600   (Stage 2)
  static const Color rangeCrisis   = Color(0xFF7F1D1D); // red-900   (hypertensive crisis)

  static const Color rangeNormalSurface   = Color(0xFFDCFCE7); // green-100
  static const Color rangeElevatedSurface = Color(0xFFFEF3C7); // = statusWarningSurface
  static const Color rangeAbnormalSurface = Color(0xFFFFF7ED); // orange-50
  static const Color rangeCriticalSurface = Color(0xFFFEE2E2); // = statusCriticalSurface
  static const Color rangeCrisisSurface   = Color(0xFFFEE2E2);

  // Named aliases for danger-sign widget (bg/border reuse imciSurface/imciBorder)
  static const Color dangerSignIconColor = rangeCritical; // #DC2626
  static const Color dangerSignText      = rangeCrisis;   // #7F1D1D
}

// ═══════════════════════════════════════════════════════════════
// SPACING
// 4-unit grid derived from HTML padding / margin / gap values
// ═══════════════════════════════════════════════════════════════

abstract final class AppSpacing {
  AppSpacing._();

  static const double xs    =  4.0;
  static const double sm    =  6.0;  // flow-dot gap, score-track margin-top
  static const double md    =  8.0;  // stat-row gap, vital-grid gap, card mb
  static const double lg    = 10.0;  // call-btn gap, step-item gap, hh-row gap
  static const double xl    = 12.0;  // card mb, patient-row padding
  static const double xxl   = 14.0;  // fingerprint icon gap, back-btn gap
  static const double xxxl  = 16.0;  // card padding, body padding, header-sub mb
  static const double h4xl  = 18.0;  // SK card padding h
  static const double h5xl  = 20.0;  // header padding h, button padding h
  static const double h6xl  = 24.0;  // body padding, s1 bottom padding
  static const double h7xl  = 28.0;  // fp drawer scanning padding top
  static const double h8xl  = 32.0;  // bio-frame top padding
}

// ═══════════════════════════════════════════════════════════════
// BORDER RADIUS
// Extracted from .border-radius values across all CSS components
// ═══════════════════════════════════════════════════════════════

abstract final class AppRadius {
  AppRadius._();

  static const double flag     =  5.0;  // .vital-flag, .diag-conf
  static const double sm       =  6.0;  // programme_tag pill, urgency_badge compact
  static const double rxIcon   =  8.0;  // .rx-icon, NID/upazila inner panels
  static const double field    = 10.0;  // .bio-field, .chat-input, .outline-field
  static const double button   = 12.0;  // .pink-btn, .navy-btn, .outline-btn, .search-bar
  static const double callBtn  = 10.0;  // .call-btn
  static const double patRow   = 14.0;  // .patient-row, .diag-box, .scribe-pill
  static const double card     = 16.0;  // .card, .ai-card, .call-box, SK identity card
  static const double pill     = 20.0;  // .score-pill, .chip border-radius
  static const double xl       = 24.0;  // bottom sheet top radius
  static const double waIcon   =  7.0;  // .wa-icon
  static const double full     = 999.0; // full circle (avatars, FAB, chat-send)
}

// ═══════════════════════════════════════════════════════════════
// SHADOWS
// Source: box-shadow values extracted from HTML components
// ═══════════════════════════════════════════════════════════════

abstract final class AppShadows {
  AppShadows._();

  /// Generic card: 0 2px 8px rgba(0,0,0,0.06)
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2)),
  ];

  /// Patient / list row: 0 2px 6px rgba(0,0,0,0.05)
  static const List<BoxShadow> listItem = [
    BoxShadow(color: Color(0x0D000000), blurRadius: 6, offset: Offset(0, 2)),
  ];

  /// Stat box: 0 1px 4px rgba(0,0,0,0.05)
  static const List<BoxShadow> statBox = [
    BoxShadow(color: Color(0x0D000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  /// Navy CTA card (fingerprint button): 0 4px 16px rgba(27,43,94,0.25)
  static const List<BoxShadow> navyCta = [
    BoxShadow(color: Color(0x401B2B5E), blurRadius: 16, offset: Offset(0, 4)),
  ];

  /// Pink app icon: 0 8px 24px rgba(232,53,109,0.35)
  static const List<BoxShadow> pinkIcon = [
    BoxShadow(color: Color(0x59E8356D), blurRadius: 24, offset: Offset(0, 8)),
  ];

  /// FAB: 0 4px 16px rgba(232,53,109,0.50)
  static const List<BoxShadow> fab = [
    BoxShadow(color: Color(0x80E8356D), blurRadius: 16, offset: Offset(0, 4)),
  ];
}

// ═══════════════════════════════════════════════════════════════
// ANIMATION TOKENS
// Durations and curves extracted from apon_sushashthya_v5 1.html
// ═══════════════════════════════════════════════════════════════

abstract final class AppAnimations {
  AppAnimations._();

  // Durations
  static const Duration screenEnter   = Duration(milliseconds: 200);
  static const Duration staggerStep   = Duration(milliseconds: 60);
  static const Duration idleGlow      = Duration(milliseconds: 2500);
  static const Duration scanPulse     = Duration(milliseconds: 700);
  static const Duration ripple        = Duration(milliseconds: 1800);
  static const Duration verifyBounce  = Duration(milliseconds: 500);
  static const Duration pressFeedback = Duration(milliseconds: 100);

  // Curves
  static const Curve standard = Curves.ease;
  static const Curve gentle   = Curves.easeInOut;
  static const Curve easeOut  = Curves.easeOut;
  // cubic-bezier(0.34, 1.56, 0.64, 1) — spring overshoot for verify bounce
  static const Curve spring   = Cubic(0.34, 1.56, 0.64, 1.0);
}

// ═══════════════════════════════════════════════════════════════
// TEXT STYLES
// Named semantic styles that directly match the HTML design.
// Use these in widgets instead of Theme.of(context).textTheme.*
// where an exact HTML match is required (e.g. section-label, score pill).
// ═══════════════════════════════════════════════════════════════

abstract final class AppTextStyles {
  AppTextStyles._();

  // ─── Header ────────────────────────────────────────────────
  // .header-title: Nunito 20px w800 white
  static const TextStyle headerTitle = TextStyle(
    fontFamily: 'Nunito', fontSize: 20, fontWeight: FontWeight.w800,
    color: Colors.white,
  );
  // .header-sub: NunitoSans 12px rgba(255,255,255,0.6)
  static const TextStyle headerSub = TextStyle(
    fontFamily: 'NunitoSans', fontSize: 12, fontWeight: FontWeight.w400,
    color: Color(0x99FFFFFF),
  );

  // ─── Body / content ────────────────────────────────────────
  // default body: NunitoSans 13px w400 --text
  static const TextStyle body = TextStyle(
    fontFamily: 'NunitoSans', fontSize: 13, fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );
  // .patient-name: NunitoSans 14px w700
  static const TextStyle listTitle = TextStyle(
    fontFamily: 'NunitoSans', fontSize: 14, fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );
  // .patient-meta, sub-text: NunitoSans 11px --muted
  static const TextStyle subText = TextStyle(
    fontFamily: 'NunitoSans', fontSize: 11, fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
  );

  // ─── Section labels ────────────────────────────────────────
  // .section-label, .ai-label: NunitoSans 11px w700 uppercase ls0.07em --muted
  static const TextStyle sectionLabel = TextStyle(
    fontFamily: 'NunitoSans', fontSize: 11, fontWeight: FontWeight.w700,
    color: AppColors.textMuted,
    letterSpacing: 0.77, // 0.07em × 11px
  );
  // Uppercase variant (text-transform applied at call site via toUpperCase())
  static const TextStyle sectionLabelOnNavy = TextStyle(
    fontFamily: 'NunitoSans', fontSize: 10, fontWeight: FontWeight.w700,
    color: Color(0x80FFFFFF), // rgba(255,255,255,0.5)
    letterSpacing: 0.80, // 0.08em × 10px
  );

  // ─── Stats & vitals ────────────────────────────────────────
  // .stat-num: Nunito 22px w800 --navy
  static const TextStyle statNumber = TextStyle(
    fontFamily: 'Nunito', fontSize: 22, fontWeight: FontWeight.w800,
    color: AppColors.navy,
  );
  // .stat-lbl: NunitoSans 10px --muted
  static const TextStyle statLabel = TextStyle(
    fontFamily: 'NunitoSans', fontSize: 10, fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
  );
  // .vital-val: Nunito 24px w800 --text
  static const TextStyle vitalValue = TextStyle(
    fontFamily: 'Nunito', fontSize: 24, fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
  );
  // .vital-lbl: NunitoSans 10px w700 uppercase ls0.05em --muted
  static const TextStyle vitalLabel = TextStyle(
    fontFamily: 'NunitoSans', fontSize: 10, fontWeight: FontWeight.w700,
    color: AppColors.textMuted, letterSpacing: 0.50,
  );
  // .vital-unit: NunitoSans 12px w400 --muted
  static const TextStyle vitalUnit = TextStyle(
    fontFamily: 'NunitoSans', fontSize: 12, fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
  );

  // ─── Score / tag pills ─────────────────────────────────────
  // .score-pill, .tag: Nunito 11px w800
  static const TextStyle scorePill = TextStyle(
    fontFamily: 'Nunito', fontSize: 11, fontWeight: FontWeight.w800,
  );
  // .chip: NunitoSans 12px w600
  static const TextStyle chip = TextStyle(
    fontFamily: 'NunitoSans', fontSize: 12, fontWeight: FontWeight.w600,
  );

  // ─── AI cards ──────────────────────────────────────────────
  // .ai-title: Nunito 18px w800 --navy
  static const TextStyle aiTitle = TextStyle(
    fontFamily: 'Nunito', fontSize: 18, fontWeight: FontWeight.w800,
    color: AppColors.navy,
  );
  // .ai-label: NunitoSans 11px w700 uppercase ls0.06em --purple
  static const TextStyle aiLabel = TextStyle(
    fontFamily: 'NunitoSans', fontSize: 11, fontWeight: FontWeight.w700,
    color: AppColors.aiPurple, letterSpacing: 0.66,
  );
  // .ai-sub: NunitoSans 12px w400 --muted
  static const TextStyle aiSub = TextStyle(
    fontFamily: 'NunitoSans', fontSize: 12, fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
  );

  // ─── Telecall ──────────────────────────────────────────────
  // .call-timer: Nunito 32px w800 white ls2px
  static const TextStyle callTimer = TextStyle(
    fontFamily: 'Nunito', fontSize: 32, fontWeight: FontWeight.w800,
    color: Colors.white, letterSpacing: 2,
  );
  // .call-name: Nunito 16px w800 white
  static const TextStyle callName = TextStyle(
    fontFamily: 'Nunito', fontSize: 16, fontWeight: FontWeight.w800,
    color: Colors.white,
  );
  // .call-sub: NunitoSans 12px rgba(255,255,255,0.6)
  static const TextStyle callSub = TextStyle(
    fontFamily: 'NunitoSans', fontSize: 12, fontWeight: FontWeight.w400,
    color: Color(0x99FFFFFF),
  );

  // ─── Navigation ────────────────────────────────────────────
  // .nav-tab-lbl: NunitoSans 10px w600 --muted
  static const TextStyle navTabLabel = TextStyle(
    fontFamily: 'NunitoSans', fontSize: 10, fontWeight: FontWeight.w600,
    color: AppColors.textMuted,
  );

  // ─── Diagnosis / step ──────────────────────────────────────
  // .diag-title: Nunito 16px w800
  static const TextStyle diagTitle = TextStyle(
    fontFamily: 'Nunito', fontSize: 16, fontWeight: FontWeight.w800,
  );
  // .diag-body: NunitoSans 12px ls1.6 #4B5563
  static const TextStyle diagBody = TextStyle(
    fontFamily: 'NunitoSans', fontSize: 12, fontWeight: FontWeight.w400,
    color: AppColors.textMid, height: 1.6,
  );
  // .step-text: NunitoSans 13px ls1.5 --text
  static const TextStyle stepText = TextStyle(
    fontFamily: 'NunitoSans', fontSize: 13, fontWeight: FontWeight.w400,
    color: AppColors.textPrimary, height: 1.5,
  );
}

// ═══════════════════════════════════════════════════════════════
// THEME EXTENSIONS
// ═══════════════════════════════════════════════════════════════

/// Semantic Leapfrog tokens consumed via
/// `Theme.of(context).extension<LeapfrogColors>()!`
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

  /// Border-radius scale (mirrors [AppRadius]).
  static const double radiusSm = AppRadius.button;   // 12
  static const double radiusMd = AppRadius.patRow;   // 14
  static const double radiusLg = AppRadius.card;     // 16
  static const double radiusXl = AppRadius.xl;       // 24

  static const List<BoxShadow> cardShadow = AppShadows.card;

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
    Color? brandNavy, Color? brandNavyDark, Color? brandPink,
    Color? brandPinkDark, Color? aiPurple, Color? aiPurpleDark,
    Color? aiSurfaceStart, Color? aiSurfaceEnd, Color? aiBorder,
    Color? canvas, Color? cardSurface, Color? cardSurfaceMuted,
    Color? textPrimary, Color? textMuted, Color? divider,
    Color? statusSuccess, Color? statusSuccessSurface,
    Color? statusWarning, Color? statusWarningSurface,
    Color? statusCritical, Color? statusCriticalSurface,
    Color? statusInfo, Color? statusInfoSurface,
    Color? whatsapp, Color? sukheeGradientStart, Color? sukheeGradientEnd,
  }) => LeapfrogColors(
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
    statusCriticalSurface: statusCriticalSurface ?? this.statusCriticalSurface,
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
      cardSurfaceMuted: Color.lerp(cardSurfaceMuted, other.cardSurfaceMuted, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      statusSuccess: Color.lerp(statusSuccess, other.statusSuccess, t)!,
      statusSuccessSurface: Color.lerp(statusSuccessSurface, other.statusSuccessSurface, t)!,
      statusWarning: Color.lerp(statusWarning, other.statusWarning, t)!,
      statusWarningSurface: Color.lerp(statusWarningSurface, other.statusWarningSurface, t)!,
      statusCritical: Color.lerp(statusCritical, other.statusCritical, t)!,
      statusCriticalSurface: Color.lerp(statusCriticalSurface, other.statusCriticalSurface, t)!,
      statusInfo: Color.lerp(statusInfo, other.statusInfo, t)!,
      statusInfoSurface: Color.lerp(statusInfoSurface, other.statusInfoSurface, t)!,
      whatsapp: Color.lerp(whatsapp, other.whatsapp, t)!,
      sukheeGradientStart: Color.lerp(sukheeGradientStart, other.sukheeGradientStart, t)!,
      sukheeGradientEnd: Color.lerp(sukheeGradientEnd, other.sukheeGradientEnd, t)!,
    );
  }
}

/// Programme → color mapping.
/// Use via `Theme.of(context).extension<ProgrammeColors>()!.of(programme)`.
@immutable
class ProgrammeColors extends ThemeExtension<ProgrammeColors> {
  const ProgrammeColors({
    required this.imci, required this.imciContainer,
    required this.anc, required this.ancContainer,
    required this.ncd, required this.ncdContainer,
    required this.tb, required this.tbContainer,
    required this.pnc, required this.pncContainer,
  });

  final Color imci; final Color imciContainer;
  final Color anc;  final Color ancContainer;
  final Color ncd;  final Color ncdContainer;
  final Color tb;   final Color tbContainer;
  final Color pnc;  final Color pncContainer;

  Color of(Programme p) {
    switch (p) {
      case Programme.imci: return imci;
      case Programme.anc:  return anc;
      case Programme.pnc:  return pnc;
      case Programme.ncd:  return ncd;
      case Programme.tb:   return tb;
      default:             return ncd;
    }
  }

  Color containerOf(Programme p) {
    switch (p) {
      case Programme.imci: return imciContainer;
      case Programme.anc:  return ancContainer;
      case Programme.pnc:  return pncContainer;
      case Programme.ncd:  return ncdContainer;
      case Programme.tb:   return tbContainer;
      default:             return ncdContainer;
    }
  }

  static const ProgrammeColors light = ProgrammeColors(
    imci: AppColors.imciText,   imciContainer: AppColors.imciSurface,
    anc:  AppColors.ancText,    ancContainer:  AppColors.ancSurface,
    ncd:  AppColors.ncdText,    ncdContainer:  AppColors.ncdSurface,
    tb:   AppColors.tbText,     tbContainer:   AppColors.tbSurface,
    pnc:  AppColors.pncText,    pncContainer:  AppColors.pncSurface,
  );

  static const ProgrammeColors dark = ProgrammeColors(
    imci: AppColors.imciTextDark, imciContainer: AppColors.imciSurfaceDark,
    anc:  AppColors.ancTextDark,  ancContainer:  AppColors.ancSurfaceDark,
    ncd:  AppColors.ncdTextDark,  ncdContainer:  AppColors.ncdSurfaceDark,
    tb:   AppColors.tbTextDark,   tbContainer:   AppColors.tbSurfaceDark,
    pnc:  AppColors.pncTextDark,  pncContainer:  AppColors.pncSurfaceDark,
  );

  @override
  ProgrammeColors copyWith({
    Color? imci, Color? imciContainer, Color? anc, Color? ancContainer,
    Color? ncd, Color? ncdContainer, Color? tb, Color? tbContainer,
    Color? pnc, Color? pncContainer,
  }) => ProgrammeColors(
    imci: imci ?? this.imci, imciContainer: imciContainer ?? this.imciContainer,
    anc:  anc  ?? this.anc,  ancContainer:  ancContainer  ?? this.ancContainer,
    ncd:  ncd  ?? this.ncd,  ncdContainer:  ncdContainer  ?? this.ncdContainer,
    tb:   tb   ?? this.tb,   tbContainer:   tbContainer   ?? this.tbContainer,
    pnc:  pnc  ?? this.pnc,  pncContainer:  pncContainer  ?? this.pncContainer,
  );

  @override
  ProgrammeColors lerp(ThemeExtension<ProgrammeColors>? other, double t) {
    if (other is! ProgrammeColors) return this;
    return ProgrammeColors(
      imci: Color.lerp(imci, other.imci, t)!,
      imciContainer: Color.lerp(imciContainer, other.imciContainer, t)!,
      anc:  Color.lerp(anc,  other.anc,  t)!,
      ancContainer:  Color.lerp(ancContainer,  other.ancContainer,  t)!,
      ncd:  Color.lerp(ncd,  other.ncd,  t)!,
      ncdContainer:  Color.lerp(ncdContainer,  other.ncdContainer,  t)!,
      tb:   Color.lerp(tb,   other.tb,   t)!,
      tbContainer:   Color.lerp(tbContainer,   other.tbContainer,   t)!,
      pnc:  Color.lerp(pnc,  other.pnc,  t)!,
      pncContainer:  Color.lerp(pncContainer,  other.pncContainer,  t)!,
    );
  }
}

/// Urgency-based color roles for visit prioritisation.
@immutable
class UrgencyTheme extends ThemeExtension<UrgencyTheme> {
  const UrgencyTheme({
    required this.visitNow, required this.visitNowContainer,
    required this.today, required this.todayContainer,
    required this.thisWeek, required this.thisWeekContainer,
    required this.routine, required this.routineContainer,
    required this.urgent, required this.urgentContainer,
  });

  final Color visitNow; final Color visitNowContainer;
  final Color today;    final Color todayContainer;
  final Color thisWeek; final Color thisWeekContainer;
  final Color routine;  final Color routineContainer;
  final Color urgent;   final Color urgentContainer;

  static const UrgencyTheme light = UrgencyTheme(
    visitNow: AppColors.statusCritical, visitNowContainer: AppColors.statusCriticalSurface,
    today:    AppColors.statusWarning,  todayContainer:    AppColors.statusWarningSurface,
    thisWeek: AppColors.statusInfo,     thisWeekContainer: AppColors.statusInfoSurface,
    routine:  AppColors.textMuted,      routineContainer:  AppColors.cardSurfaceMuted,
    urgent:   AppColors.statusCritical, urgentContainer:   AppColors.statusCriticalSurface,
  );

  static const UrgencyTheme dark = UrgencyTheme(
    visitNow: AppColors.statusCriticalDark, visitNowContainer: AppColors.statusCriticalSurfaceDark,
    today:    AppColors.statusWarningDark,  todayContainer:    AppColors.statusWarningSurfaceDark,
    thisWeek: AppColors.statusInfoDark,     thisWeekContainer: AppColors.statusInfoSurfaceDark,
    routine:  AppColors.textMutedDark,      routineContainer:  AppColors.cardSurfaceMutedDark,
    urgent:   AppColors.statusCriticalDark, urgentContainer:   AppColors.statusCriticalSurfaceDark,
  );

  @override
  UrgencyTheme copyWith({
    Color? visitNow, Color? visitNowContainer, Color? today, Color? todayContainer,
    Color? thisWeek, Color? thisWeekContainer, Color? routine, Color? routineContainer,
    Color? urgent, Color? urgentContainer,
  }) => UrgencyTheme(
    visitNow: visitNow ?? this.visitNow, visitNowContainer: visitNowContainer ?? this.visitNowContainer,
    today:    today    ?? this.today,    todayContainer:    todayContainer    ?? this.todayContainer,
    thisWeek: thisWeek ?? this.thisWeek, thisWeekContainer: thisWeekContainer ?? this.thisWeekContainer,
    routine:  routine  ?? this.routine,  routineContainer:  routineContainer  ?? this.routineContainer,
    urgent:   urgent   ?? this.urgent,   urgentContainer:   urgentContainer   ?? this.urgentContainer,
  );

  @override
  UrgencyTheme lerp(ThemeExtension<UrgencyTheme>? other, double t) {
    if (other is! UrgencyTheme) return this;
    return UrgencyTheme(
      visitNow: Color.lerp(visitNow, other.visitNow, t)!,
      visitNowContainer: Color.lerp(visitNowContainer, other.visitNowContainer, t)!,
      today:    Color.lerp(today,    other.today,    t)!,
      todayContainer:    Color.lerp(todayContainer,    other.todayContainer,    t)!,
      thisWeek: Color.lerp(thisWeek, other.thisWeek, t)!,
      thisWeekContainer: Color.lerp(thisWeekContainer, other.thisWeekContainer, t)!,
      routine:  Color.lerp(routine,  other.routine,  t)!,
      routineContainer:  Color.lerp(routineContainer,  other.routineContainer,  t)!,
      urgent:   Color.lerp(urgent,   other.urgent,   t)!,
      urgentContainer:   Color.lerp(urgentContainer,   other.urgentContainer,   t)!,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// TEXT THEME
// Sized to match the HTML prototype type scale.
// HTML body default = 13px → bodyLarge
// HTML header-title = 20px → headlineMedium
// HTML "welcome back" = 22px → headlineLarge
// ═══════════════════════════════════════════════════════════════

TextTheme _buildTextTheme(Brightness brightness) {
  final base = brightness == Brightness.light
      ? Typography.material2021().black
      : Typography.material2021().white;

  final h = base.apply(fontFamily: 'Nunito');
  final b = base.apply(fontFamily: 'NunitoSans');

  return base.copyWith(
    // ─── Display — timer, large numbers ────────────────────
    displayLarge:  h.displayLarge?.copyWith(fontSize: 32, fontWeight: FontWeight.w800),
    displayMedium: h.displayMedium?.copyWith(fontSize: 28, fontWeight: FontWeight.w800),
    displaySmall:  h.displaySmall?.copyWith(fontSize: 24, fontWeight: FontWeight.w800),
    // ─── Headline — titles, AI card titles, stat numbers ───
    headlineLarge:  h.headlineLarge?.copyWith(fontSize: 22, fontWeight: FontWeight.w800),
    headlineMedium: h.headlineMedium?.copyWith(fontSize: 20, fontWeight: FontWeight.w800),
    headlineSmall:  h.headlineSmall?.copyWith(fontSize: 18, fontWeight: FontWeight.w800),
    // ─── Title — screen sub-titles, patient names ──────────
    titleLarge:  h.titleLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w800),
    titleMedium: h.titleMedium?.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
    titleSmall:  b.titleSmall?.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
    // ─── Body — default reading text ───────────────────────
    bodyLarge:  b.bodyLarge?.copyWith(fontSize: 13, fontWeight: FontWeight.w400),
    bodyMedium: b.bodyMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w400),
    bodySmall:  b.bodySmall?.copyWith(fontSize: 11, fontWeight: FontWeight.w400),
    // ─── Label — chips, section labels, navigation ─────────
    labelLarge:  h.labelLarge?.copyWith(fontSize: 12, fontWeight: FontWeight.w700),
    labelMedium: h.labelMedium?.copyWith(fontSize: 11, fontWeight: FontWeight.w700),
    labelSmall:  b.labelSmall?.copyWith(fontSize: 10, fontWeight: FontWeight.w700),
  );
}

// ═══════════════════════════════════════════════════════════════
// APP THEME
// Single entry point: AppTheme.light / AppTheme.dark
// Free functions buildAppTheme() / buildDarkTheme() kept for
// backwards compatibility with existing main.dart call sites.
// ═══════════════════════════════════════════════════════════════

abstract final class AppTheme {
  AppTheme._();

  static ThemeData get light => buildAppTheme();
  static ThemeData get dark  => buildDarkTheme();
}

ThemeData buildAppTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    // ─── Primary: navy ─────────────────────────────────────
    primary:            AppColors.navy,
    onPrimary:          AppColors.textOnNavy,
    primaryContainer:   AppColors.aiSurfaceStart,
    onPrimaryContainer: AppColors.navy,
    // ─── Secondary: pink ───────────────────────────────────
    secondary:            AppColors.pink,
    onSecondary:          AppColors.textOnNavy,
    secondaryContainer:   AppColors.statusCriticalSurface,
    onSecondaryContainer: AppColors.pinkDark,
    // ─── Tertiary: AI purple ────────────────────────────────
    tertiary:            AppColors.aiPurple,
    onTertiary:          AppColors.textOnNavy,
    tertiaryContainer:   AppColors.aiSurfaceEnd,
    onTertiaryContainer: AppColors.aiPurpleDark,
    // ─── Error ─────────────────────────────────────────────
    error:          AppColors.statusCritical,
    onError:        AppColors.textOnNavy,
    errorContainer: AppColors.statusCriticalSurface,
    onErrorContainer: AppColors.statusCriticalText,
    // ─── Surface ───────────────────────────────────────────
    surface:          AppColors.cardSurface,
    onSurface:        AppColors.textPrimary,
    onSurfaceVariant: AppColors.textMuted,
    outline:          AppColors.border,
    outlineVariant:   AppColors.borderSoft,
    // ─── Utility ───────────────────────────────────────────
    shadow:           Color(0x1A000000),
    scrim:            Color(0x80000000),
    inverseSurface:   AppColors.navy,
    onInverseSurface: AppColors.textOnNavy,
    inversePrimary:   AppColors.aiSurfaceStart,
    surfaceTint:      AppColors.navy,
    surfaceContainerLowest:   AppColors.cardSurface,
    surfaceContainerLow:      AppColors.cardSurfaceMuted,
    surfaceContainer:         AppColors.canvas,
    surfaceContainerHigh:     Color(0xFFE6E9F2),
    surfaceContainerHighest:  Color(0xFFD9DDEA),
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
      titleTextStyle: const TextStyle(
        fontFamily: 'Nunito', fontSize: 20, fontWeight: FontWeight.w800,
        color: AppColors.textOnNavy,
      ),
      iconTheme: const IconThemeData(color: AppColors.textOnNavy),
      actionsIconTheme: const IconThemeData(color: AppColors.textOnNavy),
    ),
    cardTheme: CardThemeData(
      color: AppColors.cardSurface,
      elevation: 0,
      shadowColor: AppShadows.card.first.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      margin: EdgeInsets.zero,
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.borderSoft, thickness: 1, space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.cardSurfaceMuted,
      hintStyle: const TextStyle(
        fontFamily: 'NunitoSans', fontSize: 13, color: AppColors.textMuted,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: const BorderSide(color: AppColors.border, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: const BorderSide(color: AppColors.border, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: const BorderSide(color: AppColors.aiPurple, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: const BorderSide(color: AppColors.statusCritical, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: const BorderSide(color: AppColors.statusCritical, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.pink,
        foregroundColor: AppColors.textOnNavy,
        elevation: 0,
        shadowColor: AppShadows.fab.first.color,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.h5xl, vertical: AppSpacing.xl + 1,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        textStyle: const TextStyle(
          fontFamily: 'Nunito', fontSize: 15, fontWeight: FontWeight.w800,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.navy,
        foregroundColor: AppColors.textOnNavy,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.h5xl, vertical: AppSpacing.xl + 1,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        textStyle: const TextStyle(
          fontFamily: 'Nunito', fontSize: 15, fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.navy,
        side: const BorderSide(color: AppColors.navy, width: 1.5),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.h5xl, vertical: AppSpacing.xl,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        textStyle: const TextStyle(
          fontFamily: 'Nunito', fontSize: 14, fontWeight: FontWeight.w700,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.aiPurple,
        textStyle: const TextStyle(
          fontFamily: 'Nunito', fontSize: 14, fontWeight: FontWeight.w700,
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
      side: const BorderSide(color: AppColors.border, width: 1.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      labelStyle: const TextStyle(
        fontFamily: 'NunitoSans', fontSize: 12, fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      secondaryLabelStyle: const TextStyle(
        fontFamily: 'NunitoSans', fontSize: 12, fontWeight: FontWeight.w700,
        color: AppColors.textOnNavy,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl, vertical: AppSpacing.sm,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.cardSurface,
      indicatorColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontFamily: 'NunitoSans', fontSize: 10,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          color: selected ? AppColors.navy : AppColors.textMuted,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? AppColors.navy : AppColors.textMuted, size: 24,
        );
      }),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.cardSurface, elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.cardSurface, elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      titleTextStyle: const TextStyle(
        fontFamily: 'Nunito', fontSize: 18, fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.cardSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      modalBackgroundColor: AppColors.cardSurface,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.navy,
      contentTextStyle: const TextStyle(
        fontFamily: 'NunitoSans', color: AppColors.textOnNavy,
        fontWeight: FontWeight.w600, fontSize: 13,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    iconTheme: const IconThemeData(color: AppColors.textPrimary),
  );
}

ThemeData buildDarkTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary:            AppColors.pinkLight,
    onPrimary:          AppColors.canvasDark,
    primaryContainer:   AppColors.aiSurfaceStartDark,
    onPrimaryContainer: AppColors.textPrimaryDark,
    secondary:          AppColors.aiPurpleLight,
    onSecondary:        AppColors.canvasDark,
    secondaryContainer:   AppColors.aiSurfaceEndDark,
    onSecondaryContainer: AppColors.textPrimaryDark,
    tertiary:            AppColors.aiPurpleLight,
    onTertiary:          AppColors.canvasDark,
    tertiaryContainer:   AppColors.aiSurfaceEndDark,
    onTertiaryContainer: AppColors.textPrimaryDark,
    error:          AppColors.statusCriticalDark,
    onError:        AppColors.canvasDark,
    errorContainer: AppColors.statusCriticalSurfaceDark,
    onErrorContainer: AppColors.textPrimaryDark,
    surface:          AppColors.cardSurfaceDark,
    onSurface:        AppColors.textPrimaryDark,
    onSurfaceVariant: AppColors.textMutedDark,
    outline:          AppColors.borderDark,
    outlineVariant:   AppColors.borderSoftDark,
    shadow:           Color(0x66000000),
    scrim:            Color(0xCC000000),
    inverseSurface:   AppColors.textPrimaryDark,
    onInverseSurface: AppColors.canvasDark,
    inversePrimary:   AppColors.pink,
    surfaceTint:      AppColors.pinkLight,
    surfaceContainerLowest:  AppColors.canvasDark,
    surfaceContainerLow:     AppColors.cardSurfaceMutedDark,
    surfaceContainer:        AppColors.cardSurfaceDark,
    surfaceContainerHigh:    Color(0xFF2B3548),
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
      titleTextStyle: const TextStyle(
        fontFamily: 'Nunito', fontSize: 20, fontWeight: FontWeight.w800,
        color: AppColors.textPrimaryDark,
      ),
      iconTheme: const IconThemeData(color: AppColors.textPrimaryDark),
      actionsIconTheme: const IconThemeData(color: AppColors.textPrimaryDark),
    ),
    cardTheme: CardThemeData(
      color: AppColors.cardSurfaceDark, elevation: 0,
      shadowColor: const Color(0x66000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      margin: EdgeInsets.zero,
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.borderSoftDark, thickness: 1, space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.cardSurfaceMutedDark,
      hintStyle: const TextStyle(
        fontFamily: 'NunitoSans', fontSize: 13, color: AppColors.textMutedDark,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: const BorderSide(color: AppColors.borderDark, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: const BorderSide(color: AppColors.borderDark, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: const BorderSide(color: AppColors.aiPurpleLight, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: const BorderSide(color: AppColors.statusCriticalDark, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: const BorderSide(color: AppColors.statusCriticalDark, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.pinkLight,
        foregroundColor: AppColors.canvasDark,
        elevation: 0,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.h5xl, vertical: AppSpacing.xl + 1,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        textStyle: const TextStyle(
          fontFamily: 'Nunito', fontSize: 15, fontWeight: FontWeight.w800,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.navy,
        foregroundColor: AppColors.textPrimaryDark,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.h5xl, vertical: AppSpacing.xl + 1,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        textStyle: const TextStyle(
          fontFamily: 'Nunito', fontSize: 15, fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimaryDark,
        side: const BorderSide(color: AppColors.aiPurpleLight, width: 1.5),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.h5xl, vertical: AppSpacing.xl,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        textStyle: const TextStyle(
          fontFamily: 'Nunito', fontSize: 14, fontWeight: FontWeight.w700,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.aiPurpleLight,
        textStyle: const TextStyle(
          fontFamily: 'Nunito', fontSize: 14, fontWeight: FontWeight.w700,
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
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      labelStyle: const TextStyle(
        fontFamily: 'NunitoSans', fontSize: 12, fontWeight: FontWeight.w600,
        color: AppColors.textPrimaryDark,
      ),
      secondaryLabelStyle: const TextStyle(
        fontFamily: 'NunitoSans', fontSize: 12, fontWeight: FontWeight.w700,
        color: AppColors.textPrimaryDark,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl, vertical: AppSpacing.sm,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.cardSurfaceDark,
      indicatorColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontFamily: 'NunitoSans', fontSize: 10,
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
      color: AppColors.cardSurfaceDark, elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.cardSurfaceDark, elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      titleTextStyle: const TextStyle(
        fontFamily: 'Nunito', fontSize: 18, fontWeight: FontWeight.w800,
        color: AppColors.textPrimaryDark,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.cardSurfaceDark,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      modalBackgroundColor: AppColors.cardSurfaceDark,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.cardSurfaceMutedDark,
      contentTextStyle: const TextStyle(
        fontFamily: 'NunitoSans', color: AppColors.textPrimaryDark,
        fontWeight: FontWeight.w600, fontSize: 13,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    listTileTheme: const ListTileThemeData(iconColor: AppColors.textMutedDark),
    iconTheme: const IconThemeData(color: AppColors.textPrimaryDark),
  );
}
