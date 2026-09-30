// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/services/decoders/isa/isa_decoder_assets.dart';
import 'package:wavecrux/services/decoders/isa/user_isa_tables.dart';

part 'user_isa_tables_provider.g.dart';

/// Scans the configured ISA table directories and reports what was found.
///
/// Deliberately a *live* scan rather than a read of the boot-time load. The
/// author's loop is edit table → check Settings, and a boot-time snapshot would
/// answer with what was true before they made the change — which reads exactly
/// like the fix not working. Re-reading a handful of small files is cheap
/// enough that being current is worth more than being cached.
///
/// The decoder still composes at launch, which is why the panel carries a
/// restart note: this provider tells you whether the table *parses*, not
/// whether the running decoder has it yet.
@riverpod
Future<UserIsaTableLoadResult> userIsaTables(Ref ref) async {
  if (kIsWeb) {
    return const UserIsaTableLoadResult(
      sets: {},
      issues: [],
      scannedDirectories: [],
    );
  }
  final settings = await ref.watch(appSettingsProvider.future);
  return loadUserIsaTables(directories: settings.isaTableDirectories);
}
