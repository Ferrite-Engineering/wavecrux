// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Teardown for tests that run a CXP node over a temporary manifest directory.
//
// Windows refuses to delete a directory while any handle into it is open. A
// CXP node holds several for as long as it runs (the discovery scan lists the
// directory and reads each manifest, the manifest writer's heartbeat rewrites
// its file), so a teardown that deletes the directory before the node has
// fully stopped fails there with `PathAccessException` and passes everywhere
// else.

import 'dart:async';
import 'dart:io';

import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stops the shared CXP runtime in [container], then disposes the container.
///
/// The runtime provider stops its runtime from `onDispose` without waiting for
/// it, so disposing the container alone returns while the socket, the
/// manifest and the discovery scan are still shutting down. Awaiting
/// `dispose()` on the runtime first guarantees the server is closed and the
/// manifest removed before the caller touches the directory. A container whose
/// runtime provider was never read has nothing to stop and starting one just to
/// stop it is avoided.
Future<void> disposeCxpContainer(ProviderContainer container) async {
  if (container.exists(cruxCxpRuntimeProvider)) {
    try {
      final runtime = await container.read(cruxCxpRuntimeProvider.future);
      await runtime?.dispose();
    } on Object {
      // A runtime that failed to start has nothing to wait for.
    }
  }
  container.dispose();
}

/// Deletes the temporary directory [dir] after a CXP node has stopped.
///
/// The node's owners are awaited by the caller (see [disposeCxpContainer]),
/// but one thing cannot be: a discovery scan already in flight when the node
/// stops keeps its directory listing or manifest read open until that read
/// returns, and `CxpDiscovery.stop` does not wait for it. On Windows that
/// leaves a window of a few milliseconds in which the delete is refused. So on
/// Windows, and only there, a refused delete is retried with a growing delay;
/// every other platform deletes once and fails on the first error, and a
/// directory that is still locked after the last attempt rethrows the original
/// error rather than hiding it.
///
/// [delete], [isWindows] and [delays] exist so the retry policy is tested on
/// every platform.
Future<void> deleteCxpTempDirectory(
  Directory dir, {
  @visibleForTesting FutureOr<void> Function(Directory dir)? delete,
  @visibleForTesting bool? isWindows,
  @visibleForTesting
  List<Duration> delays = const <Duration>[
    Duration(milliseconds: 25),
    Duration(milliseconds: 50),
    Duration(milliseconds: 100),
    Duration(milliseconds: 200),
    Duration(milliseconds: 400),
    Duration(milliseconds: 800),
    Duration(milliseconds: 1600),
  ],
}) async {
  Future<void> attempt() async {
    if (delete != null) {
      await delete(dir);
    } else if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  }

  final retry = isWindows ?? Platform.isWindows;
  var tries = 0;
  while (true) {
    try {
      await attempt();
      return;
    } on FileSystemException {
      if (!retry || tries >= delays.length) rethrow;
      await Future<void>.delayed(delays[tries++]);
    }
  }
}
