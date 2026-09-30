// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:wavecrux/core/theme/wavecrux_colors.dart';

/// WaveCrux Material 3 theme definitions.
///
/// Dark is the default (engineering-tool aesthetic — near-black background,
/// muted borders, high-contrast signal colors). Light is available for bright
/// environments.
///
/// Both themes expose a [WavecruxColorExtension] via
/// `Theme.of(context).extension<WavecruxColorExtension>()!` for
/// waveform-domain color tokens that are independent of the Material palette.
abstract final class WavecruxTheme {
  /// Dark theme — default engineering-tool aesthetic.
  ///
  /// Computed once and reused; not recreated on every widget build.
  static final ThemeData dark = _build(brightness: Brightness.dark);

  /// Light theme — alternative for bright work environments.
  ///
  /// Computed once and reused; not recreated on every widget build.
  static final ThemeData light = _build(brightness: Brightness.light);

  /// High-contrast dark theme — used when the platform reports high-contrast
  /// accessibility mode is active. Passed to [MaterialApp.highContrastDarkTheme].
  static final ThemeData highContrastDark = _build(
    brightness: Brightness.dark,
    highContrast: true,
  );

  /// High-contrast light theme — used when the platform reports high-contrast
  /// accessibility mode is active. Passed to [MaterialApp.highContrastTheme].
  static final ThemeData highContrastLight = _build(
    brightness: Brightness.light,
    highContrast: true,
  );

