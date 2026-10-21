// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/models/bitfield_translator_config.dart';
import 'package:wavecrux/domain/models/custom_translator_def.dart';
import 'package:wavecrux/domain/models/named_enum_config.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/widgets/confirm_discard_changes.dart';
import 'package:wavecrux/shared/widgets/named_enum_table_form.dart';

/// Authoring dialog for a single [CustomTranslatorDef] (declarative bit-field
/// translator). Returns the edited definition, or null when cancelled.
class CustomTranslatorEditorDialog extends StatefulWidget {
  const CustomTranslatorEditorDialog({required this.initial, super.key});

  /// The definition being edited, or null when authoring a new one.
  final CustomTranslatorDef? initial;

  static Future<CustomTranslatorDef?> show(
    BuildContext context, {
    CustomTranslatorDef? initial,
  }) => showCruxDialog<CustomTranslatorDef>(
    context: context,
    // Editor dialogs hold in-progress user input: closing must be a
    // deliberate act (Cancel / Save, or Escape), never a stray scrim click —
    // the suite-wide dialog rule.
    barrierDismissible: false,
    builder: (_) => CustomTranslatorEditorDialog(initial: initial),
  );

  @override
  State<CustomTranslatorEditorDialog> createState() =>
      _CustomTranslatorEditorDialogState();
}

class _EditableField {
  _EditableField({
    required this.name,
    required this.hiBit,
    required this.loBit,
    required this.format,
    this.subConfig,
  }) : enumRows = namedEnumRowsOf(
         subConfig != null && format == DisplayFormat.namedEnum
             ? NamedEnumConfig.fromMap(subConfig)
             : const NamedEnumConfig(),
       );

  String name;
  int hiBit;
  int loBit;
  DisplayFormat format;
  Map<String, Object?>? subConfig;

  /// The enum label table as edited, for a named-enum field. Kept as typed
  /// (a value that does not parse yet included); [subConfig] follows it
  /// whenever every value parses.
  List<NamedEnumRow> enumRows;

  bool get enumRowsValid => enumRows.every((r) => r.isValid);
}

