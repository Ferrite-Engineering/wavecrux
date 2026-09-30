// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wavecrux/core/app_info/application_build_info_provider.dart';
import 'package:wavecrux/core/help_urls.dart';
import 'package:wavecrux/core/theme/wavecrux_colors.dart';
import 'package:wavecrux/domain/enums/editor_host_capability.dart';
import 'package:wavecrux/domain/models/wavecrux_tab_payload.dart';
import 'package:wavecrux/features/workspace/providers/other_tabs_from_last_session_provider.dart';
import 'package:wavecrux/features/workspace/providers/recent_files_provider.dart';
import 'package:wavecrux/features/workspace/providers/recent_workspaces_provider.dart';
import 'package:wavecrux/features/workspace/widgets/empty_canvas_docs_hint.dart';
import 'package:wavecrux/features/workspace/widgets/recent_file_tile.dart';
import 'package:wavecrux/features/workspace/widgets/web_drop_zone.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';
import 'package:wavecrux/shared/widgets/editor_host_boundary.dart';
import 'package:wavecrux/shared/widgets/glowing_app_icon.dart';

/// The empty-canvas state rendered when the workspace has zero open tabs.
///
/// Composes WaveCrux's product-specific empty-canvas content (waves header,
/// open/new-tab actions, recent files / workspaces, web drop-zone, phone
/// "other tabs from last session") into the cross-suite
/// [`crux.EmptyCanvasState`] shell (`useCard: false`), so the shared scroll +
/// width-constraint chrome is reused while WaveCrux owns the body composition.
///
/// It is *not* a route or scaffold — `ViewerScreen` keeps the toolbar, menu
/// bar, status bar, and command palette rendered around this widget so
/// settings, diagnostics, and other global actions remain reachable without
/// opening a file first.
class WaveCruxEmptyCanvas extends ConsumerWidget {
  const WaveCruxEmptyCanvas({
    required this.onOpenFile,
    required this.onOpenRecentFile,
    this.onOpenSample,
    this.onOpenWorkspace,
    this.onOpenRecentWorkspace,
    this.onOpenOtherTab,
    this.onOpenFromBytes,
    super.key,
  });

  /// Called when the user taps "Open File…".
  final VoidCallback onOpenFile;

  /// Called when the user taps "Open Sample Waveform".
  ///
  /// Optional so tests and embedders can omit it, but `ViewerScreen` always
  /// supplies it — a first-run user with no waveform of their own (every
  /// mobile user, since a phone cannot produce a VCD) would otherwise face a
  /// welcome screen whose only button leads to an empty file picker.
  final VoidCallback? onOpenSample;

  /// Called when the user taps a recent-files row. Receives the absolute path.
  final Future<void> Function(String filePath) onOpenRecentFile;

  /// Called when the user taps "Open Workspace…". Tablet/desktop only.
  final VoidCallback? onOpenWorkspace;

  /// Called when the user taps a recent-workspaces row.
  final Future<void> Function(String workspacePath)? onOpenRecentWorkspace;

  /// Called when the user taps an "Other tabs from your last session" row.
  final Future<void> Function(crux.WorkspaceTab<WaveCruxTabPayload> tab)?
  onOpenOtherTab;

  /// Called when a file is dropped onto the web drop zone. Only used on web.
  final void Function(Uint8List bytes, String name)? onOpenFromBytes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceClass = ref.watch(deviceClassProvider);
    final isPhone = deviceClass.isPhoneClass;