  static ThemeData _build({
    required Brightness brightness,
    bool highContrast = false,
  }) {
    final isDark = brightness == Brightness.dark;

    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: WavecruxColors.signalGreen,
          brightness: brightness,
        ).copyWith(
          surface: isDark
              ? WavecruxColors.darkSurface
              : WavecruxColors.lightSurface,
          surfaceContainerHighest: isDark
              ? WavecruxColors.darkSurfaceVariant
              : WavecruxColors.lightSurfaceVariant,
          // High-contrast mode: use fully-opaque, high-visibility border colors.
          outline: highContrast
              ? (isDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000))
              : (isDark
                    ? WavecruxColors.darkBorder
                    : WavecruxColors.lightBorder),
          outlineVariant: highContrast
              ? (isDark ? const Color(0xFFCCCCCC) : const Color(0xFF333333))
              : (isDark
                    ? WavecruxColors.darkBorderSubtle
                    : WavecruxColors.lightBorderSubtle),
          error: WavecruxColors.xValue,
        );

    const monoStyle = TextStyle(
      fontFamily: WavecruxColors.monoFontFamily,
      fontFamilyFallback: WavecruxColors.monoFontFamilyFallback,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isDark
          ? WavecruxColors.darkBackground
          : WavecruxColors.lightBackground,

      // Body/UI labels use system sans-serif (Flutter default).
      // bodySmall and labelSmall are monospace for signal values and time labels.
      textTheme: TextTheme(
        bodySmall: monoStyle.copyWith(fontSize: 12, letterSpacing: 0.2),
        labelSmall: monoStyle.copyWith(fontSize: 11, letterSpacing: 0.4),
        bodyMedium: const TextStyle(fontSize: 13),
        bodyLarge: const TextStyle(fontSize: 14),
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: isDark
            ? WavecruxColors.darkSurface
            : WavecruxColors.lightSurface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        titleTextStyle: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: colorScheme.onSurface,
        ),
      ),

      // 1dp panel separators — dense layout, no visual noise.
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),

      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerHighest,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        margin: EdgeInsets.zero,
      ),

      // Dense list rows for signal tree and settings panels.
      listTileTheme: ListTileThemeData(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        minVerticalPadding: 2,
        iconColor: colorScheme.onSurface.withValues(alpha: 0.7),
      ),

      iconTheme: IconThemeData(
        size: 18,
        color: colorScheme.onSurface.withValues(alpha: 0.8),
      ),

      // Compact text fields used for signal search and name filtering.
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(
            color: colorScheme.primary,
            width: highContrast ? 2.5 : 1.5,
          ),
        ),
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        hintStyle: TextStyle(
          color: colorScheme.onSurface.withValues(alpha: 0.4),
          fontSize: 13,
        ),
      ),

      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(
          colorScheme.onSurface.withValues(alpha: isDark ? 0.3 : 0.2),
        ),
        thickness: WidgetStateProperty.all(4),
        radius: const Radius.circular(2),
        crossAxisMargin: 2,
      ),

      // Compact dark tooltips — same appearance in both themes for legibility.
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A35),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        textStyle: const TextStyle(fontSize: 12, color: Color(0xFFE1E1E8)),
        waitDuration: const Duration(milliseconds: 600),
        showDuration: const Duration(seconds: 4),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: isDark
            ? WavecruxColors.darkSurfaceVariant
            : WavecruxColors.lightSurface,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        textStyle: TextStyle(fontSize: 13, color: colorScheme.onSurface),
      ),

      // ── Desktop menu bar (Windows / Linux in-window MenuBar) ────────────────
      // The macOS menu bar is drawn by the OS and ignores this theme; these
      // tokens make the Flutter-drawn Material MenuBar on Windows/Linux read
      // like a native desktop menu (compact, regular-weight, left-aligned, clear
      // hover) instead of the chunky bold Material 3 default. See
      // `features/menu_bar/widgets/desktop_menu_bar.dart`.
      //
      // `menuButtonTheme` styles both the top-level [SubmenuButton]s in the bar
      // and the [MenuItemButton]s inside each dropdown — both consume
      // [MenuButtonThemeData]. `menuBarTheme` styles the bar strip itself;
      // `menuTheme` styles the popped-up dropdown panels (matching the
      // [popupMenuTheme] surface above for consistency).
      menuBarTheme: MenuBarThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(
            isDark ? WavecruxColors.darkSurface : WavecruxColors.lightSurface,
          ),
          elevation: const WidgetStatePropertyAll(0),
          // Square corners + thin strip; full-bleed so it reads as a title-bar
          // menu strip rather than a floating Material surface.
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 4),
          ),
          minimumSize: const WidgetStatePropertyAll(Size(0, 32)),
        ),
      ),
      menuButtonTheme: MenuButtonThemeData(
        style: ButtonStyle(
          // ~13px regular — native menus are not bold and not 14px+.
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
          ),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return colorScheme.onSurface.withValues(alpha: 0.38);
            }
            return colorScheme.onSurface;
          }),
          iconColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return colorScheme.onSurface.withValues(alpha: 0.38);
            }
            return colorScheme.onSurface.withValues(alpha: 0.8);
          }),
          // Explicit, clearly-visible hover/focus/press highlight — the Material
          // default overlay is nearly invisible on the dark surface.
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return colorScheme.onSurface.withValues(alpha: 0.14);
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return colorScheme.onSurface.withValues(alpha: 0.08);
            }
            return null;
          }),
          // Keyboard-focused menu (Alt access-key navigation) gets a clear
          // primary outline — the VS Code "focused menu" frame — so arrow-key
          // traversal is obvious. Mouse hover relies on the overlay fill above.
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return BorderSide(color: colorScheme.primary, width: 1.5);
            }
            return BorderSide.none;
          }),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12),
          ),
          minimumSize: const WidgetStatePropertyAll(Size(0, 30)),
          // Slight rounding so the focus outline reads as a framed rectangle.
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(3)),
            ),
          ),
          visualDensity: VisualDensity.compact,
          // Dropdown items span the panel width; keep label + icon left-aligned.
          alignment: Alignment.centerLeft,
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(
            isDark
                ? WavecruxColors.darkSurfaceVariant
                : WavecruxColors.lightSurface,
          ),
          elevation: const WidgetStatePropertyAll(4),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 4),
          ),
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return colorScheme.primary;
          return colorScheme.onSurface.withValues(alpha: 0.4);
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary.withValues(alpha: 0.3);
          }
          return colorScheme.onSurface.withValues(alpha: 0.15);
        }),
      ),

      extensions: [
        if (isDark)
          const WavecruxColorExtension.dark()
        else
          const WavecruxColorExtension.light(),
        // Default chrome extension — wraps an empty CruxColorTheme so
        // WaveCruxChromeAccessors getters all return null and chrome
        // widgets fall back to the active ColorScheme. app.dart
        // replaces this with a CruxThemeExtension wrapping the active
        // cruxColorThemeProvider state whenever the theme changes.
        _emptyCruxThemeExtension,
      ],
    );
  }
}

