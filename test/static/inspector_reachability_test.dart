// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The Inspector is the one editor for a decoder's configuration, a signal
// row's display format and an FSM signal's state names, and every way in
// opens it with focus: a decoder row's Configure, the transaction table's
// Configure, the decoder picker, a value row's Properties, Configure Format
// and Edit Enum Labels, and a signal row's Annotate FSM States. Each
// opener is a line of wiring a green widget suite does not prove is reached,
// so this pins them against the sources, along with the per-tab bindings the
// Inspector's state needs and the absence of the dialogs it replaced.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path is missing');
  return file.readAsStringSync();
}

/// [source] from [start] to the next occurrence of [end] (or the end).
String _span(String source, String start, String end) {
  final from = source.indexOf(start);
  expect(from, isNonNegative, reason: 'no `$start`');
  final to = source.indexOf(end, from + start.length);
  return source.substring(from, to < 0 ? source.length : to);
}

void main() {
  test('the right dock mounts the Inspector as an on-demand tab', () {
    final docks = _read('lib/features/viewer/widgets/side_docks.dart');
    expect(docks, contains('const WaveCruxInspectorPanel()'));
    expect(docks, contains('kRightDockTabInspector'));
    expect(docks, contains('panelState.inspectorVisible'));
  });

  test('every opener selects its object and opens with focus', () {
    final openers = _read('lib/features/viewer/inspector_openers.dart');
    final open = _span(openers, 'void openWaveCruxInspector(', '\n}\n');
    expect(open, contains('inspectedObjectProvider.notifier'));
    expect(open, contains('read(inspectorControllerProvider).open()'));
    // The phone host: the same panel, in a sheet, under the tab's container.
    expect(openers, contains('showModalBottomSheet'));
    expect(openers, contains('UncontrolledProviderScope('));
    expect(openers, contains('const WaveCruxInspectorPanel()'));
    expect(
      _span(openers, 'void startNewDecoderInInspector(', '\n}\n'),
      contains('openWaveCruxInspector('),
    );
  });

  test(
    'a decoder row and the transaction table Configure in the Inspector',
    () {
      expect(
        _span(
          _read('lib/features/decoders/widgets/decoder_list_entry.dart'),
          'void _configureDecoder(',
          '\n  }\n',
        ),
        contains('InspectedDecoder(decoder.id)'),
      );
      expect(
        _span(
          _read('lib/features/decoders/widgets/transaction_table_panel.dart'),
          'onConfigureDecoder:',
          'onSearchChanged:',
        ),
        allOf(
          contains('openWaveCruxInspector('),
          contains('InspectedDecoder(id)'),
        ),
      );
    },
  );

  test('the decoder picker starts a new decoder in the Inspector', () {
    expect(
      _read('lib/features/decoders/widgets/decoder_picker_dialog.dart'),
      contains('startNewDecoderInInspector('),
    );
  });

  test("a value row's Properties, Configure Format and Edit Enum Labels "
      'inspect that row', () {
    final row = _read('lib/features/viewer/widgets/value_column_row.dart');
    expect(row, contains('l10n.valueColumnProperties'));
    final arm = _span(row, '(selected == _kConfigureFormat ||', '} else if');
    expect(arm, contains('_kEditEnumLabels'));
    expect(arm, contains('_kProperties'));
    expect(arm, contains('InspectedSignal(entry.id)'));
  });

  test("a signal row's Annotate FSM States inspects that row", () {
    final panel = _read('lib/features/viewer/widgets/signal_list_panel.dart');
    expect(
      _span(panel, 'Future<void> _annotateFsm(', '\n  }\n'),
      contains('annotateFsmStatesInInspector('),
    );
    expect(panel, contains('_annotateFsm(context, entry.id, signalRef)'));
    final openers = _read('lib/features/viewer/inspector_openers.dart');
    expect(
      _span(openers, 'Future<void> annotateFsmStatesInInspector(', '\n}\n'),
      allOf(
        contains('openWaveCruxInspector('),
        contains('InspectedSignal(entryId)'),
      ),
    );
    expect(
      _read('lib/features/viewer/widgets/wavecrux_inspector_panel.dart'),
      contains('fsmStateNamesInspectorSection('),
    );
  });

  test("a signal name's Properties inspects that row, and its Display "
      'Format opens the shared format menu', () {
    final panel = _read('lib/features/viewer/widgets/signal_list_panel.dart');
    final properties = _span(
      panel,
      'case _RegularAction.properties:',
      'case _RegularAction.',
    );
    expect(properties, contains('openWaveCruxInspector('));
    expect(properties, contains('InspectedSignal(widget.entry.id)'));
    expect(
      _span(
        panel,
        'case _RegularAction.displayFormat:',
        'case _RegularAction.',
      ),
      contains('showDisplayFormatMenu('),
    );
    expect(
      _read('lib/features/viewer/widgets/value_column_row.dart'),
      contains('showDisplayFormatMenu('),
    );
  });

  test('the Inspector state is per-tab', () {
    final overrides = _read('lib/services/tabs/wavecrux_tab_overrides.dart');
    for (final provider in const <String>[
      'inspectedObjectProvider',
      'inspectorControllerProvider',
      'waveformPaneFocusNodeProvider',
      'decoderDraftsProvider',
      'signalFormatDraftsProvider',
      'fsmStateNameDraftsProvider',
      'fsmKnownStateIdsProvider',
    ]) {
      expect(
        overrides,
        contains('$provider.overrideWith('),
        reason: '$provider must be re-bound per tab',
      );
    }
  });

  test('the custom translator editor hosts the label table inline', () {
    final editor = _read(
      'lib/features/settings/widgets/custom_translator_editor_dialog.dart',
    );
    expect(editor, contains('NamedEnumTableForm('));
  });

  test('no second path: the four dialogs are gone', () {
    for (final path in const <String>[
      'lib/features/decoders/widgets/decoder_config_dialog.dart',
      'lib/shared/widgets/q_format_config_dialog.dart',
      'lib/shared/widgets/named_enum_editor_dialog.dart',
      'lib/features/viewer/widgets/fsm_annotate_dialog.dart',
    ]) {
      expect(File(path).existsSync(), isFalse, reason: path);
    }
    final offenders = <String>[
      for (final entity in Directory('lib').listSync(recursive: true))
        if (entity is File &&
            entity.path.endsWith('.dart') &&
            RegExp(
              r'\b(DecoderConfigDialog|QFormatConfigDialog|NamedEnumEditorDialog|FsmAnnotateDialog)\b',
            ).hasMatch(entity.readAsStringSync()))
          entity.path,
    ];
    expect(offenders, isEmpty);
  });
}
