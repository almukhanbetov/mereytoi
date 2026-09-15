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
///
/// Stage 9 note: this class is still the dark palette specifically (its
/// name predates light theme support) — every widget that hasn't been
/// migrated to `context.mereytoiColors.xxx` keeps reading these exact
/// values, which is why dark mode looks byte-identical to before Stage 9.
/// [MereytoiColors] is the theme-aware counterpart both `AppTheme.dark`
/// and the new `AppTheme.light` actually publish through
/// `Theme.of(context)`.
class AppColors {
  AppColors._();

  // ---- Backgrounds & surfaces (each step a touch lighter — this alone is
  // what should read as "raised", no border needed to prove it) ----
  static const backgroundPrimary = Color(0xFF0A0A0C);
  static const backgroundSecondary = Color(
    0xFF121114,
  ); // bars, nav, sunken areas
  static const surface = Color(0xFF17161A); // resting card
  static const surfaceElevated = Color(0xFF1E1C20); // sheet / emphasized card
  static const surfaceSoft = Color(
    0xFF242128,
  ); // neutral soft fill — unselected chips, icon badges (deliberately *not* gold-tinted)

  // ---- Gold, strictly an accent ----
  static const goldPrimary = Color(
    0xFFC9A063,
  ); // icons, active states, CTA fill
  static const goldMuted = Color(
    0xFF8C6E45,
  ); // deep gold for text-on-gold, subtle emphasis
  static const goldSoft = Color(
    0xFFE9D6AC,
  ); // pale champagne — price highlights, labels on dark

  // ---- Text ----
  static const textPrimary = Color(0xFFF4F0E6);
  static const textSecondary = Color(0xFFA79E90);
  static const textMuted = Color(0xFF6C6459);

  /// A quiet neutral hairline — *not* gold. Used sparingly (input focus
  /// aside, most separation should come from spacing/surface, not a line).
  static const divider = Color(0x14FFFFFF);

  static const success = Color(0xFF6FA787);
  static const warning = Color(0xFFDB9245);
  static const error = Color(0xFFC0616B);

  static const onGold = Color(0xFF201406); // text/icons drawn on a gold fill

  /// The warm radial-glow stop behind the splash wordmark and Home hero —
  /// one token so both moments match.
  static const heroGlow = Color(0xFF1C181A);

  static const whatsapp = Color(0xFF3FB6AC); // reserved: WhatsApp action only
}

/// The full theme-aware token set, published through `Theme.of(context)` as
/// a [ThemeExtension] — this is what actually changes between
/// [AppTheme.dark] and [AppTheme.light]. [AppColors] stays the dark values
/// specifically (untouched, so every not-yet-migrated widget keeps its
/// exact old look); this class is what a widget should reach for instead
/// when it genuinely needs to look right in both themes — via
/// `context.mereytoiColors.xxx`.
@immutable
class MereytoiColors extends ThemeExtension<MereytoiColors> {
  const MereytoiColors({
    required this.backgroundPrimary,
    required this.backgroundSecondary,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceSoft,
    required this.surfaceTint,
    required this.card,
    required this.border,
    required this.inputBackground,
    required this.navigationBackground,
    required this.goldPrimary,
    required this.goldMuted,
    required this.goldSoft,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.divider,
    required this.success,
    required this.warning,
    required this.error,
    required this.onGold,
    required this.heroGlow,
    required this.whatsapp,
  });

  final Color backgroundPrimary;
  final Color backgroundSecondary;
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceSoft;

  /// A faint gold wash over a surface — the active-tab pill on the bottom
  /// nav, a selected chip's fill, a highlighted list row. Always this one
  /// token rather than each call site inventing its own
  /// `goldPrimary.withValues(alpha: ...)`, so the wash reads consistently
  /// and can be tuned once per theme (light needs a touch more opacity
  /// than dark to stay visible on a bright background).
  final Color surfaceTint;

  /// The color an `AppCard` (and anything else styled like one) actually
  /// paints — same as [surface] on dark (kept identical on purpose so dark
  /// mode is pixel-for-pixel unchanged), but a distinct, slightly-off-white
  /// value on light so a card still reads as "raised" against
  /// [backgroundPrimary] without needing a visible border.
  final Color card;

