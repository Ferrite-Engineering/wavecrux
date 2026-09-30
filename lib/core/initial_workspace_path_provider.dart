// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'initial_workspace_path_provider.g.dart';

/// Named-workspace file path provided via `--workspace` CLI argument on
/// startup, or via a bare positional `.wavecrux-workspace` argument.
///
/// Returns null when no workspace argument was given. Override this in
/// [ProviderScope] from `main()` to forward CLI args without platform-channel
/// calls. Consumed by `WaveCruxApp.initState`'s post-frame callback to
/// replace the current workspace with the loaded one.
@Riverpod(keepAlive: true)
String? initialWorkspacePath(Ref ref) => null;
