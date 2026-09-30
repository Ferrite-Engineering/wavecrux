// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/services/decoders/isa/instruction_set.dart';
import 'package:wavecrux/services/decoders/isa/isa_decoder_assets.dart';

/// Web build: there is no filesystem to scan, so there are no user tables.
///
/// Returns an empty result rather than reporting an issue. "You are running in
/// a browser" is not a load failure, and surfacing it as one would put a
/// permanent warning in front of every web user for a feature they cannot use.
Future<UserIsaTableLoadResult> loadUserIsaTables({
  required List<String> directories,
  Map<String, String>? environment,
}) async => const UserIsaTableLoadResult(
  sets: <String, InstructionSet>{},
  issues: <IsaTableLoadIssue>[],
  scannedDirectories: <String>[],
);
