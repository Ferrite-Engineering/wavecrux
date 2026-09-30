// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/settings/providers/user_isa_tables_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Settings panel for bring-your-own-ISA encoding tables.
///
/// This is the feature's front door. Until it existed the only way to consume
/// a hand-authored table was to build WaveCrux from source, while the docs told
/// readers to "point WaveCrux at a TOML encoding table" — a capability promised
/// in prose with nothing behind it.
///
/// It shows the scan result rather than only the configuration, because the
/// question an author has is never "what did I type into settings", it is "did
/// my table load, and if not, why not". A directory list alone answers neither.
class IsaTablesPanel extends ConsumerWidget {
  /// Creates the panel.
  const IsaTablesPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    // No filesystem to scan in a browser, so the panel would be a control that
    // cannot do anything. Hidden rather than disabled.
    if (kIsWeb) return const SizedBox.shrink();

    final settings = ref.watch(appSettingsProvider).value;
    final directories = settings?.isaTableDirectories ?? const <String>[];
    final scan = ref.watch(userIsaTablesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.isaTablesTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          l10n.isaTablesDescription,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        if (directories.isEmpty)
          Text(
            l10n.isaTablesNoDirectories,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          )
        else ...[
          Text(
            l10n.isaTablesDirectoriesHeader,
            style: theme.textTheme.labelMedium,
          ),
          const SizedBox(height: 4),
          for (final dir in directories)
            _DirectoryRow(path: dir, onRemove: () => _remove(ref, dir)),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton.icon(
              icon: const Icon(Icons.create_new_folder_outlined, size: 18),
              label: Text(l10n.isaTablesAddDirectory),
              onPressed: () => _addDirectory(ref),
            ),
            const Spacer(),
            scan.when(
              data: (result) => Text(
                l10n.isaTablesLoadedCount(result.sets.length),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              error: (_, _) => const SizedBox.shrink(),
              loading: () => const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ],
        ),
        // A table that failed to parse is the case this panel exists for. The
        // message names the file and the offending key, so it is shown in full
        // rather than reduced to a count.
        ...?scan.value?.issues.isEmpty ?? true
            ? null
            : <Widget>[
                const SizedBox(height: 8),
                Text(
                  l10n.isaTablesIssuesHeader,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 4),
                for (final issue in scan.value!.issues)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      issue.message,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
              ],
        if (directories.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            l10n.isaTablesRestartNote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _addDirectory(WidgetRef ref) async {
    if (kIsWeb) return;
    final picked = await FilePicker.getDirectoryPath();
    if (picked == null || picked.isEmpty) return;
    await ref.read(appSettingsProvider.notifier).addIsaTableDirectory(picked);
    ref.invalidate(userIsaTablesProvider);
  }

  Future<void> _remove(WidgetRef ref, String path) async {
    await ref.read(appSettingsProvider.notifier).removeIsaTableDirectory(path);
    ref.invalidate(userIsaTablesProvider);
  }
}

class _DirectoryRow extends StatelessWidget {
  const _DirectoryRow({required this.path, required this.onRemove});

  final String path;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            Icons.folder,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              path,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: l10n.isaTablesRemoveDirectory,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
