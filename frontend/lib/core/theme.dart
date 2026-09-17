import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Palette, spacing, and semantic colors that Material's [ColorScheme] does not
/// model. Read it with `context.tokens`.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.canvas,
    required this.raised,
    required this.hairline,
    required this.ink,
    required this.inkSoft,
    required this.positive,
    required this.caution,
    required this.info,
    required this.series,
    required this.pipeline,
  });

  /// Page background. Slightly warmer and flatter than [ColorScheme.surface].
  final Color canvas;

  /// Card and sheet background.
  final Color raised;

  /// One-pixel separators and card outlines.
  final Color hairline;

  /// Primary and secondary text.
  final Color ink, inkSoft;

  /// Semantic status colors, used for badges and freshness.
  final Color positive, caution, info;

  /// Single-series chart color, and a four-step ordinal ramp for pipeline
  /// meters. Both are validated for the lightness band, chroma floor, step
  /// separation, and surface contrast of their own mode; do not substitute
  /// unchecked values. [AppTokens.pipelineSteps] samples the ramp for meters
  /// with fewer than four stages.
  final Color series;
  final List<Color> pipeline;

  /// Evenly spaced samples of [pipeline] for a meter with [count] stages, so a
  /// three- and a four-stage meter both span the full ramp.
  List<Color> pipelineSteps(int count) {
    if (count <= 1) return [pipeline[pipeline.length - 1]];
    return [
      for (var i = 0; i < count; i++)
        pipeline[((i * (pipeline.length - 1)) / (count - 1)).round()],
    ];
  }

  @override
  AppTokens copyWith({
    Color? canvas,
    Color? raised,
    Color? hairline,
    Color? ink,
    Color? inkSoft,
    Color? positive,
    Color? caution,
    Color? info,
    Color? series,
    List<Color>? pipeline,
  }) =>
      AppTokens(
        canvas: canvas ?? this.canvas,
        raised: raised ?? this.raised,
        hairline: hairline ?? this.hairline,
        ink: ink ?? this.ink,
        inkSoft: inkSoft ?? this.inkSoft,
        positive: positive ?? this.positive,
        caution: caution ?? this.caution,
        info: info ?? this.info,
        series: series ?? this.series,
        pipeline: pipeline ?? this.pipeline,
      );

  @override
  AppTokens lerp(AppTokens? other, double t) {
    if (other == null) return this;
    return AppTokens(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      raised: Color.lerp(raised, other.raised, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkSoft: Color.lerp(inkSoft, other.inkSoft, t)!,
      positive: Color.lerp(positive, other.positive, t)!,
      caution: Color.lerp(caution, other.caution, t)!,
      info: Color.lerp(info, other.info, t)!,
      series: Color.lerp(series, other.series, t)!,
      pipeline: [
        for (var i = 0; i < pipeline.length; i++)
          Color.lerp(pipeline[i], other.pipeline[i % other.pipeline.length], t)!,
      ],
    );
  }
}

extension AppThemeContext on BuildContext {
  /// Falls back to the palette matching the ambient brightness when the theme
  /// carries no [AppTokens], so a widget still renders under a bare
  /// [ThemeData] instead of throwing.
  AppTokens get tokens {
    final theme = Theme.of(this);
    return theme.extension<AppTokens>() ??
        (theme.brightness == Brightness.dark
            ? AppTheme.darkTokens
            : AppTheme.lightTokens);
  }
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
}

abstract final class AppTheme {
  // A deep evergreen rather than the default mint: it reads as produce and
  // preservation, and holds contrast against the warm paper background.
  static const _green = Color(0xFF186B4E);
  static const _greenLight = Color(0xFF5BC79B);
  static const _saffron = Color(0xFFC8862B);
  static const _clay = Color(0xFFB4532F);

  static const lightTokens = AppTokens(
    canvas: Color(0xFFFAF8F3),
    raised: Color(0xFFFFFFFF),
    hairline: Color(0xFFE4E2D8),
    ink: Color(0xFF1A1C19),
    inkSoft: Color(0xFF5F655C),
    positive: Color(0xFF177A54),
    caution: Color(0xFFB07715),
    info: Color(0xFF2C5F9E),
    series: Color(0xFF0B8A5B),
    pipeline: [
      Color(0xFF63C5A1),
      Color(0xFF149C6D),
      Color(0xFF0A7049),
      Color(0xFF06462F),
    ],
  );

