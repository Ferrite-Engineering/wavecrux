// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Drives [SignalGraphStageRenderer] through its full *build + paint* path
// against a synchronous in-memory waveform source, so the happy-path build
// (sample extraction, value parsing) and `_SignalGraphPainter.paint` actually
// execute during the pump. The existing `signal_graph_stage_widget_test.dart`
// only covers the placeholder branches (unbound / no-file / loading) and the
// pure `computeSignalGraphYRange` logic; this file covers everything below the
// guards.
//
// Why a synchronous fake source rather than a live `WellenProvider`: the FFI
// provider keeps a background-isolate `Timer` alive that deadlocks under
// `testWidgets`' fake-async clock and trips the leak check at teardown. The
// shared [FakeWaveformSource] serves canned `SignalChange`s with no timers.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/timescale_unit.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/stage/widgets/primitives/signal_graph_stage_widget.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

import '../../../../support/fake_waveform_source.dart';

const _intRef = 's_int';
const _realRef = 's_real';
const _gapRef = 's_gap';

const _intBinding = StageSignalBinding(signalRef: _intRef);
const _realBinding = StageSignalBinding(signalRef: _realRef);
const _gapBinding = StageSignalBinding(signalRef: _gapRef);

/// Single-scope hierarchy carrying the metadata that `signalVariablesMap`
/// feeds the renderer (bitWidth + real-ness drive value parsing).
const _scopes = <Scope>[
  Scope(
    name: 'top',
    type: ScopeType.module,
    path: 'top',
    variables: [
      Variable(
        name: 'count',
        varType: VarType.wire,
        direction: VarDirection.output,
        signalRef: _intRef,
        scopePath: 'top',
        bitWidth: 8,
      ),
      Variable(
        name: 'level',
        varType: VarType.real,
        direction: VarDirection.output,
        signalRef: _realRef,
        scopePath: 'top',
      ),
      Variable(
        name: 'gap',
        varType: VarType.wire,
        direction: VarDirection.output,
        signalRef: _gapRef,
        scopePath: 'top',
        bitWidth: 4,
      ),
    ],
  ),
];

/// Builds the fake source with an 8-bit integer ramp, a real-valued sweep,
/// and a vector that drops to X mid-window (exercises the painter's gap path).
FakeWaveformSource _buildSource() {
  return FakeWaveformSource(
    endTime: 1000,
    timescale: const Timescale(factor: 1, unit: TimescaleUnit.nanoSeconds),
    rootScopes: _scopes,
    changes: {
      _intRef: const [
        SignalChange(time: 0, value: '00000000'),
        SignalChange(time: 200, value: '00010000'),
        SignalChange(time: 400, value: '01000000'),
        SignalChange(time: 600, value: '11111111'),
        SignalChange(time: 800, value: '00000001'),
      ],
      _realRef: const [
        SignalChange(time: 0, value: 'r0.0'),
        SignalChange(time: 300, value: 'r12.5'),
        SignalChange(time: 700, value: 'r-4.25'),
      ],
      _gapRef: const [
        SignalChange(time: 0, value: '0001'),
        SignalChange(time: 500, value: 'xxxx'),
        SignalChange(time: 700, value: '0010'),
      ],
    },
  );
}

Future<void> _pumpRenderer(
  WidgetTester tester, {
  required StageInstance instance,
  required FakeWaveformSource source,
  required int cursorTime,
  Locale locale = const Locale('en'),
  Size size = const Size(260, 140),
}) async {
  final container = ProviderContainer(
    overrides: [
      waveformSourceProvider.overrideWith(() => _FixtureSource(source)),
      hierarchyProvider.overrideWith((_) => AsyncData(source.rootScopes)),
    ],
  );
  addTearDown(container.dispose);
  container.read(cursorStateProvider.notifier).placePrimary(cursorTime);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: SignalGraphStageRenderer(instance: instance),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  // Flush the deferred signal-load kick scheduled in the first build so the
  // one-shot future settles before teardown's leak check.
  await tester.pump(const Duration(milliseconds: 350));
}

