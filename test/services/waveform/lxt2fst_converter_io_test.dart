// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Lifecycle regression tests for the desktop/mobile [Lxt2FstConverter].
//
// Focus: the converted FST must survive the *natural* cancellation that a
// stream consumer like `await stream.last` performs once it has the final
// event. A prior bug ran the output-cleanup unconditionally from the
// controller's `onCancel`, so a successful conversion deleted the very FST
// it had just produced (the bridge-equivalence test failed at "converter
// must have produced an FST"). The fix only cleans up on a genuine
// mid-conversion cancel.
//
// The worker isolate always loads the real library (it cannot take the
// test's injected opener). The converter's C ABI ships inside the wellen FFI
// library, so these tests need `native/wellen_ffi` built: they skip locally
// without it and fail in CI, which builds it before the Dart tests.

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/services/waveform/lxt2fst_converter.dart';

import '../../helpers/wellen_ffi_library_gate.dart';

const _fixtureRoot = 'test/fixtures/legacy';

void main() {
  if (!requireWellenFfiLibrary('lxt2fst converter io')) return;

  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lxt2-io-');
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  // Each fixture converts cleanly today (structure + initial values), so
  // these exercise the success path for both legacy formats.
  for (final fixture in ['simple_counter.lxt2', 'simple_counter.lxt']) {
    final src = '$_fixtureRoot/$fixture';
    if (!File(src).existsSync()) {
      test('$fixture (skipped — fixture missing)', () {});
      continue;
    }

    test('$fixture: output FST survives `await stream.last` (no cleanup on '
        'natural cancel)', () async {
      final converter = Lxt2FstConverter();
      final outPath = p.join(tmp.path, '$fixture.fst');

      final last = await converter
          .convertPath(inPath: src, outPath: outPath)
          .last;

      expect(
        last.done,
        last.total,
        reason: 'final progress event must reach (N, N)',
      );
      expect(
        File(outPath).existsSync(),
        isTrue,
        reason:
            'a successful conversion consumed via `.last` must leave the '
            'FST on disk — the post-completion subscription cancel must not '
            'delete it',
      );
      expect(
        File(outPath).lengthSync(),
        greaterThan(0),
        reason: 'the produced FST must not be empty',
      );
    });

    test(
      '$fixture: collecting the full stream also leaves the FST on disk',
      () async {
        final converter = Lxt2FstConverter();
        final outPath = p.join(tmp.path, '$fixture.toList.fst');

        // `toList()` listens, drains every event, then completes — the
        // subscription cancels on done, the same path that tripped the bug.
        final events = await converter
            .convertPath(inPath: src, outPath: outPath)
            .toList();

        expect(events, isNotEmpty, reason: 'at least one progress event');
        expect(File(outPath).existsSync(), isTrue);
      },
    );
  }
}
