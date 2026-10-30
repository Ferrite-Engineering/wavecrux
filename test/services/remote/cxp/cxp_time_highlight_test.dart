// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart' show CruxCxpHandlerResult;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/timescale_unit.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/remote/cxp/cxp_inbound_handlers.dart';

import '../../../helpers/cxp_test_overrides.dart';
import '../../../helpers/fake_waveform_data_source.dart';
import '../../../helpers/product_telemetry_config.dart';

/// The inbound half of `crux.time_ps` (CXP §9.3.2): what WaveCrux does with a
/// `request_highlight` of a signal that carries a point in simulation time.
void main() {
  const timeKey = 'crux.time_ps';

  const scope = Scope(
    name: 'top',
    path: 'top',
    type: ScopeType.module,
    variables: <Variable>[
      Variable(
        name: 'clk',
        varType: VarType.wire,
        direction: VarDirection.input,
        signalRef: 'top.clk',
        scopePath: 'top',
        bitWidth: 1,
      ),
    ],
  );

  ProviderContainer makeContainer({
    FakeWaveformDataSource? source,
    Timescale? timescale = const Timescale(
      factor: 1,
      unit: TimescaleUnit.nanoSeconds,
    ),
    int endTime = 1000,
  }) {
    final loaded =
        source ??
        FakeWaveformDataSource(
          scopes: const <Scope>[scope],
          timescale: timescale,
          endTime: endTime,
        );
    return ProviderContainer(
      overrides: [
        ...cxpTestOverrides,
        productTelemetryConfig,
        waveformSourceProvider.overrideWith(
          () => _PreloadedSourceNotifier(loaded),
        ),
      ],
    );
  }

  Future<CruxCxpHandlerResult> highlight(
    ProviderContainer container,
    Map<String, Object?> metadata, {
    ElementId element = const ElementId(
      kind: ElementKind.signal,
      path: 'top.clk',
    ),
  }) => dispatchCxpHighlight(container.read(_refProvider), element, metadata);

  int? cursor(ProviderContainer c) =>
      c.read(cursorStateProvider).primaryCursorTime;

  test(
    'the cursor goes to the time, converted to the dump timescale',
    () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      // 41250 ps on a 1 ns timescale is tick 41.
      final result = await highlight(container, {timeKey: 41250});

      expect(result.honored, isTrue);
      expect(result.reason, isNull);
      expect(cursor(container), 41);
    },
  );

  test('the signal is still brought into view and focused', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    await highlight(container, {timeKey: 41250});

    expect(container.read(selectedVariablesProvider), contains('top.clk'));
  });

  test('a net, a port and an instance take the time too', () async {
    for (final kind in [
      ElementKind.net,
      ElementKind.port,
      ElementKind.instance,
    ]) {
      final container = makeContainer();
      addTearDown(container.dispose);
      final result = await highlight(container, {
        timeKey: 300000,
      }, element: ElementId(kind: kind, path: 'top.clk'));
      expect(result.honored, isTrue, reason: kind.name);
      expect(cursor(container), 300, reason: kind.name);
    }
  });

  test('a finer timescale gets a finer tick', () async {
    final container = makeContainer(
      timescale: const Timescale(
        factor: 1,
        unit: TimescaleUnit.picoSeconds,
      ),
      endTime: 100000,
    );
    addTearDown(container.dispose);

    await highlight(container, {timeKey: 41250});

    expect(cursor(container), 41250);
  });

  test('time zero is a time', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    await highlight(container, {timeKey: 0});

    expect(cursor(container), 0);
  });

  test('a time past the dump is clamped to its end, and the sender is '
      'told', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    final result = await highlight(container, {timeKey: 9000000});

    expect(result.honored, isTrue);
    expect(result.reason, contains('nearest end'));
    expect(cursor(container), 1000);
  });

  test('without the key the cursor stays where it was', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    final result = await highlight(container, const {});

    expect(result.honored, isTrue);
    expect(result.reason, isNull);
    expect(cursor(container), isNull);
  });

  test('the un-namespaced name from before the key was registered is just '
      'an unknown key', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    final result = await highlight(container, {'time_ps': 41250});

    expect(result.honored, isTrue);
    expect(cursor(container), isNull);
  });

  test('with no waveform open the highlight is refused for the usual reason '
      'and no cursor is made', () async {
    final container = ProviderContainer(
      overrides: [...cxpTestOverrides, productTelemetryConfig],
    );
    addTearDown(container.dispose);

    final result = await highlight(container, {timeKey: 41250});

    expect(result.honored, isFalse);
    expect(result.reason, contains('no waveform file loaded'));
    expect(cursor(container), isNull);
  });

  test('a signal the dump does not hold is not found, and the time is not '
      'applied', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    final result = await highlight(
      container,
      {timeKey: 41250},
      element: const ElementId(kind: ElementKind.signal, path: 'top.nosuch'),
    );

    expect(result.honored, isFalse);
    expect(result.reason, contains('element not found'));
    expect(cursor(container), isNull);
  });

  group('a value it cannot use never costs the highlight', () {
    for (final entry in <String, Object?>{
      'negative': -5,
      'a float': 41250.5,
      'a string': '41250',
      'null': null,
    }.entries) {
      test(entry.key, () async {
        final container = makeContainer();
        addTearDown(container.dispose);

        final result = await highlight(container, {timeKey: entry.value});

        expect(result.honored, isTrue);
        expect(result.reason, contains('non-negative integer'));
        expect(cursor(container), isNull);
        expect(container.read(selectedVariablesProvider), contains('top.clk'));
      });
    }

    test('a dump with no timescale', () async {
      final container = makeContainer(timescale: null);
      addTearDown(container.dispose);

      final result = await highlight(container, {timeKey: 41250});

      expect(result.honored, isTrue);
      expect(result.reason, contains('no timescale'));
      expect(cursor(container), isNull);
      expect(container.read(selectedVariablesProvider), contains('top.clk'));
    });
  });

  test('a scope is not a signal: it takes no time', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    final result = await highlight(
      container,
      {timeKey: 41250},
      element: const ElementId(kind: ElementKind.scope, path: 'top'),
    );

    expect(result.honored, isTrue);
    expect(cursor(container), isNull);
  });

  group('scrolls the cursor into view', () {
    // 1000 ticks across a 100 px viewport, zoomed 10x at the left edge: the
    // window shows about ticks 0 to 100.
    ProviderContainer zoomedIn() {
      final container = makeContainer();
      addTearDown(container.dispose);
      container.read(timeMapperProvider.notifier)
        ..initialize(startTime: 0, endTime: 1000, viewportWidth: 100)
        ..zoomIn(focalPixel: 0, factor: 10);
      return container;
    }

    test('a time outside the window pans to it', () async {
      final container = zoomedIn();
      expect(container.read(timeMapperProvider).visibleEndTime, lessThan(200));

      await highlight(container, {timeKey: 800000});

      final mapper = container.read(timeMapperProvider);
      expect(cursor(container), 800);
      expect(mapper.visibleStartTime, lessThanOrEqualTo(800));
      expect(mapper.visibleEndTime, greaterThanOrEqualTo(800));
    });

    test('a time already in the window leaves the view alone', () async {
      final container = zoomedIn();
      final before = container.read(timeMapperProvider).panOffsetTicks;

      await highlight(container, {timeKey: 50000});

      expect(cursor(container), 50);
      expect(container.read(timeMapperProvider).panOffsetTicks, before);
    });

    test('a viewport that is not laid out yet is left alone', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      final result = await highlight(container, {timeKey: 800000});

      expect(result.honored, isTrue);
      expect(cursor(container), 800);
      expect(container.read(timeMapperProvider).isEmpty, isTrue);
    });
  });
}

final Provider<Ref> _refProvider = Provider<Ref>((ref) => ref);

class _PreloadedSourceNotifier extends WaveformSourceNotifier {
  _PreloadedSourceNotifier(this._source);
  final FakeWaveformDataSource _source;
  @override
  AsyncValue<FakeWaveformDataSource> build() => AsyncData(_source);
}
