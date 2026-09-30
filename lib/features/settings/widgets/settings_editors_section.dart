// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/models/app_settings.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Settings → Editors.
///
/// Dedicated section for external-editor integration: every Crux app
/// exposes an "Editors"
/// settings section, because editor configuration is cross-feature rather
/// than CXP-specific. WaveCrux's only editor setting today is the shell
/// command run for inbound CXP `request_open_source` messages
/// ([AppSettings.cxpEditorCommand]) — it previously lived inside the CXP
/// Cross-Probe section and moved here unchanged (same persisted key, same
/// notifier). If WaveCrux later grows LintCrux-style preset/args-template
/// editor config (`settings_editors_section.dart` there is the reference
/// shape), it belongs in this section.
class SettingsEditorsSection extends ConsumerStatefulWidget {
  /// Creates the Editors settings section for [settings].
  const SettingsEditorsSection({required this.settings, super.key});

  /// The current application settings snapshot the section renders.
  final AppSettings settings;

  @override
  ConsumerState<SettingsEditorsSection> createState() =>
      _SettingsEditorsSectionState();
}

class _SettingsEditorsSectionState
    extends ConsumerState<SettingsEditorsSection> {
  late final TextEditingController _editorController;

  @override
  void initState() {
    super.initState();
    _editorController = TextEditingController(
      text: widget.settings.cxpEditorCommand,
    );
  }

  @override
  void didUpdateWidget(covariant SettingsEditorsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The async appSettingsProvider load may resolve after this section has
    // already built once with the default `const AppSettings()`. Sync the
    // controller when the inbound settings change, but only when the user is
    // not editing — otherwise an in-flight load mid-edit would overwrite
    // their typing.
    if (_editorController.text != widget.settings.cxpEditorCommand &&
        oldWidget.settings.cxpEditorCommand !=
            widget.settings.cxpEditorCommand) {
      _editorController.text = widget.settings.cxpEditorCommand;
    }
  }

  @override
  void dispose() {
    _editorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final settingsNotifier = ref.read(appSettingsProvider.notifier);

    return CruxSettingsCard(
      children: [
        // Editor command label and its field are one logical row, so they
        // share a single card cell (no divider splitting label from input).
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.settingsEditorCommandLabel,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 2),
              Text(
                l10n.settingsEditorCommandDescription,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _editorController,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: l10n.settingsEditorCommandHint,
                ),
                onSubmitted: (value) {
                  unawaited(settingsNotifier.setCxpEditorCommand(value));
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