class _CustomTranslatorEditorDialogState
    extends State<CustomTranslatorEditorDialog> {
  late final TextEditingController _nameController;
  late final List<_EditableField> _fields;
  late final String _initialName;
  late final List<_EditableField> _initialFields;
  String? _nameError;

  // Per-field formats offered in the editor. Kept intentionally small — the
  // common radix set plus the enum-table format (which opens a sub-editor).
  static const List<DisplayFormat> _fieldFormats = [
    DisplayFormat.hexadecimal,
    DisplayFormat.unsignedDecimal,
    DisplayFormat.signedDecimal,
    DisplayFormat.binary,
    DisplayFormat.namedEnum,
  ];

  @override
  void initState() {
    super.initState();
    _initialName = widget.initial?.name ?? '';
    _nameController = TextEditingController(text: _initialName);
    List<_EditableField> fieldsFromInitial() => [
      for (final f in widget.initial?.config.fields ?? const <BitFieldSpec>[])
        _EditableField(
          name: f.name,
          hiBit: f.hiBit,
          loBit: f.loBit,
          format: f.format,
          subConfig: f.subConfig,
        ),
    ];
    _fields = fieldsFromInitial();
    // Independent snapshot for the dirty check — the rows in [_fields]
    // are mutated in place as the user edits.
    _initialFields = fieldsFromInitial();
  }

  /// Whether the form differs from the values it opened with. Clean
  /// forms close without a prompt; dirty ones confirm first (suite
  /// unsaved-changes canon — see [confirmDiscardChanges]).
  bool get _isDirty {
    if (_nameController.text != _initialName) return true;
    if (_fields.length != _initialFields.length) return true;
    for (var i = 0; i < _fields.length; i++) {
      final a = _fields[i];
      final b = _initialFields[i];
      if (a.name != b.name ||
          a.hiBit != b.hiBit ||
          a.loBit != b.loBit ||
          a.format != b.format ||
          !mapEquals(a.subConfig, b.subConfig)) {
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

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _addField() {
    setState(() {
      _fields.add(
        _EditableField(
          name: '',
          hiBit: 0,
          loBit: 0,
          format: DisplayFormat.hexadecimal,
        ),
      );
    });
  }

  /// The enum table of [field] was edited inline: keep the rows as typed and,
  /// once every value parses, the field's config with them.
  void _onEnumRows(_EditableField field, List<NamedEnumRow> rows) {
    setState(() {
      field.enumRows = rows;
      final config = namedEnumConfigOf(rows);
      if (config != null) field.subConfig = config.toMap();
    });
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(
        () => _nameError = L10N.of(context).customTranslatorNameRequired,
      );
      return;
    }
    // An enum table with a value that does not parse says so in its row and
    // is not saved.
    if (_fields.any(
      (f) => f.format == DisplayFormat.namedEnum && !f.enumRowsValid,
    )) {
      return;
    }
    final def = CustomTranslatorDef(
      name: name,
      config: BitfieldTranslatorConfig(
        fields: [
          for (final f in _fields)
            BitFieldSpec(
              name: f.name.trim(),
              hiBit: f.hiBit,
              loBit: f.loBit,
              format: f.format,
              subConfig: f.subConfig,
            ),
        ],
      ),
    );
    Navigator.of(context).pop(def);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    // Escape asks to discard unsaved edits, as Cancel does.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_onCancel());
      },
      child: _buildDialog(l10n),
    );
  }

  Widget _buildDialog(L10N l10n) {
    return CruxDialog(
      title: widget.initial == null
          ? l10n.customTranslatorAddTitle
          : l10n.customTranslatorEditTitle,
      width: 520,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CruxFormRow(
            label: l10n.customTranslatorNameLabel,
            child: TextField(
              controller: _nameController,
              decoration: InputDecoration(errorText: _nameError),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.customTranslatorFieldsHeader,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _fields.length; i++)
            _buildFieldRow(context, l10n, _fields[i]),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addField,
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.customTranslatorAddField),
            ),
          ),
        ],
      ),
      actions: [
        CruxDialogAction(
          label: l10n.customTranslatorCancel,
          onPressed: _onCancel,
        ),
        CruxDialogAction(
          label: l10n.customTranslatorSave,
          role: CruxDialogActionRole.primary,
          onPressed: _save,
        ),
      ],
    );
  }

  Widget _buildFieldRow(
    BuildContext context,
    L10N l10n,
    _EditableField field,
  ) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TextFormField(
              initialValue: field.name,
              decoration: InputDecoration(
                isDense: true,
                hintText: l10n.customTranslatorFieldName,
              ),
              onChanged: (v) => field.name = v,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 56,
            child: TextFormField(
              initialValue: field.hiBit.toString(),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                isDense: true,
                labelText: l10n.customTranslatorFieldHiBit,
              ),
              onChanged: (v) => field.hiBit = int.tryParse(v) ?? field.hiBit,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 56,
            child: TextFormField(
              initialValue: field.loBit.toString(),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                isDense: true,
                labelText: l10n.customTranslatorFieldLoBit,
              ),
              onChanged: (v) => field.loBit = int.tryParse(v) ?? field.loBit,
            ),
          ),
          const SizedBox(width: 6),
          CruxPopUpButton<DisplayFormat>(
            value: field.format,
            items: [
              for (final f in _fieldFormats)
                CruxPopUpItem<DisplayFormat>(
                  value: f,
                  label: _formatLabel(l10n, f),
                ),
            ],
            onChanged: (v) => setState(() => field.format = v),
            width: 132,
            dense: true,
            semanticLabel: l10n.customTranslatorFieldFormat,
          ),
          IconButton(
            tooltip: l10n.customTranslatorRemoveField,
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _fields.remove(field)),
          ),
        ],
      ),
    );
    if (field.format != DisplayFormat.namedEnum) return row;
    // A named-enum field's label table, inline: the same editor the
    // Inspector hosts for a signal row, not a dialog over this one.
    return Column(
      key: ObjectKey(field),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        row,
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 24, bottom: 8),
          child: NamedEnumTableForm(
            rows: field.enumRows,
            onChanged: (rows) => _onEnumRows(field, rows),
          ),
        ),
      ],
    );
  }

  String _formatLabel(L10N l10n, DisplayFormat fmt) => switch (fmt) {
    DisplayFormat.binary => l10n.displayFormatBinary,
    DisplayFormat.hexadecimal => l10n.displayFormatHexadecimal,
    DisplayFormat.octal => l10n.displayFormatOctal,
    DisplayFormat.unsignedDecimal => l10n.displayFormatUnsignedDecimal,
    DisplayFormat.signedDecimal => l10n.displayFormatSignedDecimal,
    DisplayFormat.ascii => l10n.displayFormatAscii,
    DisplayFormat.ieee754Single => l10n.displayFormatIeee754Single,
    DisplayFormat.ieee754Double => l10n.displayFormatIeee754Double,
    DisplayFormat.fixedPointQ => l10n.displayFormatFixedPointQ,
    DisplayFormat.signedMagnitude => l10n.displayFormatSignedMagnitude,
    DisplayFormat.grayCode => l10n.displayFormatGrayCode,
    DisplayFormat.namedEnum => l10n.displayFormatNamedEnum,
  };
}
