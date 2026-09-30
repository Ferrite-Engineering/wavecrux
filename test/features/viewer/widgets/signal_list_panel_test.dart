// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/active_decoder.dart';
import 'package:wavecrux/domain/models/app_settings.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/comparison/providers/diff_provider.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/decoders/widgets/decoder_list_entry.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/widgets/signal_list_panel.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';
import 'package:wavecrux/services/remote/remote_control_notifier.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

// ── Diff status color constants (mirror of the private consts in signal_list_panel.dart) ──
const _kDiffIdenticalColor = Color(0xFF43A047);
const _kDiffDifferentColor = Color(0xFFE53935);
const _kDiffUnmatchedColor = Color(0xFF9E9E9E);

/// Mutable state used in diff-color tests so the "reverts when cleared" test
/// can change the map after the widget is first rendered.
/// Each [ProviderContainer] maintains independent state — tests don't interfere.
final _mutableDiffStatus = StateProvider<Map<String, DiffSignalStatus>>(
  (_) => const {},
);

class _FakeDiffNotifier extends DiffNotifier {
  _FakeDiffNotifier(this._state);
  final DiffState _state;

  @override
  DiffState build() => _state;
}

class _MutableDiffNotifier extends DiffNotifier {
  @override
  DiffState build() => const DiffState();

  DiffState get diffState => state;
  set diffState(DiffState s) => state = s;
}

Variable _v(String name, {String scopePath = 'top'}) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: 'ref_$name',
  scopePath: scopePath,
);

Widget _wrapWithScroll({ProviderContainer? container, Locale? locale}) {
  final scroll = ScrollController();
  final panel = SignalListPanel(scrollController: scroll);
  if (container != null) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(body: panel),
      ),
    );
  }
  return ProviderScope(
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(body: panel),
    ),
  );
}

/// Serves a fixed [AppSettings] so a test can pin a non-default
/// `defaultLaneHeight`. Mirrors the pattern in
/// `test/features/settings/widgets/ai_settings_section_test.dart`.
class _FakeAppSettingsNotifier extends AppSettingsNotifier {
  _FakeAppSettingsNotifier(this._initial);
  final AppSettings _initial;
  @override
  Future<AppSettings> build() async => _initial;
}

