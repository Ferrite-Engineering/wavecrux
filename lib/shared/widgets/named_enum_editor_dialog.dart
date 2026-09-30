// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:wavecrux/core/providers/browser_download_provider.dart';
import 'package:wavecrux/domain/models/named_enum_config.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/translate/translate_filter_service.dart';
import 'package:wavecrux/shared/widgets/confirm_discard_changes.dart';

/// Full CRUD editor for [NamedEnumConfig] with GTKWave `.txt` import/export.
///
/// Returns the updated config map on OK or null if dismissed.
class NamedEnumEditorDialog extends StatefulWidget {
  const NamedEnumEditorDialog._({required this.initial});

  final NamedEnumConfig initial;

  static Future<Map<String, Object?>?> show(
    BuildContext context, {
    Map<String, Object?>? config,
  }) async {
    final initial = config != null
        ? NamedEnumConfig.fromMap(config)
        : const NamedEnumConfig();
    final result = await showDialog<NamedEnumConfig>(
      context: context,
      // Editor dialogs hold in-progress user input: closing must be a
      // deliberate act (Cancel / Save), never a stray scrim click — the
      // suite-wide dialog rule. Note this
      // also disables Escape (Flutter routes DismissIntent through the
      // barrier flag).
      barrierDismissible: false,
      builder: (_) => NamedEnumEditorDialog._(initial: initial),
    );
    return result?.toMap();
  }

  @override
  State<NamedEnumEditorDialog> createState() => _NamedEnumEditorDialogState();
}

class _NamedEnumEditorDialogState extends State<NamedEnumEditorDialog> {
  late List<_Row> _rows;
  late final List<_Row> _initialRows;
  bool _dialogInFlight = false;

  @override
  void initState() {
    super.initState();
    List<_Row> rowsFromInitial() => widget.initial.entries
        .map((e) => _Row(value: e.value.toString(), label: e.label))
        .toList();
    _rows = rowsFromInitial();
    // Independent snapshot for the dirty check — row objects in
    // [_rows] are replaced/removed as the user edits.
    _initialRows = rowsFromInitial();
  }

  /// Whether the table differs from the entries it opened with. Clean
  /// forms close without a prompt; dirty ones confirm first (suite
  /// unsaved-changes canon — see [confirmDiscardChanges]).
  bool get _isDirty {
    if (_rows.length != _initialRows.length) return true;
    for (var i = 0; i < _rows.length; i++) {
      if (_rows[i].value != _initialRows[i].value ||
          _rows[i].label != _initialRows[i].label) {
        return true;
      }
    }
    return false;
  }

  Future<void> _onCancel() async {
    if (!_isDirty) {
      Navigator.of(context).pop();
      return;
    }
    final confirmed = await confirmDiscardChanges(context);
    if (!confirmed || !mounted) return;
    Navigator.of(context).pop();
  }

  void _addRow() {
    setState(() => _rows.add(_Row(value: '0', label: '')));
  }

  void _deleteRow(int index) {
    setState(() => _rows.removeAt(index));
  }

  NamedEnumConfig? _buildConfig() {
    final entries = <NamedEnumEntry>[];
    for (final row in _rows) {
      final v = BigInt.tryParse(row.value);
      if (v == null) return null;
      entries.add(NamedEnumEntry(value: v, label: row.label));
    }
    return NamedEnumConfig(entries: entries);
  }

