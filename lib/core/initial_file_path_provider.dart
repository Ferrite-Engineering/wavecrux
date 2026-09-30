// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'initial_file_path_provider.g.dart';

/// File path provided as a CLI argument on startup (`wavecrux dump.fst`).
///
/// Returns null when no file was given. Override this in [ProviderScope] from
/// [main] to forward CLI args without platform-channel calls.
@Riverpod(keepAlive: true)
String? initialFilePath(Ref ref) => null;
