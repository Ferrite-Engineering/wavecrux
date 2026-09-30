// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/rtl_source/stems_generator.dart';
import 'package:wavecrux/services/rtl_source/stems_writer.dart';
import 'package:wavecrux/shared/widgets/confirm_discard_changes.dart';

/// HDL source extensions the generator understands.
const List<String> kHdlSourceExtensions = [
  'v',
  'sv',
  'vh',
  'svh',
  'vhd',
  'vhdl',
];

/// What the dialog returns to its caller on success: the written stems path
/// plus a summary the caller surfaces (the caller owns the per-tab load).
@immutable
class GenerateStemsOutcome {
  const GenerateStemsOutcome({
    required this.stemsPath,
    required this.mappingCount,
    required this.topModule,
    required this.warningCount,
  });

  final String stemsPath;
  final int mappingCount;
  final String topModule;
  final int warningCount;
}

/// Picks HDL source files. Injectable for tests.
typedef SourceFilesPicker = Future<List<String>> Function();

/// Picks a folder to scan recursively. Injectable for tests.
typedef SourceFolderPicker = Future<String?> Function();

/// Picks the output stems path. Injectable for tests.
typedef StemsSavePicker = Future<String?> Function(String suggestedName);

/// Writes [contents] to [path]. Injectable for tests.
typedef StemsFileSink = Future<void> Function(String path, String contents);

/// A desktop-only dialog that generates a GTKWave-compatible stems file from an
/// HDL (Verilog/SystemVerilog/VHDL) source tree, so RTL source annotation works
/// without GTKWave's `xml2stems` / `vermin`.
///
/// On success it pops a [GenerateStemsOutcome]; the caller loads the written
/// stems file into the active tab (keeping per-tab scoping correct) and surfaces
/// the result. Pickers/generator/sink are injectable so the flow is testable
/// without touching `FilePicker.platform` or the disk.
class GenerateStemsDialog extends ConsumerStatefulWidget {
  const GenerateStemsDialog({
    super.key,
    StemsGenerator generator = const StemsGenerator(),
    SourceFilesPicker? filesPicker,
    SourceFolderPicker? folderPicker,
    StemsSavePicker? savePicker,
    StemsFileSink? fileSink,
  }) : _generator = generator,
       _filesPicker = filesPicker,
       _folderPicker = folderPicker,
       _savePicker = savePicker,
       _fileSink = fileSink;

  final StemsGenerator _generator;
  final SourceFilesPicker? _filesPicker;
  final SourceFolderPicker? _folderPicker;
  final StemsSavePicker? _savePicker;
  final StemsFileSink? _fileSink;

  /// Opens the dialog modally; resolves to the [GenerateStemsOutcome] on a
  /// successful generate, or null if the user cancelled.
  static Future<GenerateStemsOutcome?> show(
    BuildContext context, {
    StemsGenerator generator = const StemsGenerator(),
    SourceFilesPicker? filesPicker,
    SourceFolderPicker? folderPicker,
    StemsSavePicker? savePicker,
    StemsFileSink? fileSink,
  }) {
    return showDialog<GenerateStemsOutcome>(
      context: context,
      // Editor dialogs hold in-progress user input: closing must be a
      // deliberate act (Cancel / Save), never a stray scrim click — the
      // suite-wide dialog rule. Note this
      // also disables Escape (Flutter routes DismissIntent through the
      // barrier flag).
      barrierDismissible: false,
      builder: (_) => GenerateStemsDialog(
        generator: generator,
        filesPicker: filesPicker,
        folderPicker: folderPicker,
        savePicker: savePicker,
        fileSink: fileSink,
      ),
    );
  }

  @override
  ConsumerState<GenerateStemsDialog> createState() =>
      _GenerateStemsDialogState();
}

class _GenerateStemsDialogState extends ConsumerState<GenerateStemsDialog> {
  // Desktop-only modal; a fixed content width is the house style for dialogs.
  static const double _contentWidth = 520;

