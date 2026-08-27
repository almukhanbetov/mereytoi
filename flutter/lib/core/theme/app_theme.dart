import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// MEREYTOI's design system — a real token set, not scattered hex values.
///
/// Direction: deep near-black + warm graphite surfaces, ivory text, and a
/// *muted* champagne gold used only as an accent (icons, active states,
/// price emphasis, the primary CTA) — never as a background fill or a
/// border wrapped around everything. Depth comes from a quiet neutral
/// surface scale + soft shadows; gold never touches a divider or an
/// unselected element.
class AppColors {
  AppColors._();

  // ---- Backgrounds & surfaces (each step a touch lighter — this alone is
  // what should read as "raised", no border needed to prove it) ----
  static const backgroundPrimary = Color(0xFF0A0A0C);
  static const backgroundSecondary = Color(0xFF121114); // bars, nav, sunken areas
  static const surface = Color(0xFF17161A); // resting card
  static const surfaceElevated = Color(0xFF1E1C20); // sheet / emphasized card
  static const surfaceSoft = Color(0xFF242128); // neutral soft fill — unselected chips, icon badges (deliberately *not* gold-tinted)

  // ---- Gold, strictly an accent ----
  static const goldPrimary = Color(0xFFC9A063); // icons, active states, CTA fill
  static const goldMuted = Color(0xFF8C6E45); // deep gold for text-on-gold, subtle emphasis
  static const goldSoft = Color(0xFFE9D6AC); // pale champagne — price highlights, labels on dark

  // ---- Text ----
  static const textPrimary = Color(0xFFF4F0E6);
  static const textSecondary = Color(0xFFA79E90);
  static const textMuted = Color(0xFF6C6459);

  /// A quiet neutral hairline — *not* gold. Used sparingly (input focus
  /// aside, most separation should come from spacing/surface, not a line).
  static const divider = Color(0x14FFFFFF);

  static const success = Color(0xFF6FA787);
  static const error = Color(0xFFC0616B);

  static const onGold = Color(0xFF201406); // text/icons drawn on a gold fill

  /// The warm radial-glow stop behind the splash wordmark and Home hero —
  /// one token so both moments match.
  static const heroGlow = Color(0xFF1C181A);

  static const whatsapp = Color(0xFF3FB6AC); // reserved: WhatsApp action only
}

/// Exactly three radii, used consistently. `chip` is the one deliberate
/// exception (filter chips/badges) — never applied to a card or a button.
class AppRadius {
  AppRadius._();

  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const chip = 999.0;
}

/// The strict spacing scale: 4 / 8 / 12 / 16 / 20 / 24 / 32. Every gap in
/// the app should be one of these seven values.
class AppSpacing {
  AppSpacing._();

  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

/// Quiet, low-spread shadows — the only depth cue cards need. Kept subtle
/// on purpose: this redesign explicitly asks for *less* glow, not more.
class AppShadows {
  AppShadows._();

  static const card = [
    BoxShadow(color: Color(0x40000000), blurRadius: 20, offset: Offset(0, 8)),
  ];

  static const raised = [
    BoxShadow(color: Color(0x52000000), blurRadius: 26, offset: Offset(0, 12)),
  ];
}

/// Groups typography + builds the app's [ThemeData]. Text-style roles map
/// onto Flutter's fixed TextTheme slots as follows:
///   display        → displayLarge / displayMedium  (serif — brand only: splash, "Спасибо!")
///   titleLarge      → titleLarge   (sans, bold — screen/section headings)
///   title           → titleMedium  (sans, semibold — card titles, subheads)
///   body            → bodyLarge    (sans, regular — primary reading text)
///   bodySmall/caption → bodyMedium / bodySmall (sans — secondary/meta text)
///   label           → labelLarge / labelMedium / labelSmall (sans, bold — buttons, chips, nav)
class AppTheme {
  AppTheme._();

  static TextTheme get _textTheme {
    final serif = GoogleFonts.playfairDisplay();
    final sans = GoogleFonts.montserrat();
    return TextTheme(
      displayLarge: serif.copyWith(fontSize: 38, fontWeight: FontWeight.w700, color: AppColors.textPrimary, height: 1.08),
      displayMedium: serif.copyWith(fontSize: 25, fontWeight: FontWeight.w700, color: AppColors.textPrimary, height: 1.15),
      titleLarge: sans.copyWith(fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.textPrimary, height: 1.25),
      titleMedium: sans.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary, height: 1.3),
      titleSmall: sans.copyWith(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary, height: 1.3),
      bodyLarge: sans.copyWith(fontSize: 14.5, color: AppColors.textPrimary, height: 1.5, fontWeight: FontWeight.w500),
      bodyMedium: sans.copyWith(fontSize: 13, color: AppColors.textSecondary, height: 1.45, fontWeight: FontWeight.w500),
      bodySmall: sans.copyWith(fontSize: 11.5, color: AppColors.textSecondary, height: 1.4, fontWeight: FontWeight.w500),
      labelLarge: sans.copyWith(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.onGold, letterSpacing: 0.1),
      labelMedium: sans.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
      labelSmall: sans.copyWith(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.3),
    );
  }

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    final textTheme = _textTheme;
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.backgroundPrimary,
      colorScheme: base.colorScheme.copyWith(
        surface: AppColors.backgroundPrimary,
        primary: AppColors.goldPrimary,
        secondary: AppColors.goldSoft,
        error: AppColors.error,
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.backgroundPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      cardColor: AppColors.surface,
      dividerColor: AppColors.divider,
      dividerTheme: const DividerThemeData(color: AppColors.divider, thickness: 1, space: 1),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.goldPrimary,
          foregroundColor: AppColors.onGold,
          disabledBackgroundColor: AppColors.goldPrimary.withValues(alpha: 0.3),
          disabledForegroundColor: AppColors.onGold.withValues(alpha: 0.55),
          textStyle: textTheme.labelLarge,
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.sm),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.divider),
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.sm),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          textStyle: textTheme.labelLarge?.copyWith(color: AppColors.textPrimary),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.goldSoft,
          textStyle: textTheme.labelMedium,
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xs),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: AppColors.textSecondary, minimumSize: const Size(44, 44)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: const BorderSide(color: AppColors.goldPrimary, width: 1.4)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: const BorderSide(color: AppColors.error, width: 1.2)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: const BorderSide(color: AppColors.error, width: 1.4)),
        hintStyle: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        labelStyle: textTheme.bodyMedium,
        errorStyle: textTheme.bodySmall?.copyWith(color: AppColors.error),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceElevated,
        contentTextStyle: textTheme.bodyLarge,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.goldPrimary),
      splashFactory: InkRipple.splashFactory,
      highlightColor: AppColors.goldPrimary.withValues(alpha: 0.05),
      splashColor: AppColors.goldPrimary.withValues(alpha: 0.07),
    );
  }
}
