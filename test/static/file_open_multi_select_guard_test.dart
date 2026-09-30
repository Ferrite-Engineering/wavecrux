// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Refuses `.single` on a `FilePicker` result.
///
/// `FilePicker.pickFiles` **is** the multi-select API: `allowMultiple` defaults
/// to `true` and is deprecated in favour of `pickFile` for the single case. The
/// panel therefore offers a multiple selection whatever the call site meant,
/// and every caller has to handle a list.
///
/// `_openFileDesktop` read `result.files.single`. `Iterable.single` throws on
/// two elements, the throw happened in an async callback, and nothing surfaced
/// it — so picking two waveforms in File ▸ Open and clicking Open did nothing
/// whatsoever: no tab, no error, no message. Dropping the same two files on the
/// window had always opened both, through the same `_openChosenPath`.
///
/// **Why a static guard and not a widget test.** A widget test that drives
/// three real opens through the screen is most of a day's fight for very little
/// signal. It needs the waveform loader stubbed (the real one never completes
/// without the wellen library), the security-scoped bookmark MethodChannel
/// mocked (its await never returns unanswered, stalling the loop on the first
/// file — which looks exactly like the bug), SharedPreferences mocked, the
/// workspace debounce zeroed, and bounded pumps rather than `pumpAndSettle`
/// (a tab whose file did not load shows the empty canvas, whose halo animates
/// forever). Past all that, opening a *second* waveform tab arms a periodic
/// timer that the binding's pending-timer check rejects at teardown, and which
/// survives six seconds of pumping and closing the tabs again.
///
/// The behaviour was verified by hand at that point — three chosen files
/// produced `[New Tab, a.vcd, b.vcd, c.vcd]`, where `.single` produced
/// `[New Tab]` — but none of that harness is worth carrying to assert one
/// `for` loop. What actually regresses is somebody reaching for `.single`
/// again, and that is exactly what this catches, in milliseconds.
///
/// Multi-path routing itself is covered where it already was: the drop handler
/// loops over the same `_openChosenPath`.
///
/// Companion to `file_picker_pin_test.dart`, which pins the version.
void main() {
  test('no picker result is read with .single', () {
    final offenders = <String>[];
    final pattern = RegExp(r'\.files\s*\.\s*single\b');

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        // Comments may name the pattern while explaining why it is gone.
        if (line.startsWith('//') || line.startsWith('///')) continue;
        if (pattern.hasMatch(line)) {
          offenders.add('${entity.path}:${i + 1}  $line');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'FilePicker.pickFiles returns every file the user selected, and the '
          'panel lets them select several however the call site is written. '
          '`.single` throws on two, inside an async callback where nothing '
          'surfaces it, so the command silently does nothing at all. Iterate '
          'the result and route each path through _openChosenPath, as '
          '_openDroppedPaths does:\n${offenders.join("\n")}',
    );
  });
}
