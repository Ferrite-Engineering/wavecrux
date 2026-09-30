// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:url_launcher/url_launcher.dart';
import 'package:wavecrux/core/help_urls.dart';
import 'package:wavecrux/core/mobile_metrics.dart';
import 'package:wavecrux/core/platform_utils.dart';
import 'package:wavecrux/domain/models/app_settings.dart';
import 'package:wavecrux/domain/models/decoder_plugin/decoder_plugin_info.dart';
import 'package:wavecrux/domain/models/decoder_plugin/decoder_plugin_load_status.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/settings/widgets/plugin_safety_dialog.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/decoders/ffi/ffi_decoder_loader_provider.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

/// Test seam — overridden by tests that don't have `path_provider`'s
/// platform channel registered or that want to inject a deterministic
/// path. Production callers leave it at the default which forwards to
/// [path_provider.getApplicationSupportDirectory].
@visibleForTesting
Future<Directory?> Function() decoderPluginsAppSupportDirectory =
    _defaultAppSupportDirectory;

Future<Directory?> _defaultAppSupportDirectory() async {
  try {
    return await path_provider.getApplicationSupportDirectory();
  } on Object {
    return null;
  }
}

/// Test seam — overridden by tests that want to assert the directory
/// reveal action without launching a real `file://` URL.
@visibleForTesting
Future<bool> Function(Uri uri) decoderPluginsLaunchUrl = launchUrl;

