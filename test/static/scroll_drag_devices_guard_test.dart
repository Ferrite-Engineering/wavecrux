// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// A `ScrollConfiguration` that sets `dragDevices` to a set without touch
// stops a finger scrolling that list on every phone and tablet. The Stage
// widget picker and the decoder picker both shipped that way: they meant to
// add mouse drag and replaced the app's devices instead, which left every
// category past the first couple unreachable on a half-folded foldable.
//
// Rule: every `dragDevices: {…}` set literal in lib/ either spreads the
// inherited devices (`...`) or names `PointerDeviceKind.touch`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no dragDevices set in lib/ leaves touch out', () {
    final offenders = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final file in files) {
      final source = file.readAsStringSync();
      for (final match in RegExp(r'dragDevices:\s*\{').allMatches(source)) {
        final end = source.indexOf('}', match.end);
        if (end < 0) continue;
        final body = source.substring(match.end, end);
        if (body.contains('...') || body.contains('PointerDeviceKind.touch')) {
          continue;
        }
        final line = '\n'.allMatches(source.substring(0, match.start)).length;
        offenders.add('${file.path}:${line + 1}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'These dragDevices sets drop touch, so a finger cannot scroll the '
          'list. Spread the inherited devices '
          '(...ScrollConfiguration.of(context).dragDevices) and add to them.',
    );
  });
}
