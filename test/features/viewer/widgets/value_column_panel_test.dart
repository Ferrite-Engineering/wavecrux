// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_dock/crux_dock.dart' show kCruxDockStripHeight;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/comparison/constants/diff_constants.dart';
import 'package:wavecrux/features/comparison/providers/diff_provider.dart';
import 'package:wavecrux/features/comparison/widgets/diff_toolbar.dart';
import 'package:wavecrux/features/viewer/providers/pattern_search_provider.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/value_column_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/widgets/pattern_search_toolbar.dart';
import 'package:wavecrux/features/viewer/widgets/time_ruler_widget.dart';
import 'package:wavecrux/features/viewer/widgets/value_column_panel.dart';
import 'package:wavecrux/features/viewer/widgets/value_column_row.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

// ── fakes & mocks ─────────────────────────────────────────────────────────────

class _FakeDiffNotifier extends DiffNotifier {
  _FakeDiffNotifier(this._state);
  final DiffState _state;

  @override
  DiffState build() => _state;
}

class _FakePatternSearchNotifier extends PatternSearchNotifier {
  _FakePatternSearchNotifier(this._state);
  final PatternSearchState _state;

  @override
  PatternSearchState build() => _state;
}

class _MutableDiffNotifier extends DiffNotifier {
  @override
  DiffState build() => const DiffState();

  DiffState get diffState => state;
  set diffState(DiffState s) => state = s;
}

class _MockSource extends Mock implements WaveformDataSource {}

class _FakeSourceNotifier extends WaveformSourceNotifier {
  _FakeSourceNotifier(this._source);
  final WaveformDataSource? _source;

  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

// ── helpers ───────────────────────────────────────────────────────────────────

Variable _v(String name, {int? bitWidth}) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: 'ref_$name',
  scopePath: 'top',
  bitWidth: bitWidth,
);

Scope _scope(List<Variable> variables) => Scope(
  name: 'top',
  path: 'top',
  type: ScopeType.module,
  variables: variables,
);

const _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('ja'),
  Locale('ko'),
];

Widget _wrap({ProviderContainer? container, Locale? locale}) {
  if (container != null) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        locale: locale,
        home: const Scaffold(body: ValueColumnPanel()),
      ),
    );
  }
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      locale: locale,
      home: const Scaffold(body: ValueColumnPanel()),
    ),
  );
}

