// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// LOCALE_SWEEP_EXEMPT: pure lazy-load side-effect regression — it asserts
// which signal refs the widget asked the source to load, and renders one
// English string only to prove the panel is not empty. The Pipeline Diagram's
// full five-locale sweep lives in pipeline_stage_renderer_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/stage/widgets/pipeline/pipeline_stage_renderer.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/translator_registry.dart';

import '../../../../helpers/generated_vcd_fixture.dart';
import '_pipeline_harness.dart';

/// **The trap this test exists for** (ARCHITECTURE §6.6, rule 1).
///
/// A Stage widget can bind any signal in the trace, including ones the user
/// never added to the viewer, so signal data is loaded lazily. Until a ref is
/// loaded, `WaveformDataSource.valueAt` answers `null` — the same answer it
/// gives for "no value at this tick" — and `changesInRange` answers empty. A
/// widget that walks the source without first watching each bound pin through
/// `stageBoundSignalProvider` therefore sees a clock that never rises and
/// draws nothing at all, on a perfectly good trace.
///
/// The Pipeline Diagram is *more* exposed to this than the Commit Inspector,
/// not less: an unloaded clock does not degrade the diagram, it deletes it.
class _LazySource implements WaveformDataSource {
  _LazySource(this._inner);

  final WaveformDataSource _inner;
  final Set<String> _loaded = <String>{};

  /// Refs the widget actually asked to be loaded.
  Set<String> get requested => Set.unmodifiable(_loaded);

  @override
  Future<void> loadSignal(String signalRef) async {
    _loaded.add(signalRef);
  }

  @override
  bool isSignalLoaded(String signalRef) => _loaded.contains(signalRef);

  @override
  Future<void> unloadSignal(String signalRef) async =>
      _loaded.remove(signalRef);

  @override
  String? valueAt(String signalRef, int time) =>
      _loaded.contains(signalRef) ? _inner.valueAt(signalRef, time) : null;

  @override
  List<SignalChange> changesInRange(String signalRef, int start, int end) =>
      _loaded.contains(signalRef)
      ? _inner.changesInRange(signalRef, start, end)
      : const [];

  @override
  SignalChange? nextTransition(String signalRef, int afterTime) =>
      _loaded.contains(signalRef)
      ? _inner.nextTransition(signalRef, afterTime)
      : null;

  @override
  SignalChange? prevTransition(String signalRef, int beforeTime) =>
      _loaded.contains(signalRef)
      ? _inner.prevTransition(signalRef, beforeTime)
      : null;

  @override
  List<Scope> get rootScopes => _inner.rootScopes;

  @override
  List<Variable> findVariables(SignalFilter filter) =>
      _inner.findVariables(filter);

  @override
  int get startTime => _inner.startTime;

  @override
  int get endTime => _inner.endTime;

  @override
  Timescale? get timescale => _inner.timescale;

  @override
  String? get date => _inner.date;

  @override
  String? get version => _inner.version;

  @override
  Future<void> openFile(String path) async {}

  @override
  void close() {}
}

class _LazySourceNotifier extends WaveformSourceNotifier {
  _LazySourceNotifier(this.source);

  final _LazySource source;

  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(source);
}

void main() {
  testWidgets('every bound pipeline pin is lazily loaded before the substrate '
      'walks the trace', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final fixture = GeneratedVcdFixture.load(cleanPipelineFixture);
    final lazy = _LazySource(fixture.source);
    final instance = pipelineInstance(fixture);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          waveformSourceProvider.overrideWith(() => _LazySourceNotifier(lazy)),
          riscvDisassemblerProvider.overrideWith(
            (ref) async => rv32Disassembler(),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Scaffold(body: PipelineStageRenderer(instance: instance)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The clock, the instruction word and all four pins of all five bound
    // stages — not just the clock, and not just whichever the first row
    // happened to read.
    expect(
      lazy.requested,
      hasLength(instance.signalBindings.length),
      reason:
          'a pin that is never watched through stageBoundSignalProvider stays '
          'unloaded, and valueAt answers null for it forever',
    );
    for (final binding in instance.signalBindings.values) {
      expect(lazy.requested, contains(binding.signalRef));
    }

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    container.read(cursorStateProvider.notifier).placePrimary(lazy.endTime);
    await tester.pumpAndSettle();

    // And the diagram is not empty — the whole point of the trap is that it
    // fails by rendering nothing rather than by throwing.
    expect(find.text('lw t0, 0(sp)'), findsOneWidget);
    expect(find.text('IF'), findsWidgets);
  });
}
