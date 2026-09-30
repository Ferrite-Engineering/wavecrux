// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'initial_additional_file_paths_provider.g.dart';

/// Additional waveform file paths to open as extra tabs on startup.
///
/// Set when the user passes two or more files on the CLI:
///   `wavecrux a.fst b.vcd c.ghw`
///
/// The first file goes to [initialFilePathProvider]; the remaining files
/// are listed here and opened as separate tabs in [WaveCruxApp.initState].
///
/// Default is the empty list (no additional files).
@Riverpod(keepAlive: true)
List<String> initialAdditionalFilePaths(Ref ref) => const [];
