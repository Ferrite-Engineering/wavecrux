// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_status_bar/crux_status_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/providers/status_bar_trailing_widgets_provider.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/enums/timescale_unit.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/cursor_state.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/widgets/status_bar.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

const _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('ja'),
  Locale('ko'),
];

Widget _wrap(
  Widget child, {
  List<Override> overrides = const [],
  TargetPlatform platform = TargetPlatform.macOS,
  Locale? locale,
}) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    // StatusBar reads MobileMetrics.of(context, deviceClass), which
    // resolves via Theme.of(context).platform. Default to macOS so the
    // historical desktop sizing applies; per-test overrides exercise the
    // touch path.
    theme: ThemeData(platform: platform),
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    locale: locale,
    home: Scaffold(body: child),
  ),
);

// ── notifier stubs ─────────────────────────────────────────────────────────────

/// [TimeMapperNotifier] initialised fit-all over [0, 1000] at 800 px.
class _LoadedTimeMapper extends TimeMapperNotifier {
  @override
  TimeMapper build() => TimeMapper.fitAll(
    startTime: 0,
    endTime: 1000,
    viewportWidth: 800,
  );
}

/// [CursorStateNotifier] with primary cursor at tick 200.
class _CursorAt200 extends CursorStateNotifier {
  @override
  CursorState build() => const CursorState(primaryCursorTime: 200);
}

/// [CursorStateNotifier] with both cursors placed (primary=200, secondary=700).
class _BothCursors extends CursorStateNotifier {
  @override
  CursorState build() =>
      const CursorState(primaryCursorTime: 200, secondaryCursorTime: 700);
}

/// [WaveformSourceNotifier] in an error state.
class _ErrorSourceNotifier extends WaveformSourceNotifier {
  @override
  AsyncValue<WaveformDataSource?> build() => AsyncError(
    Exception('parse failed'),
    StackTrace.empty,
  );
}

/// [PanelLayoutNotifier] starting with the statistics strip already expanded.
class _StatsStripExpanded extends PanelLayoutNotifier {
  @override
  PanelLayoutState build() =>
      const PanelLayoutState(statisticsStripVisible: true);
}

/// [SelectedVariablesNotifier] seeded with a single selected row (the set is
/// keyed by fullPath) so the status bar renders its clear-selection
/// affordance.
class _OneSelected extends SelectedVariablesNotifier {
  @override
  Set<String> build() => const {'top.clk'};
}

