// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show immutable, kIsWeb;
import 'package:flutter/material.dart';
import 'package:wavecrux/core/providers/browser_download_provider.dart';
import 'package:wavecrux/domain/models/named_enum_config.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// One editable row of a named-enum label table.
@immutable
class NamedEnumRow {
  /// Creates a row. [value] is the text the user typed (decimal).
  const NamedEnumRow({required this.value, required this.label});

  /// The value as typed.
  final String value;

  /// The label.
  final String label;

  /// Whether [value] parses as an integer.
  bool get isValid => BigInt.tryParse(value) != null;

  @override
  bool operator ==(Object other) =>
      other is NamedEnumRow && other.value == value && other.label == label;

  @override
  int get hashCode => Object.hash(value, label);
}

/// [config]'s entries as editable rows.
List<NamedEnumRow> namedEnumRowsOf(NamedEnumConfig config) => <NamedEnumRow>[
  for (final e in config.entries)
    NamedEnumRow(value: e.value.toString(), label: e.label),
];

/// [rows] as a config, or null while any value does not parse.
NamedEnumConfig? namedEnumConfigOf(List<NamedEnumRow> rows) {
  final entries = <NamedEnumEntry>[];
  for (final row in rows) {
    final v = BigInt.tryParse(row.value);
    if (v == null) return null;
    entries.add(NamedEnumEntry(value: v, label: row.label));
  }
  return NamedEnumConfig(entries: entries);
}

/// The value-to-label table of a named-enum display format, with GTKWave
/// `.txt` filter import and export.
///
/// One editor in two hosts: the Inspector's signal section (applied on
/// Apply) and the custom translator editor's enum fields (saved with the
/// translator). The host owns the rows: every edit goes back through
/// [onChanged]. An import replaces the rows through [onChanged] too; the host
/// bumps [revision] with it so the fields are rebuilt from the new rows.
class NamedEnumTableForm extends StatefulWidget {
  /// Creates the table for [rows].
  const NamedEnumTableForm({
    required this.rows,
    required this.onChanged,
    this.onReplaced,
    this.revision = 0,
    super.key,
  });

  /// The rows shown.
  final List<NamedEnumRow> rows;

  /// Called with every row after an edit, an added row or a removed one.
  final ValueChanged<List<NamedEnumRow>> onChanged;

  /// Called with the rows of an imported filter file. Null hands them to
  /// [onChanged].
  final ValueChanged<List<NamedEnumRow>>? onReplaced;

  /// Bumped by the host when it replaced [rows] wholesale.
  final int revision;

  @override
  State<NamedEnumTableForm> createState() => _NamedEnumTableFormState();
}

class _NamedEnumTableFormState extends State<NamedEnumTableForm> {
  final List<(TextEditingController, TextEditingController)> _fields = [];
  bool _dialogInFlight = false;

  @override
  void initState() {
    super.initState();
    _rebuildFields();
  }

  @override
  void didUpdateWidget(NamedEnumTableForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.revision != oldWidget.revision ||
        widget.rows.length != _fields.length) {
      _rebuildFields();
    }
  }

  void _rebuildFields() {
    _disposeFields();
    for (final row in widget.rows) {
      _fields.add((
        TextEditingController(text: row.value),
        TextEditingController(text: row.label),
      ));
    }
  }

  void _disposeFields() {
    for (final (value, label) in _fields) {
      value.dispose();
      label.dispose();
    }
    _fields.clear();
  }

  @override
  void dispose() {
    _disposeFields();
    super.dispose();
  }

  List<NamedEnumRow> get _rows => <NamedEnumRow>[
    for (final (value, label) in _fields)
      NamedEnumRow(value: value.text, label: label.text),
  ];

  void _emit() => widget.onChanged(_rows);

  void _addRow() {
    setState(
      () => _fields.add((
        TextEditingController(text: '0'),
        TextEditingController(),
      )),
    );
    _emit();
  }

  void _deleteRow(int index) {
    final (value, label) = _fields.removeAt(index);
    value.dispose();
    label.dispose();
    setState(() {});
    _emit();
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
    if (!mounted) return;
    final imported = parseNamedEnumFilter(content);
    (widget.onReplaced ?? widget.onChanged)(imported);
  }

  Future<void> _exportFile(L10N l10n) async {
    if (_dialogInFlight) return;
    final config = namedEnumConfigOf(_rows);
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
        // file_picker 12 requires bytes and writes the file; pass empty so it
        // only returns the chosen path and the text is written below.
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

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final allValid = _rows.every((r) => r.isValid);
    final headerStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.namedEnumEditorValueHeader,
                  style: headerStyle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: Text(
                  l10n.namedEnumEditorLabelHeader,
                  style: headerStyle,
                ),
              ),
              const SizedBox(width: 36),
            ],
          ),
        ),
        const Divider(height: 8),
        for (var i = 0; i < _fields.length; i++)
          _RowWidget(
            key: ObjectKey(_fields[i].$1),
            value: _fields[i].$1,
            label: _fields[i].$2,
            onChanged: () => setState(_emit),
            onDelete: () => _deleteRow(i),
          ),
        const Divider(height: 8),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _addRow,
              tooltip: l10n.namedEnumEditorAddTooltip,
              iconSize: 18,
            ),
            TextButton(
              onPressed: _dialogInFlight ? null : () => _importFile(l10n),
              child: Text(
                l10n.namedEnumEditorImport,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            TextButton(
              onPressed: (allValid && !_dialogInFlight)
                  ? () => _exportFile(l10n)
                  : null,
              child: Text(
                l10n.namedEnumEditorExport,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The rows of a GTKWave enum filter file: `<value> <label>` per line, the
/// value decimal, `0x` hex or `0b` binary; blank, `#` and `//` lines skipped.
List<NamedEnumRow> parseNamedEnumFilter(String content) {
  final rows = <NamedEnumRow>[];
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
      rows.add(NamedEnumRow(value: key.toString(), label: label));
    }
  }
  return rows;
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

class _RowWidget extends StatelessWidget {
  const _RowWidget({
    required this.value,
    required this.label,
    required this.onChanged,
    required this.onDelete,
    super.key,
  });

  final TextEditingController value;
  final TextEditingController label;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final invalid = BigInt.tryParse(value.text) == null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: value,
              onChanged: (_) => onChanged(),
              decoration: InputDecoration(
                isDense: true,
                hintText: l10n.namedEnumEditorValueHeader,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                errorText: invalid ? l10n.namedEnumEditorInvalidValue : null,
              ),
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextField(
              controller: label,
              onChanged: (_) => onChanged(),
              decoration: InputDecoration(
                isDense: true,
                hintText: l10n.namedEnumEditorLabelHeader,
                contentPadding: const EdgeInsets.symmetric(
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
