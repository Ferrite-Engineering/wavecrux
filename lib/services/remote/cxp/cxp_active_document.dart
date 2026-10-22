// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_cxp_ui/crux_cxp_ui.dart' show cruxCxpRuntimeProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';

/// The file the active tab shows, as other suite apps are told it: the
/// waveform's path, or the session file's for a tab restored from one, or
/// null with no tab open. The runtime reduces it to its last path component
/// before it leaves the process (CXP §8.1: display only, never a directory).
final Provider<String?> cxpActiveDocumentProvider = Provider<String?>((ref) {
  final activeId = ref.watch(activeTabIdProvider);
  for (final tab in ref.watch(tabListProvider)) {
    if (tab.id != activeId) continue;
    return tab.filePath ?? tab.sessionFilePath;
  }
  return null;
}, name: 'cxpActiveDocumentProvider');

/// Keeps the shared CXP runtime's announced active document
/// ([CruxCxpRuntime.setActiveDocument]) on the active tab's file, so a peer's
/// "Cross-probe to" menu names the waveform this window shows.
///
/// Read once at launch, beside the selection emitter: it is never rebuilt,
/// and it republishes when either the document or the runtime changes. A
/// runtime that the settings restart starts with no document, so a new
/// runtime is told the current one at once.
///
/// The subscriptions are the container's, not this provider's own `ref`
/// ones. Nothing listens to this provider, so Riverpod pauses it, and a
/// paused provider's subscriptions to a derived provider such as
/// [cxpActiveDocumentProvider] are never flushed: the document would be
/// published once and never again.
final Provider<void> cxpActiveDocumentPublisherProvider = Provider<void>((
  ref,
) {
  final container = ref.container;
  void publish() {
    final runtime = container.read(cruxCxpRuntimeProvider).value;
    if (runtime == null) return;
    unawaited(
      runtime.setActiveDocument(container.read(cxpActiveDocumentProvider)),
    );
  }

  final document = container.listen<String?>(
    cxpActiveDocumentProvider,
    (_, _) => publish(),
  );
  final runtime = container.listen(
    cruxCxpRuntimeProvider,
    (_, _) => publish(),
  );
  ref.onDispose(() {
    document.close();
    runtime.close();
  });
  publish();
}, name: 'cxpActiveDocumentPublisherProvider');
