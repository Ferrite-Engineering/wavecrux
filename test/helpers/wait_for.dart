// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Shared bounded condition-poll helper for VM unit tests.
//
// A fixed `Future<void>.delayed(...)` after a fire-and-forget action is a
// raced guess: too short and the test flakes under load, too long and
// every run pays the full wait regardless of how fast the condition
// actually became true. A bounded poll returns the instant the real
// observable (a received-messages list, a server's `connectedPeers`, a
// discovery event) is true, and fails loudly with [reason] at the
// timeout instead of letting a downstream assertion fail mysteriously.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Polls [condition] every [interval] until it returns true, failing the
/// test with [reason] if [timeout] elapses first.
///
/// [condition] may be synchronous or async. Prefer polling the ACTUAL
/// observable the code under test mutates (a received-messages list, a
/// server's `connectedPeers`, an event flag) over any proxy.
Future<void> waitFor(
  FutureOr<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  Duration interval = const Duration(milliseconds: 10),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    if (await Future<bool>.sync(condition)) return;
    if (DateTime.now().isAfter(deadline)) {
      fail(
        'waitFor: condition not met within $timeout'
        '${reason == null ? '' : ' — $reason'}',
      );
    }
    await Future<void>.delayed(interval);
  }
}
