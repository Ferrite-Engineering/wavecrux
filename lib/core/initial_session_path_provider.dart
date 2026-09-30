// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'initial_session_path_provider.g.dart';

/// Session file path provided via `--session` CLI argument on startup.
///
/// Returns null when no `--session` flag was given. Override this in
/// [ProviderScope] from [main] to forward CLI args without platform-channel
/// calls.
@Riverpod(keepAlive: true)
String? initialSessionPath(Ref ref) => null;
