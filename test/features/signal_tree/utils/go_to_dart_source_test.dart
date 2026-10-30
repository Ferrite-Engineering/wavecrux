// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/rohd_dart_source.dart';
import 'package:wavecrux/features/signal_tree/utils/go_to_dart_source.dart';

const RohdDartSource _source = RohdDartSource(
  primary: RohdDartLocation(file: '/p/lib/design.dart', line: 25, column: 21),
);

void main() {
  test('runs the editor command at file:line:column', () async {
    final calls = <(String, String)>[];
    final result = await goToDartSource(
      _source,
      editorCommand: 'code -g',
      runner: (command, target) async {
        calls.add((command, target));
        return CruxCxpHandlerResult.ok;
      },
    );
    expect(result.outcome, GoToDartOutcome.opened);
    expect(calls, [('code -g', '/p/lib/design.dart:25:21')]);
  });

  test('with no editor command set, nothing runs', () async {
    var ran = false;
    for (final command in ['', '   ']) {
      final result = await goToDartSource(
        _source,
        editorCommand: command,
        runner: (_, _) async {
          ran = true;
          return CruxCxpHandlerResult.ok;
        },
      );
      expect(result.outcome, GoToDartOutcome.noEditor);
    }
    expect(ran, isFalse);
  });

  test('a launcher that refuses is reported with its reason', () async {
    final result = await goToDartSource(
      _source,
      editorCommand: 'nope',
      runner: (_, _) async => const CruxCxpHandlerResult(
        honored: false,
        reason: 'editor not found',
      ),
    );
    expect(result.outcome, GoToDartOutcome.failed);
    expect(result.reason, 'editor not found');
  });
}
