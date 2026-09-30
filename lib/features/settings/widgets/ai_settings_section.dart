// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_license/crux_license.dart';
import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/providers/ai_key_store_provider.dart';
import 'package:wavecrux/domain/enums/ai_provider.dart';
import 'package:wavecrux/domain/models/app_settings.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/widgets/experimental_chip.dart';

/// Settings → AI Assistant section: the bring-your-own-key configuration
/// surface for the **Experimental** AI Waveform Assistant.
///
/// Visibility is layered:
/// - The hosting category is offered only when the `kAiExperimental` build flag
///   is on (`aiExperimentalBuildFlagProvider`) — a normal beta build shows no
///   AI section at all.
/// - Within the section, the "Enable experimental AI features" toggle is always
///   shown (it is the control to opt in). Everything below it — provider,
///   endpoint, API key, and the "no model configured" empty state — appears
///   only when `aiExperimentalEnabledProvider` is `true` (build flag AND the
///   user toggle).
///
/// The API **key** is read/written through `AiKeyStore` (platform secure
/// storage), never `AppSettings`/`shared_preferences` and never logged. The
/// non-secret provider and endpoint live in `AppSettings`.
class AiSettingsSection extends ConsumerStatefulWidget {
  /// Creates the AI settings section.
  const AiSettingsSection({super.key});

  @override
  ConsumerState<AiSettingsSection> createState() => _AiSettingsSectionState();
}

class _AiSettingsSectionState extends ConsumerState<AiSettingsSection> {
  final _keyController = TextEditingController();
  final _endpointController = TextEditingController();
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _keyController.addListener(_onKeyChanged);
    final settings = ref.read(appSettingsProvider).value ?? const AppSettings();
    _endpointController.text = settings.aiEndpoint;
    unawaited(_loadKey(settings.aiProvider));
  }

  @override
  void dispose() {
    _keyController
      ..removeListener(_onKeyChanged)
      ..dispose();
    _endpointController.dispose();
    super.dispose();
  }

  void _onKeyChanged() {
    // The empty-state card keys off whether a key is present, so a keystroke
    // must rebuild. Persisting the secret is handled in the field's onChanged.
    setState(() {});
  }

  Future<void> _loadKey(AiProvider provider) async {
    final key = await ref.read(aiKeyStoreProvider).readKey(provider);
    if (!mounted) return;
    _keyController.text = key ?? '';
  }

  Future<void> _writeKey(AiProvider provider, String key) =>
      ref.read(aiKeyStoreProvider).writeKey(provider, key);

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final notifier = ref.read(appSettingsProvider.notifier);
    final settings =
        ref.watch(appSettingsProvider).value ?? const AppSettings();
    final enabled = ref.watch(aiExperimentalEnabledProvider);

    return CruxSettingsCard(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  l10n.settingsAiSection,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: 8),
              const ExperimentalChip(),
            ],
          ),
        ),
        SwitchListTile(
          key: const Key('settingsAiExperimentalToggle'),
          title: Text(l10n.settingsAiExperimentalLabel),
          subtitle: Text(l10n.settingsAiExperimentalDescription),
          value: settings.aiExperimentalEnabled,
          onChanged: (v) =>
              unawaited(notifier.setAiExperimentalEnabled(enabled: v)),
        ),
        if (enabled) ..._config(context, l10n, notifier, settings),
      ],
    );
  }

  List<Widget> _config(
    BuildContext context,
    L10N l10n,
    AppSettingsNotifier notifier,
    AppSettings settings,
  ) {
    final provider = settings.aiProvider;
    final keyMissing = _keyController.text.isEmpty && !provider.isLocal;

    return [
      const Divider(height: 1),
      ListTile(
        title: Text(l10n.settingsAiProviderLabel),
        trailing: DropdownButton<AiProvider>(
          key: const Key('settingsAiProviderDropdown'),
          value: provider,
          items: [
            for (final p in AiProvider.values)
              DropdownMenuItem(value: p, child: Text(_providerLabel(p, l10n))),
          ],
          onChanged: (p) {
            if (p == null) return;
            unawaited(notifier.setAiProvider(p));
            unawaited(_loadKey(p));
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: TextField(
          key: const Key('settingsAiEndpointField'),
          controller: _endpointController,
          decoration: InputDecoration(
            labelText: l10n.settingsAiEndpointLabel,
            hintText: provider.defaultEndpoint.isEmpty
                ? l10n.settingsAiEndpointHint
                : provider.defaultEndpoint,
          ),
          onChanged: (v) => unawaited(notifier.setAiEndpoint(v)),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: TextField(
          key: const Key('settingsAiApiKeyField'),
          controller: _keyController,
          obscureText: _obscureKey,
          decoration: InputDecoration(
            labelText: l10n.settingsAiApiKeyLabel,
            helperText: l10n.settingsAiApiKeyHint,
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: _obscureKey
                      ? l10n.settingsAiApiKeyShowTooltip
                      : l10n.settingsAiApiKeyHideTooltip,
                  icon: Icon(
                    _obscureKey ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() => _obscureKey = !_obscureKey),
                ),
                IconButton(
                  key: const Key('settingsAiApiKeyClear'),
                  tooltip: l10n.settingsAiApiKeyClearTooltip,
                  icon: const Icon(Icons.clear),
                  onPressed: _keyController.text.isEmpty
                      ? null
                      : () {
                          _keyController.clear();
                          unawaited(_writeKey(provider, ''));
                        },
                ),
              ],
            ),
          ),
          onChanged: (v) => unawaited(_writeKey(provider, v)),
        ),
      ),
      if (keyMissing)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: _NoModelEmptyState(
            title: l10n.settingsAiNoModelTitle,
            body: l10n.settingsAiNoModelBody,
          ),
        ),
    ];
  }

  String _providerLabel(AiProvider provider, L10N l10n) => switch (provider) {
    AiProvider.anthropic => l10n.aiProviderAnthropic,
    AiProvider.openai => l10n.aiProviderOpenai,
    AiProvider.google => l10n.aiProviderGoogle,
    AiProvider.ollama => l10n.aiProviderOllama,
  };
}

/// The "no model configured" empty state shown when a cloud provider is
/// selected but no API key has been entered.
class _NoModelEmptyState extends StatelessWidget {
  const _NoModelEmptyState({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('settingsAiNoModelEmptyState'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.key_off_outlined,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(body, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