  /// A hairline meant to actually be seen (a card outline, an input's
  /// resting border) — distinct from [divider], which stays closer to
  /// invisible by design. On dark these can coincide; on light, "barely
  /// there" alpha-on-white borders disappear, so this is deliberately a
  /// touch stronger.
  final Color border;
  final Color inputBackground;
  final Color navigationBackground;

  final Color goldPrimary;
  final Color goldMuted;
  final Color goldSoft;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color divider;
  final Color success;
  final Color warning;
  final Color error;
  final Color onGold;
  final Color heroGlow;
  final Color whatsapp;

  /// Byte-identical to [AppColors] — dark mode's own values, just also
  /// reachable through `Theme.of(context)`.
  static const dark = MereytoiColors(
    backgroundPrimary: AppColors.backgroundPrimary,
    backgroundSecondary: AppColors.backgroundSecondary,
    surface: AppColors.surface,
    surfaceElevated: AppColors.surfaceElevated,
    surfaceSoft: AppColors.surfaceSoft,
    surfaceTint: Color(0x24C9A063), // AppColors.goldPrimary @ ~14% alpha
    card: AppColors.surface,
    border: AppColors.divider,
    inputBackground: AppColors.surface,
    navigationBackground: AppColors.backgroundSecondary,
    goldPrimary: AppColors.goldPrimary,
    goldMuted: AppColors.goldMuted,
    goldSoft: AppColors.goldSoft,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    textMuted: AppColors.textMuted,
    divider: AppColors.divider,
    success: AppColors.success,
    warning: AppColors.warning,
    error: AppColors.error,
    onGold: AppColors.onGold,
    heroGlow: AppColors.heroGlow,
    whatsapp: AppColors.whatsapp,
  );

  /// A genuinely new palette, not a mechanical inversion — warm ivory
  /// background (not stark white, matching the brand's warm direction),
  /// white raised cards, deepened/richer gold (the pale champagne
  /// [AppColors.goldSoft] reads as almost-white and would nearly vanish on
  /// a light background, so light mode uses a more saturated gold across
  /// the board instead), and every text/border tone re-checked for real
  /// contrast against a light ground rather than just flipped.
  static const light = MereytoiColors(
    backgroundPrimary: Color(0xFFFAF8F4),
    backgroundSecondary: Color(0xFFF2EEE6),
    surface: Color(0xFFFFFFFF),
    // Deliberately *not* the same as `surface` (unlike a first pass at
    // this palette) — a sheet/emphasized card, and the skeleton pulse's
    // second stop, both need a value genuinely distinct from resting
    // white, or a light-mode skeleton has nothing to visibly pulse
    // between.
    surfaceElevated: Color(0xFFF7F2E9),
    surfaceSoft: Color(0xFFEFEAE1),
    surfaceTint: Color(0x26B8873F), // light goldPrimary @ ~15% alpha
    card: Color(0xFFFFFFFF),
    border: Color(0x1F1A1611),
    inputBackground: Color(0xFFF3EFE7),
    navigationBackground: Color(0xFFFFFFFF),
    goldPrimary: Color(
      0xFFB8873F,
    ), // deeper than dark's — stays premium on white
    goldMuted: Color(0xFF7A5A28),
    goldSoft: Color(0xFF8F6A2E), // a *saturated* gold here, not a pale one
    textPrimary: Color(0xFF221D15),
    textSecondary: Color(0xFF6B6152),
    textMuted: Color(0xFF938A7B),
    divider: Color(0x141A1611),
    success: Color(0xFF3F7D5A),
    warning: Color(0xFF9C5F1E),
    error: Color(0xFFB3303F),
    onGold: AppColors.onGold, // always drawn on a gold fill either way
    heroGlow: Color(0xFFF1E3C6),
    whatsapp: Color(0xFF1F9184),
  );

