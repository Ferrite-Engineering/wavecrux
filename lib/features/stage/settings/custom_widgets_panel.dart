// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/features/stage/bundle/custom_widget_bundle_manager.dart';
import 'package:wavecrux/features/stage/bundle/custom_widget_bundle_provider.dart';
import 'package:wavecrux/features/stage/bundle/widget_bundle_failure.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Open-core Settings panel that manages installed `.wcrux-widget`
/// bundles and watched directories.
///
/// The Stage widget *capability* is free (wavecrux/CLAUDE.md lists
/// `lib/features/stage/{sdk,runtime,bundle,settings}` as the free SDK),
/// so this panel is available to **every tier** — no tier gate, no PRO
/// badge. Only the curated Pro *pack* content is gated, elsewhere.
///
/// The panel reads from [customWidgetBundleManagerProvider]; the manager
/// owns persistence, the live registry, and any active directory-watch
/// subscriptions. Mutations route back through the manager so they
/// survive app restart.
class CustomWidgetsPanel extends ConsumerWidget {
  /// Creates the panel. Tests may pass [overridePicker] /
  /// [overrideDirectoryPicker] to inject deterministic file/directory
  /// pickers that bypass the system dialog, and [overrideManager] to skip
  /// the [customWidgetBundleManagerProvider] FutureProvider altogether
  /// (e.g. when wiring through a test ProviderContainer is more friction
  /// than calling the panel directly).
  const CustomWidgetsPanel({
    super.key,
    this.overridePicker,
    this.overrideDirectoryPicker,
    this.overrideManager,
  });

  /// Test seam: returns the absolute path of the bundle file the user
  /// chose, or null when the picker was cancelled.
  final Future<String?> Function(BuildContext context)? overridePicker;

  /// Test seam: returns the absolute path of the directory the user
  /// chose, or null when the picker was cancelled.
  final Future<String?> Function(BuildContext context)? overrideDirectoryPicker;

  /// Test seam: when non-null, the panel renders against this manager
  /// directly and skips the [customWidgetBundleManagerProvider] read.
  /// Production callers always leave this null.
  final CustomWidgetBundleManager? overrideManager;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);

    final injected = overrideManager;
    if (injected != null) {
      return _PanelBody(
        manager: injected,
        overridePicker: overridePicker,
        overrideDirectoryPicker: overrideDirectoryPicker,
      );
    }

    final managerAsync = ref.watch(customWidgetBundleManagerProvider);
    return managerAsync.when(
      loading: () => Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(l10n.customStageWidgetsLoadingProgress),
          ],
        ),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          // The widget-load-failure ARB key lives in open-core (the Stage
          // SDK + bundle loader are open core — see ARCHITECTURE §10), so the error placeholder reads from
          // [L10N] rather than [L10N].
          L10N.of(context).customStageWidgetLoadFailedTooltip(e.toString()),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
      data: (manager) => _PanelBody(
        manager: manager,
        overridePicker: overridePicker,
        overrideDirectoryPicker: overrideDirectoryPicker,
      ),
    );
  }
}

class _PanelBody extends StatefulWidget {
  const _PanelBody({
    required this.manager,
    this.overridePicker,
    this.overrideDirectoryPicker,
  });

  final CustomWidgetBundleManager manager;
  final Future<String?> Function(BuildContext context)? overridePicker;
  final Future<String?> Function(BuildContext context)? overrideDirectoryPicker;

  @override
  State<_PanelBody> createState() => _PanelBodyState();
}

class _PanelBodyState extends State<_PanelBody> {
  @override
  void initState() {
    super.initState();
    widget.manager.addListener(_onManagerChange);
  }

