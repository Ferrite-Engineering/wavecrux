// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/features/comparison/providers/diff_provider.dart';
import 'package:wavecrux/features/comparison/widgets/diff_toolbar.dart';
import 'package:wavecrux/features/viewer/providers/pattern_search_provider.dart';
import 'package:wavecrux/features/viewer/widgets/pattern_search_toolbar.dart';

part 'active_toolbar_height_provider.g.dart';

/// Total pixel height of all toolbars currently rendered above the waveform
/// canvas ([DiffToolbar] and [PatternSearchToolbar]).
///
/// [ValueColumnPanel] adds this to its `timeRulerHeight` spacer so that its
/// value rows remain vertically aligned with the canvas lanes whenever any
/// toolbar is visible.  Returns `0.0` when no toolbar is active.
@riverpod
double activeToolbarHeight(Ref ref) {
  var total = 0.0;

  final diffActive = ref.watch(
    diffProvider.select((s) => s.isActive),
  );
  if (diffActive) total += DiffToolbar.height;

  final search = ref.watch(patternSearchProvider);
  final patternVisible =
      search.hasResult || search.isSearching || search.error != null;
  if (patternVisible) total += PatternSearchToolbar.height;

  return total;
}
