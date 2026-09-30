// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/helpers/wcp_frame_helpers.dart
//
// Shared frame-reading helpers for the WCP (WaveCrux remote-control
// protocol) integration tests under `integration_test/remote_control/`.
//
// Extracted from seven near-identical private copies: each `wcp_*_test.dart`
// file had hand-rolled its own `_attachFrameReader` + `_waitForFrame` pair,
// and two of them (`wcp_get_value_test.dart` and
// `wavecrux_extensions_test.dart`) had silently drifted to a 5s default
// timeout instead of 10s. One canonical implementation prevents that class of
// drift.
//
// Note on the 50 ms `Future<void>.delayed` inside `_waitForFrame`: it looks
// like a racy fixed wait after a socket write, but it is not — it is the poll
// INTERVAL inside a `DateTime`-deadline-bounded loop (10s default, tightened
// per call site where appropriate). That is the "bounded condition-poll"
// shape this repo's timing doctrine requires; see the "Integration-Test
// Timing" section of `wavecrux/CLAUDE.md` and `pumpUntil` in
// `app_driver.dart`. Do not "fix" it into a bare delay or a fixed sleep.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Attaches a null-byte-framed WCP message reader to [socket], decoding each
/// complete frame and appending it to [received] as it arrives.
///
/// The subscription is attached eagerly and remains active until the socket
/// closes. Callers poll [received] (via [waitForFrame]) to find frames of
/// interest — this avoids the re-subscription pitfalls of single-listener
/// [Stream]s when a test needs to consume more than one frame.
void attachFrameReader(
  Socket socket,
  List<Map<String, dynamic>> received,
) {
  final buffer = <int>[];
  socket.listen((chunk) {
    buffer.addAll(chunk);
    while (true) {
      final idx = buffer.indexOf(0);
      if (idx < 0) break;
      final msgBytes = buffer.sublist(0, idx);
      buffer.removeRange(0, idx + 1);
      received.add(
        jsonDecode(utf8.decode(msgBytes)) as Map<String, dynamic>,
      );
    }
  });
}

/// Polls [received] for the first frame matching [match], sleeping 50 ms
/// between checks so the real socket / WCP server has time to deliver frames.
/// This is a bounded condition-poll — [timeout] (default 10 s) is a hard
/// deadline, not a per-pump interval — throwing [TimeoutException] if no
/// matching frame arrives in time.
///
/// [tester] is accepted (and required) for call-site symmetry with the rest
/// of the WCP integration suite and to keep the option open for a future
/// `tester.pump()` if a caller's assertion ever needs it, but the current
/// implementation does not call it: real socket data arrives via the Dart
/// event loop's IO queue, independent of Flutter's frame-pump cycle, so
/// under `IntegrationTestWidgetsFlutterBinding`'s live engine the app
/// continues rendering frames on its own regardless of whether the test
/// explicitly pumps during this wait.
Future<Map<String, dynamic>> waitForFrame(
  List<Map<String, dynamic>> received,
  bool Function(Map<String, dynamic>) match, {
  required WidgetTester tester,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    for (final f in received) {
      if (match(f)) return f;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw TimeoutException(
    'no frame matching predicate within $timeout (have ${received.length}: '
    '${received.map((f) => f['type']).toList()})',
  );
}
