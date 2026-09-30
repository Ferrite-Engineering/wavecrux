// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/models/pane_id.dart';

part 'pane_id_provider.g.dart';

/// Sentinel provider that identifies the owning pane of the nearest
/// [UncontrolledProviderScope].
///
/// This provider has **no default**. Reading it outside a pane-scoped
/// [ProviderContainer] is a programming error and throws [UnimplementedError].
///
/// Every pane container overrides this with its own [PaneId]:
/// ```dart
/// ProviderContainer(
///   parent: rootContainer,
///   overrides: [paneIdProvider.overrideWithValue(id)],
/// );
/// ```
///
/// Per ARCHITECTURE.md §6.4 (per-pane ProviderScope architecture).
@Riverpod(keepAlive: true)
// ignore: avoid_unused_parameters, riverpod_annotation requires a named ref parameter
PaneId paneId(Ref ref) {
  throw UnimplementedError(
    'paneIdProvider must be overridden in a per-pane ProviderContainer. '
    'Do not read paneIdProvider from the root scope.',
  );
}
