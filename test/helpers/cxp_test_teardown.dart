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

import 'dart:io';

import 'package:crux_cxp_ui/crux_cxp_ui.dart';
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
/// The caller awaits the node's owners first (see [disposeCxpContainer]);
/// `CxpDiscovery.stop` awaits its in-flight scan, so no handle into [dir]
/// remains and the delete runs once. A directory that is already gone is not
/// an error.
Future<void> deleteCxpTempDirectory(Directory dir) async {
  if (dir.existsSync()) {
    dir.deleteSync(recursive: true);
  }
}