  @override
  void didUpdateWidget(covariant _PanelBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.manager != widget.manager) {
      oldWidget.manager.removeListener(_onManagerChange);
      widget.manager.addListener(_onManagerChange);
    }
  }

  @override
  void dispose() {
    widget.manager.removeListener(_onManagerChange);
    super.dispose();
  }

  void _onManagerChange() {
    if (mounted) setState(() {});
  }

  Future<void> _onLoadBundle() async {
    final picker = widget.overridePicker ?? _defaultPickBundle;
    final path = await picker(context);
    if (path == null) return;
    await widget.manager.loadBundle(path);
  }

  Future<void> _onWatchDirectory() async {
    final picker = widget.overrideDirectoryPicker ?? _defaultPickDirectory;
    final path = await picker(context);
    if (path == null) return;
    await widget.manager.addWatchedDirectory(path);
  }

  Future<String?> _defaultPickBundle(BuildContext context) async {
    final l10n = L10N.of(context);
    final result = await FilePicker.pickFiles(
      dialogTitle: l10n.customStageWidgetsFilePickerTitle,
      // Restrict the picker to `.wcrux-widget` bundles rather than showing
      // every file. The extension token is the part after the last dot
      // (`community_gauge.wcrux-widget` → `wcrux-widget`).
      type: FileType.custom,
      allowedExtensions: const ['wcrux-widget'],
    );
    return result?.files.singleOrNull?.path;
  }

  Future<String?> _defaultPickDirectory(BuildContext context) async {
    final l10n = L10N.of(context);
    return await FilePicker.getDirectoryPath(
      dialogTitle: l10n.customStageWidgetsDirectoryPickerTitle,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final state = widget.manager.state;
    final hasContent =
        state.loadedBundles.isNotEmpty ||
        state.errors.isNotEmpty ||
        state.watchedDirectories.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _PanelHeader(
            title: l10n.customStageWidgetsPanelTitle,
            description: l10n.customStageWidgetsPanelDescription,
            theme: theme,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _onLoadBundle,
                icon: const Icon(Icons.folder_open),
                label: Text(l10n.customStageWidgetsLoadButton),
              ),
              FilledButton.tonalIcon(
                onPressed: _onWatchDirectory,
                icon: const Icon(Icons.folder_special),
                label: Text(l10n.customStageWidgetsWatchButton),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!hasContent)
            _EmptyState(l10n: l10n)
          else ...[
            if (state.loadedBundles.isNotEmpty) ...[
              _SectionLabel(
                l10n.customStageWidgetsBundleSection,
                theme: theme,
              ),
              for (final entry in state.loadedBundles)
                _LoadedBundleRow(
                  entry: entry,
                  onRemove: () => widget.manager.removeBundle(entry.bundlePath),
                ),
            ],
            if (state.errors.isNotEmpty) ...[
              const SizedBox(height: 12),
              _SectionLabel(
                l10n.customStageWidgetsErrorSection,
                theme: theme,
              ),
              for (final err in state.errors)
                _ErrorRow(
                  error: err,
                  onDismiss: () => widget.manager.dismissError(err.bundlePath),
                ),
            ],
            if (state.watchedDirectories.isNotEmpty) ...[
              const SizedBox(height: 12),
              _SectionLabel(
                l10n.customStageWidgetsWatchedSection,
                theme: theme,
              ),
              for (final dir in state.watchedDirectories)
                _WatchedDirectoryRow(
                  path: dir,
                  onRemove: () => widget.manager.removeWatchedDirectory(dir),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.title,
    required this.description,
    required this.theme,
  });

  final String title;
  final String description;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          description,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, {required this.theme});

  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.l10n});

  final L10N l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.customStageWidgetsEmptyState,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 4),
          Text(
            l10n.customStageWidgetsEmptyStateHint,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadedBundleRow extends StatelessWidget {
  const _LoadedBundleRow({
    required this.entry,
    required this.onRemove,
  });

  final LoadedBundleEntry entry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    return ListTile(
      key: ValueKey('custom_widget_bundle_${entry.bundlePath}'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.extension_outlined),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(entry.displayName)),
          const SizedBox(width: 8),
          Text(
            l10n.customStageWidgetsBundleVersion(entry.widgetVersion),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      subtitle: Text(
        entry.bundlePath,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: l10n.customStageWidgetsRemoveBundle,
        onPressed: onRemove,
      ),
    );
  }
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({
    required this.error,
    required this.onDismiss,
  });

  final BundleLoadError error;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    return ListTile(
      key: ValueKey('custom_widget_error_${error.bundlePath}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.error_outline, color: theme.colorScheme.error),
      title: Text(
        error.bundlePath,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium,
      ),
      subtitle: Text(
        _localizedFailureMessage(l10n, error.kind),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.close),
        tooltip: l10n.customStageWidgetsDismissError,
        onPressed: onDismiss,
      ),
    );
  }
}

class _WatchedDirectoryRow extends StatelessWidget {
  const _WatchedDirectoryRow({
    required this.path,
    required this.onRemove,
  });

  final String path;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    return ListTile(
      key: ValueKey('custom_widget_watched_$path'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.folder),
      title: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: IconButton(
        icon: const Icon(Icons.visibility_off_outlined),
        tooltip: l10n.customStageWidgetsRemoveDirectory,
        onPressed: onRemove,
      ),
    );
  }
}

String _localizedFailureMessage(L10N l10n, WidgetBundleFailureKind kind) {
  switch (kind) {
    case WidgetBundleFailureKind.fileMissing:
      return l10n.customStageWidgetsErrorFileMissing;
    case WidgetBundleFailureKind.notAZipArchive:
      return l10n.customStageWidgetsErrorNotAZipArchive;
    case WidgetBundleFailureKind.manifestMissing:
      return l10n.customStageWidgetsErrorManifestMissing;
    case WidgetBundleFailureKind.manifestInvalid:
      return l10n.customStageWidgetsErrorManifestInvalid;
    case WidgetBundleFailureKind.unsupportedApiVersion:
      return l10n.customStageWidgetsErrorUnsupportedApiVersion;
    case WidgetBundleFailureKind.runtimeAssetMissing:
      return l10n.customStageWidgetsErrorRuntimeAssetMissing;
    case WidgetBundleFailureKind.pathTraversal:
      return l10n.customStageWidgetsErrorPathTraversal;
    case WidgetBundleFailureKind.symlinkRejected:
      return l10n.customStageWidgetsErrorSymlinkRejected;
    case WidgetBundleFailureKind.oversize:
      return l10n.customStageWidgetsErrorOversize;
    case WidgetBundleFailureKind.pathTooDeep:
      return l10n.customStageWidgetsErrorPathTooDeep;
    case WidgetBundleFailureKind.ioError:
      return l10n.customStageWidgetsErrorIo;
  }
}