  final _sources = <String>[];
  final _topController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _topController.dispose();
    super.dispose();
  }

  /// The dialog always opens empty, so any accumulated source or a
  /// typed top module counts as unsaved input. Clean forms close
  /// without a prompt; dirty ones confirm first (suite unsaved-changes
  /// canon — see [confirmDiscardChanges]).
  bool get _isDirty =>
      _sources.isNotEmpty || _topController.text.trim().isNotEmpty;

  Future<void> _onCancel() async {
    if (!_isDirty) {
      Navigator.of(context).pop();
      return;
    }
    final confirmed = await confirmDiscardChanges(context);
    if (!confirmed || !mounted) return;
    Navigator.of(context).pop();
  }

  Future<List<String>> _pickFiles() async {
    if (widget._filesPicker != null) return widget._filesPicker!();
    final result = await FilePicker.pickFiles(
      // file_picker 12: pickFiles selects multiple by default; allowMultiple
      // is deprecated, so it is dropped here while preserving multi-select.
      dialogTitle: L10N.of(context).rtlGenerateSourcesPickerTitle,
      type: FileType.custom,
      allowedExtensions: kHdlSourceExtensions,
    );
    return result?.files.map((f) => f.path).whereType<String>().toList() ??
        const [];
  }

  Future<String?> _pickFolder() async {
    if (widget._folderPicker != null) return widget._folderPicker!();
    return FilePicker.getDirectoryPath(
      dialogTitle: L10N.of(context).rtlGenerateFolderPickerTitle,
    );
  }

  Future<String?> _pickSave(String suggested) async {
    if (widget._savePicker != null) return widget._savePicker!(suggested);
    return FilePicker.saveFile(
      // file_picker 12 requires bytes & writes the file itself; pass empty so
      // it only returns the chosen path and we write via _write below.
      bytes: Uint8List(0),
      dialogTitle: L10N.of(context).rtlGenerateSavePickerTitle,
      fileName: suggested,
      type: FileType.custom,
      allowedExtensions: const ['stems'],
    );
  }

  Future<void> _write(String path, String contents) {
    if (widget._fileSink != null) return widget._fileSink!(path, contents);
    return File(path).writeAsString(contents);
  }

  Future<void> _addFiles() async {
    final picked = await _pickFiles();
    // The picker is its own window; where the app stays live behind it, the
    // dialog may have closed before the answer arrives.
    if (picked.isEmpty || !mounted) return;
    setState(() {
      for (final p in picked) {
        if (!_sources.contains(p)) _sources.add(p);
      }
      _error = null;
    });
  }

  Future<void> _addFolder() async {
    final dir = await _pickFolder();
    if (dir == null) return;
    final found = <String>[];
    try {
      await for (final entity in Directory(dir).list(recursive: true)) {
        if (entity is! File) continue;
        final ext = entity.path.split('.').last.toLowerCase();
        if (kHdlSourceExtensions.contains(ext)) found.add(entity.path);
      }
    } on Object {
      // Best-effort directory walk; ignore unreadable entries.
    }
    // Both the picker and the walk are awaited, and the dialog may have
    // closed during either.
    if (found.isEmpty || !mounted) return;
    setState(() {
      for (final p in found) {
        if (!_sources.contains(p)) _sources.add(p);
      }
      _error = null;
    });
  }

  Future<void> _generate() async {
    final l10n = L10N.of(context);
    if (_sources.isEmpty) {
      setState(() => _error = l10n.rtlGenerateNoSourcesYet);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final top = _topController.text.trim();
      final result = await widget._generator.generateFromPaths(
        _sources,
        topModule: top.isEmpty ? null : top,
      );
      if (!mounted) return;

      if (result.stems.isEmpty || result.resolvedTop == null) {
        // Surface the most actionable reason inline; keep the dialog open.
        setState(() {
          _busy = false;
          _error = result.availableTops.length > 1
              ? l10n.rtlGenerateNoTop(result.availableTops.join(', '))
              : l10n.rtlGenerateNoModules;
        });
        return;
      }

      final suggested = '${result.resolvedTop}.stems';
      final savePath = await _pickSave(suggested);
      if (!mounted) return;
      if (savePath == null) {
        setState(() => _busy = false);
        return;
      }

      await _write(savePath, const StemsWriter().write(result.stems));
      if (!mounted) return;
      Navigator.of(context).pop(
        GenerateStemsOutcome(
          stemsPath: savePath,
          mappingCount: result.stems.length,
          topModule: result.resolvedTop!,
          warningCount: result.warnings.length,
        ),
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = l10n.rtlGenerateError(e.toString());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l10n.rtlGenerateDialogTitle),
      content: SizedBox(
        width: _contentWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.rtlGenerateDialogDescription),
            const SizedBox(height: 16),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _addFiles,
                  icon: const Icon(Icons.note_add_outlined, size: 18),
                  label: Text(l10n.rtlGenerateAddFilesButton),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _addFolder,
                  icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                  label: Text(l10n.rtlGenerateAddFolderButton),
                ),
                const Spacer(),
                if (_sources.isNotEmpty)
                  TextButton(
                    onPressed: _busy ? null : () => setState(_sources.clear),
                    child: Text(l10n.rtlGenerateClearButton),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _sourceList(theme, l10n),
            const SizedBox(height: 16),
            TextField(
              controller: _topController,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: l10n.rtlGenerateTopModuleLabel,
                hintText: l10n.rtlGenerateTopModuleHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : _onCancel,
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: _busy ? null : _generate,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.rtlGenerateButton),
        ),
      ],
    );
  }

  Widget _sourceList(ThemeData theme, L10N l10n) {
    if (_sources.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          l10n.rtlGenerateNoSourcesYet,
          style: TextStyle(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
      );
    }
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 160),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(
              l10n.rtlGenerateSourcesCount(_sources.length),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _sources.length,
              itemBuilder: (context, i) {
                final path = _sources[i];
                final name = path.split(Platform.pathSeparator).last;
                return ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  title: Text(name, style: const TextStyle(fontSize: 12)),
                  subtitle: Text(
                    path,
                    style: const TextStyle(fontSize: 10),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).deleteButtonTooltip,
                    onPressed: _busy
                        ? null
                        : () => setState(() => _sources.removeAt(i)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
