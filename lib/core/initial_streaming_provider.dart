// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'initial_streaming_provider.g.dart';

/// Whether `--interactive` or `--stdin` was passed as a CLI argument.
///
/// When true, [ViewerScreen] will automatically start reading VCD data from
/// stdin via [StreamingSourceNotifier.startFromStdin].
///
/// Override in [ProviderScope] from [main] to forward the CLI flag without
/// platform-channel calls.
@Riverpod(keepAlive: true)
bool initialStdinMode(Ref ref) => false;

/// Named-pipe path provided via `--pipe <path>` on startup.
///
/// When non-null, [ViewerScreen] will automatically start reading VCD data
/// from the named pipe at this path via [StreamingSourceNotifier.startFromPipe].
///
/// Override in [ProviderScope] from [main] to forward the CLI argument without
/// platform-channel calls.
@Riverpod(keepAlive: true)
String? initialPipePath(Ref ref) => null;