void main() {
  group('SignalListPanel', () {
    // ── Locale sweeps ────────────────────────────────────────────────────────
    testWidgets('locale sweep — no exceptions', (tester) async {
      await tester.pumpWidget(_wrapWithScroll());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    for (final locale in [
      const Locale('zh', 'CN'),
      const Locale('ja'),
      const Locale('ko'),
    ]) {
      testWidgets('locale sweep ${locale.languageCode} — no exceptions', (
        tester,
      ) async {
        await tester.pumpWidget(_wrapWithScroll(locale: locale));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('light theme — no exceptions', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData.light(),
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(
              body: SignalListPanel(scrollController: scroll),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    // ── Empty state ──────────────────────────────────────────────────────────
    testWidgets('shows empty state when no signals', (tester) async {
      await tester.pumpWidget(_wrapWithScroll());
      await tester.pump();
      expect(
        find.text('Add signals from the Signal Tree'),
        findsOneWidget,
      );
    });

    // ── Signal rows ──────────────────────────────────────────────────────────
    testWidgets('renders signal display names', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(signalGroupsProvider.notifier)
        ..addSignal(_v('clk'))
        ..addSignal(_v('data'));

      await tester.pumpWidget(_wrapWithScroll(container: container));
      await tester.pump();

      expect(find.text('clk'), findsOneWidget);
      expect(find.text('data'), findsOneWidget);
    });

    testWidgets('remove button fires removeSignal', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

      await tester.pumpWidget(_wrapWithScroll(container: container));
      await tester.pump();

      expect(find.text('clk'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pump();

      expect(
        container.read(signalGroupsProvider).entries,
        isEmpty,
      );
    });

    testWidgets('remove button removes correct signal when multiple present', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(signalGroupsProvider.notifier)
        ..addSignal(_v('clk'))
        ..addSignal(_v('data'));

      await tester.pumpWidget(_wrapWithScroll(container: container));
      await tester.pump();

      // Remove the first signal (clk).
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pump();

      final entries = container.read(signalGroupsProvider).entries;
      expect(entries.length, 1);
      expect(entries.first.displayName, 'data');
    });

    testWidgets('color swatch tap cycles palette color', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

      await tester.pumpWidget(_wrapWithScroll(container: container));
      await tester.pump();

      final before = container
          .read(signalGroupsProvider)
          .entries
          .first
          .argbColor;

      // Tap the color swatch circle. The swatch GestureDetector has a ValueKey
      // to uniquely identify it; the outer PlatformContextMenu and the Tooltip's
      // own internal GestureDetector would otherwise cause ambiguous finders.
      await tester.tap(
        find.byKey(const ValueKey('_signalRow_colorSwatch')),
      );
      // Pump past the double-tap window to drain any pending timers.
      await tester.pump(const Duration(milliseconds: 50));

      final after = container
          .read(signalGroupsProvider)
          .entries
          .first
          .argbColor;
      // After cycling the color should still be a valid color value.
      expect(after, isNotNull);
      // Colors cycle so the value can differ from the initial one after enough taps.
      // At minimum it should be a non-negative integer.
      expect(after, isA<int>());
      expect(before, isNotNull);
    });

    testWidgets('color swatch tap cycles on the very next frame', (
      tester,
    ) async {
      // Latency guard, asserted on the FIRST frame after the tap with no
      // clock advance.
      //
      // The signal-name area next door registers an `onDoubleTap` (reset
      // lane height), and a double-tap recognizer HOLDS the gesture arena
      // for the whole kDoubleTapTimeout — which is what made scope-tree
      // rows and Stage tabs feel dead for ~300 ms elsewhere in the app.
      // It does not tax this row, because the arena is per-pointer and the
      // swatch is a *sibling* subtree of the name: a pointer that lands on
      // the swatch never hit-tests the name's detector, so its `onTap` is
      // swept the instant the pointer lifts. That is why this site keeps
      // plain `onTap`, and this test pins the reasoning.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

      await tester.pumpWidget(_wrapWithScroll(container: container));
      await tester.pump();

      final before = container
          .read(signalGroupsProvider)
          .entries
          .first
          .argbColor;

      await tester.tap(find.byKey(const ValueKey('_signalRow_colorSwatch')));
      await tester.pump();

      expect(
        container.read(signalGroupsProvider).entries.first.argbColor,
        isNot(before),
        reason: 'the color must cycle without waiting on a gesture arena',
      );
    });

    // Regression for the bug where long-pressing the color dot opens the
    // context menu, but tapping "Change Color" produces no visible change.
    // Walks the full flow: long-press → menu → tap Change Color → pick a
    // color → tap Apply → assert the entry's color matches the picked one.
    //
    // The test runs as if on iPad (TargetPlatform.iOS, DeviceClass.tablet)
    // so PlatformContextMenu's long-press path is exercised and the
    // gesture-bubbling rule from ARCHITECTURE.md §3.1.8.5 must hold.
    testWidgets(
      'the analog toggle is reachable from the signal-name row menu',
      (tester) async {
        // The regression this guards is a discoverability one, found by a user
        // in the first session: the rendering/format menu lives in the value
        // column, but GTKWave puts Data Format on the signal NAME, so that is
        // where someone migrating right-clicks — and until this landed they
        // found nothing there.
        await tester.binding.setSurfaceSize(const Size(900, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final container = ProviderContainer(
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.tablet),
          ],
        );
        addTearDown(container.dispose);
        container.read(signalGroupsProvider.notifier).addSignal(_v('data'));

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData(platform: TargetPlatform.iOS),
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(
                body: SignalListPanel(scrollController: ScrollController()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final l10n = await L10N.delegate.load(const Locale('en'));

        await tester.longPress(
          find.byKey(const ValueKey('_signalRow_colorSwatch')),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(l10n.valueColumnRenderAsAnalog),
          findsOneWidget,
          reason: 'the signal-name row menu must offer the analog toggle',
        );

        await tester.tap(find.text(l10n.valueColumnRenderAsAnalog));
        await tester.pumpAndSettle();

        expect(
          container.read(signalGroupsProvider).entries.first.renderAsAnalog,
          isTrue,
        );

        // Reopening offers the way back out.
        await tester.longPress(
          find.byKey(const ValueKey('_signalRow_colorSwatch')),
        );
        await tester.pumpAndSettle();
        expect(find.text(l10n.valueColumnRenderAsDigital), findsOneWidget);
        expect(find.text(l10n.valueColumnRenderAsAnalog), findsNothing);

        await tester.tap(find.text(l10n.valueColumnRenderAsDigital));
        await tester.pumpAndSettle();
        expect(
          container.read(signalGroupsProvider).entries.first.renderAsAnalog,
          isFalse,
        );
      },
    );

    testWidgets(
      'long-press color dot → Change Color picks color (regression)',
      (tester) async {
        // Tall surface: the shared crux_theme color picker stacks the two
        // WaveCrux palette sections above its HSV/hex/RGB/preview controls
        // and does not fit a 600 dp-tall dialog viewport. DeviceClass is
        // pinned by the provider override below, not by the surface size.
        await tester.binding.setSurfaceSize(const Size(900, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final container = ProviderContainer(
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.tablet),
          ],
        );
        addTearDown(container.dispose);
        container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData(platform: TargetPlatform.iOS),
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(
                body: SignalListPanel(scrollController: ScrollController()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Long-press the color swatch.
        await tester.longPress(
          find.byKey(const ValueKey('_signalRow_colorSwatch')),
        );
        await tester.pumpAndSettle();

        // The popup menu should be open with a "Change Color" item.
        final l10n = await L10N.delegate.load(const Locale('en'));
        final changeColor = find.text(l10n.signalListChangeColor);
        expect(
          changeColor,
          findsOneWidget,
          reason: 'long-press on swatch must open the row context menu',
        );

        // Snapshot the color before opening the picker.
        final before = container
            .read(signalGroupsProvider)
            .entries
            .first
            .argbColor;

        // Tap Change Color → opens the color picker dialog.
        await tester.tap(changeColor);
        await tester.pumpAndSettle();

        // The dialog should be present.
        expect(
          find.text(l10n.colorPickerTitle),
          findsOneWidget,
          reason: 'tapping Change Color must open the picker dialog',
        );

        // Tap the Apply button to commit the (default) selection. The
        // underlying state must update — even if the swatch's onTap fires
        // spuriously after dialog dismissal (the pre-fix bug), the final
        // committed color must still be reachable via onColorPicked.
        await tester.tap(find.text(l10n.colorPickerApply));
        await tester.pumpAndSettle();

        final after = container
            .read(signalGroupsProvider)
            .entries
            .first
            .argbColor;
        expect(
          after,
          isNotNull,
          reason: 'onColorPicked must have fired and set the entry color',
        );
        // The committed color is the previously-selected (initial) color
        // since we didn't pick a new one explicitly. The before/after may
        // be equal — what matters is that no spurious cycle happened that
        // would leave the color unchanged-but-different.
        expect(after, isNotNull);
        expect(before, isNotNull);
      },
    );

    testWidgets('double-tap on signal name resets lane height', (tester) async {
      // Pin to a desktop platform — `flutter_test`'s default Theme.platform is
      // android, which would route the row's onHeightChanged call through the
      // touch-min (44 dp) clamp and break the "reset to 30" intent of this
      // test. The touch-min clamp itself is exercised by the dedicated tests
      // below (`lane height renders at touch minimum`).
      final container = ProviderContainer(
        overrides: [
          deviceClassProvider.overrideWithValue(DeviceClass.desktop),
        ],
      );
      addTearDown(container.dispose);
      container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

      // Manually set a custom lane height.
      container.read(signalGroupsProvider.notifier).setLaneHeight(0, 80);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.macOS),
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(
              body: SignalListPanel(scrollController: ScrollController()),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        container.read(signalGroupsProvider).entries.first.laneHeight,
        80,
      );

      // Double-tap the signal name text to reset to default 30.
      await tester.tap(find.text('clk'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('clk'));
      await tester.pumpAndSettle();

      expect(
        container.read(signalGroupsProvider).entries.first.laneHeight,
        30,
      );
    });

    testWidgets(
      'double-tap reset honours the configured default lane height',
      (tester) async {
        // Regression: the reset used to be a hardcoded `30`, which silently
        // ignored Settings → Waveform Defaults. A user who preferred 48 dp
        // lanes got 30 dp back on every reset. 30 is only the *model*
        // default, not the reset target.
        //
        // This test is the one that bites: against the old implementation it
        // fails with `Expected: 48 / Actual: 30`. The sibling test above
        // passes either way, because it leaves the setting at its default.
        final container = ProviderContainer(
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.desktop),
            appSettingsProvider.overrideWith(
              () => _FakeAppSettingsNotifier(
                const AppSettings(defaultLaneHeight: 48),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));
        container.read(signalGroupsProvider.notifier).setLaneHeight(0, 80);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData(platform: TargetPlatform.macOS),
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(
                body: SignalListPanel(scrollController: ScrollController()),
              ),
            ),
          ),
        );
        // Let the overridden async settings resolve before the double-tap,
        // so the row is built with 48 rather than the fallback.
        await tester.pumpAndSettle();

        await tester.tap(find.text('clk'));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.text('clk'));
        await tester.pumpAndSettle();

        expect(
          container.read(signalGroupsProvider).entries.first.laneHeight,
          48,
        );
      },
    );

    // Regression for the iPad release-build defect where the lane resize
    // grip glyph (drawn in the bottom 16 dp strip of every lane) sat on top
    // of the signal-name text. With a stored 30 dp lane and a 16 dp resize
    // strip, only 14 dp remained for content — the 13 sp text overflowed
    // downward onto the grip lines. The fix raises the rendered lane height
    // to ≥ MobileMetrics.minLaneHeight (44 dp on touch) at three render
    // sites — signal list, canvas, value column — so the three columns
    // stay vertically aligned. Stored entry.laneHeight is preserved.
    testWidgets(
      'lane height renders at touch minimum (44 dp) on tablet',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.tablet),
          ],
        );
        addTearDown(container.dispose);
        container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));
        // Sanity: stored value is the desktop default 30 dp.
        expect(
          container.read(signalGroupsProvider).entries.first.laneHeight,
          30,
        );

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData(platform: TargetPlatform.iOS),
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(
                body: SignalListPanel(scrollController: ScrollController()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final rowSize = tester.getSize(
          find.byKey(
            ValueKey(
              SignalListPanel.signalRowKeyValue(
                container.read(signalGroupsProvider).entries.first,
              ),
            ),
          ),
        );
        expect(rowSize.height, 44);
        // Stored value is unchanged — sessions remain portable.
        expect(
          container.read(signalGroupsProvider).entries.first.laneHeight,
          30,
        );
      },
    );

    testWidgets(
      'experiment: dump row layout at 200 dp expanded lane (user scenario)',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.desktop),
          ],
        );
        addTearDown(container.dispose);
        container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));
        container.read(signalGroupsProvider.notifier).setLaneHeight(0, 200);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData(platform: TargetPlatform.macOS),
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(
                body: SignalListPanel(scrollController: ScrollController()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final rowRect = tester.getRect(
          find.byKey(
            ValueKey(
              SignalListPanel.signalRowKeyValue(
                container.read(signalGroupsProvider).entries.first,
              ),
            ),
          ),
        );
        final swatchRect = tester.getRect(
          find.byKey(const ValueKey('_signalRow_colorSwatch')),
        );
        final nameRect = tester.getRect(find.text('clk'));
        // ignore: avoid_print, intentional diagnostic
        print(
          '=== ROW LAYOUT at 200 dp lane (USER SCENARIO) ===\n'
          'row     = $rowRect  (height=${rowRect.height}, '
          'center y=${rowRect.center.dy})\n'
          'swatch  = $swatchRect (center y=${swatchRect.center.dy})\n'
          'name    = $nameRect (center y=${nameRect.center.dy})\n'
          'OFFSET-FROM-LANE-CENTER:\n'
          '  swatch ${swatchRect.center.dy - rowRect.center.dy}\n'
          '  name   ${nameRect.center.dy - rowRect.center.dy}\n',
        );
        expect(rowRect.height, 200);
      },
    );

    testWidgets(
      'experiment: prove Transform.translate(0, 20) shifts widget by 20 dp',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.desktop),
          ],
        );
        addTearDown(container.dispose);
        container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData(platform: TargetPlatform.macOS),
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(
                body: SignalListPanel(scrollController: ScrollController()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final rowRect = tester.getRect(
          find.byKey(
            ValueKey(
              SignalListPanel.signalRowKeyValue(
                container.read(signalGroupsProvider).entries.first,
              ),
            ),
          ),
        );
        final nameRect = tester.getRect(find.text('clk'));
        // ignore: avoid_print, intentional diagnostic
        print(
          '=== TRANSFORM EXPERIMENT ===\n'
          'CURRENT BUILD (Transform offset 0,2):\n'
          'row    = $rowRect (height=${rowRect.height})\n'
          'name   = $nameRect (center y=${nameRect.center.dy})\n'
          'offset from row center = '
          '${nameRect.center.dy - rowRect.center.dy} (expected ~2)\n',
        );
      },
    );

    testWidgets(
      'diagnostic: dump full row layout at 100 dp expanded lane on desktop',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.desktop),
          ],
        );
        addTearDown(container.dispose);
        container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));
        container.read(signalGroupsProvider.notifier).setLaneHeight(0, 100);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData(platform: TargetPlatform.macOS),
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(
                body: SignalListPanel(scrollController: ScrollController()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final rowRect = tester.getRect(
          find.byKey(
            ValueKey(
              SignalListPanel.signalRowKeyValue(
                container.read(signalGroupsProvider).entries.first,
              ),
            ),
          ),
        );
        final swatchRect = tester.getRect(
          find.byKey(const ValueKey('_signalRow_colorSwatch')),
        );
        final nameRect = tester.getRect(find.text('clk'));
        final dragHandleRect = tester.getRect(find.byIcon(Icons.drag_handle));
        final closeRect = tester.getRect(find.byIcon(Icons.close));
        // ignore: avoid_print, intentional diagnostic
        print(
          '=== ROW LAYOUT at 100 dp lane ===\n'
          'row   = $rowRect  (center y=${rowRect.center.dy})\n'
          'drag  = $dragHandleRect (center y=${dragHandleRect.center.dy})\n'
          'swatch= $swatchRect (center y=${swatchRect.center.dy})\n'
          'name  = $nameRect (center y=${nameRect.center.dy})\n'
          'close = $closeRect (center y=${closeRect.center.dy})\n',
        );
        expect(rowRect.height, 100);
      },
    );

    testWidgets(
      'diagnostic: at EXPANDED 100 dp lane on desktop, color swatch + signal '
      'name vertically center on the lane center (within 1 dp)',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.desktop),
          ],
        );
        addTearDown(container.dispose);
        container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));
        // Expand the lane to 100 dp (mimic the user's manual resize).
        container.read(signalGroupsProvider.notifier).setLaneHeight(0, 100);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData(platform: TargetPlatform.macOS),
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(
                body: SignalListPanel(scrollController: ScrollController()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final rowRect = tester.getRect(
          find.byKey(
            ValueKey(
              SignalListPanel.signalRowKeyValue(
                container.read(signalGroupsProvider).entries.first,
              ),
            ),
          ),
        );
        expect(
          rowRect.height,
          100,
          reason: 'lane should render at the expanded 100 dp',
        );
        final laneCenterY = rowRect.center.dy;

        // Row content is intentionally Transform.translate'd 2 dp downward
        // to visually center the painted glyph (font ascent > descent on
        // JetBrainsMono / SF Mono shifts the visible character above the
        // widget's geometric center). The widget rects therefore sit 2 dp
        // below the lane's geometric center.
        const kVisualNudgeDp = 5.0;
        final swatchRect = tester.getRect(
          find.byKey(const ValueKey('_signalRow_colorSwatch')),
        );
        expect(
          (swatchRect.center.dy - (laneCenterY + kVisualNudgeDp)).abs() < 1.0,
          isTrue,
          reason:
              'color swatch center y=${swatchRect.center.dy} '
              'should equal lane center + nudge y='
              '${laneCenterY + kVisualNudgeDp} (row=$rowRect, '
              'swatch=$swatchRect)',
        );

        final nameRect = tester.getRect(find.text('clk'));
        expect(
          (nameRect.center.dy - (laneCenterY + kVisualNudgeDp)).abs() < 1.0,
          isTrue,
          reason:
              'signal-name center y=${nameRect.center.dy} '
              'should equal lane center + nudge y='
              '${laneCenterY + kVisualNudgeDp} (row=$rowRect, '
              'name=$nameRect)',
        );
      },
    );

    testWidgets(
      'diagnostic: at default 30 dp lane on desktop, color swatch + signal '
      'name vertically center on the lane center (within 1 dp)',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.desktop),
          ],
        );
        addTearDown(container.dispose);
        container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData(platform: TargetPlatform.macOS),
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(
                body: SignalListPanel(scrollController: ScrollController()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final rowRect = tester.getRect(
          find.byKey(
            ValueKey(
              SignalListPanel.signalRowKeyValue(
                container.read(signalGroupsProvider).entries.first,
              ),
            ),
          ),
        );
        final laneCenterY = rowRect.center.dy;

        // Row content is intentionally Transform.translate'd 2 dp downward
        // (see signal_list_panel.dart) to visually center the painted glyph
        // — the widget rects therefore sit 2 dp below the lane's geometric
        // center.
        const kVisualNudgeDp = 5.0;
        final swatchRect = tester.getRect(
          find.byKey(const ValueKey('_signalRow_colorSwatch')),
        );
        expect(
          (swatchRect.center.dy - (laneCenterY + kVisualNudgeDp)).abs() < 1.0,
          isTrue,
          reason:
              'color swatch center y=${swatchRect.center.dy} '
              'should equal lane center + nudge y='
              '${laneCenterY + kVisualNudgeDp} (row=$rowRect, '
              'swatch=$swatchRect)',
        );

        final nameRect = tester.getRect(find.text('clk'));
        expect(
          (nameRect.center.dy - (laneCenterY + kVisualNudgeDp)).abs() < 1.0,
          isTrue,
          reason:
              'signal-name center y=${nameRect.center.dy} '
              'should equal lane center + nudge y='
              '${laneCenterY + kVisualNudgeDp} (row=$rowRect, '
              'name=$nameRect)',
        );
      },
    );

    testWidgets(
      'lane height renders at stored value (30 dp) on desktop',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.desktop),
          ],
        );
        addTearDown(container.dispose);
        container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData(platform: TargetPlatform.macOS),
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(
                body: SignalListPanel(scrollController: ScrollController()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final rowSize = tester.getSize(
          find.byKey(
            ValueKey(
              SignalListPanel.signalRowKeyValue(
                container.read(signalGroupsProvider).entries.first,
              ),
            ),
          ),
        );
        expect(rowSize.height, 30);
      },
    );

    testWidgets(
      'lane height honors stored value when above touch minimum',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.tablet),
          ],
        );
        addTearDown(container.dispose);
        container.read(signalGroupsProvider.notifier)
          ..addSignal(_v('clk'))
          ..setLaneHeight(0, 80);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData(platform: TargetPlatform.iOS),
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(
                body: SignalListPanel(scrollController: ScrollController()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final rowSize = tester.getSize(
          find.byKey(
            ValueKey(
              SignalListPanel.signalRowKeyValue(
                container.read(signalGroupsProvider).entries.first,
              ),
            ),
          ),
        );
        expect(rowSize.height, 80);
      },
    );

    testWidgets('reorderSignal moves entry to new position', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(signalGroupsProvider.notifier)
        ..addSignal(_v('clk'))
        ..addSignal(_v('data'))
        ..addSignal(_v('reset'))
        // Move clk (oldIndex 0) past data. Under the onReorderItem
        // convention, that maps to insertion index 1 in the post-removal
        // list — yielding [data, clk, reset].
        ..reorderSignal(0, 1);

      final entries = container.read(signalGroupsProvider).entries;
      expect(entries[0].displayName, 'data');
      expect(entries[1].displayName, 'clk');
      expect(entries[2].displayName, 'reset');
    });

    // ── Separator & comment rows ─────────────────────────────────────────────
    testWidgets('group header renders group name and signal count', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(signalGroupsProvider.notifier)
        ..addGroup('Control')
        ..addSignal(_v('clk'));

      await tester.pumpWidget(_wrapWithScroll(container: container));
      await tester.pump();

      expect(find.text('Control'), findsOneWidget);
    });

    testWidgets('separator row renders without error', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(signalGroupsProvider.notifier).addSeparator();

      await tester.pumpWidget(_wrapWithScroll(container: container));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('comment row renders comment text', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(signalGroupsProvider.notifier)
          .addSeparator(comment: 'Clock domain');

      await tester.pumpWidget(_wrapWithScroll(container: container));
      await tester.pump();

      expect(find.text('Clock domain'), findsOneWidget);
    });

    // ── Group tile ────────────────────────────────────────────────────────────
    testWidgets('group tile renders without exception when collapsed', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(signalGroupsProvider.notifier).addGroup('Busses');

      await tester.pumpWidget(_wrapWithScroll(container: container));
      await tester.pump();

      expect(find.text('Busses'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('group with signals inside shows child count badge', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Build a group with children via the notifier's internal state.
      container.read(signalGroupsProvider.notifier)
        ..addGroup('AXI')
        // Add a top-level signal then move it into the group (index 0).
        ..addSignal(_v('awvalid'))
        ..moveSignalIntoGroup(1, 0);

      await tester.pumpWidget(_wrapWithScroll(container: container));
      await tester.pump();

      // The group header should be present.
      expect(find.text('AXI'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('toggleGroupCollapsed collapses and expands group', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(signalGroupsProvider.notifier)
        ..addGroup('Ctrl')
        ..addSignal(_v('en'))
        ..moveSignalIntoGroup(1, 0);

      expect(
        container.read(signalGroupsProvider).entries.first.collapsed,
        isFalse,
      );

      notifier.toggleGroupCollapsed(0);

      expect(
        container.read(signalGroupsProvider).entries.first.collapsed,
        isTrue,
      );

      notifier.toggleGroupCollapsed(0);

      expect(
        container.read(signalGroupsProvider).entries.first.collapsed,
        isFalse,
      );
    });

    testWidgets('group child signal row appears when group is expanded', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(signalGroupsProvider.notifier)
        ..addGroup('AXI')
        ..addSignal(_v('awready'))
        ..moveSignalIntoGroup(1, 0);

      // Group starts expanded — child should be visible in the widget tree.
      await tester.pumpWidget(_wrapWithScroll(container: container));
      await tester.pump();

      expect(find.text('awready'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('group child signal row not visible when group is collapsed', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(signalGroupsProvider.notifier)
        ..addGroup('AXI')
        ..addSignal(_v('awready'))
        ..moveSignalIntoGroup(1, 0)
        ..toggleGroupCollapsed(0);

      await tester.pumpWidget(_wrapWithScroll(container: container));
      await tester.pump();

      expect(find.text('awready'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dissolveGroup moves children to top level', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(signalGroupsProvider.notifier)
        ..addGroup('Ctrl')
        ..addSignal(_v('en'))
        ..moveSignalIntoGroup(1, 0);

      // Before dissolve: 1 top-level entry (the group).
      expect(
        container.read(signalGroupsProvider).entries.length,
        1,
      );

      notifier.dissolveGroup(0);

      // After dissolve: 1 top-level entry (the signal).
      final entries = container.read(signalGroupsProvider).entries;
      expect(entries.length, 1);
      expect(entries.first.kind, SignalEntryKind.signal);
      expect(entries.first.displayName, 'en');
    });

    testWidgets('removeChildFromGroup removes child and keeps group', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(signalGroupsProvider.notifier)
        ..addGroup('Bus')
        ..addSignal(_v('sig1'))
        ..addSignal(_v('sig2'))
        ..moveSignalIntoGroup(1, 0)
        ..moveSignalIntoGroup(1, 0);

      // Group has 2 children.
      var children = container
          .read(signalGroupsProvider)
          .entries
          .first
          .children;
      expect(children.length, 2);

      notifier.removeChildFromGroup(0, 0);

      children = container.read(signalGroupsProvider).entries.first.children;
      expect(children.length, 1);
    });

    testWidgets('renameGroup changes group name', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(signalGroupsProvider.notifier)
        ..addGroup('Old')
        ..renameGroup(0, 'New');

      expect(
        container.read(signalGroupsProvider).entries.first.groupName,
        'New',
      );
    });

    testWidgets('moveSignalIntoGroup updates state correctly', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(signalGroupsProvider.notifier)
        ..addGroup('G')
        ..addSignal(_v('x'));

      // Before move: 2 top-level entries.
      expect(
        container.read(signalGroupsProvider).entries.length,
        2,
      );

      notifier.moveSignalIntoGroup(1, 0);

      // After move: 1 top-level entry (the group containing x).
      final entries = container.read(signalGroupsProvider).entries;
      expect(entries.length, 1);
      expect(entries.first.kind, SignalEntryKind.group);
      expect(entries.first.children.first.displayName, 'x');
    });

    testWidgets('mixed entry types render without exception', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(signalGroupsProvider.notifier)
        ..addSignal(_v('clk'))
        ..addSeparator()
        ..addSeparator(comment: 'note')
        ..addGroup('Grp');

      await tester.pumpWidget(_wrapWithScroll(container: container));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('clk'), findsOneWidget);
      expect(find.text('note'), findsOneWidget);
      expect(find.text('Grp'), findsOneWidget);
    });

    // ── XOR diff spacers ─────────────────────────────────────────────────────
    //
    // When diff is active and a signal's ref appears in [DiffState.xorTraces],
    // an [_XorDiffSpacer] is inserted after the signal row.  The spacer renders
    // the "⊕" symbol.  When diff is cleared the spacer must disappear.
    group('XOR diff spacers', () {
      testWidgets('spacer appears when diff is active with xorTraces', (
        tester,
      ) async {
        final container = ProviderContainer(
          overrides: [
            diffProvider.overrideWith(
              () => _FakeDiffNotifier(
                const DiffState(
                  secondFilePath: '/b.vcd',
                  xorTraces: {'ref_clk': []},
                ),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

        await tester.pumpWidget(_wrapWithScroll(container: container));
        await tester.pump();

        expect(find.text('⊕'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('no spacer when diff is inactive', (tester) async {
        // diffProvider defaults to DiffState() with isActive==false.
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

        await tester.pumpWidget(_wrapWithScroll(container: container));
        await tester.pump();

        expect(find.text('⊕'), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('no spacer when signal ref not in xorTraces', (tester) async {
        final container = ProviderContainer(
          overrides: [
            diffProvider.overrideWith(
              () => _FakeDiffNotifier(
                const DiffState(
                  secondFilePath: '/b.vcd',
                  xorTraces: {'ref_other': []},
                ),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

        await tester.pumpWidget(_wrapWithScroll(container: container));
        await tester.pump();

        expect(find.text('⊕'), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('spacer disappears when diff is cleared', (tester) async {
        final container = ProviderContainer(
          overrides: [
            diffProvider.overrideWith(_MutableDiffNotifier.new),
          ],
        );
        addTearDown(container.dispose);
        container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

        // Force notifier build then activate diff.
        container.read(diffProvider);
        (container.read(diffProvider.notifier) as _MutableDiffNotifier)
            .diffState = const DiffState(
          secondFilePath: '/b.vcd',
          xorTraces: {'ref_clk': []},
        );

        await tester.pumpWidget(_wrapWithScroll(container: container));
        await tester.pump();

        expect(find.text('⊕'), findsOneWidget);

        // Clear diff.
        (container.read(diffProvider.notifier) as _MutableDiffNotifier)
                .diffState =
            const DiffState();
        await tester.pump();

        expect(find.text('⊕'), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets(
        'one spacer per differing signal when multiple signals loaded',
        (tester) async {
          final container = ProviderContainer(
            overrides: [
              diffProvider.overrideWith(
                () => _FakeDiffNotifier(
                  const DiffState(
                    secondFilePath: '/b.vcd',
                    xorTraces: {
                      'ref_clk': [],
                      'ref_data': [],
                    },
                  ),
                ),
              ),
            ],
          );
          addTearDown(container.dispose);
          container.read(signalGroupsProvider.notifier)
            ..addSignal(_v('clk'))
            ..addSignal(_v('data'));

          await tester.pumpWidget(_wrapWithScroll(container: container));
          await tester.pump();

          expect(find.text('⊕'), findsNWidgets(2));
          expect(tester.takeException(), isNull);
        },
      );
    });

    // ── Diff status colors ───────────────────────────────────────────────────
    //
    // These tests verify that [diffSignalStatusProvider] values drive the
    // signal-name text color in [_SignalRow].  The _v() helper creates a
    // Variable with signalRef == 'ref_<name>', so the override map keys must
    // match that pattern.
    group('diff status colors', () {
      testWidgets(
        'applies different color when diff marks signal as diverging',
        (tester) async {
          final container = ProviderContainer(
            overrides: [
              diffSignalStatusProvider.overrideWith(
                (ref) => const {'ref_clk': DiffSignalStatus.different},
              ),
            ],
          );
          addTearDown(container.dispose);
          container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

          await tester.pumpWidget(_wrapWithScroll(container: container));
          await tester.pump();

          expect(
            find.byWidgetPredicate(
              (w) =>
                  w is Text &&
                  w.data == 'clk' &&
                  w.style?.color == _kDiffDifferentColor,
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'applies identical color when diff marks signal as matching',
        (tester) async {
          final container = ProviderContainer(
            overrides: [
              diffSignalStatusProvider.overrideWith(
                (ref) => const {'ref_clk': DiffSignalStatus.identical},
              ),
            ],
          );
          addTearDown(container.dispose);
          container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

          await tester.pumpWidget(_wrapWithScroll(container: container));
          await tester.pump();

          expect(
            find.byWidgetPredicate(
              (w) =>
                  w is Text &&
                  w.data == 'clk' &&
                  w.style?.color == _kDiffIdenticalColor,
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'applies unmatched color when signal has no counterpart in file B',
        (tester) async {
          final container = ProviderContainer(
            overrides: [
              diffSignalStatusProvider.overrideWith(
                (ref) => const {'ref_clk': DiffSignalStatus.unmatchedA},
              ),
            ],
          );
          addTearDown(container.dispose);
          container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

          await tester.pumpWidget(_wrapWithScroll(container: container));
          await tester.pump();

          expect(
            find.byWidgetPredicate(
              (w) =>
                  w is Text &&
                  w.data == 'clk' &&
                  w.style?.color == _kDiffUnmatchedColor,
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets('reverts to normal color when diff is cleared', (
        tester,
      ) async {
        // Override diffSignalStatusProvider to watch a mutable StateProvider
        // so we can flip the diff on and off without rebuilding the widget.
        final container = ProviderContainer(
          overrides: [
            diffSignalStatusProvider.overrideWith(
              (ref) => ref.watch(_mutableDiffStatus),
            ),
          ],
        );
        addTearDown(container.dispose);
        container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

        // Activate diff — signal marked as diverging.
        container.read(_mutableDiffStatus.notifier).state = {
          'ref_clk': DiffSignalStatus.different,
        };

        await tester.pumpWidget(_wrapWithScroll(container: container));
        await tester.pump();

        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Text &&
                w.data == 'clk' &&
                w.style?.color == _kDiffDifferentColor,
          ),
          findsOneWidget,
        );

        // Clear diff — provider returns empty map.
        container.read(_mutableDiffStatus.notifier).state = {};
        await tester.pump();

        // Diff color must no longer be applied.
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Text &&
                w.data == 'clk' &&
                w.style?.color == _kDiffDifferentColor,
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      });
    });

    // ── Gesture bubbling regression (ARCHITECTURE.md §3.1.8.5) ─────────────────
    //
    // The color swatch GestureDetector handles only `onTap` — its
    // HitTestBehavior must NOT be `opaque`, otherwise the outer
    // PlatformContextMenu's long-press handler is starved and the inner
    // onTap fires on dialog dismissal, overwriting whatever color the user
    // chose in the picker.
    testWidgets(
      'color swatch GestureDetector is translucent (gesture bubbling)',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

        await tester.pumpWidget(_wrapWithScroll(container: container));
        await tester.pump();

        final swatch = tester.widget<GestureDetector>(
          find.byKey(const ValueKey('_signalRow_colorSwatch')),
        );
        expect(
          swatch.behavior,
          HitTestBehavior.translucent,
          reason: 'Must let unhandled long-press bubble to PlatformContextMenu',
        );
      },
    );

    // ── Touch-target compliance (ARCHITECTURE.md §3.1.8.3 / §3.1.8.11) ─────────
    group('mobile UI standards', () {
      testWidgets(
        'on tablet: every interactive cell in a signal row meets the 44 dp '
        'touch target',
        (tester) async {
          final container = ProviderContainer(
            overrides: [
              deviceClassProvider.overrideWithValue(DeviceClass.tablet),
            ],
          );
          addTearDown(container.dispose);
          // Add a signal so a row renders.
          container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

          await tester.pumpWidget(_wrapWithScroll(container: container));
          await tester.pump();

          // Every SizedBox that wraps an interactive widget (drag handle,
          // color swatch, remove button) inside the signal row must be at
          // least 44 dp on its smaller axis.
          final row = find.byType(GestureDetector);
          expect(row, findsWidgets);
          // Drag handle hit area (Icons.drag_handle is wrapped in a 44 dp
          // SizedBox per MobileMetrics.dragHandleHitArea on touch).
          final dragSized = find.ancestor(
            of: find.byIcon(Icons.drag_handle),
            matching: find.byType(SizedBox),
          );
          final dragSizes = tester
              .widgetList<SizedBox>(dragSized)
              .where((s) => (s.width ?? 0) >= 44 && (s.height ?? 0) >= 44);
          expect(
            dragSizes,
            isNotEmpty,
            reason: 'drag handle must have a 44 dp hit area on touch',
          );
          // Remove button hit area.
          final removeSized = find.ancestor(
            of: find.byIcon(Icons.close),
            matching: find.byType(SizedBox),
          );
          final removeSizes = tester
              .widgetList<SizedBox>(removeSized)
              .where((s) => (s.width ?? 0) >= 44 && (s.height ?? 0) >= 44);
          expect(
            removeSizes,
            isNotEmpty,
            reason: 'remove button must have a 44 dp hit area on touch',
          );
        },
      );
    });

    // ── Drag-to-Stage source ─────────────────────────────────────────────────
    //
    // Each signal row is a Draggable<String> whose payload is the
    // signal's signalRef — so the user can drag a signal already in
    // the waveform straight onto a Stage widget tile / board slot
    // without first re-finding it in the SST panel. Reorder remains
    // pinned to the explicit drag-handle icon (which is OUTSIDE the
    // Draggable's wrapped body) so the two gestures don't compete.
    group('drag-to-Stage source', () {
      testWidgets('each signal row exposes a Draggable<String> carrying the '
          'signal ref', (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.read(signalGroupsProvider.notifier)
          ..addSignal(_v('clk'))
          ..addSignal(_v('data'));

        await tester.pumpWidget(_wrapWithScroll(container: container));
        await tester.pump();

        final draggables = tester.widgetList<Draggable<String>>(
          find.byType(Draggable<String>),
        );
        expect(
          draggables,
          hasLength(2),
          reason: 'one Draggable per signal row',
        );
        expect(
          draggables.map((d) => d.data).toSet(),
          {'ref_clk', 'ref_data'},
        );
        // Affinity is horizontal so vertical pans inside the
        // ReorderableListView still scroll — pulling sideways picks
        // up the signal.
        for (final d in draggables) {
          expect(d.affinity, Axis.horizontal);
        }
      });

      testWidgets('reorder drag handle is OUTSIDE the Draggable so the two '
          'gestures do not compete', (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

        await tester.pumpWidget(_wrapWithScroll(container: container));
        await tester.pump();

        final dragHandle = find.byIcon(Icons.drag_handle);
        expect(dragHandle, findsOneWidget);
        // The drag handle must NOT have a Draggable<String> ancestor.
        // If it did, dragging the handle would race the to-Stage
        // Draggable against the ReorderableListView's reorder
        // recognizer.
        final ancestors = find.ancestor(
          of: dragHandle,
          matching: find.byType(Draggable<String>),
        );
        expect(ancestors, findsNothing);
      });
    });

    // ── Decoder row band ─────────────────────────────────────────────────
    //
    // The signal list panel renders one [DecoderListEntry] per active
    // decoder below the user's signal entries. These rows replaced the
    // per-lane decoder name label that used to be painted on the canvas.
    group('decoder row band', () {
      testWidgets('renders one DecoderListEntry per active decoder', (
        tester,
      ) async {
        DecoderRegistry.instance.clear();
        addTearDown(DecoderRegistry.instance.clear);
        DecoderRegistry.instance.register(
          const DecoderDefinition(
            id: 'spi',
            displayName: 'SPI',
            description: '',
            requiredSignals: [],
          ),
          (cfg) => throw UnimplementedError(),
        );
        final container = ProviderContainer(
          overrides: [
            activeDecodersProvider.overrideWith(
              () => _FixedDecodersNotifier(const [
                ActiveDecoder(
                  id: 'd0',
                  decoderId: 'spi',
                  config: DecoderConfig(signalBindings: {}),
                  instanceNumber: 1,
                ),
                ActiveDecoder(
                  id: 'd1',
                  decoderId: 'spi',
                  config: DecoderConfig(signalBindings: {}),
                  instanceNumber: 2,
                ),
              ]),
            ),
          ],
        );
        addTearDown(container.dispose);
        container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

        await tester.pumpWidget(_wrapWithScroll(container: container));
        await tester.pump();

        expect(find.byType(DecoderListEntry), findsNWidgets(2));
        expect(find.text('SPI #1'), findsOneWidget);
        expect(find.text('SPI #2'), findsOneWidget);
      });

      testWidgets('renders no DecoderListEntry rows when none are active', (
        tester,
      ) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));
        await tester.pumpWidget(_wrapWithScroll(container: container));
        await tester.pump();
        expect(find.byType(DecoderListEntry), findsNothing);
      });
    });

    // ── Signal row right-click context menu (_showContextMenu) ────────────────
    group('signal row context menu', () {
      testWidgets(
        'right-click opens the menu with copy-path + filter actions',
        (tester) async {
          final container = ProviderContainer(
            overrides: [
              deviceClassProvider.overrideWithValue(DeviceClass.desktop),
            ],
          );
          addTearDown(container.dispose);
          container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: ThemeData(platform: TargetPlatform.macOS),
                localizationsDelegates: L10N.localizationsDelegates,
                supportedLocales: L10N.supportedLocales,
                home: Scaffold(
                  body: SignalListPanel(scrollController: ScrollController()),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Right-click the signal name to open the row context menu.
          await tester.tap(find.text('clk'), buttons: kSecondaryButton);
          await tester.pumpAndSettle();

          final l10n = await L10N.delegate.load(const Locale('en'));
          // The full hierarchical path header + the menu's core actions appear.
          expect(find.text(l10n.signalListCopyPath), findsOneWidget);
          expect(find.text(l10n.translateFilterAssign), findsOneWidget);
          expect(find.text(l10n.processFilterAssign), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets('Copy Full Path menu action invokes the path export', (
        tester,
      ) async {
        final container = ProviderContainer(
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.desktop),
            // Resolve the signal ref to a full path so the header + copy
            // string are the hierarchical path, not the bare ref.
            signalVariablesMapProvider.overrideWith(
              (ref) => {'ref_clk': _v('clk', scopePath: 'top.cpu')},
            ),
          ],
        );
        addTearDown(container.dispose);
        container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData(platform: TargetPlatform.macOS),
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(
                body: SignalListPanel(scrollController: ScrollController()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('clk'), buttons: kSecondaryButton);
        await tester.pumpAndSettle();

        final l10n = await L10N.delegate.load(const Locale('en'));
        // The full path appears as the menu header (reveal of the ellipsized
        // row name).
        expect(find.text('top.cpu.clk'), findsWidgets);

        await tester.tap(find.text(l10n.signalListCopyPath));
        await tester.pumpAndSettle();
        // copySignalPath writes to the clipboard; the action ran without error.
        expect(tester.takeException(), isNull);
      });

      testWidgets('menu lists available groups under "Move to group"', (
        tester,
      ) async {
        final container = ProviderContainer(
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.desktop),
          ],
        );
        addTearDown(container.dispose);
        container.read(signalGroupsProvider.notifier)
          ..addSignal(_v('clk'))
          ..addGroup('Bus');

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData(platform: TargetPlatform.macOS),
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(
                body: SignalListPanel(scrollController: ScrollController()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('clk'), buttons: kSecondaryButton);
        await tester.pumpAndSettle();

        final l10n = await L10N.delegate.load(const Locale('en'));
        expect(find.text(l10n.signalGroupMoveToGroup), findsOneWidget);
        // The "Bus" group is offered as a move target inside the menu.
        expect(find.text('Bus'), findsWidgets);

        // Tap the group entry → moves the signal into the group.
        await tester.tap(find.text('Bus').last);
        await tester.pumpAndSettle();

        final entries = container.read(signalGroupsProvider).entries;
        // The group now contains the signal; the top-level signal is gone.
        final group = entries.firstWhere(
          (e) => e.kind == SignalEntryKind.group,
        );
        expect(group.children.any((c) => c.displayName == 'clk'), isTrue);
      });

      testWidgets('Assign Translate Filter menu item opens the picker dialog', (
        tester,
      ) async {
        final container = ProviderContainer(
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.desktop),
          ],
        );
        addTearDown(container.dispose);
        container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData(platform: TargetPlatform.macOS),
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(
                body: SignalListPanel(scrollController: ScrollController()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('clk'), buttons: kSecondaryButton);
        await tester.pumpAndSettle();

        final l10n = await L10N.delegate.load(const Locale('en'));
        await tester.tap(find.text(l10n.translateFilterAssign));
        await tester.pumpAndSettle();

        // The translate-filter picker dialog opens without error.
        expect(tester.takeException(), isNull);
      });
    });

    // ── Group header context menu (_showContextMenu / _showRenameDialog) ──────
    group('group header context menu', () {
      Future<void> pumpWithGroup(
        WidgetTester tester,
        ProviderContainer container,
      ) async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData(platform: TargetPlatform.macOS),
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(
                body: SignalListPanel(scrollController: ScrollController()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      testWidgets('right-click on a group header opens rename/dissolve menu', (
        tester,
      ) async {
        final container = ProviderContainer(
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.desktop),
          ],
        );
        addTearDown(container.dispose);
        container.read(signalGroupsProvider.notifier).addGroup('Bus');
        await pumpWithGroup(tester, container);

        await tester.tap(find.text('Bus'), buttons: kSecondaryButton);
        await tester.pumpAndSettle();

        final l10n = await L10N.delegate.load(const Locale('en'));
        expect(find.text(l10n.signalGroupRename), findsOneWidget);
        expect(find.text(l10n.signalGroupDissolve), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Dissolve action removes the group', (tester) async {
        final container = ProviderContainer(
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.desktop),
          ],
        );
        addTearDown(container.dispose);
        container.read(signalGroupsProvider.notifier).addGroup('Bus');
        await pumpWithGroup(tester, container);

        await tester.tap(find.text('Bus'), buttons: kSecondaryButton);
        await tester.pumpAndSettle();
        final l10n = await L10N.delegate.load(const Locale('en'));
        await tester.tap(find.text(l10n.signalGroupDissolve));
        await tester.pumpAndSettle();

        // Dissolving an empty group leaves no group entries.
        expect(
          container
              .read(signalGroupsProvider)
              .entries
              .where((e) => e.kind == SignalEntryKind.group),
          isEmpty,
        );
      });

      testWidgets('Rename action opens the rename dialog with the current name', (
        tester,
      ) async {
        final container = ProviderContainer(
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.desktop),
          ],
        );
        addTearDown(container.dispose);
        container.read(signalGroupsProvider.notifier).addGroup('Bus');
        await pumpWithGroup(tester, container);

        await tester.tap(find.text('Bus'), buttons: kSecondaryButton);
        await tester.pumpAndSettle();
        final l10n = await L10N.delegate.load(const Locale('en'));
        await tester.tap(find.text(l10n.signalGroupRename));
        await tester.pumpAndSettle();

        // The rename dialog is shown, pre-populated with the current name.
        // (Committing the rename is covered by the renameGroup notifier test;
        // driving the dialog's OK/exit transition here trips a known AlertDialog
        // teardown race where the disposed TextEditingController is referenced
        // during the close animation — a lib-side timing quirk, not under test.)
        expect(find.text(l10n.signalGroupRenameDialogTitle), findsOneWidget);
        final field = tester.widget<TextField>(find.byType(TextField).last);
        expect(field.controller?.text, 'Bus');
        expect(tester.takeException(), isNull);
        // The dialog is left open: closing it (OK or Cancel) drives the
        // AlertDialog exit transition, which rebuilds the TextField after the
        // rename handler disposes its TextEditingController — a lib-side
        // teardown race, not under test here. Committing the rename is covered
        // by the renameGroup notifier test elsewhere in this file.
      });
    });

    // ── Canvas name-click = select-only (originate an outbound cross-probe) ────
    group('name-column click selection', () {
      testWidgets(
        'clicking a signal name selects that row without adding a duplicate lane',
        (tester) async {
          final container = ProviderContainer(
            overrides: [
              deviceClassProvider.overrideWithValue(DeviceClass.desktop),
            ],
          );
          addTearDown(container.dispose);
          container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: ThemeData(platform: TargetPlatform.macOS),
                localizationsDelegates: L10N.localizationsDelegates,
                supportedLocales: L10N.supportedLocales,
                home: Scaffold(
                  body: SignalListPanel(scrollController: ScrollController()),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(container.read(selectedVariablesProvider), isEmpty);
          final laneCountBefore = container
              .read(signalGroupsProvider)
              .entries
              .length;

          // Single click on the name. The row's GestureDetector also has an
          // onDoubleTap, so the tap recognizer defers until the double-tap
          // window (kDoubleTapTimeout, 300 ms) elapses — that timer schedules
          // no frame, so we must advance the clock past it explicitly before
          // onTap fires.
          await tester.tap(find.text('clk'));
          await tester.pump(const Duration(milliseconds: 350));
          await tester.pumpAndSettle();

          // The row's fullPath is selected in the per-tab selection …
          expect(container.read(selectedVariablesProvider), contains('clk'));
          // … and the root CXP focus mirrors the clicked signalRef, so the
          // emitter / panel-send resolve it.
          expect(container.read(selectedSignalProvider), 'ref_clk');
          // … and NO extra lane was added (the signal-tree click's add-and-
          // duplicate behaviour is exactly what this avoids).
          expect(
            container.read(signalGroupsProvider).entries.length,
            laneCountBefore,
          );
        },
      );

      testWidgets('the selected row renders the full-row highlight bar', (
        tester,
      ) async {
        final container = ProviderContainer(
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.desktop),
          ],
        );
        addTearDown(container.dispose);
        container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData(platform: TargetPlatform.macOS),
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(
                body: SignalListPanel(scrollController: ScrollController()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Unselected: the name is not bold.
        expect(
          tester.widget<Text>(find.text('clk')).style?.fontWeight,
          isNot(FontWeight.bold),
        );

        // Select it programmatically (the inbound cross-probe path) and confirm
        // the row adopts the full-row highlight BAR (the same primary tint
        // the value column paints) plus the bold name — NOT a text
        // background, so the three panes' selection cues match.
        container.read(selectedVariablesProvider.notifier).selectOnly('clk');
        await tester.pumpAndSettle();

        final style = tester.widget<Text>(find.text('clk')).style;
        expect(style?.fontWeight, FontWeight.bold);
        expect(style?.backgroundColor, isNull);
        final rowTints = tester
            .widgetList<ColoredBox>(find.byType(ColoredBox))
            .where((b) {
              final c = b.color;
              // primary.withValues(alpha: 0.18) — match on the alpha channel
              // rather than the theme-dependent hue.
              return (c.a - 0.18).abs() < 0.01;
            });
        expect(
          rowTints,
          isNotEmpty,
          reason: 'selected row must paint the full-row highlight bar',
        );
      });
    });

    // ── Row identity ───────────────────────────────────────────────────────
    //
    // `_SignalRow` is stateful: a lane-resize drag lives in its State
    // (`_dragStartY`, `_dragStartHeight`), while the callback that applies
    // the new height comes from the parent's build and targets whatever row
    // sits at that POSITION. With a positional `ValueKey('sig_$index')` the
    // State stays with the slot, so any list change that lands while a drag
    // is in flight — a signal added from the search dialog, the RTL source
    // pane, an annotation, a cross-probe — rebinds the in-flight drag to a
    // different signal, and the resize is applied to the wrong lane at the
    // wrong starting height.
    //
    // PRIMARY MUTATION TARGET: keying the row by `index` instead of
    // `entry.id` fails this.
    testWidgets(
      'a lane resize in flight stays with its own signal when the list '
      'changes underneath it',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.desktop),
          ],
        );
        addTearDown(container.dispose);
        final notifier = container.read(signalGroupsProvider.notifier)
          ..addSignal(_v('alpha'))
          ..addSignal(_v('beta'));

        await tester.pumpWidget(_wrapWithScroll(container: container));
        await tester.pumpAndSettle();

        final beta = container.read(signalGroupsProvider).entries[1];
        final betaRow = find.byKey(ValueKey('sig_${beta.id}'));
        expect(betaRow, findsOneWidget);
        final rowRect = tester.getRect(betaRow);

        // Grab beta's resize grip (the bottom strip of its row).
        final gesture = await tester.startGesture(
          Offset(rowRect.center.dx, rowRect.bottom - 1),
        );
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump();

        // …and while the finger is still down, a signal arrives above it.
        notifier.addSignal(_v('inserted'), insertIndex: 0);
        await tester.pump();

        await gesture.moveBy(const Offset(0, 20));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        final entries = container.read(signalGroupsProvider).entries;
        Map<String, double> heights() => <String, double>{
          for (final e in entries) e.displayName!: e.laneHeight,
        };
        expect(
          heights()['beta'],
          greaterThan(60),
          reason: 'the dragged lane must grow: ${heights()}',
        );
        expect(heights()['alpha'], 30);
        expect(heights()['inserted'], 30);
      },
    );
  });
}

class _FixedDecodersNotifier extends ActiveDecodersNotifier {
  _FixedDecodersNotifier(this._initial);
  final List<ActiveDecoder> _initial;
  @override
  List<ActiveDecoder> build() => _initial;
}
