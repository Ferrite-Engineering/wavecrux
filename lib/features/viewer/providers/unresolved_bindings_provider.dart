// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/services/session/binding_paths.dart';

/// The decoder and Stage bindings the last session restore or reload of this
/// tab could not find in the opened waveform, for `UnresolvedBindingsBanner`.
///
/// Written by `SessionNotifier` after it re-resolves bindings by their saved
/// hierarchical paths ([BindingPaths]); cleared when the user dismisses the
/// banner and whenever the tab opens or closes a waveform, so a notice never
/// outlives the file it describes. Per-tab: overridden in
/// `wavecruxTabOverrides`.
final unresolvedBindingsProvider =
    NotifierProvider<UnresolvedBindingsNotifier, List<UnresolvedBinding>>(
      UnresolvedBindingsNotifier.new,
    );

/// Notifier backing [unresolvedBindingsProvider].
class UnresolvedBindingsNotifier extends Notifier<List<UnresolvedBinding>> {
  @override
  List<UnresolvedBinding> build() => const [];

  /// Replaces the reported set with [unresolved] (one restore's findings).
  void report(List<UnresolvedBinding> unresolved) {
    state = List.unmodifiable(unresolved);
  }

  /// Clears the notice. A no-op when nothing is reported, so the many
  /// open-file paths that call it do not notify listeners for nothing.
  void clear() {
    if (state.isNotEmpty) state = const [];
  }
}
