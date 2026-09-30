// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/widgets/signal_list_panel.dart';
import 'package:wavecrux/features/viewer/widgets/time_ruler_widget.dart';
import 'package:wavecrux/features/viewer/widgets/waveform_view_center.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

// ── fakes ─────────────────────────────────────────────────────────────────────

class _MockSource extends Mock implements WaveformDataSource {}

class _LoadedSourceNotifier extends WaveformSourceNotifier {
  _LoadedSourceNotifier(this._source);
  final WaveformDataSource _source;

  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

class _ErrorSourceNotifier extends WaveformSourceNotifier {
  @override
  AsyncValue<WaveformDataSource?> build() =>
      AsyncError(Exception('parse failed'), StackTrace.empty);
}

/// A source stuck in the loading state, as during a long parse. Mirrors the
/// openFromBytes web path, where only lastAttemptedPath carries the picked
/// file's name (currentFilePath stays null).
class _ParsingSourceNotifier extends WaveformSourceNotifier {
  @override
  AsyncValue<WaveformDataSource?> build() {
    lastAttemptedPath = 'luke_wren_gatelevel_netlist_dec_2025.fst';
    return const AsyncLoading();
  }
}

class _WasmRequiredSourceNotifier extends WaveformSourceNotifier {
  @override
  AsyncValue<WaveformDataSource?> build() =>
      const AsyncError(WebAssemblyRequiredError(), StackTrace.empty);
}

// ── helpers ───────────────────────────────────────────────────────────────────

Variable _v(String name) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: 'ref_$name',
  scopePath: 'top',
);

Scope _scope(List<Variable> vars) => Scope(
  name: 'top',
  path: 'top',
  type: ScopeType.module,
  variables: vars,
);

Widget _wrap({List<Override> overrides = const []}) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: Scaffold(body: WaveformViewCenter(onCompareWith: () {})),
  ),
);

