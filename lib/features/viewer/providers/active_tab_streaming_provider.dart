// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/streaming_source_provider.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

/// Root-scope mirror of the **active tab's** [streamingSourceProvider].
///
/// Streaming is per-tab state: `ViewerScreen` starts and stops it through the
/// active tab's container. The toolbar, however, is a sibling of `PaneHost` at
/// the root scope, so its own `ref.watch(streamingSourceProvider)` resolved the
/// *root* container — an instance nothing ever writes to. The LIVE badge and
/// Stop Streaming button were therefore dead in the multi-tab layout and only
/// worked in the empty-canvas branch, which wraps its column in the active
/// tab's scope.
///
/// This re-emits the active tab's state up to the root, exactly like
/// [ActiveTabActionFlags] does for the per-tab gating booleans. It carries the
/// full [StreamingViewerState] rather than a bool because the badge renders the
/// elapsed time; the `streamingActive` field on `ActionContext` selects the
/// bool off it, so a per-second elapsed tick does not churn the action context
/// and rebuild every surface.
final activeTabStreamingProvider =
    NotifierProvider<ActiveTabStreamingNotifier, StreamingViewerState>(
      ActiveTabStreamingNotifier.new,
    );

class ActiveTabStreamingNotifier extends Notifier<StreamingViewerState> {
  @override
  StreamingViewerState build() {
    final tabId = ref.watch(activeTabIdProvider);

    final ProviderContainer container;
    try {
      container = ref.watch(tabContainerManagerProvider).containerFor(tabId);
    } on Object {
      return const StreamingViewerIdle();
    }

    final sub = container.listen<StreamingViewerState>(
      streamingSourceProvider,
      (_, next) => state = next,
    );
    ref.onDispose(sub.close);

    return container.read(streamingSourceProvider);
  }
}