/// Empty-state `CruxThemeExtension` used as the default chrome
/// extension in `WavecruxTheme.dark` / `.light`. Wraps a
/// `CruxColorTheme` with no token overrides so every
/// `WaveCruxChromeAccessors` getter returns null and chrome widgets
/// fall back to the active `ColorScheme`.
final CruxThemeExtension _emptyCruxThemeExtension = CruxThemeExtension(
  theme: CruxColorTheme(
    id: 'wavecrux-bootstrap-empty',
    displayName: 'WaveCrux Bootstrap (empty)',
    brightness: Brightness.dark,
    tokens: const <String, Map<String, Color>>{},
  ),
);

/// Theme extension carrying waveform-domain color tokens.
///
/// Provides signal colors, waveform-state colors (X, Z), and the tick colors
/// the side panels and the time ruler's major ticks use. These tokens are
/// domain-specific and independent of the Material color palette. The
/// cursors, markers and the rest of the ruler are colored by the active
/// canvas theme instead (`WaveCruxThemeAccessors`).
///
/// Retrieve via:
/// ```dart
/// final waveColors = Theme.of(context).extension<WavecruxColorExtension>()!;
/// ```
@immutable
class WavecruxColorExtension extends ThemeExtension<WavecruxColorExtension> {
  /// Creates a [WavecruxColorExtension] with all required color tokens.
  const WavecruxColorExtension({
    required this.signalGreen,
    required this.signalCyan,
    required this.signalYellow,
    required this.signalMagenta,
    required this.signalOrange,
    required this.signalWhite,
    required this.xValue,
    required this.xValueHatch,
    required this.zValue,
    required this.selectionHighlight,
    required this.timeRulerTick,
    required this.timeRulerMajorTick,
  });

  /// Color tokens optimized for dark backgrounds (default).
  const WavecruxColorExtension.dark()
    : this(
        signalGreen: WavecruxColors.signalGreen,
        signalCyan: WavecruxColors.signalCyan,
        signalYellow: WavecruxColors.signalYellow,
        signalMagenta: WavecruxColors.signalMagenta,
        signalOrange: WavecruxColors.signalOrange,
        signalWhite: WavecruxColors.signalWhite,
        xValue: WavecruxColors.xValue,
        xValueHatch: WavecruxColors.xValueHatch,
        zValue: WavecruxColors.zValueDark,
        selectionHighlight: WavecruxColors.selectionHighlight,
        timeRulerTick: WavecruxColors.timeRulerTick,
        timeRulerMajorTick: WavecruxColors.timeRulerMajorTick,
      );

  /// Color tokens adapted for light backgrounds.
  ///
  /// Signal colors are preserved (engineering convention); the white signal
  /// and the Z-state color are darkened for legibility against
  /// white/light-gray surfaces.
  const WavecruxColorExtension.light()
    : this(
        signalGreen: WavecruxColors.signalGreen,
        signalCyan: WavecruxColors.signalCyan,
        signalYellow: WavecruxColors.signalYellow,
        signalMagenta: WavecruxColors.signalMagenta,
        signalOrange: WavecruxColors.signalOrange,
        // Pure #EEE is invisible on light backgrounds; use medium gray.
        signalWhite: const Color(0xFF9E9E9E),
        xValue: WavecruxColors.xValue,
        xValueHatch: WavecruxColors.xValueHatch,
        zValue: WavecruxColors.zValueLight,
        selectionHighlight: WavecruxColors.selectionHighlight,
        timeRulerTick: const Color(0xFF8888A0),
        timeRulerMajorTick: const Color(0xFF565668),
      );

  // ---------------------------------------------------------------------------
  // Signal colors
  // ---------------------------------------------------------------------------

  /// Green signal color.
  final Color signalGreen;