void main() {
  setUpAll(() {
    registerFallbackValue(const SignalFilter());
  });

  group('WaveformViewCenter', () {
    testWidgets(
      'loading overlay names the file from lastAttemptedPath '
      '(web opens never set currentFilePath)',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            overrides: [
              waveformSourceProvider.overrideWith(_ParsingSourceNotifier.new),
            ],
          ),
        );
        await tester.pump();

        final l10n = L10N.of(tester.element(find.byType(Scaffold)));
        expect(
          find.text(
            l10n.waveformCenterLoadingFile(
              'luke_wren_gatelevel_netlist_dec_2025.fst',
            ),
          ),
          findsOneWidget,
          reason:
              'the visible loading overlay must name the file being parsed, '
              'not fall back to the bare ellipsis',
        );
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('renders in en locale without exceptions', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows TimeRulerWidget when no file is loaded', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(TimeRulerWidget), findsOneWidget);
    });

    testWidgets('shows TimeRulerWidget when signals are loaded', (
      tester,
    ) async {
      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.endTime).thenReturn(1000);
      when(() => source.timescale).thenReturn(null);
      when(() => source.rootScopes).thenReturn([
        _scope([_v('clk')]),
      ]);
      when(() => source.findVariables(any())).thenReturn([_v('clk')]);
      when(() => source.isSignalLoaded(any())).thenReturn(false);
      when(() => source.loadSignal(any())).thenAnswer((_) async {});
      when(() => source.changesInRange(any(), any(), any())).thenReturn([]);

      final container = ProviderContainer(
        overrides: [
          waveformSourceProvider.overrideWith(
            () => _LoadedSourceNotifier(source),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(body: WaveformViewCenter(onCompareWith: () {})),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(TimeRulerWidget), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'SignalListPanel top is offset by timeRulerHeight when signals loaded',
      (tester) async {
        final source = _MockSource();
        when(() => source.startTime).thenReturn(0);
        when(() => source.endTime).thenReturn(1000);
        when(() => source.timescale).thenReturn(null);
        when(() => source.rootScopes).thenReturn([
          _scope([_v('clk')]),
        ]);
        when(() => source.findVariables(any())).thenReturn([_v('clk')]);
        when(() => source.isSignalLoaded(any())).thenReturn(false);
        when(() => source.loadSignal(any())).thenAnswer((_) async {});
        when(() => source.changesInRange(any(), any(), any())).thenReturn([]);

        final container = ProviderContainer(
          overrides: [
            waveformSourceProvider.overrideWith(
              () => _LoadedSourceNotifier(source),
            ),
          ],
        );
        addTearDown(container.dispose);
        container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(body: WaveformViewCenter(onCompareWith: () {})),
            ),
          ),
        );
        await tester.pump();

        final centerTop = tester.getTopLeft(find.byType(WaveformViewCenter)).dy;
        final listTop = tester.getTopLeft(find.byType(SignalListPanel)).dy;
        expect(listTop - centerTop, timeRulerHeight);
      },
    );

    testWidgets('error state shows no retry button', (tester) async {
      // With one parser per platform any load failure is deterministic, so
      // the error overlay no longer offers a retry affordance. Re-opening
      // via File → Open is the supported recovery path.
      final container = ProviderContainer(
        overrides: [
          waveformSourceProvider.overrideWith(_ErrorSourceNotifier.new),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(body: WaveformViewCenter(onCompareWith: () {})),
          ),
        ),
      );
      await tester.pump();
      expect(find.byIcon(Icons.refresh), findsNothing);
      // The error message itself is still rendered.
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets(
      'WebAssembly required error shows WebAssembly guidance message',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            waveformSourceProvider.overrideWith(
              _WasmRequiredSourceNotifier.new,
            ),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(body: WaveformViewCenter(onCompareWith: () {})),
            ),
          ),
        );
        await tester.pump();
        // No retry button (same as the generic error state).
        expect(find.byIcon(Icons.refresh), findsNothing);
        // Surfaces the WebAssembly-required guidance message + warning icon.
        expect(
          find.textContaining('WebAssembly', findRichText: true),
          findsWidgets,
        );
        expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      },
    );

    // Regression for the iPad release-build defect where the signal-list
    // column was capped at 180 dp on every device class. With touch metrics
    // (drag handle 44 + color swatch 44 + remove 44 = 132 dp of fixed
    // chrome) only ~48 dp remained for the signal name — names like
    // `p2_wdata` truncated to 3 monospace chars and the chrome visually
    // crowded the name region. The fix bumps the cap to 260 dp on touch
    // so ≥ 120 dp is left for the name.
    testWidgets(
      'signal-list column is 180 dp on desktop',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1400, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final source = _MockSource();
        when(() => source.startTime).thenReturn(0);
        when(() => source.endTime).thenReturn(1000);
        when(() => source.timescale).thenReturn(null);
        when(() => source.rootScopes).thenReturn([
          _scope([_v('clk')]),
        ]);
        when(() => source.findVariables(any())).thenReturn([_v('clk')]);
        when(() => source.isSignalLoaded(any())).thenReturn(false);
        when(() => source.loadSignal(any())).thenAnswer((_) async {});
        when(() => source.changesInRange(any(), any(), any())).thenReturn([]);

        final container = ProviderContainer(
          overrides: [
            waveformSourceProvider.overrideWith(
              () => _LoadedSourceNotifier(source),
            ),
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
              home: Scaffold(body: WaveformViewCenter(onCompareWith: () {})),
            ),
          ),
        );
        await tester.pump();

        final listWidth = tester.getSize(find.byType(SignalListPanel)).width;
        expect(listWidth, 180);
      },
    );

    testWidgets(
      'signal-list column is 260 dp on touch (tablet on iOS)',
      (tester) async {
        // iPad-landscape-ish surface: enough room that the LayoutBuilder
        // clamp `(width − 100)` doesn't override the target width.
        await tester.binding.setSurfaceSize(const Size(1100, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final source = _MockSource();
        when(() => source.startTime).thenReturn(0);
        when(() => source.endTime).thenReturn(1000);
        when(() => source.timescale).thenReturn(null);
        when(() => source.rootScopes).thenReturn([
          _scope([_v('clk')]),
        ]);
        when(() => source.findVariables(any())).thenReturn([_v('clk')]);
        when(() => source.isSignalLoaded(any())).thenReturn(false);
        when(() => source.loadSignal(any())).thenAnswer((_) async {});
        when(() => source.changesInRange(any(), any(), any())).thenReturn([]);

        final container = ProviderContainer(
          overrides: [
            waveformSourceProvider.overrideWith(
              () => _LoadedSourceNotifier(source),
            ),
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
              home: Scaffold(body: WaveformViewCenter(onCompareWith: () {})),
            ),
          ),
        );
        await tester.pump();

        final listWidth = tester.getSize(find.byType(SignalListPanel)).width;
        expect(listWidth, 260);
      },
    );

    // Defensive: at narrow widths the LayoutBuilder clamp `(width − 100)`
    // must still apply on touch so the inner Row doesn't overflow. With a
    // 320 dp surface the target 260 dp is clamped to 220 dp.
    testWidgets(
      'signal-list column clamps to (width − 100) on narrow touch surface',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final source = _MockSource();
        when(() => source.startTime).thenReturn(0);
        when(() => source.endTime).thenReturn(1000);
        when(() => source.timescale).thenReturn(null);
        when(() => source.rootScopes).thenReturn([
          _scope([_v('clk')]),
        ]);
        when(() => source.findVariables(any())).thenReturn([_v('clk')]);
        when(() => source.isSignalLoaded(any())).thenReturn(false);
        when(() => source.loadSignal(any())).thenAnswer((_) async {});
        when(() => source.changesInRange(any(), any(), any())).thenReturn([]);

        final container = ProviderContainer(
          overrides: [
            waveformSourceProvider.overrideWith(
              () => _LoadedSourceNotifier(source),
            ),
            deviceClassProvider.overrideWithValue(DeviceClass.phone),
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
              home: Scaffold(body: WaveformViewCenter(onCompareWith: () {})),
            ),
          ),
        );
        await tester.pump();

        final listWidth = tester.getSize(find.byType(SignalListPanel)).width;
        expect(listWidth, 220); // 320 − 100 floor for the canvas
        expect(tester.takeException(), isNull);
      },
    );

    // Regression: Issue 30. On iPhone landscape, the "+ New Group" inline
    // header read as a stray popover floating just below the toolbar
    // because the phone-class chrome leaves it adjacent to the tab-bar
    // region. The header is now suppressed on phone and phone-landscape;
    // group creation remains reachable via the signal-row context menu
    // and the command palette.
    testWidgets(
      'hides "+ New Group" header on phone-landscape (Issue 30)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(844, 390));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final source = _MockSource();
        when(() => source.startTime).thenReturn(0);
        when(() => source.endTime).thenReturn(1000);
        when(() => source.timescale).thenReturn(null);
        when(() => source.rootScopes).thenReturn([
          _scope([_v('clk')]),
        ]);
        when(() => source.findVariables(any())).thenReturn([_v('clk')]);
        when(() => source.isSignalLoaded(any())).thenReturn(false);
        when(() => source.loadSignal(any())).thenAnswer((_) async {});
        when(() => source.changesInRange(any(), any(), any())).thenReturn([]);

        final container = ProviderContainer(
          overrides: [
            waveformSourceProvider.overrideWith(
              () => _LoadedSourceNotifier(source),
            ),
            deviceClassProvider.overrideWithValue(DeviceClass.phoneLandscape),
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
              home: Scaffold(body: WaveformViewCenter(onCompareWith: () {})),
            ),
          ),
        );
        await tester.pump();

        final l10n = await L10N.delegate.load(const Locale('en'));
        expect(
          find.text(l10n.signalGroupCreateNew),
          findsNothing,
          reason:
              'the "+ New Group" affordance must be hidden on '
              'phone-landscape so it does not crowd the tab-bar region',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'shows "+ New Group" header on tablet/desktop',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1400, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final source = _MockSource();
        when(() => source.startTime).thenReturn(0);
        when(() => source.endTime).thenReturn(1000);
        when(() => source.timescale).thenReturn(null);
        when(() => source.rootScopes).thenReturn([
          _scope([_v('clk')]),
        ]);
        when(() => source.findVariables(any())).thenReturn([_v('clk')]);
        when(() => source.isSignalLoaded(any())).thenReturn(false);
        when(() => source.loadSignal(any())).thenAnswer((_) async {});
        when(() => source.changesInRange(any(), any(), any())).thenReturn([]);

        final container = ProviderContainer(
          overrides: [
            waveformSourceProvider.overrideWith(
              () => _LoadedSourceNotifier(source),
            ),
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
              home: Scaffold(body: WaveformViewCenter(onCompareWith: () {})),
            ),
          ),
        );
        await tester.pump();

        final l10n = await L10N.delegate.load(const Locale('en'));
        expect(
          find.text(l10n.signalGroupCreateNew),
          findsOneWidget,
          reason:
              'the "+ New Group" affordance must remain available '
              'on tablet and desktop',
        );
      },
    );

    testWidgets('error state locale sweep — no exceptions', (tester) async {
      for (final locale in [
        const Locale('en'),
        const Locale('zh', 'CN'),
        const Locale('ja'),
        const Locale('ko'),
      ]) {
        final container = ProviderContainer(
          overrides: [
            waveformSourceProvider.overrideWith(_ErrorSourceNotifier.new),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              locale: locale,
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(body: WaveformViewCenter(onCompareWith: () {})),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
      'inner Columns drop fixed-height chrome when the host gives it less '
      'than `timeRulerHeight` of vertical space — repro of the resize-down '
      'overflow at waveform_view_center.dart:270/:282',
      (tester) async {
        // The panes package's MultiPane lets each pane overshoot its container
        // when the container is smaller than the sum of pane minSizes. When
        // the user shrinks the app window vertically, the IdeLayout center
        // pane can be given a maxHeight smaller than the 36 dp time ruler /
        // _SignalListHeader, producing yellow/black RenderFlex overflow bars.
        // The LayoutBuilder guards in WaveformViewCenter drop the fixed-
        // height chrome (header, ruler, cocotb overlay, scrollbar) when there
        // is no room. This test reproduces the constraint directly with a
        // 30 dp tall SizedBox and asserts no exception fires — without the
        // guards, this throws `A RenderFlex overflowed by 6.0 pixels...`.
        final source = _MockSource();
        when(() => source.startTime).thenReturn(0);
        when(() => source.endTime).thenReturn(1000);
        when(() => source.timescale).thenReturn(null);
        when(() => source.rootScopes).thenReturn([
          _scope([_v('clk')]),
        ]);
        when(() => source.findVariables(any())).thenReturn([_v('clk')]);
        when(() => source.isSignalLoaded(any())).thenReturn(false);
        when(() => source.loadSignal(any())).thenAnswer((_) async {});
        when(() => source.changesInRange(any(), any(), any())).thenReturn([]);

        final container = ProviderContainer(
          overrides: [
            waveformSourceProvider.overrideWith(
              () => _LoadedSourceNotifier(source),
            ),
          ],
        );
        addTearDown(container.dispose);
        container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(
                body: SizedBox(
                  width: 800,
                  // 30 dp < timeRulerHeight (36 dp); the inner Columns must
                  // drop the header + ruler so the Expanded canvas takes the
                  // 30 dp without overflow.
                  height: 30,
                  child: WaveformViewCenter(onCompareWith: () {}),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        // The ruler and scrollbar are dropped when the column constraint is
        // smaller than their fixed height — without the guards both would be
        // visible (overflowing). With the guards, neither is in the tree.
        expect(find.byType(TimeRulerWidget), findsNothing);
      },
    );
  });
}
