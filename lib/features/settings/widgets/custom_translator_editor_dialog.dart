// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/models/bitfield_translator_config.dart';
import 'package:wavecrux/domain/models/custom_translator_def.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/widgets/confirm_discard_changes.dart';
import 'package:wavecrux/shared/widgets/named_enum_editor_dialog.dart';

/// Authoring dialog for a single [CustomTranslatorDef] (declarative bit-field
/// translator). Returns the edited definition, or null when cancelled.
class CustomTranslatorEditorDialog extends StatefulWidget {
  const CustomTranslatorEditorDialog({required this.initial, super.key});

  /// The definition being edited, or null when authoring a new one.
  final CustomTranslatorDef? initial;

  static Future<CustomTranslatorDef?> show(
    BuildContext context, {
    CustomTranslatorDef? initial,
  }) => showDialog<CustomTranslatorDef>(
    context: context,
    // Editor dialogs hold in-progress user input: closing must be a
    // deliberate act (Cancel / Save), never a stray scrim click — the
    // suite-wide dialog rule. Note this
    // also disables Escape (Flutter routes DismissIntent through the
    // barrier flag).
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
  });

  String name;
  int hiBit;
  int loBit;
  DisplayFormat format;
  Map<String, Object?>? subConfig;
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

  Future<void> _editEnumTable(_EditableField field) async {
    final updated = await NamedEnumEditorDialog.show(
      context,
      config: field.subConfig,
    );
    // This dialog can be removed from under the enum editor it opened (a
    // route cleared programmatically), so the answer may find it disposed.
    if (updated != null && mounted) setState(() => field.subConfig = updated);
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(
        () => _nameError = L10N.of(context).customTranslatorNameRequired,
      );
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
    return AlertDialog(
      title: Text(
        widget.initial == null
            ? l10n.customTranslatorAddTitle
            : l10n.customTranslatorEditTitle,
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: l10n.customTranslatorNameLabel,
                  errorText: _nameError,
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
        ),
      ),
      actions: [
        TextButton(
          onPressed: _onCancel,
          child: Text(l10n.customTranslatorCancel),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(l10n.customTranslatorSave),
        ),
      ],
    );
  }

  Widget _buildFieldRow(
    BuildContext context,
    L10N l10n,
    _EditableField field,
  ) {
    return Padding(
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
          DropdownButton<DisplayFormat>(
            value: field.format,
            isDense: true,
            onChanged: (v) {
              if (v != null) setState(() => field.format = v);
            },
            items: [
              for (final f in _fieldFormats)
                DropdownMenuItem(value: f, child: Text(_formatLabel(l10n, f))),
            ],
          ),
          if (field.format == DisplayFormat.namedEnum)
            IconButton(
              tooltip: l10n.valueColumnEditEnumLabels,
              icon: const Icon(Icons.list_alt, size: 18),
              onPressed: () => _editEnumTable(field),
            ),
          IconButton(
            tooltip: l10n.customTranslatorRemoveField,
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _fields.remove(field)),
          ),
        ],
      ),
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