  /// Cyan signal color.
  final Color signalCyan;

  /// Yellow signal color.
  final Color signalYellow;

  /// Magenta signal color.
  final Color signalMagenta;

  /// Orange signal color.
  final Color signalOrange;

  /// White/gray signal color — adjusted for legibility on the active theme.
  final Color signalWhite;

  // ---------------------------------------------------------------------------
  // Waveform state
  // ---------------------------------------------------------------------------

  /// Fill color for unknown (X) states.
  final Color xValue;

  /// Hatch-line color drawn over [xValue] fill.
  final Color xValueHatch;

  /// Color for high-impedance (Z) dashed center line.
  final Color zValue;

  // ---------------------------------------------------------------------------
  // Selection
  // ---------------------------------------------------------------------------

  /// Time-range selection overlay fill.
  final Color selectionHighlight;

  // ---------------------------------------------------------------------------
  // Time ruler
  // ---------------------------------------------------------------------------

  /// Minor tick mark color.
  final Color timeRulerTick;

  /// Major tick mark color.
  final Color timeRulerMajorTick;

  // ---------------------------------------------------------------------------
  // ThemeExtension overrides
  // ---------------------------------------------------------------------------

  @override
  WavecruxColorExtension copyWith({
    Color? signalGreen,
    Color? signalCyan,
    Color? signalYellow,
    Color? signalMagenta,
    Color? signalOrange,
    Color? signalWhite,
    Color? xValue,
    Color? xValueHatch,
    Color? zValue,
    Color? selectionHighlight,
    Color? timeRulerTick,
    Color? timeRulerMajorTick,
  }) {
    return WavecruxColorExtension(
      signalGreen: signalGreen ?? this.signalGreen,
      signalCyan: signalCyan ?? this.signalCyan,
      signalYellow: signalYellow ?? this.signalYellow,
      signalMagenta: signalMagenta ?? this.signalMagenta,
      signalOrange: signalOrange ?? this.signalOrange,
      signalWhite: signalWhite ?? this.signalWhite,
      xValue: xValue ?? this.xValue,
      xValueHatch: xValueHatch ?? this.xValueHatch,
      zValue: zValue ?? this.zValue,
      selectionHighlight: selectionHighlight ?? this.selectionHighlight,
      timeRulerTick: timeRulerTick ?? this.timeRulerTick,
      timeRulerMajorTick: timeRulerMajorTick ?? this.timeRulerMajorTick,
    );
  }

  @override
  WavecruxColorExtension lerp(
    WavecruxColorExtension? other,
    double t,
  ) {
    if (other is! WavecruxColorExtension) return this;
    return WavecruxColorExtension(
      signalGreen: Color.lerp(signalGreen, other.signalGreen, t)!,
      signalCyan: Color.lerp(signalCyan, other.signalCyan, t)!,
      signalYellow: Color.lerp(signalYellow, other.signalYellow, t)!,
      signalMagenta: Color.lerp(signalMagenta, other.signalMagenta, t)!,
      signalOrange: Color.lerp(signalOrange, other.signalOrange, t)!,
      signalWhite: Color.lerp(signalWhite, other.signalWhite, t)!,
      xValue: Color.lerp(xValue, other.xValue, t)!,
      xValueHatch: Color.lerp(xValueHatch, other.xValueHatch, t)!,
      zValue: Color.lerp(zValue, other.zValue, t)!,
      selectionHighlight: Color.lerp(
        selectionHighlight,
        other.selectionHighlight,
        t,
      )!,
      timeRulerTick: Color.lerp(timeRulerTick, other.timeRulerTick, t)!,
      timeRulerMajorTick: Color.lerp(
        timeRulerMajorTick,
        other.timeRulerMajorTick,
        t,
      )!,
    );
  }
}

// Chrome color overrides live on `crux_theme`'s `CruxThemeExtension`;
// `app.dart` folds them into the Material theme with `applyChromeTokens`,
// so chrome widgets read ordinary `ColorScheme` roles rather than tokens.
// The default empty extension is `_emptyCruxThemeExtension`, registered
// above; `app.dart` replaces it at every active-theme rebuild.
