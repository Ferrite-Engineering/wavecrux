// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/features/annotations/annotation_clipboard.dart';
import 'package:wavecrux/features/annotations/providers/annotation_authoring_provider.dart';
import 'package:wavecrux/features/annotations/providers/session_annotations_provider.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import 'package:wavecrux/services/time_format/time_format_service.dart';

/// What Copy puts on the clipboard for the **active tab's** selected
/// annotation, or null when no annotation is selected there.
///
/// The selection is the one the Annotations panel row and the canvas balloon
/// already share ([annotationSelectedProvider]); the text is
/// [annotationClipboardText] of that annotation, so it carries the time and
/// signal the row shows above the note. The annotation is looked up in the
/// composed set the panel lists, so a colleague's note from a live session
/// copies as well as a local one.
///
/// Root-scope mirror, like `ActiveTabHasSelection`: the Edit menu and the
/// Ctrl+C binding sit above every tab's `ProviderContainer`, so this re-emits
/// the active tab's state at the root. Reads go through the resolved
/// `container`, not `ref`, so the per-tab scope-leak guard does not flag it.
final activeTabAnnotationCopyTextProvider =
    NotifierProvider<ActiveTabAnnotationCopyText, String?>(
      ActiveTabAnnotationCopyText.new,
    );

/// See [activeTabAnnotationCopyTextProvider].
class ActiveTabAnnotationCopyText extends Notifier<String?> {
  @override
  String? build() {
    final tabId = ref.watch(activeTabIdProvider);

    final ProviderContainer container;
    try {
      container = ref.watch(tabContainerManagerProvider).containerFor(tabId);
    } on Object {
      return null;
    }

    String? compute() {
      final id = container.read(annotationSelectedProvider);
      if (id == null) return null;
      final annotation = container
          .read(composedAnnotationsProvider)
          .where((a) => a.id == id)
          .firstOrNull;
      if (annotation == null) return null;
      final formatter = TimeFormatService(
        timescale: container.read(currentTimescaleProvider),
      );
      return annotationClipboardText([annotation], formatter);
    }

    // A tab-container provider can notify while a widget is mounting (a
    // widget that watches this provider flushes the tab's providers on its
    // first build), and Riverpod forbids writing a provider mid-build. Inside
    // the frame the write waits for its end; outside it stays synchronous.
    var pending = false;
    void update() {
      if (SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks) {
        if (pending) return;
        pending = true;
        SchedulerBinding.instance.addPostFrameCallback((_) {
          pending = false;
          if (ref.mounted) state = compute();
        });
        return;
      }
      state = compute();
    }

    final subs = <ProviderSubscription<Object?>>[
      container.listen<String?>(annotationSelectedProvider, (_, _) => update()),
      container.listen<List<Annotation>>(
        composedAnnotationsProvider,
        (_, _) => update(),
      ),
      container.listen<Timescale?>(
        currentTimescaleProvider,
        (_, _) => update(),
      ),
    ];
    for (final sub in subs) {
      ref.onDispose(sub.close);
    }

    return compute();
  }
}
