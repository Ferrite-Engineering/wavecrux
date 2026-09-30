// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_data_revision_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/annotations/annotation_witness_service.dart';

import '../../helpers/product_telemetry_config.dart';
import '../../helpers/wellen_ffi_library_gate.dart';

/// Annotations — drift must recompute when the file is reloaded in place.
///
/// Keeping annotations across an auto-reload is only half the behaviour. If
/// their *status* does not recompute against the newly-parsed data, the notes
/// survive but keep asserting the old answer — which is worse than losing
/// them, because it looks correct.
void main() {
  if (!requireWellenFfiLibrary('annotation drift on reload')) return;

  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late String vcdPath;

  /// Writes the fixture with `bus` holding [busBits] from tick 400.
  Future<void> writeVcd(String busBits) async {
    await File(vcdPath).writeAsString('''
\$timescale 1 ns \$end
\$scope module top \$end
\$var wire 1 ! clk \$end
\$var wire 8 " bus \$end
\$upscope \$end
\$enddefinitions \$end

#0
0!
b0 "
#400
1!
b$busBits "
#800
0!
''');
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('wavecrux_drift_');
    vcdPath = '${dir.path}/reload.vcd';
    await writeVcd('10100011');
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } on FileSystemException catch (_) {}
  });

  test('an in-place reload recomputes drift', () async {
    final container = ProviderContainer(overrides: [productTelemetryConfig])
      ..listen(annotationsProvider, (_, _) {})
      ..listen(waveformSourceProvider, (_, _) {})
      ..listen(signalGroupsProvider, (_, _) {})
      ..listen(annotationStatusesProvider, (_, _) {})
      ..listen(waveformDataRevisionProvider, (_, _) {});
    addTearDown(container.dispose);

    final source = container.read(waveformSourceProvider.notifier);
    await source.openFile(vcdPath);
    addTearDown(source.close);

    // Display the bus so the annotation has a lane.
    final variables = container
        .read(waveformSourceProvider)
        .value!
        .findVariables(const SignalFilter());
    final bus = variables.firstWhere((v) => v.name == 'bus');
    container.read(signalGroupsProvider.notifier).addSignal(bus);
    await container
        .read(waveformSourceProvider)
        .value!
        .loadSignal(
          bus.signalRef,
        );

    container
        .read(annotationsProvider.notifier)
        .add(
          Annotation(
            id: 'a1',
            shape: AnnotationShape.callout,
            anchor: PointAnchor(time: 500, rowId: bus.fullPath),
            authorName: 'Martin',
            createdAt: DateTime.utc(2026, 8, 12),
            text: 'bus should read a3',
            witness: const AnnotationWitness(bits: '10100011'),
          ),
        );

    expect(
      container.read(annotationStatusesProvider)['a1'],
      AnnotationStatus.resolved,
      reason: 'baseline: the witness matches what the file holds',
    );

    // The simulation re-runs and rewrites the dump in place; the file watcher
    // re-opens the same path. `reloadCurrentFile` then restores the signal
    // list and the canvas re-loads sample data — modelled with the same steps,
    // since neither widget is in this test.
    await writeVcd('00000000');
    final displayedBefore = container.read(signalGroupsProvider);
    await source.openFile(vcdPath, preserveDecoders: true);
    container
        .read(signalGroupsProvider.notifier)
        .restoreFromSession(displayedBefore);

    final reloaded = container.read(waveformSourceProvider).value!;
    container.read(signalGroupsProvider.notifier).reresolveSignalRefs(reloaded);
    final reloadedBus = reloaded
        .findVariables(const SignalFilter())
        .firstWhere((v) => v.name == 'bus');
    await reloaded.loadSignal(reloadedBus.signalRef);
    // What the canvas publishes once its lanes are readable.
    container.read(waveformDataRevisionProvider.notifier).bump();

    expect(
      container.read(annotationStatusesProvider)['a1'],
      AnnotationStatus.drifted,
      reason:
          'a note that survives a reload but keeps reporting the old '
          'answer is worse than one that vanished — it looks correct',
    );
  });
}