    return SafeArea(
      key: const Key('empty_canvas_state'),
      child: crux.EmptyCanvasState(
        // The shared canvas names itself after `title`, which WaveCrux
        // replaces with its own header, so the region name is passed here.
        semanticLabel: L10N.of(context).emptyCanvasTitle,
        useCard: false,
        maxContentWidth: isPhone ? double.infinity : 560,
        children: [
          const _Header(),
          const SizedBox(height: 24),
          _Actions(
            onOpenFile: onOpenFile,
            onOpenSample: onOpenSample,
            onOpenWorkspace: isPhone ? null : onOpenWorkspace,
          ),
          if (kIsWeb && onOpenFromBytes != null) ...[
            const SizedBox(height: 16),
            WebDropZone(onFilesDropped: onOpenFromBytes!),
          ],
          // Interactive VCD's boundary, stated where
          // someone would go looking for it: the ways of getting waveform
          // data into the viewer are listed directly above this line, and
          // "attach a running simulation" is the one that is not among them.
          //
          // Renders nothing outside an editor host — the widget makes that
          // check itself, so this call site stays a plain child. Not a nudge:
          // it is part of the screen the user is already reading, so the
          // once-per-session rule does not apply. See `editor_host_boundary.dart`.
          //
          // The gate is repeated here rather than left to the widget so the
          // spacing around it disappears too: an unhosted build must lay out
          // byte-for-byte as it did before this landed.
          if (isEditorHosted(ref)) ...[
            const SizedBox(height: 16),
            const EditorHostCapabilityNote(
              capability: EditorHostCapability.interactiveVcd,
            ),
          ],
          const SizedBox(height: 24),
          _RecentFilesSection(onOpenFile: onOpenRecentFile),
          const SizedBox(height: 24),
          if (isPhone) ...[
            _OtherTabsFromLastSessionSection(onOpenOtherTab: onOpenOtherTab),
            const SizedBox(height: 24),
          ],
          _RecentWorkspacesSection(onOpenWorkspace: onOpenRecentWorkspace),
          const SizedBox(height: 16),
          const EmptyCanvasDocsHint(),
          // What the other three products do for someone who is here, looking
          // at a waveform. Below the recents and the docs hint, because it is
          // the only thing on this screen that is not about the work in front
          // of them — and above the suite line, which is the quieter version
          // of the same statement.
          const SizedBox(height: 24),
          const WaveCruxSuitePeers(),
          const SizedBox(height: 4),
          crux.CruxSuiteFooter(
            label: L10N.of(context).emptyCanvasSuiteFooter,
            onTap: () =>
                unawaited(suiteSiteLaunchUrl(Uri.parse(HelpUrls.suiteHome))),
          ),
        ],
      ),
    );
  }
}

/// The "More from EDACrux" rows, wired to WaveCrux's own landing path.
///
/// The blurbs are WaveCrux's: they say what each other tool does for someone
/// holding a waveform, which is not what it does for someone holding a lint
/// report. See the `emptyCanvasPeer*` ARB descriptions.
class WaveCruxSuitePeers extends StatelessWidget {
  /// Creates the peers section.
  const WaveCruxSuitePeers({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    return crux.CruxSuitePeers(
      heading: l10n.emptyCanvasPeersHeading,
      entries: [
        crux.CruxSuitePeerEntry(
          product: crux.CruxSuiteProduct.netCrux,
          blurb: l10n.emptyCanvasPeerNetCrux,
        ),
        crux.CruxSuitePeerEntry(
          product: crux.CruxSuiteProduct.lintCrux,
          blurb: l10n.emptyCanvasPeerLintCrux,
        ),
        crux.CruxSuitePeerEntry(
          product: crux.CruxSuiteProduct.simCrux,
          blurb: l10n.emptyCanvasPeerSimCrux,
        ),
      ],
      onOpenPeer: (peer) => unawaited(
        suiteSiteLaunchUrl(Uri.parse(HelpUrls.suitePeer(peer.slug))),
      ),
    );
  }
}

/// Opens the suite site when the welcome screen's suite-membership line is
/// followed.
///
/// A mutable top-level seam rather than a direct `launchUrl` call so widget
/// tests can activate the line without the `url_launcher` platform channel.
Future<bool> Function(Uri uri) suiteSiteLaunchUrl = launchUrl;

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    // The running version, shown as a muted line under the subtitle. On web
    // there is no native menu bar, so this is the only always-visible place
    // a user can read the version without knowing the palette/overflow About
    // entry points. Resolves in milliseconds; renders nothing until then.
    final version = ref.watch(applicationBuildInfoProvider).value?.version;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The official WaveCrux app icon with its animated halo/pulse — the
        // same widget the About dialog uses — rather than a static Material
        // `waves_outlined` glyph. This restores the animated logo that the
        // welcome screen lost when the separate welcome window was removed.
        const GlowingAppIcon(size: 72),
        const SizedBox(height: 12),
        Semantics(
          header: true,
          container: true,
          child: Text(
            l10n.emptyCanvasTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: WavecruxColors.monoFontFamily,
              fontFamilyFallback: WavecruxColors.monoFontFamilyFallback,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.emptyCanvasSubtitle,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
        ),
        if (version != null) ...[
          const SizedBox(height: 6),
          Text(
            l10n.emptyCanvasVersion(version),
            key: const Key('empty_canvas_version'),
            textAlign: TextAlign.center,
            // Full-strength: 11 px text needs 4.5:1, which the 70% tint missed.
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.onOpenFile,
    required this.onOpenSample,
    required this.onOpenWorkspace,
  });

  final VoidCallback onOpenFile;
  final VoidCallback? onOpenSample;
  final VoidCallback? onOpenWorkspace;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          key: const Key('emptyCanvasOpenFileButton'),
          onPressed: onOpenFile,
          icon: const Icon(Icons.folder_open_outlined, size: 18),
          label: Text(l10n.emptyCanvasOpenFile),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
        if (onOpenSample != null) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const Key('emptyCanvasOpenSampleButton'),
            onPressed: onOpenSample,
            icon: const Icon(Icons.play_circle_outline, size: 18),
            label: Text(l10n.emptyCanvasOpenSample),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ],
        if (onOpenWorkspace != null) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const Key('emptyCanvasOpenWorkspaceButton'),
            onPressed: onOpenWorkspace,
            icon: const Icon(Icons.folder_special_outlined, size: 18),
            label: Text(l10n.emptyCanvasOpenWorkspace),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ],
      ],
    );
  }
}

