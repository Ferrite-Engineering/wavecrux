// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/features/rtl_source/widgets/generate_stems_dialog.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/rtl_source/stems_writer.dart';
import 'package:wavecrux/services/rtl_source/verilator_ast_stems_importer.dart';
import 'package:wavecrux/shared/widgets/confirm_discard_changes.dart';

/// Picks the Verilator AST tree JSON file. Injectable for tests.
typedef AstFilePicker = Future<String?> Function();

/// A desktop-only dialog that imports a Verilator `--json-only` AST dump
/// (`V<top>.tree.json` + sibling `.tree.meta.json`) as a stems source: the
/// fully elaborated hierarchy — generate loops unrolled — is converted and
/// written as a portable GTKWave-compatible stems file, which the caller then
/// loads. WaveCrux thus replaces the retired `xml2stems` flow (Verilator 5.x
/// no longer emits the XML that tool consumed).
///
/// On success it pops a [GenerateStemsOutcome] — the same contract as
/// [GenerateStemsDialog], so the caller's load-and-announce path is shared.
/// A cancelled or failed import pops nothing and leaves the current stems
/// state untouched. Pickers/importer/sink are injectable so the flow is
/// testable without touching `FilePicker.platform` or the disk.
class ImportVerilatorAstDialog extends ConsumerStatefulWidget {
  const ImportVerilatorAstDialog({
    super.key,
    VerilatorAstStemsImporter importer = const VerilatorAstStemsImporter(),
    AstFilePicker? astPicker,
    StemsSavePicker? savePicker,
    StemsFileSink? fileSink,
  }) : _importer = importer,
       _astPicker = astPicker,
       _savePicker = savePicker,
       _fileSink = fileSink;

  final VerilatorAstStemsImporter _importer;
  final AstFilePicker? _astPicker;
  final StemsSavePicker? _savePicker;
  final StemsFileSink? _fileSink;

  /// Opens the dialog modally; resolves to the [GenerateStemsOutcome] on a
  /// successful import, or null if the user cancelled.
  static Future<GenerateStemsOutcome?> show(
    BuildContext context, {
    VerilatorAstStemsImporter importer = const VerilatorAstStemsImporter(),
    AstFilePicker? astPicker,
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
      builder: (_) => ImportVerilatorAstDialog(
        importer: importer,
        astPicker: astPicker,
        savePicker: savePicker,
        fileSink: fileSink,
      ),
    );
  }

  @override
  ConsumerState<ImportVerilatorAstDialog> createState() =>
      _ImportVerilatorAstDialogState();
}

class _ImportVerilatorAstDialogState
    extends ConsumerState<ImportVerilatorAstDialog> {
  // Desktop-only modal; a fixed content width is the house style for dialogs.
  static const double _contentWidth = 520;

  String? _astPath;
  final _topController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _topController.dispose();
    super.dispose();
  }

  /// The dialog always opens empty, so a chosen AST file or a typed
  /// top module counts as unsaved input. Clean forms close without a
  /// prompt; dirty ones confirm first (suite unsaved-changes canon —
  /// see [confirmDiscardChanges]).
  bool get _isDirty =>
      _astPath != null || _topController.text.trim().isNotEmpty;

  Future<void> _onCancel() async {
    if (!_isDirty) {
      Navigator.of(context).pop();
      return;
    }
    final confirmed = await confirmDiscardChanges(context);
    if (!confirmed || !mounted) return;
    Navigator.of(context).pop();
  }

  Future<String?> _pickAstFile() async {
    if (widget._astPicker != null) return await widget._astPicker!();
    final result = await FilePicker.pickFiles(
      dialogTitle: L10N.of(context).rtlImportAstPickerTitle,
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    final files = result?.files;
    if (files == null || files.isEmpty) return null;
    return files.first.path;
  }

  Future<String?> _pickSave(String suggested) async {
    if (widget._savePicker != null) return await widget._savePicker!(suggested);
    return await FilePicker.saveFile(
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

  Future<void> _chooseAstFile() async {
    final picked = await _pickAstFile();
    // The picker is its own window; where the app stays live behind it, the
    // dialog may have closed before the answer arrives.
    if (picked == null || !mounted) return;
    setState(() {
      _astPath = picked;
      _error = null;
    });
  }

  Future<void> _import() async {
    final l10n = L10N.of(context);
    final astPath = _astPath;
    if (astPath == null) {
      setState(() => _error = l10n.rtlImportAstNoFileYet);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final top = _topController.text.trim();
      final result = await widget._importer.importFromPath(
        astPath,
        topModule: top.isEmpty ? null : top,
      );
      if (!mounted) return;

      if (result.stems.isEmpty || result.resolvedTop == null) {
        // Surface the most actionable reason inline; keep the dialog open.
        // Ambiguous tops reuse the Generate flow's message + top-module
        // field UX; everything else (missing meta, malformed JSON, no
        // modules) shows the importer's first diagnostic.
        setState(() {
          _busy = false;
          _error = result.availableTops.length > 1
              ? l10n.rtlGenerateNoTop(result.availableTops.join(', '))
              : (result.warnings.isNotEmpty
                    ? l10n.rtlImportAstFailed(result.warnings.first)
                    : l10n.rtlImportAstNoModules);
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
        _error = l10n.rtlImportAstFailed(e.toString());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l10n.rtlImportAstDialogTitle),
      // Scrollable: the explanatory text plus error line can exceed the
      // dialog's max height on short windows (and the test viewport).
      content: SizedBox(
        width: _contentWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.rtlImportAstDialogDescription),
              const SizedBox(height: 16),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _chooseAstFile,
                    icon: const Icon(Icons.data_object, size: 18),
                    label: Text(l10n.rtlImportAstPickButton),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _pickedFile(theme, l10n),
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
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : _onCancel,
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: _busy ? null : _import,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.rtlImportAstButton),
        ),
      ],
    );
  }

  Widget _pickedFile(ThemeData theme, L10N l10n) {
    final astPath = _astPath;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(6),
      ),
      child: astPath == null
          ? Text(
              l10n.rtlImportAstNoFileYet,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  astPath.split(Platform.pathSeparator).last,
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  astPath,
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
    );
  }
}
