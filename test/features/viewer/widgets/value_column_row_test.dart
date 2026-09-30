// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/theme/wavecrux_colors.dart';
import 'package:wavecrux/core/theme/wavecrux_theme.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/value_column_provider.dart';
import 'package:wavecrux/features/viewer/widgets/value_column_row.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/waveform_geom/lane_geometry.dart';

import '../../../helpers/product_telemetry_config.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

final _signalEntry = SignalEntry.signal(
  signalRef: 'ref_clk',
  displayName: 'clk',
);

const _groupEntry = SignalEntry.group(groupName: 'CPU');

const _separatorEntry = SignalEntry.separator();

const _commentEntry = SignalEntry.comment(text: 'my comment');

const _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('ja'),
  Locale('ko'),
];

Widget _wrap(Widget child, {ProviderContainer? container, Locale? locale}) {
  final app = MaterialApp(
    theme: WavecruxTheme.dark,
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    locale: locale,
    home: Scaffold(body: child),
  );
  final scope = container != null
      ? UncontrolledProviderScope(container: container, child: app)
      : ProviderScope(overrides: [productTelemetryConfig], child: app);
  return scope;
}

Variable _v(String name) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: 'ref_$name',
  scopePath: 'top',
  bitWidth: 1,
);

void main() {
  group('ValueColumnRow — locale sweep', () {
    for (final locale in _locales) {
      testWidgets('signal row renders in $locale without exception', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(
            ValueColumnRow(
              entry: _signalEntry,
              signalValue: null,
            ),
            locale: locale,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      });

      testWidgets('group row renders in $locale without exception', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(
            const ValueColumnRow(entry: _groupEntry, signalValue: null),
            locale: locale,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      });

      testWidgets('separator row renders in $locale without exception', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(
            const ValueColumnRow(entry: _separatorEntry, signalValue: null),
            locale: locale,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      });

      testWidgets('comment row renders in $locale without exception', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(
            const ValueColumnRow(entry: _commentEntry, signalValue: null),
            locale: locale,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('ValueColumnRow — signal row display', () {
    testWidgets('shows em-dash when signalValue is null', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ValueColumnRow(entry: _signalEntry, signalValue: null),
        ),
      );
      await tester.pump();
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('shows formatted value when signalValue is provided', (
      tester,
    ) async {
      const sv = SignalValue(formatted: '0xff', rawValue: '11111111');
      await tester.pumpWidget(
        _wrap(
          ValueColumnRow(
            entry: _signalEntry,
            signalValue: sv,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('0xff'), findsOneWidget);
    });

    testWidgets('X value text uses xValue color', (tester) async {
      const sv = SignalValue(formatted: 'x', rawValue: 'x');
      await tester.pumpWidget(
        _wrap(
          ValueColumnRow(entry: _signalEntry, signalValue: sv),
        ),
      );
      await tester.pump();

      final text = tester.widget<Text>(find.text('x'));
      expect(text.style?.color, WavecruxColors.xValue);
    });

    testWidgets('Z value text uses zValue color', (tester) async {
      const sv = SignalValue(formatted: 'z', rawValue: 'z');
      await tester.pumpWidget(
        _wrap(
          ValueColumnRow(entry: _signalEntry, signalValue: sv),
        ),
      );
      await tester.pump();

      final text = tester.widget<Text>(find.text('z'));
      // Dark theme (default in tests) uses zValueDark.
      expect(text.style?.color, WavecruxColors.zValueDark);
    });

    testWidgets('uses monospace font family', (tester) async {
      const sv = SignalValue(formatted: '1', rawValue: '1');
      await tester.pumpWidget(
        _wrap(
          ValueColumnRow(entry: _signalEntry, signalValue: sv),
        ),
      );
      await tester.pump();

      final text = tester.widget<Text>(find.text('1'));
      expect(text.style?.fontFamily, WavecruxColors.monoFontFamily);
    });

    testWidgets('separator row has correct height', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ValueColumnRow(entry: _separatorEntry, signalValue: null),
        ),
      );
      await tester.pump();
      final box = tester.getSize(find.byType(SizedBox).first);
      expect(box.height, _separatorEntry.laneHeight);
    });

    testWidgets('comment row shows text', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ValueColumnRow(entry: _commentEntry, signalValue: null),
        ),
      );
      await tester.pump();
      expect(find.text('my comment'), findsOneWidget);
    });
  });

  group('ValueColumnRow — model-driven height (shared geometry)', () {
    // The default flutter_test host platform is touch, so MobileMetrics
    // resolves minLaneHeight = 44. These guard that ValueColumnRow sources
    // every row height from LaneGeometry (the one clamp + fixed-height site)
    // rather than re-deriving it — the original three-column divergence bug.
    testWidgets('signal row clamps stored laneHeight up to the touch min', (
      tester,
    ) async {
      // Stored 30 dp (default) renders at the 44 dp touch floor.
      await tester.pumpWidget(
        _wrap(ValueColumnRow(entry: _signalEntry, signalValue: null)),
      );
      await tester.pump();
      expect(tester.getSize(find.byType(ValueColumnRow)).height, 44);
    });

    testWidgets('group/separator/comment use centralized fixed heights', (
      tester,
    ) async {
      for (final (entry, expected) in <(SignalEntry, double)>[
        (_groupEntry, kGroupHeaderHeight),
        (_separatorEntry, kSeparatorHeight),
        (_commentEntry, kCommentHeight),
      ]) {
        await tester.pumpWidget(
          _wrap(ValueColumnRow(entry: entry, signalValue: null)),
        );
        await tester.pump();
        expect(
          tester.getSize(find.byType(ValueColumnRow)).height,
          expected,
          reason: '${entry.kind} row height',
        );
      }
    });
  });

  group('ValueColumnRow — format change', () {
    testWidgets('right-click opens context menu with format options', (
      tester,
    ) async {
      final container = ProviderContainer(overrides: [productTelemetryConfig]);
      addTearDown(container.dispose);
      container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));
      final entry = container.read(signalGroupsProvider).entries.first;

      await tester.pumpWidget(
        _wrap(
          ValueColumnRow(
            entry: entry,
            signalValue: const SignalValue(formatted: '1', rawValue: '1'),
          ),
          container: container,
        ),
      );
      await tester.pump();

      // Trigger secondary (right-click) tap.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(GestureDetector).first),
        buttons: kSecondaryButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      // The top-level menu collapses the formats behind a single "Display
      // Format" entry (issue #40) — the individual non-current format options
      // are NOT inline (Binary is not the default, so it must be absent here).
      expect(find.text('Display Format'), findsOneWidget);
      expect(find.text('Binary'), findsNothing);
      // Translator entries stay in the (short) top-level menu.
      expect(find.text('Custom translator…'), findsOneWidget);

      // Opening Display Format reveals the format options in the nested menu.
      await tester.tap(find.text('Display Format'));
      await tester.pumpAndSettle();
      expect(find.text('Binary'), findsOneWidget);
      expect(find.text('Hexadecimal'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the analog toggle is offered, applied and reversible', (
      tester,
    ) async {
      final container = ProviderContainer(overrides: [productTelemetryConfig]);
      addTearDown(container.dispose);
      container.read(signalGroupsProvider.notifier).addSignal(_v('data'));
      final entry = container.read(signalGroupsProvider).entries.first;

      Future<void> openMenu(SignalEntry current) async {
        await tester.pumpWidget(
          _wrap(
            ValueColumnRow(
              entry: current,
              signalValue: const SignalValue(formatted: 'ff', rawValue: '1'),
            ),
            container: container,
          ),
        );
        await tester.pump();
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(GestureDetector).first),
          buttons: kSecondaryButton,
        );
        await gesture.up();
        await tester.pumpAndSettle();
      }

      await openMenu(entry);
      expect(find.text('Render as analog'), findsOneWidget);
      expect(find.text('Render as digital'), findsNothing);

      await tester.tap(find.text('Render as analog'));
      await tester.pumpAndSettle();

      final updated = container.read(signalGroupsProvider).entries.first;
      expect(updated.renderAsAnalog, isTrue);
      // Orthogonal to the format: turning the curve on must not disturb how
      // the bits are read as a number.
      expect(updated.format, entry.format);

      // The label flips, so the same entry is the way back out.
      await openMenu(updated);
      expect(find.text('Render as digital'), findsOneWidget);
      expect(find.text('Render as analog'), findsNothing);

      await tester.tap(find.text('Render as digital'));
      await tester.pumpAndSettle();
      expect(
        container.read(signalGroupsProvider).entries.first.renderAsAnalog,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    });

    for (final locale in _locales) {
      testWidgets('the analog toggle is localized in $locale', (tester) async {
        final container = ProviderContainer(
          overrides: [productTelemetryConfig],
        );
        addTearDown(container.dispose);
        container.read(signalGroupsProvider.notifier).addSignal(_v('data'));
        final entry = container.read(signalGroupsProvider).entries.first;

        await tester.pumpWidget(
          _wrap(
            ValueColumnRow(
              entry: entry,
              signalValue: const SignalValue(formatted: 'ff', rawValue: '1'),
            ),
            container: container,
            locale: locale,
          ),
        );
        await tester.pump();
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(GestureDetector).first),
          buttons: kSecondaryButton,
        );
        await gesture.up();
        await tester.pumpAndSettle();

        final l10n = L10N.of(
          tester.element(find.byType(ValueColumnRow)),
        );
        expect(find.text(l10n.valueColumnRenderAsAnalog), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('selecting a format updates SignalGroupsNotifier', (
      tester,
    ) async {
      final container = ProviderContainer(overrides: [productTelemetryConfig]);
      addTearDown(container.dispose);
      container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));
      // Use the actual notifier entry so its UUID matches the one setSignalFormatById targets.
      final entry = container.read(signalGroupsProvider).entries.first;

      await tester.pumpWidget(
        _wrap(
          ValueColumnRow(
            entry: entry,
            signalValue: const SignalValue(formatted: '1', rawValue: '1'),
          ),
          container: container,
        ),
      );
      await tester.pump();

      // Open context menu via right-click.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(GestureDetector).first),
        buttons: kSecondaryButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      // Open the nested format menu, then tap 'Binary'.
      await tester.tap(find.text('Display Format'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Binary'));
      await tester.pumpAndSettle();

      expect(
        container.read(signalGroupsProvider).entries.first.format,
        DisplayFormat.binary,
      );
    });
  });

  group('ValueColumnRow — signal selection', () {
    testWidgets('Ctrl/Cmd-click on the value cell toggles the selection', (
      tester,
    ) async {
      // Drives the value cell's modifier branch — the Ctrl/Cmd-click selection
      // path mirroring VariableTreeLeaf. pumpAndSettle after each gesture
      // flushes both the PlatformContextMenu gesture recognizers and Riverpod's
      // auto-dispose scheduler so no Timer leaks into teardown.
      final container = ProviderContainer(overrides: [productTelemetryConfig]);
      addTearDown(container.dispose);
      container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));
      final entry = container.read(signalGroupsProvider).entries.first;

      await tester.pumpWidget(
        _wrap(
          ValueColumnRow(
            entry: entry,
            signalValue: const SignalValue(formatted: '1', rawValue: '1'),
          ),
          container: container,
        ),
      );
      await tester.pumpAndSettle();
      expect(container.read(selectedVariablesProvider), isEmpty);

      final cell = tester.getCenter(find.text('1'));
      await simulateKeyDownEvent(LogicalKeyboardKey.controlLeft);
      final g = await tester.startGesture(cell);
      await g.up();
      await simulateKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(
        container.read(selectedVariablesProvider),
        contains(entry.signalPath),
      );
    });

    testWidgets('selected row paints the selection tint', (tester) async {
      final container = ProviderContainer(overrides: [productTelemetryConfig]);
      addTearDown(container.dispose);
      container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));
      final entry = container.read(signalGroupsProvider).entries.first;
      container
          .read(selectedVariablesProvider.notifier)
          .selectOnly(entry.signalPath!);

      await tester.pumpWidget(
        _wrap(
          ValueColumnRow(
            entry: entry,
            signalValue: const SignalValue(formatted: '1', rawValue: '1'),
          ),
          container: container,
        ),
      );
      // pumpAndSettle so Riverpod's auto-dispose scheduler timer (armed by the
      // selectOnly read above) flushes and does not trip the pending-timer
      // teardown invariant.
      await tester.pumpAndSettle();

      final expectedTint = WavecruxTheme.dark.colorScheme.primary.withValues(
        alpha: 0.18,
      );
      final tinted = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.color == expectedTint);
      expect(
        tinted,
        isNotEmpty,
        reason: 'a selected signal row should paint the primary tint',
      );
    });

    testWidgets('unselected row does not paint the selection tint', (
      tester,
    ) async {
      final container = ProviderContainer(overrides: [productTelemetryConfig]);
      addTearDown(container.dispose);
      container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));
      final entry = container.read(signalGroupsProvider).entries.first;

      await tester.pumpWidget(
        _wrap(
          ValueColumnRow(
            entry: entry,
            signalValue: const SignalValue(formatted: '1', rawValue: '1'),
          ),
          container: container,
        ),
      );
      await tester.pump();

      final expectedTint = WavecruxTheme.dark.colorScheme.primary.withValues(
        alpha: 0.18,
      );
      final tinted = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.color == expectedTint);
      expect(tinted, isEmpty);
    });

    testWidgets('touch context menu "Select Signal" toggles the selection', (
      tester,
    ) async {
      final container = ProviderContainer(overrides: [productTelemetryConfig]);
      addTearDown(container.dispose);
      container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));
      final entry = container.read(signalGroupsProvider).entries.first;

      await tester.pumpWidget(
        _wrap(
          ValueColumnRow(
            entry: entry,
            signalValue: const SignalValue(formatted: '1', rawValue: '1'),
          ),
          container: container,
        ),
      );
      await tester.pump();

      // Right-click opens the context menu (same path the long-press
      // PlatformContextMenu uses on touch).
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(GestureDetector).first),
        buttons: kSecondaryButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Select Signal'), findsOneWidget);
      await tester.tap(find.text('Select Signal'));
      await tester.pumpAndSettle();

      expect(
        container.read(selectedVariablesProvider),
        contains(entry.signalPath),
      );
    });
  });
}