/// Settings → Decoders → Plugins panel.
///
/// Surfaces the list of decoder plugins discovered by
/// [decoderPluginListProvider] with one row per plugin showing its
/// id, file path, declared ABI version, load status, and a per-plugin
/// disable toggle. Above the list, "Add directory" / "Open plugin
/// directory" / "Reload plugins" controls let the user manage the
/// directory list and re-run discovery without restarting the app.
///
/// Desktop only — the conditional FFI loader is a no-op on iOS,
/// Android, and Web. The panel is platform-only-gated by its caller in
/// [SettingsScreen]; if mounted on a non-desktop host it still renders
/// safely (the empty/disabled banner reflects the underlying loader's
/// no-op stub).
///
/// Per the WaveCrux mobile UI standards (ARCHITECTURE.md §3.1.8) we
/// still apply touch-aware sizing because the iPad-Pro-in-Stage-Manager
/// case classifies as desktop-class but runs on a mobile host with no
/// mouse — the same metric source ensures consistent hit areas.
class DecoderPluginsPanel extends ConsumerWidget {
  const DecoderPluginsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final settings =
        ref.watch(appSettingsProvider).value ?? const AppSettings();
    final pluginsAsync = ref.watch(decoderPluginListProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!settings.pluginSafetyAcknowledged &&
              !settings.pluginLoadingDisabled)
            const _AcknowledgmentBanner(),
          if (settings.pluginLoadingDisabled)
            const _PluginLoadingDisabledBanner(),
          const SizedBox(height: 8),
          Text(
            l10n.decoderPluginsPanelDescription,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          const _ActionRow(),
          const SizedBox(height: 12),
          _DirectoriesSection(directories: settings.userPluginDirectories),
          const SizedBox(height: 16),
          Text(
            l10n.decoderPluginsListHeader,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          pluginsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => _ErrorState(
              message: l10n.decoderPluginsLoadFailed(e.toString()),
            ),
            data: (plugins) {
              if (plugins.isEmpty) {
                final emptyMessage = settings.pluginLoadingDisabled
                    ? l10n.decoderPluginsEmptyDisabled
                    : !settings.pluginSafetyAcknowledged
                    ? l10n.decoderPluginsEmptyNeedsAck
                    : l10n.decoderPluginsEmptyNoPlugins;
                return CruxPanelEmptyState(message: emptyMessage);
              }
              return Column(
                children: [
                  for (final p in plugins)
                    _PluginRow(
                      info: p,
                      disabled: settings.perPluginDisabled[p.pluginId] ?? false,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Acknowledgment banner ────────────────────────────────────────────────────

class _AcknowledgmentBanner extends ConsumerWidget {
  const _AcknowledgmentBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        // Wrap (instead of Row) so the icon + body + action button stack
        // vertically on narrow viewports — e.g. SettingsScreen.openAdaptive
        // at 500×500 the Row form overflows by ~30 px once the FilledButton's
        // intrinsic width and the long description text compete for the
        // ~400 px available content area.
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: theme.colorScheme.onErrorContainer,
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                l10n.decoderPluginsBannerNeedsAck,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
            FilledButton(
              onPressed: () async {
                final ok = await PluginSafetyDialog.show(context);
                if (!context.mounted) return;
                if (ok) {
                  await ref.read(decoderPluginListProvider.notifier).refresh();
                }
              },
              child: Text(l10n.decoderPluginsBannerReview),
            ),
          ],
        ),
      ),
    );
  }
}

class _PluginLoadingDisabledBanner extends ConsumerWidget {
  const _PluginLoadingDisabledBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.block, color: theme.colorScheme.onSurface),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.decoderPluginsBannerDisabled,
                style: TextStyle(color: theme.colorScheme.onSurface),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () async {
                await ref
                    .read(appSettingsProvider.notifier)
                    .setPluginLoadingDisabled(disabled: false);
                if (!context.mounted) return;
                await ref.read(decoderPluginListProvider.notifier).refresh();
              },
              child: Text(l10n.decoderPluginsBannerEnable),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Action row ───────────────────────────────────────────────────────────────

class _ActionRow extends ConsumerWidget {
  const _ActionRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final settings =
        ref.watch(appSettingsProvider).value ?? const AppSettings();
    final canDisable =
        settings.pluginSafetyAcknowledged && !settings.pluginLoadingDisabled;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.create_new_folder_outlined, size: 18),
          label: Text(l10n.decoderPluginsAddDirectory),
          onPressed: () => _addDirectory(context, ref),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.folder_open, size: 18),
          label: Text(l10n.decoderPluginsOpenDirectory),
          onPressed: () => _openDefaultDirectory(context, ref),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(l10n.decoderPluginsReload),
          onPressed: () =>
              ref.read(decoderPluginListProvider.notifier).refresh(),
        ),
        if (canDisable)
          TextButton.icon(
            icon: const Icon(Icons.block, size: 18),
            label: Text(l10n.decoderPluginsDisable),
            onPressed: () => ref
                .read(appSettingsProvider.notifier)
                .setPluginLoadingDisabled(disabled: true),
          ),
        TextButton.icon(
          icon: const Icon(Icons.help_outline, size: 18),
          label: Text(l10n.decoderPluginsLearnMore),
          onPressed: () => decoderPluginsLaunchUrl(
            Uri.parse(HelpUrls.decoderPluginsInstall),
          ),
        ),
      ],
    );
  }

  Future<void> _addDirectory(BuildContext context, WidgetRef ref) async {
    if (kIsWeb) return;
    final picked = await FilePicker.getDirectoryPath();
    if (picked == null || picked.isEmpty) return;
    await ref.read(appSettingsProvider.notifier).addUserPluginDirectory(picked);
    await ref.read(decoderPluginListProvider.notifier).refresh();
  }

  Future<void> _openDefaultDirectory(
    BuildContext context,
    WidgetRef ref,
  ) async {
    if (kIsWeb || !isDesktopPlatform) return;
    final l10n = L10N.of(context);
    final path = await _resolveDefaultDirectoryPath();
    if (path == null) {
      if (context.mounted) {
        showCruxErrorSnack(context, l10n.decoderPluginsOpenDirectoryFailed);
      }
      return;
    }
    final dir = Directory(path);
    try {
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      await decoderPluginsLaunchUrl(Uri.directory(path));
    } on Object catch (e) {
      if (context.mounted) {
        showCruxErrorSnack(
          context,
          l10n.decoderPluginsOpenDirectoryError(e.toString()),
        );
      }
    }
  }

  Future<String?> _resolveDefaultDirectoryPath() async {
    final dir = await decoderPluginsAppSupportDirectory();
    if (dir == null) return null;
    if (Platform.isWindows) return '${dir.path}\\WaveCrux\\decoders';
    return '${dir.path}/wavecrux/decoders';
  }
}

// ── Directories section ──────────────────────────────────────────────────────

class _DirectoriesSection extends ConsumerWidget {
  const _DirectoriesSection({required this.directories});