  @override
  MereytoiColors copyWith({
    Color? backgroundPrimary,
    Color? backgroundSecondary,
    Color? surface,
    Color? surfaceElevated,
    Color? surfaceSoft,
    Color? surfaceTint,
    Color? card,
    Color? border,
    Color? inputBackground,
    Color? navigationBackground,
    Color? goldPrimary,
    Color? goldMuted,
    Color? goldSoft,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? divider,
    Color? success,
    Color? warning,
    Color? error,
    Color? onGold,
    Color? heroGlow,
    Color? whatsapp,
  }) {
    return MereytoiColors(
      backgroundPrimary: backgroundPrimary ?? this.backgroundPrimary,
      backgroundSecondary: backgroundSecondary ?? this.backgroundSecondary,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceSoft: surfaceSoft ?? this.surfaceSoft,
      surfaceTint: surfaceTint ?? this.surfaceTint,
      card: card ?? this.card,
      border: border ?? this.border,
      inputBackground: inputBackground ?? this.inputBackground,
      navigationBackground: navigationBackground ?? this.navigationBackground,
      goldPrimary: goldPrimary ?? this.goldPrimary,
      goldMuted: goldMuted ?? this.goldMuted,
      goldSoft: goldSoft ?? this.goldSoft,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      divider: divider ?? this.divider,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      onGold: onGold ?? this.onGold,
      heroGlow: heroGlow ?? this.heroGlow,
      whatsapp: whatsapp ?? this.whatsapp,
    );
  }

  @override
  MereytoiColors lerp(ThemeExtension<MereytoiColors>? other, double t) {
    if (other is! MereytoiColors) return this;
    return MereytoiColors(
      backgroundPrimary: Color.lerp(
        backgroundPrimary,
        other.backgroundPrimary,
        t,
      )!,
      backgroundSecondary: Color.lerp(
        backgroundSecondary,
        other.backgroundSecondary,
        t,
      )!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      surfaceSoft: Color.lerp(surfaceSoft, other.surfaceSoft, t)!,
      surfaceTint: Color.lerp(surfaceTint, other.surfaceTint, t)!,
      card: Color.lerp(card, other.card, t)!,
      border: Color.lerp(border, other.border, t)!,
      inputBackground: Color.lerp(inputBackground, other.inputBackground, t)!,
      navigationBackground: Color.lerp(
        navigationBackground,
        other.navigationBackground,
        t,
      )!,
      goldPrimary: Color.lerp(goldPrimary, other.goldPrimary, t)!,
      goldMuted: Color.lerp(goldMuted, other.goldMuted, t)!,
      goldSoft: Color.lerp(goldSoft, other.goldSoft, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      onGold: Color.lerp(onGold, other.onGold, t)!,
      heroGlow: Color.lerp(heroGlow, other.heroGlow, t)!,
      whatsapp: Color.lerp(whatsapp, other.whatsapp, t)!,
    );
  }
}

/// Sugar for `Theme.of(context).extension<MereytoiColors>()!` — the
/// intended everyday call site for any widget that wants to look correct
/// in both themes instead of always rendering dark via `AppColors.xxx`.
extension MereytoiThemeContext on BuildContext {
  MereytoiColors get mereytoiColors =>
      Theme.of(this).extension<MereytoiColors>()!;
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
/// Same values for both themes: a soft black shadow reads as "lifted" on a
/// light ground just as well as on a dark one, and dark mode must stay
/// pixel-identical.
class AppShadows {
  AppShadows._();

  static const card = [
    BoxShadow(color: Color(0x40000000), blurRadius: 20, offset: Offset(0, 8)),
  ];

  static const raised = [
    BoxShadow(color: Color(0x52000000), blurRadius: 26, offset: Offset(0, 12)),
  ];
}

/// Groups typography + builds the app's [ThemeData] — one shared builder
/// ([_build]) parametrized by [MereytoiColors] so [dark] and [light] can
/// never silently drift apart the way two hand-duplicated theme trees
/// eventually would. Text-style roles map onto Flutter's fixed TextTheme
/// slots as follows:
///   display        → displayLarge / displayMedium  (serif — brand only: splash, "Спасибо!")
///   titleLarge      → titleLarge   (sans, bold — screen/section headings)
///   title           → titleMedium  (sans, semibold — card titles, subheads)
///   body            → bodyLarge    (sans, regular — primary reading text)
///   bodySmall/caption → bodyMedium / bodySmall (sans — secondary/meta text)
///   label           → labelLarge / labelMedium / labelSmall (sans, bold — buttons, chips, nav)
class AppTheme {
  AppTheme._();

