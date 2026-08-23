
import 'package:flutter/material.dart';

/// Colour tokens from the Quantal design system.
///
/// Depth is communicated by shifts in surface luminance and hairline dividers
/// rather than shadows, so there is no elevation ramp here — only a small set
/// of flat surface levels.
abstract final class AppColors {
  /// Level 0 — the application canvas.
  static const Color background = Color(0xFF0A0A0A);

  /// App bar and other chrome pinned to the canvas.
  static const Color chrome = Color(0xFF121317);

  /// Level 1 — cards, sheets, grouped list containers.
  static const Color surface = Color(0xFF1C1C1E);

  /// Bottom navigation and other secondary chrome.
  static const Color surfaceContainer = Color(0xFF1E1F23);

  /// Pressed / hovered row state.
  static const Color surfaceHighlight = Color(0xFF2A2A2C);

  /// 0.5pt hairline between list items and around containers.
  static const Color hairline = Color(0xFF2C2C2E);

  static const Color onSurface = Color(0xFFE3E2E7);
  static const Color onSurfaceVariant = Color(0xFFC4C7C7);

  /// Secondary metadata, labels, inactive states.
  static const Color muted = Color(0xFF8E9192);

  /// Gains, buy actions, upticks.
  static const Color buy = Color(0xFF00B386);

  /// Losses, sell actions, downticks.
  static const Color sell = Color(0xFFFF5B5B);

  /// Active navigation tint — the brighter mint from the token set, which
  /// holds contrast against the nav surface better than [buy] does.
  static const Color accent = Color(0xFF50DDAD);

  /// Backgrounds for the tick flash. Low alpha so a rapid sequence of ticks
  /// reads as a pulse rather than a strobe.
  static const Color buyFlash = Color(0x2600B386);
  static const Color sellFlash = Color(0x26FF5B5B);

  /// The colour for a signed value: gains green, losses red, flat neutral.
  static Color forSign({required bool isNegative, required bool isZero}) {
    if (isZero) return onSurfaceVariant;
    return isNegative ? sell : buy;
  }
}

/// Typography from the Quantal scale.
///
/// Every style that can render a changing number carries
/// [FontFeature.tabularFigures]. Without it, digit glyphs have different
/// advance widths and prices visibly jitter horizontally on each tick, which
/// makes a dense list look broken.
abstract final class AppTypography {
  static const String fontFamily = 'Inter';

  static const List<FontFeature> _tabular = <FontFeature>[
    FontFeature.tabularFigures(),
  ];

  static const TextStyle displayLg = TextStyle(
    fontSize: 32,
    height: 40 / 32,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.64,
    fontFeatures: _tabular,
  );

  static const TextStyle headlineMd = TextStyle(
    fontSize: 20,
    height: 28 / 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );

  /// Instrument names, e.g. RELIANCE.
  static const TextStyle titleSm = TextStyle(
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle bodyMd = TextStyle(
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
  );

  /// Secondary metadata, e.g. company name, "Qty: 10".
  static const TextStyle bodySm = TextStyle(
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w400,
  );

  /// Prices, quantities, percentages — anything numeric that can change.
  static const TextStyle labelNumeric = TextStyle(
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w500,
    fontFeatures: _tabular,
  );

  /// The secondary numeric line (change and change %), one step smaller.
  static const TextStyle bodyNumericSm = TextStyle(
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w400,
    fontFeatures: _tabular,
  );

  /// Section headers and column titles.
  static const TextStyle labelCaps = TextStyle(
    fontSize: 11,
    height: 16 / 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.55,
  );
}

/// Layout constants from the design system's tight vertical rhythm.
abstract final class AppSpacing {
  static const double unit = 4;
  static const double edge = 16;
  static const double gutter = 12;
  static const double vTight = 4;
  static const double vStandard = 12;
  static const double vListItem = 16;

  /// Design system specifies 64–72px list rows. A fixed extent also lets
  /// ListView skip layout for off-screen children.
  static const double listRowExtent = 68;

  static const double navBarHeight = 56;
  static const double appBarHeight = 56;

  static const double radiusSm = 4;
  static const double radiusLg = 8;
  static const double radiusXl = 12;
}

abstract final class AppTheme {
  static ThemeData get dark {
    const ColorScheme scheme = ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: Color(0xFF003828),
      secondary: AppColors.buy,
      onSecondary: Colors.white,
      error: AppColors.sell,
      onError: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.onSurface,
      surfaceContainer: AppColors.surfaceContainer,
      onSurfaceVariant: AppColors.onSurfaceVariant,
      outlineVariant: AppColors.hairline,
    );

    final TextTheme textTheme = const TextTheme(
      displayLarge: AppTypography.displayLg,
      headlineMedium: AppTypography.headlineMd,
      titleSmall: AppTypography.titleSm,
      bodyMedium: AppTypography.bodyMd,
      bodySmall: AppTypography.bodySm,
      labelMedium: AppTypography.labelNumeric,
      labelSmall: AppTypography.labelCaps,
    ).apply(
      fontFamily: AppTypography.fontFamily,
      bodyColor: AppColors.onSurface,
      displayColor: AppColors.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      fontFamily: AppTypography.fontFamily,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      textTheme: textTheme,
      dividerTheme: const DividerThemeData(
        color: AppColors.hairline,
        thickness: 0.5,
        space: 0.5,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.chrome,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: AppSpacing.appBarHeight,
       ),
      // Material's default snack bar inverts the surface, which lands as a
      // white slab in a dark trading UI. Undo prompts appear over live prices,
      // so they have to sit in the same palette.
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceContainer,
        contentTextStyle: AppTypography.bodyMd.copyWith(
          color: AppColors.onSurface,
        ),
        actionTextColor: AppColors.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
      ),
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.compact,
    );
  }
}