class _RecentFilesSection extends ConsumerWidget {
  const _RecentFilesSection({required this.onOpenFile});

  final Future<void> Function(String filePath) onOpenFile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final asyncFiles = ref.watch(recentFilesProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            l10n.emptyCanvasRecentFiles,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        asyncFiles.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (files) {
            if (files.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Text(
                  l10n.emptyCanvasNoRecentFiles,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              );
            }
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.builder(
                key: const Key('emptyCanvasRecentFilesList'),
                shrinkWrap: true,
                itemCount: files.length,
                itemBuilder: (context, index) {
                  final path = files[index];
                  return RecentFileTile(
                    filePath: path,
                    onTap: () => onOpenFile(path),
                    onRemove: () =>
                        ref.read(recentFilesProvider.notifier).removeFile(path),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }
}

/// "Other tabs from your last session" section — phone single-tab fallback
/// surface (ARCHITECTURE.md §3.1.4).
class _OtherTabsFromLastSessionSection extends ConsumerWidget {
  const _OtherTabsFromLastSessionSection({required this.onOpenOtherTab});

  final Future<void> Function(crux.WorkspaceTab<WaveCruxTabPayload> tab)?
  onOpenOtherTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final otherTabs = ref.watch(otherTabsFromLastSessionProvider);
    if (otherTabs.isEmpty) return const SizedBox.shrink();

    final l10n = L10N.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            l10n.emptyCanvasOtherTabsFromLastSession,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: ListView.builder(
            key: const Key('emptyCanvasOtherTabsList'),
            shrinkWrap: true,
            itemCount: otherTabs.length,
            itemBuilder: (context, index) {
              final tab = otherTabs[index];
              final path = tab.payload.filePath;
              if (path == null) return const SizedBox.shrink();
              return RecentFileTile(
                key: Key('emptyCanvasOtherTabTile_${tab.id.value}'),
                filePath: path,
                onTap: onOpenOtherTab == null
                    ? () {}
                    : () => onOpenOtherTab!(tab),
                onRemove: () => ref
                    .read(otherTabsFromLastSessionProvider.notifier)
                    .remove(tab),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Recent named-workspaces (`.wavecrux-workspace`) list.
class _RecentWorkspacesSection extends ConsumerWidget {
  const _RecentWorkspacesSection({required this.onOpenWorkspace});

  final Future<void> Function(String workspacePath)? onOpenWorkspace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final asyncWorkspaces = ref.watch(recentWorkspacesProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            l10n.emptyCanvasRecentWorkspaces,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        asyncWorkspaces.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (paths) {
            if (paths.isEmpty || onOpenWorkspace == null) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Text(
                  l10n.emptyCanvasNoRecentWorkspaces,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              );
            }
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                key: const Key('emptyCanvasRecentWorkspacesList'),
                shrinkWrap: true,
                itemCount: paths.length,
                itemBuilder: (context, index) {
                  final path = paths[index];
                  return RecentFileTile(
                    filePath: path,
                    onTap: () => onOpenWorkspace!(path),
                    onRemove: () => ref
                        .read(recentWorkspacesProvider.notifier)
                        .removeWorkspace(path),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }
}