class _FixtureSource extends WaveformSourceNotifier {
  _FixtureSource(this._source);
  final WaveformDataSource _source;
  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

void main() {
  group('SignalGraphStageRenderer — paint path', () {
    testWidgets('integer signal renders a CustomPaint with samples', (
      tester,
    ) async {
      final source = _buildSource();
      await source.loadSignal(_intRef);
      const instance = StageInstance(
        id: 'i_int',
        widgetId: SignalGraphStageWidget.widgetId,
        signalBindings: {'value': _intBinding},
      );

      await _pumpRenderer(
        tester,
        instance: instance,
        source: source,
        cursorTime: 500,
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('real-valued signal parses and paints', (tester) async {
      final source = _buildSource();
      await source.loadSignal(_realRef);
      const instance = StageInstance(
        id: 'i_real',
        widgetId: SignalGraphStageWidget.widgetId,
        signalBindings: {'value': _realBinding},
      );

      await _pumpRenderer(
        tester,
        instance: instance,
        source: source,
        cursorTime: 500,
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('X/Z gap signal paints a broken trace without throwing', (
      tester,
    ) async {
      final source = _buildSource();
      await source.loadSignal(_gapRef);
      const instance = StageInstance(
        id: 'i_gap',
        widgetId: SignalGraphStageWidget.widgetId,
        signalBindings: {'value': _gapBinding},
      );

      await _pumpRenderer(
        tester,
        instance: instance,
        source: source,
        cursorTime: 600,
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('cursor at window start (no preceding sample) still paints', (
      tester,
    ) async {
      final source = _buildSource();
      await source.loadSignal(_intRef);
      const instance = StageInstance(
        id: 'i_start',
        widgetId: SignalGraphStageWidget.widgetId,
        signalBindings: {'value': _intBinding},
      );

      await _pumpRenderer(
        tester,
        instance: instance,
        source: source,
        cursorTime: 0,
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('cursor at window end paints with trailing hold', (
      tester,
    ) async {
      final source = _buildSource();
      await source.loadSignal(_intRef);
      const instance = StageInstance(
        id: 'i_end',
        widgetId: SignalGraphStageWidget.widgetId,
        signalBindings: {'value': _intBinding},
      );

      await _pumpRenderer(
        tester,
        instance: instance,
        source: source,
        cursorTime: 1000,
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('repaints cleanly when the cursor moves', (tester) async {
      final source = _buildSource();
      await source.loadSignal(_intRef);
      const instance = StageInstance(
        id: 'i_move',
        widgetId: SignalGraphStageWidget.widgetId,
        signalBindings: {'value': _intBinding},
      );

      final container = ProviderContainer(
        overrides: [
          waveformSourceProvider.overrideWith(() => _FixtureSource(source)),
          hierarchyProvider.overrideWith((_) => AsyncData(source.rootScopes)),
        ],
      );
      addTearDown(container.dispose);
      container.read(cursorStateProvider.notifier).placePrimary(200);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 260,
                height: 140,
                child: SignalGraphStageRenderer(instance: instance),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Move the cursor — exercises the painter's shouldRepaint and re-builds
      // the sample window.
      container.read(cursorStateProvider.notifier).placePrimary(700);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(tester.takeException(), isNull);
    });
  });

  group('SignalGraphStageRenderer — locale sweep (bound + painting)', () {
    for (final locale in ['en', 'zh', 'ja', 'ko']) {
      testWidgets('renders bound graph without exception in $locale', (
        tester,
      ) async {
        final source = _buildSource();
        await source.loadSignal(_intRef);
        const instance = StageInstance(
          id: 'i_locale',
          widgetId: SignalGraphStageWidget.widgetId,
          signalBindings: {'value': _intBinding},
        );

        await _pumpRenderer(
          tester,
          instance: instance,
          source: source,
          cursorTime: 500,
          locale: Locale(locale),
        );

        expect(tester.takeException(), isNull);
      });
    }
  });
}
