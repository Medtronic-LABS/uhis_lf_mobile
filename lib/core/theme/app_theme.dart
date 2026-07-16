// Design tokens extracted from apon_sushashthya_v5 1.html.
// This is the single source of truth for all visual constants in the app.
// Widgets must consume [AppColors], [AppSpacing], [AppRadius], [AppShadows],
// or theme extension values — never hardcoded literals.
//
// lib/app/theme.dart re-exports this file so existing imports keep working.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  // Care-thread supplement (reuse existing where hex matches)
  // threadGrowthText  → aiPurpleDark (0xFF3D3599)
  // threadImmText     → tbText       (0xFF065F46)
  // threadSugarBg     → statusInfoSurface (0xFFE0F2FE)
  // threadGeneralText → textMid      (0xFF4B5563)
  static const Color threadInfoText   = Color(0xFF075985); // info-blue text (sugar/newborn)
  static const Color threadGeneralBg  = Color(0xFFF3F4F6); // neutral grey bg (general enrolment)
  static const Color threadImmBg      = Color(0xFFECFDF5); // immunization surface (≠ tbSurface)

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

  // ─── v11 additions — Brand / AI scribe ──────────────────────
  static const Color brandAccentDeep     = Color(0xFFB01F52); // splash gradient end
  static const Color brandAccentDeepDark = brandAccentDeep;

  static const Color aiScribeActiveBorder     = Color(0xFF7F77DD); // scribe autofill field border
  static const Color aiScribeActiveBorderDark = aiPurpleLight;
  static const Color aiScribeSurface          = Color(0xFFEEF2FF); // scribe listening pill bg
  static const Color aiScribeSurfaceDark      = Color(0xFF241F45);

  // ─── v11 additions — Neutrals ───────────────────────────────
  static const Color textDisabled     = Color(0xFF9CA3AF);
  static const Color textDisabledDark = Color(0xFF64748B);
  static const Color borderDashed     = Color(0xFFD1D5DB);
  static const Color borderDashedDark = Color(0xFF475569);

  // Promoted from inline ColorScheme literals in buildAppTheme()/buildDarkTheme()
  static const Color surfaceContainerHigh         = Color(0xFFE6E9F2);
  static const Color surfaceContainerHighest      = Color(0xFFD9DDEA);
  static const Color surfaceContainerHighDark     = Color(0xFF2B3548);
  static const Color surfaceContainerHighestDark  = Color(0xFF36405A);

  // ─── v11 additions — Status border members ─────────────────
  // (status *base*/*surface*/*text* already existed; *border* was only
  // complete for critical — add success/warning to match colors.md §4)
  static const Color statusSuccessBorder     = Color(0xFFA7F3D0);
  static const Color statusSuccessBorderDark = Color(0xFF065F46);
  static const Color statusWarningBorder     = Color(0xFFFDE68A);
  static const Color statusWarningBorderDark = Color(0xFF78350F);
  // statusCriticalBorder itself predates v11 (see Status section above);
  // it never had a dark pair — add one following the same convention.
  static const Color statusCriticalBorderDark = statusCriticalText; // reuse sibling value, #991B1B

  // ─── v11 additions — Programme "mid" (progress-fill) tones ─
  // dark-mode mid reuses the light-mode *Text tone, same convention
  // ancTextDark/imciTextDark/etc. already use below (reusing a sibling
  // light-mode value rather than minting a new hex).
  static const Color ancMid      = Color(0xFFFBCFE8);
  static const Color ancMidDark  = ancText;
  static const Color imciMid     = Color(0xFFFECACA);
  static const Color imciMidDark = imciText;
  static const Color ncdMid      = Color(0xFFFDE68A);
  static const Color ncdMidDark  = ncdText;
  static const Color tbMid       = Color(0xFFA7F3D0);
  static const Color tbMidDark   = tbText;
  static const Color pncMid      = Color(0xFFDDD6FE);
  static const Color pncMidDark  = pncText;

  // ─── v11 addition — Programme "child" (immunisation) set ────
  // Maps to Programme.epi — design_v11 calls this token "programme.child".
  // No *BorderDark: matches the existing convention where anc/imci/ncd/tb/pnc
  // borders also have no separate dark variant.
  static const Color childText      = Color(0xFF1E40AF);
  static const Color childBorder    = Color(0xFF93C5FD);
  static const Color childSurface   = Color(0xFFEFF6FF);
  static const Color childMid       = Color(0xFFBFDBFE);
  static const Color childTextDark    = childBorder;
  static const Color childSurfaceDark = Color(0xFF172554);
  static const Color childMidDark     = childText;

  // ─── v11 addition — Tag gold ─────────────────────────────────
  static const Color tagGold     = Color(0xFFFFD700);
  static const Color tagGoldDark = tagGold;

  // ─── v11 addition — Scrims ───────────────────────────────────
  // rgba(15,15,30,0.55) / rgba(0,0,0,0.92)
  static const Color scrimDrawer     = Color(0x8C0F0F1E);
  static const Color scrimDrawerDark = Color(0xB30F0F1E); // deepened for dark theme
  static const Color scrimCamera     = Color(0xEB000000);
  static const Color scrimCameraDark = scrimCamera;

  // ─── v11 addition — On-dark alpha ladder (white over navy) ──
  // onDarkLow/onDarkFaint dedupe literals already inline in AppTextStyles
  // below (headerSub/callSub, sectionLabelOnNavy); onDarkDivider reuses
  // borderSoftDark directly (numerically identical, see OnDarkColors).
  static const Color onDarkHigh    = Color(0xE6FFFFFF); // 0.9
  static const Color onDarkMid     = Color(0xBFFFFFFF); // 0.75
  static const Color onDarkLow     = Color(0x99FFFFFF); // 0.6
  static const Color onDarkFaint   = Color(0x80FFFFFF); // 0.5
  static const Color onDarkSurface = Color(0x26FFFFFF); // 0.15

  // ─── v11 addition — Partner (Sukhee teleconsult) ─────────────
  static const Color partnerSukheeBar             = Color(0xFF0F2544);
  static const Color partnerSukheeBarDark         = partnerSukheeBar;
  static const Color partnerSukheeCardStart       = Color(0xFF0D2137);
  static const Color partnerSukheeCardStartDark   = partnerSukheeCardStart;
  static const Color partnerSukheeCardEnd         = Color(0xFF163354);
  static const Color partnerSukheeCardEndDark     = partnerSukheeCardEnd;
  static const Color partnerSukheeCardShimmer     = Color(0xFF1A3F6F);
  static const Color partnerSukheeCardShimmerDark = partnerSukheeCardShimmer;

  // ─── v11 addition — Field-kind legend (form_gallery_screen.dart) ──
  // Distinct hues for the dev-only FieldKind catalog legend; #047857
  // intentionally reuses statusSuccessActionDark rather than duplicating it.
  static const Color fieldKindGreen   = Color(0xFF1D6D2F);
  static const Color fieldKindPurple  = Color(0xFF7B3FA0);
  static const Color fieldKindOrange  = Color(0xFFC2410C);
  static const Color fieldKindBlue    = Color(0xFF0F6CBD);
  static const Color fieldKindRed     = Color(0xFFB91C1C);
  static const Color fieldKindViolet  = Color(0xFF7C3AED);
  static const Color fieldKindAmber   = Color(0xFFB45309);
  static const Color fieldKindIndigo  = Color(0xFF1D4ED8);
  static const Color fieldKindTeal    = Color(0xFF0369A1);
  static const Color fieldKindSlate   = Color(0xFF64748B);

  // ─── household-enrollment merge additions ───────────────────
  // Recurring hardcoded colors found across lib/features/household/enrollment,
  // lib/features/visit/visit_flow_screen.dart, and counselling_screen.dart —
  // named here so they have a single home instead of duplicated literals.
  static const Color enrollmentSuccess     = Color(0xFF14996A); // success-screen hero, NID-scan badge
  static const Color enrollmentSuccessDark = Color(0xFF34D399);
  static const Color infoAccent     = Color(0xFF3B82F6); // "existing patient" info banner border
  static const Color infoAccentDark = Color(0xFF1D4ED8); // ...and its icon/text tone
  static const Color infoAccentDarkDark = Color(0xFF60A5FA);
  static const Color warningBorderAlt     = Color(0xFFFED7AA); // human-review / Bangla-name banners
  static const Color warningBorderAltDark = Color(0xFF9A3412);
  static const Color warningTextAlt       = Color(0xFF9A3412);
  static const Color warningTextAltDark   = Color(0xFFFDBA74);
  static const Color followUpIconBg     = Color(0xFFE0E7FF); // NABA follow-up icon tile
  static const Color followUpIconBgDark = Color(0xFF312E81);
  static const Color followUpIconFg     = Color(0xFF4338CA);
  static const Color followUpIconFgDark = Color(0xFFA5B4FC);
  // WhatsApp-preview screen chrome — mimics the real WhatsApp app palette,
  // deliberately distinct from AppColors.whatsapp/waHeader (the in-app accent).
  static const Color whatsappPreviewHeader = Color(0xFF075E54);
  static const Color whatsappPreviewBubble = Color(0xFFDCF8C6);

  // ─── v13 Dashboard / AI Worklist additions ──────────────────
  // v13 updated --pink to #EC4899 (FAB, village tab active underline).
  // Existing AppColors.pink (#E8356D) is retained for all pre-v13 screens;
  // use pinkWorklist for the dashboard FAB and village chip indicator.
  static const Color pinkWorklist     = Color(0xFFEC4899);
  static const Color pinkWorklistDark = Color(0xFFEC4899);

  // Category filter bubble surfaces — lighter/distinct from status palette:
  static const Color catHighriskSurface  = Color(0xFFFEF2F2); // lighter than statusCriticalSurface
  static const Color catChildSurface     = Color(0xFFFFFBEB); // yellow-50
  static const Color catNcdBorder        = Color(0xFF0D9488); // teal-600
  static const Color catNcdSurface       = Color(0xFFF0FDFA); // teal-50
  static const Color catMissedSurface    = Color(0xFFF9FAFB); // gray-50
  static const Color catReferralBorder   = Color(0xFF8B5CF6); // violet-500
  static const Color catHomeSurface      = Color(0xFFECFDF5); // green-50
  static const Color catFacilityBorder   = Color(0xFF6366F1); // indigo-500
  static const Color catFacilitySurface  = Color(0xFFEEF2FF); // indigo-50

  // Referral alert strip (dashboard urgent banner):
  static const Color referralAlertBg     = Color(0xFFDC2626); // explicit #DC2626 from v13
  static const Color referralAlertBgDark = Color(0xFFB91C1C);

  // QR search result card accent:
  static const Color qrResultBorder     = aiPurple;
  static const Color qrResultShadow     = Color(0x26633BD4); // rgba(107,99,212,0.15)

  // Lock screen offline indicator — v13 spec amber, deliberately distinct
  // from statusWarning (#F59E0B); do not collapse the two.
  static const Color lockOfflineIndicator = Color(0xFFFBBF24);

  // Dashboard referral-banner pulse dot — no other consumer of this hex.
  static const Color referralPulseDot = Color(0xFFFEF08A);
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

  /// Bottom-list clearance so content isn't hidden behind a sticky bottom
  /// action bar. Not part of the 4-pt rhythm above (it's a layout-contract
  /// value driven by the sticky bar's own height, not a spacing rung) —
  /// named separately so it has one home instead of a repeated literal
  /// across the household-enrollment screens.
  static const double stickyBarClearance = 96.0;
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
  static const double fabPill  = 28.0;  // dashboard "+ Enrol new" extended FAB
  static const double waIcon   =  7.0;  // .wa-icon
  static const double full     = 999.0; // full circle (avatars, FAB, chat-send)

  // Lock screen — no v13/v5 CSS source, promoted from lock_screen.dart's
  // existing inline literals so they have one named home:
  static const double avatarLarge = 26.0; // Lock screen app-icon avatar box
  static const double profileCard = 18.0; // Lock screen SK identity card
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

  /// Household card (v13 `renderHouseholds` card): 0 1px 6px rgba(0,0,0,0.06).
  /// Distinct from [card] — same alpha, tighter blur/offset.
  static const List<BoxShadow> householdCard = [
    BoxShadow(color: Color(0x0F000000), blurRadius: 6, offset: Offset(0, 1)),
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

  /// Lock screen SK identity card — no v13/v5 CSS source, promoted from
  /// lock_screen.dart's existing inline literal: 0 4px 16px rgba(27,43,94,0.07)
  static const List<BoxShadow> profileCard = [
    BoxShadow(color: Color(0x121B2B5E), blurRadius: 16, offset: Offset(0, 4)),
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

  // v11 additions — durations missing from the original extraction
  static const Duration control     = Duration(milliseconds: 150);
  static const Duration sheet       = Duration(milliseconds: 300);
  static const Duration state       = Duration(milliseconds: 400);
  static const Duration hero        = Duration(milliseconds: 600);
  static const Duration sweep       = Duration(milliseconds: 900);
  static const Duration blink       = Duration(milliseconds: 1000);
  // notifBadgePulse keyframe half-cycle — repeat(reverse:true) doubles this
  // to the full 2s pulse (0%→50%→100%), peak scale at the 1s midpoint.
  static const Duration badgePulse  = Duration(milliseconds: 1000);
  static const Duration pulseSlow   = Duration(milliseconds: 1200);
  static const Duration scan        = Duration(milliseconds: 1500);
  static const Duration shimmer     = Duration(milliseconds: 3000);
  static const Duration splashHold  = Duration(milliseconds: 3200);

  // Curves
  static const Curve standard = Curves.ease;
  static const Curve gentle   = Curves.easeInOut;
  static const Curve easeOut  = Curves.easeOut;
  // cubic-bezier(0.34, 1.56, 0.64, 1) — spring overshoot for verify bounce
  static const Curve spring   = Cubic(0.34, 1.56, 0.64, 1.0);
  // cubic-bezier(0.34, 1.15, 0.64, 1) — softened spring for sheet/drawer slide-in
  static const Curve sheetSpring = Cubic(0.34, 1.15, 0.64, 1.0);
  static const Curve linear      = Curves.linear;
}

// ═══════════════════════════════════════════════════════════════
// FONTS
// Single source of truth for font family names. Use AppFonts.display
// and AppFonts.body everywhere instead of bare string literals.
// ═══════════════════════════════════════════════════════════════

abstract final class AppFonts {
  static const String display = 'Nunito';
  static const String body    = 'NunitoSans';
}

// ═══════════════════════════════════════════════════════════════
// TEXT STYLES
// Named semantic styles that directly match the HTML design.
// Use these in widgets instead of Theme.of(context).textTheme.*
// where an exact HTML match is required (e.g. section-label, score pill).
// ═══════════════════════════════════════════════════════════════

abstract final class AppTextStyles {
  AppTextStyles._();

  // Every style below carries fontFamilyFallback: ['NotoSansBengali'] so
  // mixed Bangla/Latin strings resolve per-glyph (design_v11 typography.md
  // §3 rule 1). No Bengali font asset ships yet — Flutter silently skips
  // an unregistered fallback family, so this is safe to land ahead of the
  // asset. TODO(design-v11): register NotoSansBengali in pubspec.yaml
  // fonts: once assets/fonts/NotoSansBengali-*.ttf lands.
  static const List<String> _bn = ['NotoSansBengali'];

  // Legibility bump: every fontSize below is ~13-17% larger than the literal
  // HTML/CSS mockup value cited in its own comment (that comment is kept as
  // the original design provenance, not the shipped value). Rounded to the
  // nearest 0.5px so the scale stays on the app's existing half-point grid.

  // ─── Header ────────────────────────────────────────────────
  // .header-title: Nunito 20px w800 white
  static const TextStyle headerTitle = TextStyle(
    fontFamily: AppFonts.display, fontFamilyFallback: _bn, fontSize: 20, fontWeight: FontWeight.w800,
    color: Colors.white,
  );
  // .header-sub: NunitoSans 12px rgba(255,255,255,0.6)
  static const TextStyle headerSub = TextStyle(
    fontFamily: AppFonts.body, fontFamilyFallback: _bn, fontSize: 13, fontWeight: FontWeight.w400,
    color: AppColors.onDarkLow,
  );

  // Household list/detail navy headers: same size as headerTitle/headerSub
  // but one weight lighter (w700 vs w800) — a deliberate, explicit choice for
  // this feature area, not a duplicate of the dashboard's own header tokens.
  static const TextStyle householdHeaderTitle = TextStyle(
    fontFamily: AppFonts.display, fontFamilyFallback: _bn, fontSize: 20, fontWeight: FontWeight.w700,
    color: Colors.white,
  );
  static const TextStyle householdHeaderSub = TextStyle(
    fontFamily: AppFonts.body, fontFamilyFallback: _bn, fontSize: 13, fontWeight: FontWeight.w400,
    color: AppColors.onDarkLow,
  );

  // ─── Body / content ────────────────────────────────────────
  // default body: NunitoSans 13px w400 --text
  static const TextStyle body = TextStyle(
    fontFamily: AppFonts.body, fontFamilyFallback: _bn, fontSize: 15, fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );
  // .patient-name: NunitoSans 14px w700
  static const TextStyle listTitle = TextStyle(
    fontFamily: AppFonts.body, fontFamilyFallback: _bn, fontSize: 16, fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );
  // .patient-meta, sub-text: NunitoSans 11px --muted
  static const TextStyle subText = TextStyle(
    fontFamily: AppFonts.body, fontFamilyFallback: _bn, fontSize: 12.5, fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
  );

  // ─── Section labels ────────────────────────────────────────
  // .section-label, .ai-label: NunitoSans 11px w700 uppercase ls0.07em --muted
  static const TextStyle sectionLabel = TextStyle(
    fontFamily: AppFonts.body, fontFamilyFallback: _bn, fontSize: 12.5, fontWeight: FontWeight.w700,
    color: AppColors.textMuted,
    letterSpacing: 0.77, // 0.07em × 11px (original mockup size, kept as-is)
  );
  // Uppercase variant (text-transform applied at call site via toUpperCase())
  static const TextStyle sectionLabelOnNavy = TextStyle(
    fontFamily: AppFonts.body, fontFamilyFallback: _bn, fontSize: 11.5, fontWeight: FontWeight.w700,
    color: AppColors.onDarkFaint, // rgba(255,255,255,0.5)
    letterSpacing: 0.80, // 0.08em × 10px (original mockup size, kept as-is)
  );

  // ─── Stats & vitals ────────────────────────────────────────
  // .stat-num: Nunito 22px w800 --navy
  static const TextStyle statNumber = TextStyle(
    fontFamily: AppFonts.display, fontFamilyFallback: _bn, fontSize: 25.5, fontWeight: FontWeight.w800,
    color: AppColors.navy,
  );
  // .stat-lbl: NunitoSans 10px --muted
  static const TextStyle statLabel = TextStyle(
    fontFamily: AppFonts.body, fontFamilyFallback: _bn, fontSize: 11.5, fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
  );
  // .vital-val: Nunito 24px w800 --text
  static const TextStyle vitalValue = TextStyle(
    fontFamily: AppFonts.display, fontFamilyFallback: _bn, fontSize: 27.5, fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
  );
  // .vital-lbl: NunitoSans 10px w700 uppercase ls0.05em --muted
  static const TextStyle vitalLabel = TextStyle(
    fontFamily: AppFonts.body, fontFamilyFallback: _bn, fontSize: 11.5, fontWeight: FontWeight.w700,
    color: AppColors.textMuted, letterSpacing: 0.50,
  );
  // .vital-unit: NunitoSans 12px w400 --muted
  static const TextStyle vitalUnit = TextStyle(
    fontFamily: AppFonts.body, fontFamilyFallback: _bn, fontSize: 14, fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
  );

  // ─── Score / tag pills ─────────────────────────────────────
  // .score-pill, .tag: Nunito 11px w800
  static const TextStyle scorePill = TextStyle(
    fontFamily: AppFonts.display, fontFamilyFallback: _bn, fontSize: 12.5, fontWeight: FontWeight.w800,
  );
  // .chip: NunitoSans 12px w600
  static const TextStyle chip = TextStyle(
    fontFamily: AppFonts.body, fontFamilyFallback: _bn, fontSize: 14, fontWeight: FontWeight.w600,
  );

  // ─── AI cards ──────────────────────────────────────────────
  // .ai-title: Nunito 18px w800 --navy
  static const TextStyle aiTitle = TextStyle(
    fontFamily: AppFonts.display, fontFamilyFallback: _bn, fontSize: 20.5, fontWeight: FontWeight.w800,
    color: AppColors.navy,
  );
  // .ai-label: NunitoSans 11px w700 uppercase ls0.06em --purple
  static const TextStyle aiLabel = TextStyle(
    fontFamily: AppFonts.body, fontFamilyFallback: _bn, fontSize: 12.5, fontWeight: FontWeight.w700,
    color: AppColors.aiPurple, letterSpacing: 0.66,
  );
  // .ai-sub: NunitoSans 12px w400 --muted
  static const TextStyle aiSub = TextStyle(
    fontFamily: AppFonts.body, fontFamilyFallback: _bn, fontSize: 14, fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
  );

  // ─── Telecall ──────────────────────────────────────────────
  // .call-timer: Nunito 32px w800 white ls2px
  static const TextStyle callTimer = TextStyle(
    fontFamily: AppFonts.display, fontFamilyFallback: _bn, fontSize: 37, fontWeight: FontWeight.w800,
    color: Colors.white, letterSpacing: 2,
  );
  // .call-name: Nunito 16px w800 white
  static const TextStyle callName = TextStyle(
    fontFamily: AppFonts.display, fontFamilyFallback: _bn, fontSize: 18.5, fontWeight: FontWeight.w800,
    color: Colors.white,
  );
  // .call-sub: NunitoSans 12px rgba(255,255,255,0.6)
  static const TextStyle callSub = TextStyle(
    fontFamily: AppFonts.body, fontFamilyFallback: _bn, fontSize: 14, fontWeight: FontWeight.w400,
    color: AppColors.onDarkLow,
  );

  // ─── Navigation ────────────────────────────────────────────
  // .nav-tab-lbl: NunitoSans 10px w600 --muted
  static const TextStyle navTabLabel = TextStyle(
    fontFamily: AppFonts.body, fontFamilyFallback: _bn, fontSize: 11.5, fontWeight: FontWeight.w600,
    color: AppColors.textMuted,
  );

  // ─── Diagnosis / step ──────────────────────────────────────
  // .diag-title: Nunito 16px w800
  static const TextStyle diagTitle = TextStyle(
    fontFamily: AppFonts.display, fontFamilyFallback: _bn, fontSize: 18.5, fontWeight: FontWeight.w800,
  );
  // .diag-body: NunitoSans 12px ls1.6 #4B5563
  static const TextStyle diagBody = TextStyle(
    fontFamily: AppFonts.body, fontFamilyFallback: _bn, fontSize: 14, fontWeight: FontWeight.w400,
    color: AppColors.textMid, height: 1.6,
  );
  // .step-text: NunitoSans 13px ls1.5 --text
  static const TextStyle stepText = TextStyle(
    fontFamily: AppFonts.body, fontFamilyFallback: _bn, fontSize: 15, fontWeight: FontWeight.w400,
    color: AppColors.textPrimary, height: 1.5,
  );

  // ─── Micro badges ──────────────────────────────────────────
  /// 9px tag/severity-badge text found in a few household-enrollment and
  /// visit-flow spots. design_v11's accessibility spec (accessibility.md
  /// §Type sizes) bans anything below 10px on new screens — this exists
  /// only so the existing 9px usages have a named home instead of a bare
  /// literal; do not use it in new code, use [scorePill]/[chip] instead.
  static const TextStyle microTag = TextStyle(
    fontFamily: AppFonts.display, fontFamilyFallback: _bn, fontSize: 10.5, fontWeight: FontWeight.w800,
  );

  // ─── v13 Dashboard / AI Worklist text styles ───────────────
  // Legibility bump over the literal .patient-name spec (13.5px) — CHWs
  // read these outdoors on varied devices; restored after a pixel-match
  // pass briefly shrank it back to the literal mockup size.
  static const TextStyle worklistPatientName = TextStyle(
    fontFamily: AppFonts.display, fontFamilyFallback: _bn, fontSize: 15.5, fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
  );
  // .patient-meta age row: legibility-bumped size; w800 matches spec exactly
  // (was w700, a pixel mismatch — also was previously unwired dead code,
  // now actually referenced by mission_queue_card.dart's age text).
  static const TextStyle worklistPatientMeta = TextStyle(
    fontFamily: AppFonts.body, fontFamilyFallback: _bn, fontSize: 13, fontWeight: FontWeight.w800,
    color: Color(0xFF111827),
  );
  // .worklist-row-label: legibility-bumped over the literal 13.5px spec.
  static const TextStyle worklistRowLabel = TextStyle(
    fontFamily: AppFonts.display, fontFamilyFallback: _bn, fontSize: 15.5, fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
  );
  // .v-status status pill: legibility-bumped over the literal 10px spec.
  static const TextStyle worklistStatusPill = TextStyle(
    fontFamily: AppFonts.body, fontFamilyFallback: _bn, fontSize: 12.5, fontWeight: FontWeight.w800,
  );
  // .cat-bubble label: NunitoSans 9.5px w700 #6B7280
  static const TextStyle categoryBubbleLabel = TextStyle(
    fontFamily: AppFonts.body, fontFamilyFallback: _bn, fontSize: 11, fontWeight: FontWeight.w700,
    color: AppColors.textMuted,
  );
  // Village tab: legibility-bumped over the literal 13px spec.
  static const TextStyle villageTab = TextStyle(
    fontFamily: AppFonts.body, fontFamilyFallback: _bn, fontSize: 15, fontWeight: FontWeight.w700,
  );
  // Worklist card address line — legibility-bumped size/weight (w600, not
  // the spec's plain w400 — lighter text is harder to read outdoors). No
  // baked-in color (like [worklistStatusPill]) — caller supplies the
  // theme-aware muted color.
  static const TextStyle worklistAddress = TextStyle(
    fontFamily: AppFonts.body, fontFamilyFallback: _bn, fontSize: 14, fontWeight: FontWeight.w600,
  );
  // Worklist card phone line — legibility-bumped over the literal 11.5px spec.
  static const TextStyle worklistPhone = TextStyle(
    fontFamily: AppFonts.body, fontFamilyFallback: _bn, fontSize: 13, fontWeight: FontWeight.w400,
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
    @Deprecated('Use AiColors.primary instead — kept for ai_brief_card.dart, '
        'mission_dashboard_screen.dart, patient_context_screen.dart until migrated')
    required this.aiPurple,
    @Deprecated('Use AiColors.primaryDeep instead — kept for patient_context_screen.dart until migrated')
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
    @Deprecated('Use PartnerColors.whatsapp instead — kept for referral_list_screen.dart until migrated')
    required this.whatsapp,
    @Deprecated('Use PartnerColors.sukheeStart instead — no outside consumers, kept for uniformity')
    required this.sukheeGradientStart,
    @Deprecated('Use PartnerColors.sukheeEnd instead — no outside consumers, kept for uniformity')
    required this.sukheeGradientEnd,
    required this.textStrong,
    required this.textMid,
    required this.textDisabled,
    required this.borderDefault,
    required this.borderDashed,
    required this.surfaceTrack,
    required this.surfaceChat,
    required this.brandAccentDeep,
    required this.statusSuccessText,
    required this.statusWarningText,
    required this.statusCriticalText,
    required this.statusInfoText,
    required this.statusSuccessBorder,
    required this.statusWarningBorder,
    required this.statusCriticalBorder,
    required this.statusSuccessAction,
    required this.statusSuccessActionPressed,
    required this.tagBlueSurface,
    required this.tagBlueText,
    required this.tagTealSurface,
    required this.tagTealText,
    required this.tagGold,
    required this.scrimDrawer,
    required this.scrimCamera,
  });

  final Color brandNavy;
  final Color brandNavyDark;
  final Color brandPink;
  final Color brandPinkDark;
  @Deprecated('Use AiColors.primary instead')
  final Color aiPurple;
  @Deprecated('Use AiColors.primaryDeep instead')
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
  @Deprecated('Use PartnerColors.whatsapp instead')
  final Color whatsapp;
  @Deprecated('Use PartnerColors.sukheeStart instead')
  final Color sukheeGradientStart;
  @Deprecated('Use PartnerColors.sukheeEnd instead')
  final Color sukheeGradientEnd;
  final Color textStrong;
  final Color textMid;
  final Color textDisabled;
  final Color borderDefault;
  final Color borderDashed;
  final Color surfaceTrack;
  final Color surfaceChat;
  final Color brandAccentDeep;
  final Color statusSuccessText;
  final Color statusWarningText;
  final Color statusCriticalText;
  final Color statusInfoText;
  final Color statusSuccessBorder;
  final Color statusWarningBorder;
  final Color statusCriticalBorder;
  final Color statusSuccessAction;
  final Color statusSuccessActionPressed;
  final Color tagBlueSurface;
  final Color tagBlueText;
  final Color tagTealSurface;
  final Color tagTealText;
  final Color tagGold;
  final Color scrimDrawer;
  final Color scrimCamera;

  /// Border-radius scale (mirrors [AppRadius]).
  static const double radiusSm = AppRadius.button;   // 12
  static const double radiusMd = AppRadius.patRow;   // 14
  static const double radiusLg = AppRadius.card;     // 16
  static const double radiusXl = AppRadius.xl;       // 24

  static const List<BoxShadow> cardShadow = AppShadows.card;

  // ignore: deprecated_member_use_from_same_package
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
    textStrong: AppColors.textStrong,
    textMid: AppColors.textMid,
    textDisabled: AppColors.textDisabled,
    borderDefault: AppColors.border,
    borderDashed: AppColors.borderDashed,
    surfaceTrack: AppColors.progressTrack,
    surfaceChat: AppColors.chatBg,
    brandAccentDeep: AppColors.brandAccentDeep,
    statusSuccessText: AppColors.statusSuccessText,
    statusWarningText: AppColors.statusWarningText,
    statusCriticalText: AppColors.statusCriticalText,
    statusInfoText: AppColors.statusInfoText,
    statusSuccessBorder: AppColors.statusSuccessBorder,
    statusWarningBorder: AppColors.statusWarningBorder,
    statusCriticalBorder: AppColors.statusCriticalBorder,
    statusSuccessAction: AppColors.statusSuccessAction,
    statusSuccessActionPressed: AppColors.statusSuccessActionDark,
    tagBlueSurface: AppColors.tagBlueSurface,
    tagBlueText: AppColors.tagBlueText,
    tagTealSurface: AppColors.tagTealSurface,
    tagTealText: AppColors.tagTealText,
    tagGold: AppColors.tagGold,
    scrimDrawer: AppColors.scrimDrawer,
    scrimCamera: AppColors.scrimCamera,
  );

  // ignore: deprecated_member_use_from_same_package
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
    textStrong: AppColors.textPrimaryDark,
    textMid: AppColors.textMutedDark,
    textDisabled: AppColors.textDisabledDark,
    borderDefault: AppColors.borderDark,
    borderDashed: AppColors.borderDashedDark,
    surfaceTrack: AppColors.cardSurfaceMutedDark,
    surfaceChat: AppColors.cardSurfaceMutedDark,
    brandAccentDeep: AppColors.brandAccentDeepDark,
    statusSuccessText: AppColors.statusSuccessDark,
    statusWarningText: AppColors.statusWarningDark,
    statusCriticalText: AppColors.statusCriticalDark,
    statusInfoText: AppColors.statusInfoDark,
    statusSuccessBorder: AppColors.statusSuccessBorderDark,
    statusWarningBorder: AppColors.statusWarningBorderDark,
    statusCriticalBorder: AppColors.statusCriticalBorderDark,
    statusSuccessAction: AppColors.statusSuccessActionDark,
    statusSuccessActionPressed: AppColors.statusSuccessAction,
    tagBlueSurface: AppColors.tagBlueSurface,
    tagBlueText: AppColors.tagBlueText,
    tagTealSurface: AppColors.tagTealSurface,
    tagTealText: AppColors.tagTealText,
    tagGold: AppColors.tagGoldDark,
    scrimDrawer: AppColors.scrimDrawerDark,
    scrimCamera: AppColors.scrimCameraDark,
  );

  @override
  // ignore: deprecated_member_use_from_same_package
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
    Color? textStrong, Color? textMid, Color? textDisabled,
    Color? borderDefault, Color? borderDashed,
    Color? surfaceTrack, Color? surfaceChat, Color? brandAccentDeep,
    Color? statusSuccessText, Color? statusWarningText,
    Color? statusCriticalText, Color? statusInfoText,
    Color? statusSuccessBorder, Color? statusWarningBorder,
    Color? statusCriticalBorder,
    Color? statusSuccessAction, Color? statusSuccessActionPressed,
    Color? tagBlueSurface, Color? tagBlueText,
    Color? tagTealSurface, Color? tagTealText, Color? tagGold,
    Color? scrimDrawer, Color? scrimCamera,
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
    textStrong: textStrong ?? this.textStrong,
    textMid: textMid ?? this.textMid,
    textDisabled: textDisabled ?? this.textDisabled,
    borderDefault: borderDefault ?? this.borderDefault,
    borderDashed: borderDashed ?? this.borderDashed,
    surfaceTrack: surfaceTrack ?? this.surfaceTrack,
    surfaceChat: surfaceChat ?? this.surfaceChat,
    brandAccentDeep: brandAccentDeep ?? this.brandAccentDeep,
    statusSuccessText: statusSuccessText ?? this.statusSuccessText,
    statusWarningText: statusWarningText ?? this.statusWarningText,
    statusCriticalText: statusCriticalText ?? this.statusCriticalText,
    statusInfoText: statusInfoText ?? this.statusInfoText,
    statusSuccessBorder: statusSuccessBorder ?? this.statusSuccessBorder,
    statusWarningBorder: statusWarningBorder ?? this.statusWarningBorder,
    statusCriticalBorder: statusCriticalBorder ?? this.statusCriticalBorder,
    statusSuccessAction: statusSuccessAction ?? this.statusSuccessAction,
    statusSuccessActionPressed:
        statusSuccessActionPressed ?? this.statusSuccessActionPressed,
    tagBlueSurface: tagBlueSurface ?? this.tagBlueSurface,
    tagBlueText: tagBlueText ?? this.tagBlueText,
    tagTealSurface: tagTealSurface ?? this.tagTealSurface,
    tagTealText: tagTealText ?? this.tagTealText,
    tagGold: tagGold ?? this.tagGold,
    scrimDrawer: scrimDrawer ?? this.scrimDrawer,
    scrimCamera: scrimCamera ?? this.scrimCamera,
  );

  @override
  // ignore: deprecated_member_use_from_same_package
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
      textStrong: Color.lerp(textStrong, other.textStrong, t)!,
      textMid: Color.lerp(textMid, other.textMid, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      borderDefault: Color.lerp(borderDefault, other.borderDefault, t)!,
      borderDashed: Color.lerp(borderDashed, other.borderDashed, t)!,
      surfaceTrack: Color.lerp(surfaceTrack, other.surfaceTrack, t)!,
      surfaceChat: Color.lerp(surfaceChat, other.surfaceChat, t)!,
      brandAccentDeep: Color.lerp(brandAccentDeep, other.brandAccentDeep, t)!,
      statusSuccessText: Color.lerp(statusSuccessText, other.statusSuccessText, t)!,
      statusWarningText: Color.lerp(statusWarningText, other.statusWarningText, t)!,
      statusCriticalText: Color.lerp(statusCriticalText, other.statusCriticalText, t)!,
      statusInfoText: Color.lerp(statusInfoText, other.statusInfoText, t)!,
      statusSuccessBorder: Color.lerp(statusSuccessBorder, other.statusSuccessBorder, t)!,
      statusWarningBorder: Color.lerp(statusWarningBorder, other.statusWarningBorder, t)!,
      statusCriticalBorder: Color.lerp(statusCriticalBorder, other.statusCriticalBorder, t)!,
      statusSuccessAction: Color.lerp(statusSuccessAction, other.statusSuccessAction, t)!,
      statusSuccessActionPressed: Color.lerp(
          statusSuccessActionPressed, other.statusSuccessActionPressed, t)!,
      tagBlueSurface: Color.lerp(tagBlueSurface, other.tagBlueSurface, t)!,
      tagBlueText: Color.lerp(tagBlueText, other.tagBlueText, t)!,
      tagTealSurface: Color.lerp(tagTealSurface, other.tagTealSurface, t)!,
      tagTealText: Color.lerp(tagTealText, other.tagTealText, t)!,
      tagGold: Color.lerp(tagGold, other.tagGold, t)!,
      scrimDrawer: Color.lerp(scrimDrawer, other.scrimDrawer, t)!,
      scrimCamera: Color.lerp(scrimCamera, other.scrimCamera, t)!,
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
    required this.child, required this.childContainer,
    required this.imciBorder, required this.imciMid, required this.imciHeaderDark,
    required this.ancBorder, required this.ancMid, required this.ancHeaderDark,
    required this.ncdBorder, required this.ncdMid, required this.ncdHeaderDark,
    required this.tbBorder, required this.tbMid, required this.tbHeaderDark,
    required this.pncBorder, required this.pncMid, required this.pncHeaderDark,
    required this.childBorder, required this.childMid, required this.childHeaderDark,
  });

  final Color imci; final Color imciContainer;
  final Color anc;  final Color ancContainer;
  final Color ncd;  final Color ncdContainer;
  final Color tb;   final Color tbContainer;
  final Color pnc;  final Color pncContainer;
  /// Maps to [Programme.epi] (immunisation) — design_v11 calls this
  /// token set "programme.child".
  final Color child; final Color childContainer;

  final Color imciBorder; final Color imciMid; final Color imciHeaderDark;
  final Color ancBorder;  final Color ancMid;  final Color ancHeaderDark;
  final Color ncdBorder;  final Color ncdMid;  final Color ncdHeaderDark;
  final Color tbBorder;   final Color tbMid;   final Color tbHeaderDark;
  final Color pncBorder;  final Color pncMid;  final Color pncHeaderDark;
  final Color childBorder; final Color childMid; final Color childHeaderDark;

  Color of(Programme p) {
    switch (p) {
      case Programme.imci: return imci;
      case Programme.anc:  return anc;
      case Programme.pnc:  return pnc;
      case Programme.ncd:  return ncd;
      case Programme.tb:   return tb;
      case Programme.epi:  return child;
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
      case Programme.epi:  return childContainer;
      default:             return ncdContainer;
    }
  }

  /// Progress-fill tone (mid saturation between [of] and [containerOf]).
  Color midOf(Programme p) {
    switch (p) {
      case Programme.imci: return imciMid;
      case Programme.anc:  return ancMid;
      case Programme.pnc:  return pncMid;
      case Programme.ncd:  return ncdMid;
      case Programme.tb:   return tbMid;
      case Programme.epi:  return childMid;
      default:             return ncdMid;
    }
  }

  /// Border tone matching [of]'s surface family.
  Color borderOf(Programme p) {
    switch (p) {
      case Programme.imci: return imciBorder;
      case Programme.anc:  return ancBorder;
      case Programme.pnc:  return pncBorder;
      case Programme.ncd:  return ncdBorder;
      case Programme.tb:   return tbBorder;
      case Programme.epi:  return childBorder;
      default:             return ncdBorder;
    }
  }

  /// Dark background for the programme-tinted AppBar variant
  /// (visit-screen headers). PNC/child have no v11-sourced override —
  /// both fall back to the brand default [AppColors.navy], which is
  /// also what those screens render today (no override exists yet).
  Color headerDarkOf(Programme p) {
    switch (p) {
      case Programme.imci: return imciHeaderDark;
      case Programme.anc:  return ancHeaderDark;
      case Programme.pnc:  return pncHeaderDark;
      case Programme.ncd:  return ncdHeaderDark;
      case Programme.tb:   return tbHeaderDark;
      case Programme.epi:  return childHeaderDark;
      default:             return ncdHeaderDark;
    }
  }

  static const ProgrammeColors light = ProgrammeColors(
    imci: AppColors.imciText,   imciContainer: AppColors.imciSurface,
    anc:  AppColors.ancText,    ancContainer:  AppColors.ancSurface,
    ncd:  AppColors.ncdText,    ncdContainer:  AppColors.ncdSurface,
    tb:   AppColors.tbText,     tbContainer:   AppColors.tbSurface,
    pnc:  AppColors.pncText,    pncContainer:  AppColors.pncSurface,
    child: AppColors.childText, childContainer: AppColors.childSurface,
    imciBorder: AppColors.imciBorder, imciMid: AppColors.imciMid, imciHeaderDark: AppColors.imciHeader,
    ancBorder:  AppColors.ancBorder,  ancMid:  AppColors.ancMid,  ancHeaderDark:  AppColors.ancHeader,
    ncdBorder:  AppColors.ncdBorder,  ncdMid:  AppColors.ncdMid,  ncdHeaderDark:  AppColors.ncdHeader,
    tbBorder:   AppColors.tbBorder,   tbMid:   AppColors.tbMid,   tbHeaderDark:   AppColors.tbHeader,
    pncBorder:  AppColors.pncBorder,  pncMid:  AppColors.pncMid,  pncHeaderDark:  AppColors.navy,
    childBorder: AppColors.childBorder, childMid: AppColors.childMid, childHeaderDark: AppColors.navy,
  );

  static const ProgrammeColors dark = ProgrammeColors(
    imci: AppColors.imciTextDark, imciContainer: AppColors.imciSurfaceDark,
    anc:  AppColors.ancTextDark,  ancContainer:  AppColors.ancSurfaceDark,
    ncd:  AppColors.ncdTextDark,  ncdContainer:  AppColors.ncdSurfaceDark,
    tb:   AppColors.tbTextDark,   tbContainer:   AppColors.tbSurfaceDark,
    pnc:  AppColors.pncTextDark,  pncContainer:  AppColors.pncSurfaceDark,
    child: AppColors.childTextDark, childContainer: AppColors.childSurfaceDark,
    // Border/headerDark are fixed brand tones — identical across brightness,
    // same treatment as OnDarkColors/MotionTheme (see their doc comments).
    imciBorder: AppColors.imciBorder, imciMid: AppColors.imciMidDark, imciHeaderDark: AppColors.imciHeader,
    ancBorder:  AppColors.ancBorder,  ancMid:  AppColors.ancMidDark,  ancHeaderDark:  AppColors.ancHeader,
    ncdBorder:  AppColors.ncdBorder,  ncdMid:  AppColors.ncdMidDark,  ncdHeaderDark:  AppColors.ncdHeader,
    tbBorder:   AppColors.tbBorder,   tbMid:   AppColors.tbMidDark,   tbHeaderDark:   AppColors.tbHeader,
    pncBorder:  AppColors.pncBorder,  pncMid:  AppColors.pncMidDark,  pncHeaderDark:  AppColors.navy,
    childBorder: AppColors.childBorder, childMid: AppColors.childMidDark, childHeaderDark: AppColors.navy,
  );

  @override
  ProgrammeColors copyWith({
    Color? imci, Color? imciContainer, Color? anc, Color? ancContainer,
    Color? ncd, Color? ncdContainer, Color? tb, Color? tbContainer,
    Color? pnc, Color? pncContainer, Color? child, Color? childContainer,
    Color? imciBorder, Color? imciMid, Color? imciHeaderDark,
    Color? ancBorder, Color? ancMid, Color? ancHeaderDark,
    Color? ncdBorder, Color? ncdMid, Color? ncdHeaderDark,
    Color? tbBorder, Color? tbMid, Color? tbHeaderDark,
    Color? pncBorder, Color? pncMid, Color? pncHeaderDark,
    Color? childBorder, Color? childMid, Color? childHeaderDark,
  }) => ProgrammeColors(
    imci: imci ?? this.imci, imciContainer: imciContainer ?? this.imciContainer,
    anc:  anc  ?? this.anc,  ancContainer:  ancContainer  ?? this.ancContainer,
    ncd:  ncd  ?? this.ncd,  ncdContainer:  ncdContainer  ?? this.ncdContainer,
    tb:   tb   ?? this.tb,   tbContainer:   tbContainer   ?? this.tbContainer,
    pnc:  pnc  ?? this.pnc,  pncContainer:  pncContainer  ?? this.pncContainer,
    child: child ?? this.child, childContainer: childContainer ?? this.childContainer,
    imciBorder: imciBorder ?? this.imciBorder, imciMid: imciMid ?? this.imciMid,
    imciHeaderDark: imciHeaderDark ?? this.imciHeaderDark,
    ancBorder: ancBorder ?? this.ancBorder, ancMid: ancMid ?? this.ancMid,
    ancHeaderDark: ancHeaderDark ?? this.ancHeaderDark,
    ncdBorder: ncdBorder ?? this.ncdBorder, ncdMid: ncdMid ?? this.ncdMid,
    ncdHeaderDark: ncdHeaderDark ?? this.ncdHeaderDark,
    tbBorder: tbBorder ?? this.tbBorder, tbMid: tbMid ?? this.tbMid,
    tbHeaderDark: tbHeaderDark ?? this.tbHeaderDark,
    pncBorder: pncBorder ?? this.pncBorder, pncMid: pncMid ?? this.pncMid,
    pncHeaderDark: pncHeaderDark ?? this.pncHeaderDark,
    childBorder: childBorder ?? this.childBorder, childMid: childMid ?? this.childMid,
    childHeaderDark: childHeaderDark ?? this.childHeaderDark,
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
      child: Color.lerp(child, other.child, t)!,
      childContainer: Color.lerp(childContainer, other.childContainer, t)!,
      imciBorder: Color.lerp(imciBorder, other.imciBorder, t)!,
      imciMid: Color.lerp(imciMid, other.imciMid, t)!,
      imciHeaderDark: Color.lerp(imciHeaderDark, other.imciHeaderDark, t)!,
      ancBorder: Color.lerp(ancBorder, other.ancBorder, t)!,
      ancMid: Color.lerp(ancMid, other.ancMid, t)!,
      ancHeaderDark: Color.lerp(ancHeaderDark, other.ancHeaderDark, t)!,
      ncdBorder: Color.lerp(ncdBorder, other.ncdBorder, t)!,
      ncdMid: Color.lerp(ncdMid, other.ncdMid, t)!,
      ncdHeaderDark: Color.lerp(ncdHeaderDark, other.ncdHeaderDark, t)!,
      tbBorder: Color.lerp(tbBorder, other.tbBorder, t)!,
      tbMid: Color.lerp(tbMid, other.tbMid, t)!,
      tbHeaderDark: Color.lerp(tbHeaderDark, other.tbHeaderDark, t)!,
      pncBorder: Color.lerp(pncBorder, other.pncBorder, t)!,
      pncMid: Color.lerp(pncMid, other.pncMid, t)!,
      pncHeaderDark: Color.lerp(pncHeaderDark, other.pncHeaderDark, t)!,
      childBorder: Color.lerp(childBorder, other.childBorder, t)!,
      childMid: Color.lerp(childMid, other.childMid, t)!,
      childHeaderDark: Color.lerp(childHeaderDark, other.childHeaderDark, t)!,
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

/// AI-identity tokens — split out of [LeapfrogColors] as the explainability
/// seam. Use via `Theme.of(context).extension<AiColors>()!`.
@immutable
class AiColors extends ThemeExtension<AiColors> {
  const AiColors({
    required this.primary,
    required this.primaryDeep,
    required this.surface,
    required this.surfaceEnd,
    required this.border,
    required this.scribeActiveBorder,
    required this.scribeSurface,
  });

  final Color primary;
  final Color primaryDeep;
  final Color surface;
  final Color surfaceEnd;
  final Color border;
  final Color scribeActiveBorder;
  final Color scribeSurface;

  static const AiColors light = AiColors(
    primary: AppColors.aiPurple,
    primaryDeep: AppColors.aiPurpleDark,
    surface: AppColors.aiSurfaceStart,
    surfaceEnd: AppColors.aiSurfaceEnd,
    border: AppColors.aiBorder,
    scribeActiveBorder: AppColors.aiScribeActiveBorder,
    scribeSurface: AppColors.aiScribeSurface,
  );

  static const AiColors dark = AiColors(
    primary: AppColors.aiPurpleLight,
    primaryDeep: AppColors.aiPurple,
    surface: AppColors.aiSurfaceStartDark,
    surfaceEnd: AppColors.aiSurfaceEndDark,
    border: AppColors.aiBorderDark,
    scribeActiveBorder: AppColors.aiScribeActiveBorderDark,
    scribeSurface: AppColors.aiScribeSurfaceDark,
  );

  @override
  AiColors copyWith({
    Color? primary, Color? primaryDeep, Color? surface, Color? surfaceEnd,
    Color? border, Color? scribeActiveBorder, Color? scribeSurface,
  }) => AiColors(
    primary: primary ?? this.primary,
    primaryDeep: primaryDeep ?? this.primaryDeep,
    surface: surface ?? this.surface,
    surfaceEnd: surfaceEnd ?? this.surfaceEnd,
    border: border ?? this.border,
    scribeActiveBorder: scribeActiveBorder ?? this.scribeActiveBorder,
    scribeSurface: scribeSurface ?? this.scribeSurface,
  );

  @override
  AiColors lerp(ThemeExtension<AiColors>? other, double t) {
    if (other is! AiColors) return this;
    return AiColors(
      primary: Color.lerp(primary, other.primary, t)!,
      primaryDeep: Color.lerp(primaryDeep, other.primaryDeep, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceEnd: Color.lerp(surfaceEnd, other.surfaceEnd, t)!,
      border: Color.lerp(border, other.border, t)!,
      scribeActiveBorder: Color.lerp(scribeActiveBorder, other.scribeActiveBorder, t)!,
      scribeSurface: Color.lerp(scribeSurface, other.scribeSurface, t)!,
    );
  }
}

/// On-dark alpha ladder (white text/surfaces over the navy AppBar chrome).
/// `.light`/`.dark` are identical: the AppBar stays a dark navy tone in both
/// [ThemeData] brightnesses, so the ladder's reference surface doesn't change.
/// Use via `Theme.of(context).extension<OnDarkColors>()!`.
@immutable
class OnDarkColors extends ThemeExtension<OnDarkColors> {
  const OnDarkColors({
    required this.high,
    required this.mid,
    required this.low,
    required this.faint,
    required this.surface,
    required this.divider,
  });

  final Color high;    // 0.9
  final Color mid;     // 0.75
  final Color low;     // 0.6
  final Color faint;   // 0.5
  final Color surface; // 0.15 — ghost-button chrome
  final Color divider; // 0.08 — header row dividers

  static const OnDarkColors light = OnDarkColors(
    high: AppColors.onDarkHigh,
    mid: AppColors.onDarkMid,
    low: AppColors.onDarkLow,
    faint: AppColors.onDarkFaint,
    surface: AppColors.onDarkSurface,
    divider: AppColors.borderSoftDark, // numerically identical to 0.08 white
  );

  static const OnDarkColors dark = light;

  @override
  OnDarkColors copyWith({
    Color? high, Color? mid, Color? low, Color? faint,
    Color? surface, Color? divider,
  }) => OnDarkColors(
    high: high ?? this.high,
    mid: mid ?? this.mid,
    low: low ?? this.low,
    faint: faint ?? this.faint,
    surface: surface ?? this.surface,
    divider: divider ?? this.divider,
  );

  @override
  OnDarkColors lerp(ThemeExtension<OnDarkColors>? other, double t) {
    if (other is! OnDarkColors) return this;
    return OnDarkColors(
      high: Color.lerp(high, other.high, t)!,
      mid: Color.lerp(mid, other.mid, t)!,
      low: Color.lerp(low, other.low, t)!,
      faint: Color.lerp(faint, other.faint, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
    );
  }
}

/// External-partner tokens (WhatsApp counselling, Sukhee teleconsult).
/// Split out of [LeapfrogColors]. Use via
/// `Theme.of(context).extension<PartnerColors>()!`.
@immutable
class PartnerColors extends ThemeExtension<PartnerColors> {
  const PartnerColors({
    required this.whatsapp,
    required this.whatsappSurface,
    required this.whatsappBorder,
    required this.sukheeStart,
    required this.sukheeEnd,
    required this.sukheeBar,
    required this.sukheeCardStart,
    required this.sukheeCardEnd,
    required this.sukheeCardShimmer,
    required this.waHeader,
    required this.sukheeHeader,
  });

  final Color whatsapp;
  final Color whatsappSurface;
  final Color whatsappBorder;
  final Color sukheeStart;
  final Color sukheeEnd;
  final Color sukheeBar;
  final Color sukheeCardStart;
  final Color sukheeCardEnd;
  final Color sukheeCardShimmer;
  final Color waHeader;
  final Color sukheeHeader;

  static const PartnerColors light = PartnerColors(
    whatsapp: AppColors.whatsapp,
    whatsappSurface: AppColors.waBg,
    whatsappBorder: AppColors.waBorder,
    sukheeStart: AppColors.sukheeStart,
    sukheeEnd: AppColors.sukheeEnd,
    sukheeBar: AppColors.partnerSukheeBar,
    sukheeCardStart: AppColors.partnerSukheeCardStart,
    sukheeCardEnd: AppColors.partnerSukheeCardEnd,
    sukheeCardShimmer: AppColors.partnerSukheeCardShimmer,
    waHeader: AppColors.waHeader,
    sukheeHeader: AppColors.sukheeHeader,
  );

  // Partner chrome is a fixed dark-card treatment in both themes today —
  // no v11-sourced light/dark split, same identical-instance treatment
  // as OnDarkColors/MotionTheme.
  static const PartnerColors dark = light;

  @override
  PartnerColors copyWith({
    Color? whatsapp, Color? whatsappSurface, Color? whatsappBorder,
    Color? sukheeStart, Color? sukheeEnd, Color? sukheeBar,
    Color? sukheeCardStart, Color? sukheeCardEnd, Color? sukheeCardShimmer,
    Color? waHeader, Color? sukheeHeader,
  }) => PartnerColors(
    whatsapp: whatsapp ?? this.whatsapp,
    whatsappSurface: whatsappSurface ?? this.whatsappSurface,
    whatsappBorder: whatsappBorder ?? this.whatsappBorder,
    sukheeStart: sukheeStart ?? this.sukheeStart,
    sukheeEnd: sukheeEnd ?? this.sukheeEnd,
    sukheeBar: sukheeBar ?? this.sukheeBar,
    sukheeCardStart: sukheeCardStart ?? this.sukheeCardStart,
    sukheeCardEnd: sukheeCardEnd ?? this.sukheeCardEnd,
    sukheeCardShimmer: sukheeCardShimmer ?? this.sukheeCardShimmer,
    waHeader: waHeader ?? this.waHeader,
    sukheeHeader: sukheeHeader ?? this.sukheeHeader,
  );

  @override
  PartnerColors lerp(ThemeExtension<PartnerColors>? other, double t) {
    if (other is! PartnerColors) return this;
    return PartnerColors(
      whatsapp: Color.lerp(whatsapp, other.whatsapp, t)!,
      whatsappSurface: Color.lerp(whatsappSurface, other.whatsappSurface, t)!,
      whatsappBorder: Color.lerp(whatsappBorder, other.whatsappBorder, t)!,
      sukheeStart: Color.lerp(sukheeStart, other.sukheeStart, t)!,
      sukheeEnd: Color.lerp(sukheeEnd, other.sukheeEnd, t)!,
      sukheeBar: Color.lerp(sukheeBar, other.sukheeBar, t)!,
      sukheeCardStart: Color.lerp(sukheeCardStart, other.sukheeCardStart, t)!,
      sukheeCardEnd: Color.lerp(sukheeCardEnd, other.sukheeCardEnd, t)!,
      sukheeCardShimmer: Color.lerp(sukheeCardShimmer, other.sukheeCardShimmer, t)!,
      waHeader: Color.lerp(waHeader, other.waHeader, t)!,
      sukheeHeader: Color.lerp(sukheeHeader, other.sukheeHeader, t)!,
    );
  }
}

/// Category filter bubble tokens for the AI Worklist (Screen 2, v13).
/// Each of the 9 filter categories has a border accent and a surface tint.
/// Use via `Theme.of(context).extension<WorklistCategoryColors>()!`.
@immutable
class WorklistCategoryColors extends ThemeExtension<WorklistCategoryColors> {
  const WorklistCategoryColors({
    required this.highRiskBorder,  required this.highRiskSurface,
    required this.ancBorder,       required this.ancSurface,
    required this.childBorder,     required this.childSurface,
    required this.ncdBorder,       required this.ncdSurface,
    required this.eyeBorder,       required this.eyeSurface,
    required this.missedBorder,    required this.missedSurface,
    required this.referralBorder,  required this.referralSurface,
    required this.homeBorder,      required this.homeSurface,
    required this.facilityBorder,  required this.facilitySurface,
    required this.villageTabIndicator,
    required this.fabBackground,
    required this.fabShadow,
  });

  final Color highRiskBorder;  final Color highRiskSurface;
  final Color ancBorder;       final Color ancSurface;
  final Color childBorder;     final Color childSurface;
  final Color ncdBorder;       final Color ncdSurface;
  final Color eyeBorder;       final Color eyeSurface;
  final Color missedBorder;    final Color missedSurface;
  final Color referralBorder;  final Color referralSurface;
  final Color homeBorder;      final Color homeSurface;
  final Color facilityBorder;  final Color facilitySurface;

  // Village tab active underline — v13 uses #EC4899 (pinkWorklist).
  final Color villageTabIndicator;
  // Enrol FAB — v13 uses #EC4899 + rgba(232,53,109,0.45) shadow.
  final Color fabBackground;
  final Color fabShadow;

  static const WorklistCategoryColors light = WorklistCategoryColors(
    highRiskBorder:  AppColors.statusCritical,        highRiskSurface:  AppColors.catHighriskSurface,
    ancBorder:       AppColors.pinkWorklist,           ancSurface:       AppColors.ancSurface,
    childBorder:     AppColors.statusWarning,          childSurface:     AppColors.catChildSurface,
    ncdBorder:       AppColors.catNcdBorder,           ncdSurface:       AppColors.catNcdSurface,
    eyeBorder:       AppColors.infoAccent,             eyeSurface:       AppColors.childSurface,
    missedBorder:    AppColors.textMuted,              missedSurface:    AppColors.catMissedSurface,
    referralBorder:  AppColors.catReferralBorder,      referralSurface:  AppColors.pncSurface,
    homeBorder:      AppColors.statusSuccess,          homeSurface:      AppColors.catHomeSurface,
    facilityBorder:  AppColors.catFacilityBorder,      facilitySurface:  AppColors.catFacilitySurface,
    villageTabIndicator: AppColors.pinkWorklist,
    fabBackground:       AppColors.pinkWorklist,
    fabShadow:           Color(0x73E8356D), // rgba(232,53,109,0.45)
  );

  static const WorklistCategoryColors dark = WorklistCategoryColors(
    highRiskBorder:  AppColors.statusCriticalDark,     highRiskSurface:  AppColors.statusCriticalSurfaceDark,
    ancBorder:       AppColors.pinkWorklistDark,        ancSurface:       AppColors.ancSurfaceDark,
    childBorder:     AppColors.statusWarningDark,       childSurface:     AppColors.ncdSurfaceDark,
    ncdBorder:       AppColors.catNcdBorder,            ncdSurface:       AppColors.tbSurfaceDark,
    eyeBorder:       AppColors.infoAccentDarkDark,      eyeSurface:       AppColors.childSurfaceDark,
    missedBorder:    AppColors.textMutedDark,           missedSurface:    AppColors.cardSurfaceMutedDark,
    referralBorder:  AppColors.catReferralBorder,       referralSurface:  AppColors.pncSurfaceDark,
    homeBorder:      AppColors.statusSuccessDark,       homeSurface:      AppColors.statusSuccessSurfaceDark,
    facilityBorder:  AppColors.catFacilityBorder,       facilitySurface:  AppColors.aiSurfaceStartDark,
    villageTabIndicator: AppColors.pinkWorklistDark,
    fabBackground:       AppColors.pinkWorklistDark,
    fabShadow:           Color(0x73E8356D),
  );

  @override
  WorklistCategoryColors copyWith({
    Color? highRiskBorder, Color? highRiskSurface,
    Color? ancBorder, Color? ancSurface,
    Color? childBorder, Color? childSurface,
    Color? ncdBorder, Color? ncdSurface,
    Color? eyeBorder, Color? eyeSurface,
    Color? missedBorder, Color? missedSurface,
    Color? referralBorder, Color? referralSurface,
    Color? homeBorder, Color? homeSurface,
    Color? facilityBorder, Color? facilitySurface,
    Color? villageTabIndicator, Color? fabBackground, Color? fabShadow,
  }) => WorklistCategoryColors(
    highRiskBorder:  highRiskBorder  ?? this.highRiskBorder,
    highRiskSurface: highRiskSurface ?? this.highRiskSurface,
    ancBorder:       ancBorder       ?? this.ancBorder,
    ancSurface:      ancSurface      ?? this.ancSurface,
    childBorder:     childBorder     ?? this.childBorder,
    childSurface:    childSurface    ?? this.childSurface,
    ncdBorder:       ncdBorder       ?? this.ncdBorder,
    ncdSurface:      ncdSurface      ?? this.ncdSurface,
    eyeBorder:       eyeBorder       ?? this.eyeBorder,
    eyeSurface:      eyeSurface      ?? this.eyeSurface,
    missedBorder:    missedBorder    ?? this.missedBorder,
    missedSurface:   missedSurface   ?? this.missedSurface,
    referralBorder:  referralBorder  ?? this.referralBorder,
    referralSurface: referralSurface ?? this.referralSurface,
    homeBorder:      homeBorder      ?? this.homeBorder,
    homeSurface:     homeSurface     ?? this.homeSurface,
    facilityBorder:  facilityBorder  ?? this.facilityBorder,
    facilitySurface: facilitySurface ?? this.facilitySurface,
    villageTabIndicator: villageTabIndicator ?? this.villageTabIndicator,
    fabBackground:   fabBackground   ?? this.fabBackground,
    fabShadow:       fabShadow       ?? this.fabShadow,
  );

  @override
  WorklistCategoryColors lerp(ThemeExtension<WorklistCategoryColors>? other, double t) {
    if (other is! WorklistCategoryColors) return this;
    return WorklistCategoryColors(
      highRiskBorder:  Color.lerp(highRiskBorder,  other.highRiskBorder,  t)!,
      highRiskSurface: Color.lerp(highRiskSurface, other.highRiskSurface, t)!,
      ancBorder:       Color.lerp(ancBorder,       other.ancBorder,       t)!,
      ancSurface:      Color.lerp(ancSurface,      other.ancSurface,      t)!,
      childBorder:     Color.lerp(childBorder,     other.childBorder,     t)!,
      childSurface:    Color.lerp(childSurface,    other.childSurface,    t)!,
      ncdBorder:       Color.lerp(ncdBorder,       other.ncdBorder,       t)!,
      ncdSurface:      Color.lerp(ncdSurface,      other.ncdSurface,      t)!,
      eyeBorder:       Color.lerp(eyeBorder,       other.eyeBorder,       t)!,
      eyeSurface:      Color.lerp(eyeSurface,      other.eyeSurface,      t)!,
      missedBorder:    Color.lerp(missedBorder,    other.missedBorder,    t)!,
      missedSurface:   Color.lerp(missedSurface,   other.missedSurface,   t)!,
      referralBorder:  Color.lerp(referralBorder,  other.referralBorder,  t)!,
      referralSurface: Color.lerp(referralSurface, other.referralSurface, t)!,
      homeBorder:      Color.lerp(homeBorder,      other.homeBorder,      t)!,
      homeSurface:     Color.lerp(homeSurface,     other.homeSurface,     t)!,
      facilityBorder:  Color.lerp(facilityBorder,  other.facilityBorder,  t)!,
      facilitySurface: Color.lerp(facilitySurface, other.facilitySurface, t)!,
      villageTabIndicator: Color.lerp(villageTabIndicator, other.villageTabIndicator, t)!,
      fabBackground:   Color.lerp(fabBackground,   other.fabBackground,   t)!,
      fabShadow:       Color.lerp(fabShadow,       other.fabShadow,       t)!,
    );
  }
}

/// Motion tokens as instance fields (wraps [AppAnimations]). Gives a single
/// seam to later swap in a reduced-motion variant (loops → static); motion
/// has no brightness semantics so `.light`/`.dark` are identical.
/// Use via `Theme.of(context).extension<MotionTheme>()!`.
@immutable
class MotionTheme extends ThemeExtension<MotionTheme> {
  const MotionTheme({
    required this.pressFeedback,
    required this.control,
    required this.screenEnter,
    required this.sheet,
    required this.state,
    required this.verifyBounce,
    required this.hero,
    required this.scanPulse,
    required this.sweep,
    required this.blink,
    required this.pulseSlow,
    required this.scan,
    required this.ripple,
    required this.idleGlow,
    required this.shimmer,
    required this.splashHold,
    required this.staggerStep,
    required this.standard,
    required this.gentle,
    required this.easeOut,
    required this.spring,
    required this.sheetSpring,
    required this.linear,
  });

  final Duration pressFeedback;
  final Duration control;
  final Duration screenEnter;
  final Duration sheet;
  final Duration state;
  final Duration verifyBounce;
  final Duration hero;
  final Duration scanPulse;
  final Duration sweep;
  final Duration blink;
  final Duration pulseSlow;
  final Duration scan;
  final Duration ripple;
  final Duration idleGlow;
  final Duration shimmer;
  final Duration splashHold;
  final Duration staggerStep;
  final Curve standard;
  final Curve gentle;
  final Curve easeOut;
  final Curve spring;
  final Curve sheetSpring;
  final Curve linear;

  static const MotionTheme light = MotionTheme(
    pressFeedback: AppAnimations.pressFeedback,
    control: AppAnimations.control,
    screenEnter: AppAnimations.screenEnter,
    sheet: AppAnimations.sheet,
    state: AppAnimations.state,
    verifyBounce: AppAnimations.verifyBounce,
    hero: AppAnimations.hero,
    scanPulse: AppAnimations.scanPulse,
    sweep: AppAnimations.sweep,
    blink: AppAnimations.blink,
    pulseSlow: AppAnimations.pulseSlow,
    scan: AppAnimations.scan,
    ripple: AppAnimations.ripple,
    idleGlow: AppAnimations.idleGlow,
    shimmer: AppAnimations.shimmer,
    splashHold: AppAnimations.splashHold,
    staggerStep: AppAnimations.staggerStep,
    standard: AppAnimations.standard,
    gentle: AppAnimations.gentle,
    easeOut: AppAnimations.easeOut,
    spring: AppAnimations.spring,
    sheetSpring: AppAnimations.sheetSpring,
    linear: AppAnimations.linear,
  );

  static const MotionTheme dark = light;

  @override
  MotionTheme copyWith({
    Duration? pressFeedback, Duration? control, Duration? screenEnter,
    Duration? sheet, Duration? state, Duration? verifyBounce, Duration? hero,
    Duration? scanPulse, Duration? sweep, Duration? blink, Duration? pulseSlow,
    Duration? scan, Duration? ripple, Duration? idleGlow, Duration? shimmer,
    Duration? splashHold, Duration? staggerStep,
    Curve? standard, Curve? gentle, Curve? easeOut, Curve? spring,
    Curve? sheetSpring, Curve? linear,
  }) => MotionTheme(
    pressFeedback: pressFeedback ?? this.pressFeedback,
    control: control ?? this.control,
    screenEnter: screenEnter ?? this.screenEnter,
    sheet: sheet ?? this.sheet,
    state: state ?? this.state,
    verifyBounce: verifyBounce ?? this.verifyBounce,
    hero: hero ?? this.hero,
    scanPulse: scanPulse ?? this.scanPulse,
    sweep: sweep ?? this.sweep,
    blink: blink ?? this.blink,
    pulseSlow: pulseSlow ?? this.pulseSlow,
    scan: scan ?? this.scan,
    ripple: ripple ?? this.ripple,
    idleGlow: idleGlow ?? this.idleGlow,
    shimmer: shimmer ?? this.shimmer,
    splashHold: splashHold ?? this.splashHold,
    staggerStep: staggerStep ?? this.staggerStep,
    standard: standard ?? this.standard,
    gentle: gentle ?? this.gentle,
    easeOut: easeOut ?? this.easeOut,
    spring: spring ?? this.spring,
    sheetSpring: sheetSpring ?? this.sheetSpring,
    linear: linear ?? this.linear,
  );

  @override
  MotionTheme lerp(ThemeExtension<MotionTheme>? other, double t) {
    // Durations/curves aren't meaningfully lerp-able — step at the midpoint,
    // matching ThemeExtension's documented behavior for non-color fields.
    if (other is! MotionTheme) return this;
    return t < 0.5 ? this : other;
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

  final h = base.apply(fontFamily: AppFonts.display);
  final b = base.apply(fontFamily: AppFonts.body);

  // Bangla fallback on every role — see AppTextStyles._bn for why this is
  // safe to land ahead of the actual font asset.
  const bn = AppTextStyles._bn;

  // Legibility bump: every fontSize below is ~13-17% larger than the raw
  // Material type-scale default, rounded to the nearest 0.5px.
  return base.copyWith(
    // ─── Display — timer, large numbers ────────────────────
    displayLarge:  h.displayLarge?.copyWith(fontSize: 37, fontWeight: FontWeight.w800, fontFamilyFallback: bn),
    displayMedium: h.displayMedium?.copyWith(fontSize: 32, fontWeight: FontWeight.w800, fontFamilyFallback: bn),
    displaySmall:  h.displaySmall?.copyWith(fontSize: 27.5, fontWeight: FontWeight.w800, fontFamilyFallback: bn),
    // ─── Headline — titles, AI card titles, stat numbers ───
    headlineLarge:  h.headlineLarge?.copyWith(fontSize: 25.5, fontWeight: FontWeight.w800, fontFamilyFallback: bn),
    headlineMedium: h.headlineMedium?.copyWith(fontSize: 23, fontWeight: FontWeight.w800, fontFamilyFallback: bn),
    headlineSmall:  h.headlineSmall?.copyWith(fontSize: 20.5, fontWeight: FontWeight.w800, fontFamilyFallback: bn),
    // ─── Title — screen sub-titles, patient names ──────────
    titleLarge:  h.titleLarge?.copyWith(fontSize: 18.5, fontWeight: FontWeight.w800, fontFamilyFallback: bn),
    titleMedium: h.titleMedium?.copyWith(fontSize: 17.5, fontWeight: FontWeight.w700, fontFamilyFallback: bn),
    titleSmall:  b.titleSmall?.copyWith(fontSize: 16, fontWeight: FontWeight.w700, fontFamilyFallback: bn),
    // ─── Body — default reading text ───────────────────────
    bodyLarge:  b.bodyLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w400, fontFamilyFallback: bn),
    bodyMedium: b.bodyMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w400, fontFamilyFallback: bn),
    bodySmall:  b.bodySmall?.copyWith(fontSize: 12.5, fontWeight: FontWeight.w400, fontFamilyFallback: bn),
    // ─── Label — chips, section labels, navigation ─────────
    labelLarge:  h.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w700, fontFamilyFallback: bn),
    labelMedium: h.labelMedium?.copyWith(fontSize: 12.5, fontWeight: FontWeight.w700, fontFamilyFallback: bn),
    labelSmall:  b.labelSmall?.copyWith(fontSize: 11.5, fontWeight: FontWeight.w700, fontFamilyFallback: bn),
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

  /// The "dense" InputDecoration padding for inline row editors / compact
  /// sheet forms (design_v11 theme.md §3) — e.g. the healthcare form
  /// widgets' side-by-side numeric fields (BP systolic/diastolic,
  /// anthropometry height/weight, MUAC, etc). Single named home instead of
  /// each widget hand-rolling its own EdgeInsets.
  static const EdgeInsets denseFieldPadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.xl, vertical: AppSpacing.lg, // 12×10
  );
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
    scrim:            AppColors.scrimDrawer,
    inverseSurface:   AppColors.navy,
    onInverseSurface: AppColors.textOnNavy,
    inversePrimary:   AppColors.aiSurfaceStart,
    surfaceTint:      AppColors.navy,
    surfaceContainerLowest:   AppColors.cardSurface,
    surfaceContainerLow:      AppColors.cardSurfaceMuted,
    surfaceContainer:         AppColors.canvas,
    surfaceContainerHigh:     AppColors.surfaceContainerHigh,
    surfaceContainerHighest:  AppColors.surfaceContainerHighest,
  );

  final textTheme = _buildTextTheme(Brightness.light);

  return ThemeData(
    useMaterial3: true,
    fontFamily: AppFonts.body,
    colorScheme: scheme,
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    extensions: const <ThemeExtension<dynamic>>[
      LeapfrogColors.light,
      ProgrammeColors.light,
      UrgencyTheme.light,
      AiColors.light,
      OnDarkColors.light,
      PartnerColors.light,
      MotionTheme.light,
      WorklistCategoryColors.light,
    ],
    scaffoldBackgroundColor: AppColors.canvas,
    appBarTheme: AppBarTheme(
      backgroundColor: const Color(0xFF831843),
      foregroundColor: AppColors.textOnNavy,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: const TextStyle(
        fontFamily: AppFonts.display, fontSize: 23, fontWeight: FontWeight.w800,
        color: AppColors.textOnNavy,
      ),
      iconTheme: const IconThemeData(color: AppColors.textOnNavy),
      actionsIconTheme: const IconThemeData(color: AppColors.textOnNavy),
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
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
        fontFamily: AppFonts.body, fontSize: 15, color: AppColors.textMuted,
      ),
      errorStyle: const TextStyle(
        fontFamily: AppFonts.body, fontSize: 12.5, fontWeight: FontWeight.w400,
        color: AppColors.statusCriticalText,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
        borderSide: const BorderSide(color: AppColors.border, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
        borderSide: const BorderSide(color: AppColors.border, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
        borderSide: const BorderSide(color: AppColors.aiPurple, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
        borderSide: const BorderSide(color: AppColors.statusCritical, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
        borderSide: const BorderSide(color: AppColors.statusCritical, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxl, vertical: AppSpacing.xl, // 14×12
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.pink,
        foregroundColor: AppColors.textOnNavy,
        elevation: 0,
        shadowColor: AppShadows.fab.first.color,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxxl, vertical: AppSpacing.xl, // 16×12
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        textStyle: const TextStyle(
          fontFamily: AppFonts.display, fontSize: 15, fontWeight: FontWeight.w800,
        ),
      ).copyWith(
        overlayColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.pressed) ? AppColors.pinkDark : null),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.navy,
        foregroundColor: AppColors.textOnNavy,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxxl, vertical: AppSpacing.xl, // 16×12
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        textStyle: const TextStyle(
          fontFamily: AppFonts.display, fontSize: 15, fontWeight: FontWeight.w700,
        ),
      ).copyWith(
        overlayColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.pressed) ? AppColors.navyDark : null),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.navy,
        side: const BorderSide(color: AppColors.navy, width: 1.5),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxxl, vertical: AppSpacing.xl, // 16×12
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        textStyle: const TextStyle(
          fontFamily: AppFonts.display, fontSize: 15, fontWeight: FontWeight.w700,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.aiPurple,
        textStyle: const TextStyle(
          fontFamily: AppFonts.display, fontSize: 15, fontWeight: FontWeight.w700,
        ),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.pink,
      foregroundColor: AppColors.textOnNavy,
      // Depth comes from the explicit AppShadows.fab decoration drawn by
      // the widget, not Material elevation (elevation.md §Cards contract).
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      disabledElevation: 0,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.cardSurface,
      selectedColor: AppColors.navy,
      side: const BorderSide(color: AppColors.border, width: 1.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      labelStyle: const TextStyle(
        fontFamily: AppFonts.body, fontSize: 14, fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      secondaryLabelStyle: const TextStyle(
        fontFamily: AppFonts.body, fontSize: 14, fontWeight: FontWeight.w700,
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
          fontFamily: AppFonts.body, fontSize: 11.5,
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
      color: AppColors.cardSurface, elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.cardSurface, elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      titleTextStyle: const TextStyle(
        fontFamily: AppFonts.display, fontSize: 20.5, fontWeight: FontWeight.w800,
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
      showDragHandle: true,
      dragHandleColor: AppColors.borderDashed,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.navy,
      contentTextStyle: const TextStyle(
        fontFamily: AppFonts.body, color: AppColors.textOnNavy,
        fontWeight: FontWeight.w600, fontSize: 15,
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
    scrim:            AppColors.scrimDrawerDark,
    inverseSurface:   AppColors.textPrimaryDark,
    onInverseSurface: AppColors.canvasDark,
    inversePrimary:   AppColors.pink,
    surfaceTint:      AppColors.pinkLight,
    surfaceContainerLowest:  AppColors.canvasDark,
    surfaceContainerLow:     AppColors.cardSurfaceMutedDark,
    surfaceContainer:        AppColors.cardSurfaceDark,
    surfaceContainerHigh:    AppColors.surfaceContainerHighDark,
    surfaceContainerHighest: AppColors.surfaceContainerHighestDark,
  );

  final textTheme = _buildTextTheme(Brightness.dark);

  return ThemeData(
    useMaterial3: true,
    fontFamily: AppFonts.body,
    brightness: Brightness.dark,
    colorScheme: scheme,
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    extensions: const <ThemeExtension<dynamic>>[
      LeapfrogColors.dark,
      ProgrammeColors.dark,
      UrgencyTheme.dark,
      AiColors.dark,
      OnDarkColors.dark,
      PartnerColors.dark,
      MotionTheme.dark,
      WorklistCategoryColors.dark,
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
        fontFamily: AppFonts.display, fontSize: 23, fontWeight: FontWeight.w800,
        color: AppColors.textPrimaryDark,
      ),
      iconTheme: const IconThemeData(color: AppColors.textPrimaryDark),
      actionsIconTheme: const IconThemeData(color: AppColors.textPrimaryDark),
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
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
        fontFamily: AppFonts.body, fontSize: 15, color: AppColors.textMutedDark,
      ),
      errorStyle: const TextStyle(
        fontFamily: AppFonts.body, fontSize: 12.5, fontWeight: FontWeight.w400,
        color: AppColors.statusCriticalDark,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
        borderSide: const BorderSide(color: AppColors.borderDark, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
        borderSide: const BorderSide(color: AppColors.borderDark, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
        borderSide: const BorderSide(color: AppColors.aiPurpleLight, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
        borderSide: const BorderSide(color: AppColors.statusCriticalDark, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
        borderSide: const BorderSide(color: AppColors.statusCriticalDark, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxl, vertical: AppSpacing.xl, // 14×12
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.pinkLight,
        foregroundColor: AppColors.canvasDark,
        elevation: 0,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxxl, vertical: AppSpacing.xl, // 16×12
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        textStyle: const TextStyle(
          fontFamily: AppFonts.display, fontSize: 15, fontWeight: FontWeight.w800,
        ),
      ).copyWith(
        overlayColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.pressed) ? AppColors.pink : null),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.navy,
        foregroundColor: AppColors.textPrimaryDark,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxxl, vertical: AppSpacing.xl, // 16×12
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        textStyle: const TextStyle(
          fontFamily: AppFonts.display, fontSize: 15, fontWeight: FontWeight.w700,
        ),
      ).copyWith(
        overlayColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.pressed) ? AppColors.navyDeepDark : null),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimaryDark,
        side: const BorderSide(color: AppColors.aiPurpleLight, width: 1.5),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxxl, vertical: AppSpacing.xl, // 16×12
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        textStyle: const TextStyle(
          fontFamily: AppFonts.display, fontSize: 15, fontWeight: FontWeight.w700,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.aiPurpleLight,
        textStyle: const TextStyle(
          fontFamily: AppFonts.display, fontSize: 15, fontWeight: FontWeight.w700,
        ),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.pinkLight,
      foregroundColor: AppColors.canvasDark,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      disabledElevation: 0,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.cardSurfaceDark,
      // brand.primary-family dark tone, not AI purple — "selected" must never
      // collide with the AI-identity signature (theme.md §7).
      selectedColor: AppColors.navyOnDark,
      side: const BorderSide(color: AppColors.borderDark),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      labelStyle: const TextStyle(
        fontFamily: AppFonts.body, fontSize: 14, fontWeight: FontWeight.w600,
        color: AppColors.textPrimaryDark,
      ),
      secondaryLabelStyle: const TextStyle(
        fontFamily: AppFonts.body, fontSize: 14, fontWeight: FontWeight.w700,
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
          fontFamily: AppFonts.body, fontSize: 11.5,
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
      color: AppColors.cardSurfaceDark, elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.cardSurfaceDark, elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      titleTextStyle: const TextStyle(
        fontFamily: AppFonts.display, fontSize: 20.5, fontWeight: FontWeight.w800,
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
      showDragHandle: true,
      dragHandleColor: AppColors.borderDashedDark,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.cardSurfaceMutedDark,
      contentTextStyle: const TextStyle(
        fontFamily: AppFonts.body, color: AppColors.textPrimaryDark,
        fontWeight: FontWeight.w600, fontSize: 15,
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