  Future<void> _importFile(L10N l10n) async {
    if (_dialogInFlight) return;
    setState(() => _dialogInFlight = true);
    final FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        dialogTitle: l10n.namedEnumEditorImport,
      );
    } finally {
      if (mounted) setState(() => _dialogInFlight = false);
    }
    if (!mounted) return;
    final path = result?.files.firstOrNull?.path;
    if (path == null) return;
    final content = await File(path).readAsString();
    const service = TranslateFilterService();
    final filter = service.parse(content);
    // TranslateFilter._map is not public, so we re-parse the file directly.
    // Build NamedEnumEntries from the raw text.
    final importedRows = <_Row>[];
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty ||
          trimmed.startsWith('#') ||
          trimmed.startsWith('//')) {
        continue;
      }
      final spaceIdx = trimmed.indexOf(RegExp(r'\s'));
      if (spaceIdx == -1) continue;
      final keyStr = trimmed.substring(0, spaceIdx);
      final label = trimmed.substring(spaceIdx).trim();
      if (label.isEmpty) continue;
      final key = _parseKey(keyStr);
      if (key != null) {
        importedRows.add(_Row(value: key.toString(), label: label));
      }
    }
    // Suppress unused variable warning — filter was computed but internal map
    // is not accessible; we re-parsed the file ourselves above.
    filter.length; // keeps the import for analyzer
    if (mounted) setState(() => _rows = importedRows);
  }

  Future<void> _exportFile(L10N l10n) async {
    if (_dialogInFlight) return;
    final config = _buildConfig();
    if (config == null) return;
    final buf = StringBuffer();
    for (final e in config.entries) {
      buf.writeln('${e.value}  ${e.label}');
    }
    if (kIsWeb) {
      // The browser has no save dialog that returns a path: download instead.
      await downloadInBrowser(
        fileName: 'enum_filter.txt',
        bytes: utf8.encode(buf.toString()),
      );
      return;
    }
    setState(() => _dialogInFlight = true);
    final String? path;
    try {
      path = await FilePicker.saveFile(
        // file_picker 12 requires bytes & writes the file; pass empty so it
        // only returns the chosen path and we write via our own service below.
        bytes: Uint8List(0),
        dialogTitle: l10n.namedEnumEditorExport,
        fileName: 'enum_filter.txt',
      );
    } finally {
      if (mounted) setState(() => _dialogInFlight = false);
    }
    if (!mounted || path == null) return;
    await File(path).writeAsString(buf.toString());
  }

  BigInt? _parseKey(String s) {
    final lower = s.toLowerCase();
    if (lower.startsWith('0x')) {
      return BigInt.tryParse(lower.substring(2), radix: 16);
    }
    if (lower.startsWith('0b')) {
      return BigInt.tryParse(lower.substring(2), radix: 2);
    }
    return BigInt.tryParse(s);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final allValid = _rows.every((r) => BigInt.tryParse(r.value) != null);

    return AlertDialog(
      title: Text(l10n.namedEnumEditorTitle),
      content: SizedBox(
        width: 480,
        height: 360,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.namedEnumEditorValueHeader,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: Text(
                    l10n.namedEnumEditorLabelHeader,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 36),
              ],
            ),
            const Divider(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _rows.length,
                itemBuilder: (_, i) => _RowWidget(
                  row: _rows[i],
                  onChanged: (r) => setState(() => _rows[i] = r),
                  onDelete: () => _deleteRow(i),
                  invalidValue: BigInt.tryParse(_rows[i].value) == null,
                  invalidLabel: l10n.namedEnumEditorInvalidValue,
                ),
              ),
            ),
            const Divider(height: 8),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _addRow,
                  tooltip: l10n.namedEnumEditorAddTooltip,
                  iconSize: 18,
                ),
                const Spacer(),
                Flexible(
                  child: TextButton(
                    onPressed: _dialogInFlight ? null : () => _importFile(l10n),
                    child: Text(
                      l10n.namedEnumEditorImport,
                      style: const TextStyle(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: TextButton(
                    onPressed: (allValid && !_dialogInFlight)
                        ? () => _exportFile(l10n)
                        : null,
                    child: Text(
                      l10n.namedEnumEditorExport,
                      style: const TextStyle(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _onCancel,
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: allValid
              ? () => Navigator.of(context).pop(_buildConfig())
              : null,
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }
}

class _Row {
  _Row({required this.value, required this.label});
  String value;
  String label;
}

class _RowWidget extends StatelessWidget {
  const _RowWidget({
    required this.row,
    required this.onChanged,
    required this.onDelete,
    required this.invalidValue,
    required this.invalidLabel,
  });

  final _Row row;
  final ValueChanged<_Row> onChanged;
  final VoidCallback onDelete;
  final bool invalidValue;
  final String invalidLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              initialValue: row.value,
              onChanged: (v) => onChanged(_Row(value: v, label: row.label)),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                errorText: invalidValue ? invalidLabel : null,
              ),
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextFormField(
              initialValue: row.label,
              onChanged: (v) => onChanged(_Row(value: row.value, label: v)),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          IconButton(
            tooltip: l10n.namedEnumEditorDeleteRowTooltip,
            icon: const Icon(Icons.delete_outline, size: 16),
            onPressed: onDelete,
            iconSize: 16,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