  static TextTheme _textTheme(MereytoiColors c) {
    final serif = GoogleFonts.playfairDisplay();
    final sans = GoogleFonts.montserrat();
    return TextTheme(
      displayLarge: serif.copyWith(
        fontSize: 38,
        fontWeight: FontWeight.w700,
        color: c.textPrimary,
        height: 1.08,
      ),
      displayMedium: serif.copyWith(
        fontSize: 25,
        fontWeight: FontWeight.w700,
        color: c.textPrimary,
        height: 1.15,
      ),
      titleLarge: sans.copyWith(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        color: c.textPrimary,
        height: 1.25,
      ),
      titleMedium: sans.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: c.textPrimary,
        height: 1.3,
      ),
      titleSmall: sans.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: c.textPrimary,
        height: 1.3,
      ),
      bodyLarge: sans.copyWith(
        fontSize: 14.5,
        color: c.textPrimary,
        height: 1.5,
        fontWeight: FontWeight.w500,
      ),
      bodyMedium: sans.copyWith(
        fontSize: 13,
        color: c.textSecondary,
        height: 1.45,
        fontWeight: FontWeight.w500,
      ),
      bodySmall: sans.copyWith(
        fontSize: 11.5,
        color: c.textSecondary,
        height: 1.4,
        fontWeight: FontWeight.w500,
      ),
      labelLarge: sans.copyWith(
        fontSize: 14.5,
        fontWeight: FontWeight.w700,
        color: c.onGold,
        letterSpacing: 0.1,
      ),
      labelMedium: sans.copyWith(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: c.textPrimary,
      ),
      labelSmall: sans.copyWith(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: c.textSecondary,
        letterSpacing: 0.3,
      ),
    );
  }

  static ThemeData _build(Brightness brightness, MereytoiColors c) {
    // Same base Material3 foundation each mode always had on its own
    // (`ThemeData.dark()` for dark, unchanged from before Stage 9) — every
    // widget property this file doesn't explicitly override below still
    // needs to come from *some* sensible default, and mixing bases (e.g.
    // a dark seed color scheme under `brightness: light`) would risk
    // exactly the kind of implicit drift Stage 9 must avoid for dark mode.
    final base = brightness == Brightness.dark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);
    final textTheme = _textTheme(c);
    return base.copyWith(
      scaffoldBackgroundColor: c.backgroundPrimary,
      colorScheme: base.colorScheme.copyWith(
        brightness: brightness,
        surface: c.backgroundPrimary,
        primary: c.goldPrimary,
        secondary: c.goldSoft,
        error: c.error,
        onSurface: c.textPrimary,
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: c.backgroundPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: IconThemeData(color: c.textPrimary),
      ),
      cardColor: c.card,
      dividerColor: c.divider,
      dividerTheme: DividerThemeData(color: c.divider, thickness: 1, space: 1),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.goldPrimary,
          foregroundColor: c.onGold,
          disabledBackgroundColor: c.goldPrimary.withValues(alpha: 0.3),
          disabledForegroundColor: c.onGold.withValues(alpha: 0.55),
          textStyle: textTheme.labelLarge,
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.textPrimary,
          side: BorderSide(color: c.border),
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: textTheme.labelLarge?.copyWith(color: c.textPrimary),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.goldSoft,
          textStyle: textTheme.labelMedium,
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.xs,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: c.textSecondary,
          minimumSize: const Size(44, 44),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.inputBackground,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: c.goldPrimary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: c.error, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: c.error, width: 1.4),
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(color: c.textSecondary),
        labelStyle: textTheme.bodyMedium,
        errorStyle: textTheme.bodySmall?.copyWith(color: c.error),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.surfaceElevated,
        contentTextStyle: textTheme.bodyLarge?.copyWith(color: c.textPrimary),
        actionTextColor: c.goldSoft,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceSoft,
        selectedColor: c.surfaceTint,
        disabledColor: c.surfaceSoft.withValues(alpha: 0.5),
        labelStyle: textTheme.labelMedium!,
        secondaryLabelStyle: textTheme.labelMedium!.copyWith(
          color: c.goldPrimary,
        ),
        side: BorderSide.none,
        shape: const StadiumBorder(),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.goldPrimary),
      splashFactory: InkRipple.splashFactory,
      highlightColor: c.goldPrimary.withValues(alpha: 0.05),
      splashColor: c.goldPrimary.withValues(alpha: 0.07),
      extensions: [c],
    );
  }

  static ThemeData get dark => _build(Brightness.dark, MereytoiColors.dark);

  static ThemeData get light => _build(Brightness.light, MereytoiColors.light);
}
