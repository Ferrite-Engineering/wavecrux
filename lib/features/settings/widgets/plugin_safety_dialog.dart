// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wavecrux/core/help_urls.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// One-time safety acknowledgment shown the first time the user opens
/// the Settings → Decoders → Plugins panel before any plugin discovery
/// has happened.
///
/// Plugins run as native code with the same privileges as the host
/// process — they can read any file the user can, open network
/// connections, and call any OS API. This dialog explains that in plain
/// language and offers two outcomes:
///
///   1. **I understand, continue** — sets
///      `AppSettings.pluginSafetyAcknowledged` to `true` and closes the
///      dialog. The Settings panel then reveals plugins (or prompts for
///      a directory if none are configured).
///   2. **Disable plugin loading** — flips
///      `AppSettings.pluginLoadingDisabled` to `true`, leaves the
///      acknowledgment flag at `false`, and closes the dialog. The
///      loader's `scan()` short-circuits to an empty list and the
///      Settings panel surfaces a banner inviting the user to opt in
///      later.
///
/// **Bypass for Enterprise plugin governance.** When
/// the closed-source Pro overlay layers Enterprise plugin
/// governance on top of the loader, this acknowledgment should be
/// short-circuited because the organization's signing/policy layer
/// already controls which plugins may load. The hook for that bypass is
/// the optional `enterpriseGovernanceBypass` constructor argument: when
/// provided and `true`, the dialog auto-acknowledges synchronously
/// without rendering. The Enterprise feature gate wires this.
class PluginSafetyDialog extends ConsumerWidget {
  const PluginSafetyDialog({
    super.key,
    this.enterpriseGovernanceBypass = false,
  });

  /// Set by the Enterprise overlay to skip the dialog when
  /// the organization's plugin-governance policy already controls
  /// load decisions. Defaults to `false` so open-core builds always
  /// show the dialog.
  final bool enterpriseGovernanceBypass;

  /// Shows the dialog and returns whether the user acknowledged.
  ///
  /// `true` — user clicked "I understand, continue".
  /// `false` — user clicked "Disable plugin loading" or dismissed the
  /// dialog.
  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PluginSafetyDialog(),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (enterpriseGovernanceBypass) {
      // Enterprise bypass — acknowledge synchronously and pop next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await ref
            .read(appSettingsProvider.notifier)
            .setPluginSafetyAcknowledged(acknowledged: true);
        if (context.mounted) Navigator.of(context).pop(true);
      });
      return const SizedBox.shrink();
    }

    final l10n = L10N.of(context);
    final theme = Theme.of(context);

    return AlertDialog(
      icon: Icon(
        Icons.warning_amber_rounded,
        color: theme.colorScheme.error,
        size: 32,
      ),
      title: Text(l10n.pluginSafetyDialogTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.pluginSafetyDialogBody),
            const SizedBox(height: 12),
            Text(
              l10n.pluginSafetyDialogBullets,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: () =>
                  launchUrl(Uri.parse(HelpUrls.decoderPluginsSecurity)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.open_in_new,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l10n.pluginSafetyDialogLearnMore,
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await ref
                .read(appSettingsProvider.notifier)
                .setPluginLoadingDisabled(disabled: true);
            if (context.mounted) Navigator.of(context).pop(false);
          },
          child: Text(l10n.pluginSafetyDialogDisable),
        ),
        FilledButton(
          onPressed: () async {
            await ref
                .read(appSettingsProvider.notifier)
                .setPluginSafetyAcknowledged(acknowledged: true);
            if (context.mounted) Navigator.of(context).pop(true);
          },
          child: Text(l10n.pluginSafetyDialogContinue),
        ),
      ],
    );
  }
}
