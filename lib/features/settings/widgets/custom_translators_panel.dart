// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/models/custom_translator_def.dart';
import 'package:wavecrux/features/settings/providers/custom_translators_provider.dart';
import 'package:wavecrux/features/settings/widgets/custom_translator_editor_dialog.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Settings panel that lists user-authored declarative bit-field translators
/// and lets the user add / edit / delete them. Mirrors the structure of the
/// Stage Custom Widgets panel. Pure Dart — runs identically on every platform
/// including web.
class CustomTranslatorsPanel extends ConsumerWidget {
  const CustomTranslatorsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final translators = ref.watch(customTranslatorsProvider);
    final notifier = ref.read(customTranslatorsProvider.notifier);

    return Padding(
      // Aligns with the 16 dp ListTile inset of the surrounding settings card
      // so the description and button line up with the tile rows, matching the
      // other settings sections (e.g. ColorThemeSection).
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.customTranslatorsPanelDescription,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (translators.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                l10n.customTranslatorsEmpty,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final def in translators)
              _TranslatorTile(
                def: def,
                onEdit: () => _edit(context, ref, notifier, def),
                onDelete: () => notifier.remove(def.name),
              ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: () => _edit(context, ref, notifier, null),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.customTranslatorsAdd),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    CustomTranslators notifier,
    CustomTranslatorDef? existing,
  ) async {
    final result = await CustomTranslatorEditorDialog.show(
      context,
      initial: existing,
    );
    if (result == null) return;
    if (existing != null && existing.name != result.name) {
      notifier.rename(existing.name, result);
    } else {
      notifier.upsert(result);
    }
  }
}

class _TranslatorTile extends StatelessWidget {
  const _TranslatorTile({
    required this.def,
    required this.onEdit,
    required this.onDelete,
  });

  final CustomTranslatorDef def;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(def.name),
      subtitle: Text(l10n.customTranslatorFieldCount(def.config.fields.length)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: l10n.customTranslatorEditTitle,
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: onEdit,
          ),
          IconButton(
            tooltip: l10n.customTranslatorDelete,
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
