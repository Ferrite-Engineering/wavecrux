// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';

import '../../helpers/product_telemetry_config.dart';
import '../../helpers/wellen_ffi_library_gate.dart';

/// Annotations across a file reload.
///
/// **Why this matters more than it looks.** The file watcher's auto-reload
/// calls `openFile` with the same path every time a simulation rewrites the
/// dump. That is not a "new file" — it is the precise moment the witness
/// mechanism earns its keep, because the notes that no longer hold are about
/// to flag themselves. Clearing annotations there deletes the user's work at
/// exactly the moment it became most useful, and it did: the reset block
/// treated every `openFile` as a fresh file.
///
/// Opening a *different* file must still clear them — a note anchored to
/// `top.bus` in one design means nothing in another.
const _demo = 'examples/annotations/annotations-demo.vcd';
const _other = 'examples/five-buses/five-buses.vcd';

Annotation _ann({String id = 'a1'}) => Annotation(
  id: id,
  shape: AnnotationShape.callout,
  anchor: const PointAnchor(time: 500, rowId: 'top.bus'),
  authorName: 'Martin',
  createdAt: DateTime.utc(2026, 8, 12),
  text: 'survives a re-simulation',
);

void main() {
  if (!requireWellenFfiLibrary('annotations across a file reload')) return;

  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(overrides: [productTelemetryConfig])
      ..listen(annotationsProvider, (_, _) {})
      ..listen(waveformSourceProvider, (_, _) {});
  });
  tearDown(() async {
    await container.read(waveformSourceProvider.notifier).close();
    container.dispose();
  });

  test('a reload of the same file keeps annotations', () async {
    final source = container.read(waveformSourceProvider.notifier);
    await source.openFile(_demo);

    container.read(annotationsProvider.notifier).add(_ann());
    expect(container.read(annotationsProvider), hasLength(1));

    // What the file watcher does when a simulation rewrites the dump.
    await source.openFile(_demo);

    expect(
      container.read(annotationsProvider).map((a) => a.id),
      ['a1'],
      reason:
          'auto-reload after a re-simulation is exactly when the witness '
          'is supposed to speak, so the notes have to still be there',
    );
  });

  test('opening a different file clears annotations', () async {
    final source = container.read(waveformSourceProvider.notifier);
    await source.openFile(_demo);
    container.read(annotationsProvider.notifier).add(_ann());

    await source.openFile(_other);

    expect(
      container.read(annotationsProvider),
      isEmpty,
      reason: 'a note anchored to top.bus means nothing in another design',
    );
  });

  test('closing the file clears annotations', () async {
    final source = container.read(waveformSourceProvider.notifier);
    await source.openFile(_demo);
    container.read(annotationsProvider.notifier).add(_ann());

    await source.close();

    expect(container.read(annotationsProvider), isEmpty);
  });

  test("undo cannot resurrect the previous file's notes", () async {
    final source = container.read(waveformSourceProvider.notifier);
    await source.openFile(_demo);
    container.read(annotationsProvider.notifier).add(_ann());

    await source.openFile(_other);
    // Assert behaviour rather than `canUndo`: reading `.notifier` does not
    // flush a pending invalidation the way reading the value does, so that
    // flag is an implementation detail. What must never happen is the old
    // file's notes reappearing on screen.
    expect(container.read(annotationsProvider), isEmpty);

    container.read(annotationsProvider.notifier).undo();

    expect(
      container.read(annotationsProvider),
      isEmpty,
      reason:
          'undo across a file switch would resurrect notes anchored into '
          'a design that is no longer open',
    );
  });
}