  static const darkTokens = AppTokens(
    canvas: Color(0xFF14160F),
    raised: Color(0xFF1B1E16),
    hairline: Color(0xFF32362C),
    ink: Color(0xFFE6E5DD),
    inkSoft: Color(0xFFA3A89C),
    positive: Color(0xFF5BC79B),
    caution: Color(0xFFE3B458),
    info: Color(0xFF85B4EC),
    series: Color(0xFF28A876),
    pipeline: [
      Color(0xFF0C6B48),
      Color(0xFF149C6D),
      Color(0xFF3FBE8F),
      Color(0xFF9BDFC4),
    ],
  );

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;

    final scheme = isLight
        ? const ColorScheme.light(
            primary: _green,
            onPrimary: Color(0xFFFFFFFF),
            primaryContainer: Color(0xFFD3EEE0),
            onPrimaryContainer: Color(0xFF07301F),
            secondary: _saffron,
            onSecondary: Color(0xFFFFFFFF),
            secondaryContainer: Color(0xFFFBEBCE),
            onSecondaryContainer: Color(0xFF3E2A05),
            tertiary: _clay,
            onTertiary: Color(0xFFFFFFFF),
            tertiaryContainer: Color(0xFFF9DED2),
            onTertiaryContainer: Color(0xFF3A1509),
            error: Color(0xFFB3261E),
            onError: Color(0xFFFFFFFF),
            errorContainer: Color(0xFFF9DEDC),
            onErrorContainer: Color(0xFF410E0B),
            surface: Color(0xFFFAF8F3),
            onSurface: Color(0xFF1A1C19),
            surfaceContainerLowest: Color(0xFFFFFFFF),
            surfaceContainerLow: Color(0xFFFFFFFF),
            surfaceContainer: Color(0xFFF3F1EA),
            surfaceContainerHigh: Color(0xFFEDEBE3),
            surfaceContainerHighest: Color(0xFFE7E5DC),
            onSurfaceVariant: Color(0xFF5A5F58),
            outline: Color(0xFF8A9088),
            outlineVariant: Color(0xFFDCDCD2),
            inverseSurface: Color(0xFF2F3130),
            onInverseSurface: Color(0xFFF1F1EC),
            inversePrimary: _greenLight,
            shadow: Color(0xFF000000),
            scrim: Color(0xFF000000),
          )
        : const ColorScheme.dark(
            primary: _greenLight,
            onPrimary: Color(0xFF003824),
            primaryContainer: Color(0xFF115139),
            onPrimaryContainer: Color(0xFFCDEEDC),
            secondary: Color(0xFFEFC078),
            onSecondary: Color(0xFF412D04),
            secondaryContainer: Color(0xFF5E4413),
            onSecondaryContainer: Color(0xFFFBE6C6),
            tertiary: Color(0xFFF0A688),
            onTertiary: Color(0xFF522113),
            tertiaryContainer: Color(0xFF6E3722),
            onTertiaryContainer: Color(0xFFFFDBCE),
            error: Color(0xFFF2B8B5),
            onError: Color(0xFF601410),
            errorContainer: Color(0xFF8C1D18),
            onErrorContainer: Color(0xFFF9DEDC),
            surface: Color(0xFF14160F),
            onSurface: Color(0xFFE6E5DD),
            surfaceContainerLowest: Color(0xFF0E100A),
            surfaceContainerLow: Color(0xFF1B1E16),
            surfaceContainer: Color(0xFF1F221A),
            surfaceContainerHigh: Color(0xFF292C23),
            surfaceContainerHighest: Color(0xFF34372D),
            onSurfaceVariant: Color(0xFFA9AEA2),
            outline: Color(0xFF6C7168),
            outlineVariant: Color(0xFF3A3E35),
            inverseSurface: Color(0xFFE6E5DD),
            onInverseSurface: Color(0xFF2F3129),
            inversePrimary: _green,
            shadow: Color(0xFF000000),
            scrim: Color(0xFF000000),
          );