void main() {
  group('StatusBar', () {
    for (final locale in _locales) {
      testWidgets('renders in $locale without exceptions', (tester) async {
        await tester.pumpWidget(_wrap(const StatusBar(), locale: locale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('renders trailing widgets injected via the open-core seam', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const StatusBar(),
          overrides: [
            statusBarTrailingWidgetsProvider.overrideWithValue(
              const [Text('COLLAB', key: Key('collab-trailing'))],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('collab-trailing')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('composes the shared CruxStatusBar chrome', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const StatusBar()));
      await tester.pumpAndSettle();

      // WaveCrux is the canonical adopter: its StatusBar mounts on the shared
      // cross-suite CruxStatusBar and contributes its own segments.
      expect(find.byType(CruxStatusBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('has desktop height (24 dp) on desktop class + macOS host', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const StatusBar()));
      await tester.pumpAndSettle();

      final box = tester.getSize(find.byType(StatusBar));
      expect(box.height, 24);
    });

    testWidgets('has touch height (40 dp) on phone class', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const StatusBar(),
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.phone),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final box = tester.getSize(find.byType(StatusBar));
      expect(box.height, 40);
    });

    testWidgets('has touch height (40 dp) on iPad-class iOS host', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const StatusBar(), platform: TargetPlatform.iOS),
      );
      await tester.pumpAndSettle();

      final box = tester.getSize(find.byType(StatusBar));
      expect(box.height, 40);
    });

    testWidgets('shows no range or cursor segments when mapper is empty', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const StatusBar()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Range:'), findsNothing);
      expect(find.textContaining('Zoom:'), findsNothing);
      expect(find.textContaining('T:'), findsNothing);
    });

    testWidgets('shows sim range and zoom when mapper has data', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const StatusBar(),
          overrides: [
            timeMapperProvider.overrideWith(_LoadedTimeMapper.new),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Range:'), findsOneWidget);
      expect(find.textContaining('Zoom:'), findsOneWidget);
    });

    testWidgets('shows cursor time when cursor is placed', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const StatusBar(),
          overrides: [
            timeMapperProvider.overrideWith(_LoadedTimeMapper.new),
            cursorStateProvider.overrideWith(_CursorAt200.new),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('T:'), findsOneWidget);
    });

    testWidgets('shows 100% zoom when fit-all', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const StatusBar(),
          overrides: [
            timeMapperProvider.overrideWith(_LoadedTimeMapper.new),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // At fit-all the visible range == full range → 100%.
      expect(find.textContaining('100%'), findsOneWidget);
    });

    testWidgets('shows secondary cursor time when secondary cursor is placed', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const StatusBar(),
          overrides: [
            timeMapperProvider.overrideWith(_LoadedTimeMapper.new),
            cursorStateProvider.overrideWith(_BothCursors.new),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('T2:'), findsOneWidget);
    });

    testWidgets('shows delta time when both cursors are placed', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const StatusBar(),
          overrides: [
            timeMapperProvider.overrideWith(_LoadedTimeMapper.new),
            cursorStateProvider.overrideWith(_BothCursors.new),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Δ:'), findsOneWidget);
    });

    testWidgets(
      'shows frequency when both cursors are placed and timescale known',
      (tester) async {
        // Frequency requires a timescale so secondsPerTick can be computed.
        const ns = Timescale(factor: 1, unit: TimescaleUnit.nanoSeconds);
        await tester.pumpWidget(
          _wrap(
            const StatusBar(),
            overrides: [
              timeMapperProvider.overrideWith(_LoadedTimeMapper.new),
              cursorStateProvider.overrideWith(_BothCursors.new),
              currentTimescaleProvider.overrideWithValue(ns),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('f:'), findsOneWidget);
      },
    );

    testWidgets('shows no T2/delta/frequency when only primary cursor placed', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const StatusBar(),
          overrides: [
            timeMapperProvider.overrideWith(_LoadedTimeMapper.new),
            cursorStateProvider.overrideWith(_CursorAt200.new),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('T2:'), findsNothing);
      expect(find.textContaining('Δ:'), findsNothing);
      expect(find.textContaining('f:'), findsNothing);
    });

    testWidgets('shows error label when source is in error state', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const StatusBar(),
          overrides: [
            waveformSourceProvider.overrideWith(_ErrorSourceNotifier.new),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Failed to load waveform'), findsOneWidget);
    });

    // ── phone — condensed view ─────────────────────────────────────────────────

    testWidgets('phone shows primary cursor time', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const StatusBar(),
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.phone),
            timeMapperProvider.overrideWith(_LoadedTimeMapper.new),
            cursorStateProvider.overrideWith(_CursorAt200.new),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('T:'), findsOneWidget);
    });

    testWidgets('phone hides secondary cursor segment', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const StatusBar(),
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.phone),
            timeMapperProvider.overrideWith(_LoadedTimeMapper.new),
            cursorStateProvider.overrideWith(_BothCursors.new),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('T2:'), findsNothing);
    });

    testWidgets('phone hides delta segment', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const StatusBar(),
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.phone),
            timeMapperProvider.overrideWith(_LoadedTimeMapper.new),
            cursorStateProvider.overrideWith(_BothCursors.new),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Δ:'), findsNothing);
    });

    testWidgets('phone hides sim range segment', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const StatusBar(),
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.phone),
            timeMapperProvider.overrideWith(_LoadedTimeMapper.new),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Range:'), findsNothing);
    });

    testWidgets('phone hides zoom level segment', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const StatusBar(),
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.phone),
            timeMapperProvider.overrideWith(_LoadedTimeMapper.new),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('100%'), findsNothing);
    });

    testWidgets('phoneLandscape also hides secondary segments', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const StatusBar(),
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.phoneLandscape),
            timeMapperProvider.overrideWith(_LoadedTimeMapper.new),
            cursorStateProvider.overrideWith(_BothCursors.new),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('T2:'), findsNothing);
      expect(find.textContaining('Range:'), findsNothing);
    });

    testWidgets('tablet shows full bar including secondary cursor', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const StatusBar(),
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.tablet),
            timeMapperProvider.overrideWith(_LoadedTimeMapper.new),
            cursorStateProvider.overrideWith(_BothCursors.new),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('T2:'), findsOneWidget);
      expect(find.textContaining('Range:'), findsOneWidget);
    });

    // ── statistics strip disclosure (owned by the strip, not the bar) ──────────

    // The strip's disclosure triangle sits on the strip itself, as it does in
    // NetCrux and SimCrux. WaveCrux used to duplicate it here, which meant two
    // affordances for one piece of state. Assert the bar stays out of it — on
    // desktop most of all, where a stats control would once have appeared.
    for (final deviceClass in DeviceClass.values) {
      testWidgets('carries no statistics-strip toggle on ${deviceClass.name}', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(
            const StatusBar(),
            overrides: [
              deviceClassProvider.overrideWithValue(deviceClass),
              if (deviceClass == DeviceClass.desktop)
                panelLayoutProvider.overrideWith(_StatsStripExpanded.new),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Stats'), findsNothing);
        expect(find.text('▲'), findsNothing);
        expect(find.text('▼'), findsNothing);
        expect(
          tester
              .widgetList<Tooltip>(find.byType(Tooltip))
              .map((t) => t.message),
          isNot(contains(anyOf('Show Statistics', 'Hide Statistics'))),
        );
      });
    }

    testWidgets('shows a clear-selection button when a signal is selected', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const StatusBar(),
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.desktop),
            timeMapperProvider.overrideWith(_LoadedTimeMapper.new),
            selectedVariablesProvider.overrideWith(_OneSelected.new),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('status_bar_clear_selection')),
        findsOneWidget,
      );
    });

    testWidgets('hides the clear-selection button when nothing is selected', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const StatusBar(),
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.desktop),
            timeMapperProvider.overrideWith(_LoadedTimeMapper.new),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('status_bar_clear_selection')),
        findsNothing,
      );
    });

    testWidgets('tapping the clear-selection button clears the selection', (
      tester,
    ) async {
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.desktop),
            timeMapperProvider.overrideWith(_LoadedTimeMapper.new),
            selectedVariablesProvider.overrideWith(_OneSelected.new),
          ],
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(
                theme: ThemeData(platform: TargetPlatform.macOS),
                localizationsDelegates: L10N.localizationsDelegates,
                supportedLocales: L10N.supportedLocales,
                home: const Scaffold(body: StatusBar()),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(container.read(selectedVariablesProvider), isNotEmpty);

      await tester.tap(
        find.byKey(const ValueKey('status_bar_clear_selection')),
      );
      await tester.pumpAndSettle();

      expect(container.read(selectedVariablesProvider), isEmpty);
    });

    testWidgets('clear-selection button hidden on phone', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const StatusBar(),
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.phone),
            timeMapperProvider.overrideWith(_LoadedTimeMapper.new),
            selectedVariablesProvider.overrideWith(_OneSelected.new),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('status_bar_clear_selection')),
        findsNothing,
      );
    });
  });
}
