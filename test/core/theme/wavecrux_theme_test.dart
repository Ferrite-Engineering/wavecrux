// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/theme/wavecrux_colors.dart';
import 'package:wavecrux/core/theme/wavecrux_theme.dart';
import 'package:wavecrux/core/theme/wavecrux_theme_tokens.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    if (!ThemeRegistry.instance.hasCategory(canvasTokens.id)) {
      registerWaveCruxThemeTokens();
    }
  });

  group('WavecruxTheme', () {
    group('dark theme', () {
      test('uses Material 3', () {
        expect(WavecruxTheme.dark.useMaterial3, isTrue);
      });

      test('has dark brightness', () {
        expect(
          WavecruxTheme.dark.colorScheme.brightness,
          equals(Brightness.dark),
        );
      });

      test('scaffold background is near-black', () {
        expect(
          WavecruxTheme.dark.scaffoldBackgroundColor,
          equals(WavecruxColors.darkBackground),
        );
      });

      test('app bar background matches dark surface', () {
        expect(
          WavecruxTheme.dark.appBarTheme.backgroundColor,
          equals(WavecruxColors.darkSurface),
        );
      });

      test('bodySmall uses monospace font', () {
        expect(
          WavecruxTheme.dark.textTheme.bodySmall?.fontFamily,
          equals(WavecruxColors.monoFontFamily),
        );
      });

      test('labelSmall uses monospace font', () {
        expect(
          WavecruxTheme.dark.textTheme.labelSmall?.fontFamily,
          equals(WavecruxColors.monoFontFamily),
        );
      });

      test('contains WavecruxColorExtension', () {
        expect(
          WavecruxTheme.dark.extension<WavecruxColorExtension>(),
          isNotNull,
        );
      });

      test('WavecruxColorExtension has correct signal green', () {
        final ext = WavecruxTheme.dark.extension<WavecruxColorExtension>()!;
        expect(ext.signalGreen, equals(WavecruxColors.signalGreen));
      });

      test('error color is xValue red', () {
        expect(
          WavecruxTheme.dark.colorScheme.error,
          equals(WavecruxColors.xValue),
        );
      });

      // ── desktop menu bar theming (native-like Windows/Linux MenuBar) ────────

      test('menu bar background matches dark surface', () {
        final bg = WavecruxTheme.dark.menuBarTheme.style?.backgroundColor
            ?.resolve(<WidgetState>{});
        expect(bg, equals(WavecruxColors.darkSurface));
      });

      test('menu bar has no elevation (flat strip)', () {
        final elevation = WavecruxTheme.dark.menuBarTheme.style?.elevation
            ?.resolve(<WidgetState>{});
        expect(elevation, equals(0));
      });

      test('menu button text is regular weight, not bold', () {
        final style = WavecruxTheme.dark.menuButtonTheme.style?.textStyle
            ?.resolve(<WidgetState>{});
        expect(style?.fontWeight, equals(FontWeight.w400));
      });

      test(
        'menu button text is 13px (native size, not 14px Material default)',
        () {
          final style = WavecruxTheme.dark.menuButtonTheme.style?.textStyle
              ?.resolve(<WidgetState>{});
          expect(style?.fontSize, equals(13));
        },
      );

      test('menu button has a visible hover overlay', () {
        final overlay = WavecruxTheme.dark.menuButtonTheme.style?.overlayColor;
        expect(
          overlay?.resolve(<WidgetState>{WidgetState.hovered}),
          isNotNull,
        );
        // Idle (no states) must NOT paint an overlay.
        expect(overlay?.resolve(<WidgetState>{}), isNull);
      });

      test('disabled menu item is dimmed', () {
        final fg = WavecruxTheme.dark.menuButtonTheme.style?.foregroundColor;
        final enabled = fg?.resolve(<WidgetState>{});
        final disabled = fg?.resolve(<WidgetState>{WidgetState.disabled});
        expect(disabled, isNot(equals(enabled)));
      });

      test('dropdown menu surface matches the popup menu surface', () {
        final menuBg = WavecruxTheme.dark.menuTheme.style?.backgroundColor
            ?.resolve(<WidgetState>{});
        expect(menuBg, equals(WavecruxColors.darkSurfaceVariant));
      });
    });

    group('light theme', () {
      test('uses Material 3', () {
        expect(WavecruxTheme.light.useMaterial3, isTrue);
      });

      test('has light brightness', () {
        expect(
          WavecruxTheme.light.colorScheme.brightness,
          equals(Brightness.light),
        );
      });

      test('scaffold background is light', () {
        expect(
          WavecruxTheme.light.scaffoldBackgroundColor,
          equals(WavecruxColors.lightBackground),
        );
      });

      test('contains WavecruxColorExtension', () {
        expect(
          WavecruxTheme.light.extension<WavecruxColorExtension>(),
          isNotNull,
        );
      });
    });

    test('dark and light have different scaffold backgrounds', () {
      expect(
        WavecruxTheme.dark.scaffoldBackgroundColor,
        isNot(equals(WavecruxTheme.light.scaffoldBackgroundColor)),
      );
    });

    test(
      'dark and light instances are stable (same object on repeated access)',
      () {
        expect(WavecruxTheme.dark, same(WavecruxTheme.dark));
        expect(WavecruxTheme.light, same(WavecruxTheme.light));
      },
    );
  });

  group('WavecruxColorExtension', () {
    const dark = WavecruxColorExtension.dark();
    const light = WavecruxColorExtension.light();

    test('dark and light share the same signalGreen', () {
      expect(dark.signalGreen, equals(light.signalGreen));
    });

    test('dark and light have different zValue (legibility adjustment)', () {
      expect(dark.zValue, isNot(equals(light.zValue)));
    });

    group('copyWith', () {
      test('returns equal values when no arguments provided', () {
        final copy = dark.copyWith();
        expect(copy.signalGreen, equals(dark.signalGreen));
        expect(copy.xValue, equals(dark.xValue));
        expect(copy.zValue, equals(dark.zValue));
      });

      test('overrides only the specified field', () {
        const newColor = Color(0xFFFF0000);
        final copy = dark.copyWith(signalGreen: newColor);
        expect(copy.signalGreen, equals(newColor));
        expect(copy.signalCyan, equals(dark.signalCyan));
        expect(copy.xValue, equals(dark.xValue));
      });
    });

    group('lerp', () {
      test('at t=0 returns original colors', () {
        final result = dark.lerp(light, 0);
        expect(result.signalGreen, equals(dark.signalGreen));
        expect(result.zValue, equals(dark.zValue));
      });

      test('at t=1 returns other colors', () {
        final result = dark.lerp(light, 1);
        expect(result.zValue, equals(light.zValue));
      });

      test('with null returns self', () {
        final result = dark.lerp(null, 0.5);
        expect(result.signalGreen, equals(dark.signalGreen));
      });
    });
  });

  group('CruxThemeExtension (chrome)', () {
    testWidgets('WavecruxTheme.dark contains non-null CruxThemeExtension', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WavecruxTheme.dark,
          locale: const Locale('en'),
          localizationsDelegates: L10N.localizationsDelegates,
          home: Builder(
            builder: (context) {
              final ext = Theme.of(context).extension<CruxThemeExtension>();
              expect(ext, isNotNull);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('WavecruxTheme widget tests', () {
    testWidgets('dark theme renders in en without exception', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WavecruxTheme.dark,
          locale: const Locale('en'),
          localizationsDelegates: L10N.localizationsDelegates,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('light theme renders in en without exception', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WavecruxTheme.light,
          locale: const Locale('en'),
          localizationsDelegates: L10N.localizationsDelegates,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