  final List<String> directories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);

    if (directories.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          l10n.decoderPluginsNoUserDirectories,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.decoderPluginsUserDirectoriesHeader,
          style: theme.textTheme.labelMedium,
        ),
        const SizedBox(height: 4),
        for (final dir in directories)
          Padding(
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
                    dir,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: l10n.decoderPluginsRemoveDirectory,
                  onPressed: () async {
                    await ref
                        .read(appSettingsProvider.notifier)
                        .removeUserPluginDirectory(dir);
                    await ref
                        .read(decoderPluginListProvider.notifier)
                        .refresh();
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ── Plugin row ───────────────────────────────────────────────────────────────

class _PluginRow extends ConsumerWidget {
  const _PluginRow({required this.info, required this.disabled});

  final DecoderPluginInfo info;
  final bool disabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final deviceClass = ref.watch(deviceClassProvider);
    final metrics = MobileMetrics.of(context, deviceClass);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.displayName,
                    style: theme.textTheme.titleSmall,
                  ),
                  if (info.pluginDescription != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      info.pluginDescription!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    info.filePath,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 6),
                  _StatusChip(
                    status: info.loadStatus,
                    abiVersion: info.declaredAbiVersion,
                  ),
                  if (info.loadStatus == DecoderPluginLoadStatus.loaded &&
                      info.registeredDecoderIds.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      l10n.decoderPluginsDecoderCount(
                        info.registeredDecoderIds.length,
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  // A policy refusal has to say that it IS one, and that this
                  // panel cannot undo it. A user who reads "Not approved"
                  // beside a switch reaches for the switch; the sentence is
                  // what stops that becoming a support ticket ending in "you
                  // cannot".
                  if (info.loadStatus ==
                      DecoderPluginLoadStatus.notAllowlisted) ...[
                    const SizedBox(height: 6),
                    Text(
                      l10n.decoderPluginNotAllowlistedHelp,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.tertiary,
                      ),
                    ),
                  ],
                  if (info.errorMessage != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      info.errorMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(
              width: metrics.touchTarget + 60,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    l10n.decoderPluginsRowDisableLabel,
                    style: theme.textTheme.labelSmall,
                  ),
                  Switch(
                    value: !disabled,
                    // Disabled, not hidden, when the organization refused it.
                    // A missing control invites "where did the toggle go?";
                    // a greyed one beside the sentence above says plainly that
                    // the decision was made somewhere this panel does not
                    // reach. Same reasoning as the licence panel under a
                    // policy licence: locked, not hidden.
                    onChanged:
                        info.loadStatus ==
                            DecoderPluginLoadStatus.notAllowlisted
                        ? null
                        : (enabled) async {
                            await ref
                                .read(appSettingsProvider.notifier)
                                .setPluginDisabled(
                                  info.pluginId,
                                  disabled: !enabled,
                                );
                            await ref
                                .read(decoderPluginListProvider.notifier)
                                .refresh();
                          },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.abiVersion});

  final DecoderPluginLoadStatus status;
  final int abiVersion;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final (label, color) = switch (status) {
      DecoderPluginLoadStatus.loaded => (
        l10n.decoderPluginStatusLoaded,
        theme.colorScheme.primary,
      ),
      DecoderPluginLoadStatus.abiMismatch => (
        l10n.decoderPluginStatusAbiMismatch,
        theme.colorScheme.error,
      ),
      DecoderPluginLoadStatus.missingSymbol => (
        l10n.decoderPluginStatusMissingSymbol,
        theme.colorScheme.error,
      ),
      DecoderPluginLoadStatus.manifestInvalid => (
        l10n.decoderPluginStatusManifestInvalid,
        theme.colorScheme.error,
      ),
      DecoderPluginLoadStatus.loadError => (
        l10n.decoderPluginStatusLoadError,
        theme.colorScheme.error,
      ),
      DecoderPluginLoadStatus.disabled => (
        l10n.decoderPluginStatusDisabled,
        theme.colorScheme.onSurfaceVariant,
      ),
      // Not `outline` like `disabled`, and not `error` like a broken plugin.
      // It is neither: the file is fine and the organization said no. A
      // refusal that looks like a fault sends somebody debugging their build,
      // and one that looks like their own toggle sends them to Settings — the
      // tertiary colour is what says "this is a decision, and not yours".
      DecoderPluginLoadStatus.notAllowlisted => (
        l10n.decoderPluginStatusNotAllowlisted,
        theme.colorScheme.tertiary,
      ),
    };
    final major = (abiVersion >> 16) & 0xFFFF;
    final minor = abiVersion & 0xFFFF;

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: color),
          ),
        ),
        if (abiVersion != 0)
          Text(
            l10n.decoderPluginsAbiVersion(major, minor),
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

// ── Error state ─────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
    );
  }
}