    final tokens = isLight ? lightTokens : darkTokens;
    final text = _textTheme(tokens);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: [tokens],
      scaffoldBackgroundColor: tokens.canvas,
      canvasColor: tokens.canvas,
      textTheme: text,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      dividerTheme: DividerThemeData(
        color: tokens.hairline,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.canvas,
        surfaceTintColor: Colors.transparent,
        foregroundColor: tokens.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        systemOverlayStyle:
            isLight ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: tokens.raised,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: tokens.hairline),
        ),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        titleTextStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        subtitleTextStyle: text.bodySmall?.copyWith(color: tokens.inkSoft),
        minVerticalPadding: 10,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? const Color(0xFFF4F2EB) : const Color(0xFF20241B),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        labelStyle: text.bodyMedium?.copyWith(color: tokens.inkSoft),
        helperStyle: text.bodySmall?.copyWith(color: tokens.inkSoft),
        hintStyle: text.bodyMedium?.copyWith(
          color: tokens.inkSoft.withValues(alpha: 0.7),
        ),
        border: _fieldBorder(tokens.hairline),
        enabledBorder: _fieldBorder(tokens.hairline),
        focusedBorder: _fieldBorder(scheme.primary, width: 2),
        errorBorder: _fieldBorder(scheme.error),
        focusedErrorBorder: _fieldBorder(scheme.error, width: 2),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          textStyle: text.labelLarge,
          side: BorderSide(color: tokens.hairline),
          foregroundColor: tokens.ink,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: scheme.primaryContainer,
          selectedForegroundColor: scheme.onPrimaryContainer,
          side: BorderSide(color: tokens.hairline),
          textStyle: text.labelLarge,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isLight
            ? const Color(0xFFF1EFE7)
            : const Color(0xFF24281E),
        side: BorderSide(color: tokens.hairline),
        labelStyle: text.labelMedium?.copyWith(color: tokens.ink),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        shape: const StadiumBorder(),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: tokens.raised,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelSmall?.copyWith(
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? tokens.ink
                : tokens.inkSoft,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: tokens.canvas,
        indicatorColor: scheme.primaryContainer,
        selectedLabelTextStyle:
            text.labelMedium?.copyWith(fontWeight: FontWeight.w700),
        unselectedLabelTextStyle:
            text.labelMedium?.copyWith(color: tokens.inkSoft),
        selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: tokens.inkSoft),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        insetPadding: const EdgeInsets.all(16),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.raised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        highlightElevation: 2,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        extendedTextStyle: text.labelLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: tokens.hairline,
        circularTrackColor: tokens.hairline,
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        side: BorderSide(color: tokens.inkSoft, width: 1.6),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static OutlineInputBorder _fieldBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );

  /// Tightened tracking and taller body leading. The stock Material scale is
  /// loose at display sizes, which is most of what makes a default theme
  /// recognisable as a default theme.
  static TextTheme _textTheme(AppTokens tokens) {
    final ink = tokens.ink;
    final soft = tokens.inkSoft;
    return TextTheme(
      displayLarge: TextStyle(
          fontSize: 54, height: 1.04, letterSpacing: -1.6, color: ink,
          fontWeight: FontWeight.w800),
      displayMedium: TextStyle(
          fontSize: 44, height: 1.06, letterSpacing: -1.2, color: ink,
          fontWeight: FontWeight.w800),
      displaySmall: TextStyle(
          fontSize: 36, height: 1.08, letterSpacing: -0.9, color: ink,
          fontWeight: FontWeight.w800),
      headlineLarge: TextStyle(
          fontSize: 31, height: 1.12, letterSpacing: -0.7, color: ink,
          fontWeight: FontWeight.w700),
      headlineMedium: TextStyle(
          fontSize: 26, height: 1.16, letterSpacing: -0.5, color: ink,
          fontWeight: FontWeight.w700),
      headlineSmall: TextStyle(
          fontSize: 22, height: 1.2, letterSpacing: -0.3, color: ink,
          fontWeight: FontWeight.w700),
      titleLarge: TextStyle(
          fontSize: 19, height: 1.25, letterSpacing: -0.2, color: ink,
          fontWeight: FontWeight.w700),
      titleMedium: TextStyle(
          fontSize: 16, height: 1.3, letterSpacing: -0.1, color: ink,
          fontWeight: FontWeight.w600),
      titleSmall: TextStyle(
          fontSize: 14, height: 1.3, color: ink, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: ink),
      bodyMedium: TextStyle(fontSize: 14.5, height: 1.5, color: ink),
      bodySmall: TextStyle(fontSize: 13, height: 1.45, color: soft),
      labelLarge: TextStyle(
          fontSize: 14.5, height: 1.2, letterSpacing: 0.1, color: ink,
          fontWeight: FontWeight.w600),
      labelMedium: TextStyle(
          fontSize: 13, height: 1.2, color: ink, fontWeight: FontWeight.w600),
      labelSmall: TextStyle(
          fontSize: 11.5, height: 1.2, letterSpacing: 0.2, color: soft,
          fontWeight: FontWeight.w600),
    );
  }
}