ProviderContainer _container({WaveformDataSource? source}) {
  final c = ProviderContainer(
    overrides: [
      if (source != null)
        waveformSourceProvider.overrideWith(
          () => _FakeSourceNotifier(source),
        ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('ValueColumnPanel — locale sweep', () {
    for (final locale in _locales) {
      testWidgets('renders in $locale without exception', (tester) async {
        await tester.pumpWidget(_wrap(locale: locale));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('light theme — renders without exception', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData.light(),
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: const Scaffold(body: ValueColumnPanel()),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('ValueColumnPanel — empty state', () {
    testWidgets('shows empty box when no signals added', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      // No signal rows; panel should render without crashing.
      expect(find.byType(ValueColumnPanel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('ValueColumnPanel — with signals', () {
    testWidgets('shows formatted value for loaded signal', (tester) async {
      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.rootScopes).thenReturn([
        _scope([_v('clk')]),
      ]);
      when(() => source.isSignalLoaded('ref_clk')).thenReturn(true);
      when(() => source.valueAt('ref_clk', 0)).thenReturn('1');

      final container = _container(source: source);
      container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

      await tester.pumpWidget(_wrap(container: container));
      await tester.pump();

      expect(find.text('1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows em-dash for unloaded signal', (tester) async {
      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.rootScopes).thenReturn([
        _scope([_v('clk')]),
      ]);
      when(() => source.isSignalLoaded('ref_clk')).thenReturn(false);

      final container = _container(source: source);
      container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

      await tester.pumpWidget(_wrap(container: container));
      await tester.pump();

      expect(find.text('—'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders one row per top-level entry', (tester) async {
      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.rootScopes).thenReturn([
        _scope([_v('clk'), _v('data', bitWidth: 8)]),
      ]);
      when(() => source.isSignalLoaded(any())).thenReturn(false);

      final container = _container(source: source);
      container.read(signalGroupsProvider.notifier)
        ..addSignal(_v('clk'))
        ..addSignal(_v('data', bitWidth: 8));

      await tester.pumpWidget(_wrap(container: container));
      await tester.pump();

      // Two signal rows → two em-dash texts.
      expect(find.text('—'), findsNWidgets(2));
    });

    testWidgets('format change from context menu updates displayed value', (
      tester,
    ) async {
      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.rootScopes).thenReturn([
        _scope([_v('data', bitWidth: 8)]),
      ]);
      when(() => source.isSignalLoaded('ref_data')).thenReturn(true);
      when(() => source.valueAt('ref_data', 0)).thenReturn('11111111');

      final container = _container(source: source);
      container
          .read(signalGroupsProvider.notifier)
          .addSignal(
            _v('data', bitWidth: 8),
          );

      await tester.pumpWidget(_wrap(container: container));
      await tester.pump();

      // Default for 8-bit is hex.
      expect(find.text('ff'), findsOneWidget);

      // Change to binary via the notifier (simulating context menu selection).
      container
          .read(signalGroupsProvider.notifier)
          .setSignalFormat(0, DisplayFormat.binary);
      await tester.pump();

      expect(find.text('11111111'), findsOneWidget);
    });

    testWidgets('duplicate signal added twice renders two rows without error', (
      tester,
    ) async {
      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.rootScopes).thenReturn([
        _scope([_v('clk')]),
      ]);
      when(() => source.isSignalLoaded('ref_clk')).thenReturn(false);

      final container = _container(source: source);
      // Add the same signal twice — previously caused duplicate key exception.
      container.read(signalGroupsProvider.notifier)
        ..addSignal(_v('clk'))
        ..addSignal(_v('clk'));

      await tester.pumpWidget(_wrap(container: container));
      await tester.pump();

      expect(find.text('—'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('scroll sync: listening to WaveformScrollNotifier', (
      tester,
    ) async {
      final container = _container();
      container.read(signalGroupsProvider.notifier)
        ..addSignal(_v('a'))
        ..addSignal(_v('b'));

      await tester.pumpWidget(_wrap(container: container));
      await tester.pump();

      // Update the shared scroll offset — should not throw.
      container.read(waveformScrollProvider.notifier).setOffset(100);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('ValueColumnPanel — ruler alignment', () {
    testWidgets('first value row is offset by timeRulerHeight MINUS the dock '
        'strip the right region spends above the panel', (
      tester,
    ) async {
      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.rootScopes).thenReturn([
        _scope([_v('clk')]),
      ]);
      when(() => source.isSignalLoaded('ref_clk')).thenReturn(false);

      final container = _container(source: source);
      container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

      await tester.pumpWidget(_wrap(container: container));
      await tester.pump();

      final panelTop = tester.getTopLeft(find.byType(ValueColumnPanel)).dy;
      final rowTop = tester.getTopLeft(find.byType(ValueColumnRow).first).dy;
      expect(rowTop - panelTop, timeRulerHeight - kCruxDockStripHeight);
    });
  });

  group('ValueColumnPanel — XOR diff spacers', () {
    testWidgets(
      'spacer SizedBox appears after signal row when diff is active',
      (tester) async {
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

        await tester.pumpWidget(_wrap(container: container));
        await tester.pump();

        // The spacer is a SizedBox with diffXorLaneHeight.
        // Scope to the ListView so the panel's own bottom scrollbar-band
        // reservation (matches WaveformHorizontalScrollbar's bandHeight in
        // the canvas column to keep maxScrollExtents aligned) doesn't collide
        // with the predicate. The XOR spacer lives inside the ListView; the
        // scrollbar reservation is a Column sibling.
        expect(
          find.descendant(
            of: find.byType(ListView),
            matching: find.byWidgetPredicate(
              (w) => w is SizedBox && w.height == diffXorLaneHeight,
            ),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('no spacer SizedBox when diff is inactive', (tester) async {
      final container = _container();
      container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

      await tester.pumpWidget(_wrap(container: container));
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.byWidgetPredicate(
            (w) => w is SizedBox && w.height == diffXorLaneHeight,
          ),
        ),
        findsNothing,
      );
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

      await tester.pumpWidget(_wrap(container: container));
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.byWidgetPredicate(
            (w) => w is SizedBox && w.height == diffXorLaneHeight,
          ),
        ),
        findsNothing,
      );
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

      await tester.pumpWidget(_wrap(container: container));
      await tester.pump();

      // Scope to the ListView so the panel's own bottom scrollbar-band
      // reservation (matches WaveformHorizontalScrollbar's bandHeight in
      // the canvas column to keep maxScrollExtents aligned) doesn't collide
      // with the predicate. The XOR spacer lives inside the ListView; the
      // scrollbar reservation is a Column sibling.
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.byWidgetPredicate(
            (w) => w is SizedBox && w.height == diffXorLaneHeight,
          ),
        ),
        findsOneWidget,
      );

      // Clear diff.
      (container.read(diffProvider.notifier) as _MutableDiffNotifier)
              .diffState =
          const DiffState();
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.byWidgetPredicate(
            (w) => w is SizedBox && w.height == diffXorLaneHeight,
          ),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('one spacer per differing signal', (tester) async {
      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.rootScopes).thenReturn([
        _scope([_v('clk'), _v('data', bitWidth: 8)]),
      ]);
      when(() => source.isSignalLoaded(any())).thenReturn(false);

      final container = ProviderContainer(
        overrides: [
          waveformSourceProvider.overrideWith(
            () => _FakeSourceNotifier(source),
          ),
          diffProvider.overrideWith(
            () => _FakeDiffNotifier(
              const DiffState(
                secondFilePath: '/b.vcd',
                xorTraces: {'ref_clk': [], 'ref_data': []},
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(signalGroupsProvider.notifier)
        ..addSignal(_v('clk'))
        ..addSignal(_v('data', bitWidth: 8));

      await tester.pumpWidget(_wrap(container: container));
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.byWidgetPredicate(
            (w) => w is SizedBox && w.height == diffXorLaneHeight,
          ),
        ),
        findsNWidgets(2),
      );
      expect(tester.takeException(), isNull);
    });
  });

  // ── toolbar-height alignment ────────────────────────────────────────────────

  /// Returns a [ProviderContainer] with optional diff and pattern-search
  /// overrides, plus the waveform source override.
  ProviderContainer containerWithToolbars({
    WaveformDataSource? source,
    DiffState? diffState,
    PatternSearchState? patternState,
  }) {
    final c = ProviderContainer(
      overrides: [
        if (source != null)
          waveformSourceProvider.overrideWith(
            () => _FakeSourceNotifier(source),
          ),
        if (diffState != null)
          diffProvider.overrideWith(
            () => _FakeDiffNotifier(diffState),
          ),
        if (patternState != null)
          patternSearchProvider.overrideWith(
            () => _FakePatternSearchNotifier(patternState),
          ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('ValueColumnPanel — toolbar alignment spacer', () {
    testWidgets('spacer is timeRulerHeight minus the dock strip when no '
        'toolbars are active', (
      tester,
    ) async {
      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.rootScopes).thenReturn([
        _scope([_v('clk')]),
      ]);
      when(() => source.isSignalLoaded('ref_clk')).thenReturn(false);

      final container = containerWithToolbars(source: source);
      container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

      await tester.pumpWidget(_wrap(container: container));
      await tester.pump();

      final panelTop = tester.getTopLeft(find.byType(ValueColumnPanel)).dy;
      final rowTop = tester.getTopLeft(find.byType(ValueColumnRow).first).dy;
      expect(rowTop - panelTop, timeRulerHeight - kCruxDockStripHeight);
      expect(tester.takeException(), isNull);
    });

    testWidgets('spacer grows by DiffToolbar.height when diff is active', (
      tester,
    ) async {
      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.rootScopes).thenReturn([
        _scope([_v('clk')]),
      ]);
      when(() => source.isSignalLoaded('ref_clk')).thenReturn(false);

      final container = containerWithToolbars(
        source: source,
        diffState: const DiffState(secondFilePath: '/b.vcd'),
      );
      container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

      await tester.pumpWidget(_wrap(container: container));
      await tester.pump();

      final panelTop = tester.getTopLeft(find.byType(ValueColumnPanel)).dy;
      final rowTop = tester.getTopLeft(find.byType(ValueColumnRow).first).dy;
      expect(
        rowTop - panelTop,
        timeRulerHeight + DiffToolbar.height - kCruxDockStripHeight,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'spacer grows by PatternSearchToolbar.height when pattern search has results',
      (tester) async {
        final source = _MockSource();
        when(() => source.startTime).thenReturn(0);
        when(() => source.rootScopes).thenReturn([
          _scope([_v('clk')]),
        ]);
        when(() => source.isSignalLoaded('ref_clk')).thenReturn(false);

        final container = containerWithToolbars(
          source: source,
          // hasResult == true when result is non-null and isSearching is false.
          patternState: const PatternSearchState(isSearching: true),
        );
        container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

        await tester.pumpWidget(_wrap(container: container));
        await tester.pump();

        final panelTop = tester.getTopLeft(find.byType(ValueColumnPanel)).dy;
        final rowTop = tester.getTopLeft(find.byType(ValueColumnRow).first).dy;
        expect(
          rowTop - panelTop,
          timeRulerHeight + PatternSearchToolbar.height - kCruxDockStripHeight,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('spacer uses combined height when both toolbars are active', (
      tester,
    ) async {
      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.rootScopes).thenReturn([
        _scope([_v('clk')]),
      ]);
      when(() => source.isSignalLoaded('ref_clk')).thenReturn(false);

      final container = containerWithToolbars(
        source: source,
        diffState: const DiffState(secondFilePath: '/b.vcd'),
        patternState: const PatternSearchState(isSearching: true),
      );
      container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

      await tester.pumpWidget(_wrap(container: container));
      await tester.pump();

      final panelTop = tester.getTopLeft(find.byType(ValueColumnPanel)).dy;
      final rowTop = tester.getTopLeft(find.byType(ValueColumnRow).first).dy;
      expect(
        rowTop - panelTop,
        timeRulerHeight +
            DiffToolbar.height +
            PatternSearchToolbar.height -
            kCruxDockStripHeight,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('spacer returns to timeRulerHeight after diff is dismissed', (
      tester,
    ) async {
      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.rootScopes).thenReturn([
        _scope([_v('clk')]),
      ]);
      when(() => source.isSignalLoaded('ref_clk')).thenReturn(false);

      final container = ProviderContainer(
        overrides: [
          waveformSourceProvider.overrideWith(
            () => _FakeSourceNotifier(source),
          ),
          diffProvider.overrideWith(_MutableDiffNotifier.new),
        ],
      );
      addTearDown(container.dispose);
      container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

      // Activate diff.
      container.read(diffProvider);
      (container.read(diffProvider.notifier) as _MutableDiffNotifier)
          .diffState = const DiffState(
        secondFilePath: '/b.vcd',
      );

      await tester.pumpWidget(_wrap(container: container));
      await tester.pump();

      final panelTop = tester.getTopLeft(find.byType(ValueColumnPanel)).dy;
      expect(
        tester.getTopLeft(find.byType(ValueColumnRow).first).dy - panelTop,
        timeRulerHeight + DiffToolbar.height - kCruxDockStripHeight,
      );

      // Dismiss diff.
      (container.read(diffProvider.notifier) as _MutableDiffNotifier)
              .diffState =
          const DiffState();
      await tester.pump();

      expect(
        tester.getTopLeft(find.byType(ValueColumnRow).first).dy - panelTop,
        timeRulerHeight - kCruxDockStripHeight,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('ValueColumnPanel — no overflow when canvasViewportHeight lags', () {
    testWidgets(
      'a stale canvasViewportHeight taller than the pane does not overflow',
      (tester) async {
        // Regression: the canvas republishes canvasViewportHeightProvider via a
        // post-frame callback, so for one frame after an overlay layer is added
        // (e.g. entering diff / pattern-search mode adds a timeline overlay) the
        // value column reserves the new overlay height on top of a
        // canvasViewportHeight that still reflects the taller pre-overlay
        // viewport. The fixed children then exceed the pane — the 8 dp RenderFlex
        // overflow seen in the Pro decoder + diff/pattern coexistence integration
        // tests. The Expanded + ClipRect/OverflowBox host must absorb the
        // transient overshoot without throwing.
        final source = _MockSource();
        when(() => source.startTime).thenReturn(0);
        when(() => source.rootScopes).thenReturn([
          _scope([_v('clk')]),
        ]);
        when(() => source.isSignalLoaded('ref_clk')).thenReturn(false);

        final container = _container(source: source);
        container.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

        await tester.pumpWidget(_wrap(container: container));
        await tester.pump();

        // Push a canvasViewportHeight far larger than the (default 600 dp) pane —
        // the stale, too-large value the one-frame lag produces.
        container.read(canvasViewportHeightProvider.notifier).setHeight(2000);
        await tester.pump();

        expect(tester.takeException(), isNull);
      },
    );
  });
}
