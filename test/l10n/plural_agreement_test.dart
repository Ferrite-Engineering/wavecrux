// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Singular agreement for every open-core message that carries an ICU plural.
///
/// `test/static/l10n_house_style_guard_test.dart` already proves that every
/// plural in every locale *has* an `=1` arm. It cannot prove the arm says the
/// right thing — a `=1{{count} signals}` copy-paste passes that guard and
/// still puts "1 signals" on screen. This file closes that gap by asserting
/// the rendered English text, which is the only locale where getting it wrong
/// is grammatically visible.
///
/// The CJK sweep at the bottom is the complementary check: those arms differ
/// from `other` only in the literal numeral, so what matters there is that
/// they resolve at all and leave no `{` behind.
const List<Locale> _locales = [
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('zh'),
  Locale('ja'),
  Locale('ko'),
];

void main() {
  group('English singular agreement', () {
    late L10N l10n;

    setUp(() async {
      l10n = await L10N.delegate.load(const Locale('en'));
    });

    // A .gtkw with one signal, one group or one marker is the ordinary
    // small-import case, and all three counts land in the same result dialog.
    test('the GTKWave import result dialog', () {
      expect(l10n.gtkwImportSignalsMatched(1), '1 signal imported');
      expect(l10n.gtkwImportSignalsMatched(12), '12 signals imported');
      expect(l10n.gtkwImportGroupCount(1), '1 group');
      expect(l10n.gtkwImportGroupCount(3), '3 groups');
      expect(l10n.gtkwImportMarkerCount(1), '1 marker');
      expect(l10n.gtkwImportMarkerCount(2), '2 markers');
    });

    // The panel header counts down as the user narrows the filter, so it
    // passes through 1 on the way to 0 on essentially every search.
    test('the cocotb log panel counts', () {
      expect(l10n.cocotbLogEntryCount(1), '1 entry');
      expect(l10n.cocotbLogEntryCount(40), '40 entries');
      expect(l10n.cocotbLogFilteredCount(1, 1), '1 of 1 entry');
      expect(l10n.cocotbLogFilteredCount(3, 40), '3 of 40 entries');
    });

    // A single-module design generates exactly one mapping.
    test('the RTL source mapping results', () {
      expect(
        l10n.rtlGenerateSuccess(1, 'top'),
        'Generated 1 mapping from top module top.',
      );
      expect(
        l10n.rtlGenerateSuccess(9, 'top'),
        'Generated 9 mappings from top module top.',
      );
      expect(
        l10n.rtlImportAstSuccess(1, 'top'),
        'Imported 1 mapping from top module top.',
      );
    });

    // One connected client / one peer is the *modal* value for both of these,
    // not an edge case — most sessions are a single remote controller.
    test('the Settings connection counters', () {
      expect(
        l10n.settingsRemoteControlClientsConnected(1),
        '1 client connected',
      );
      expect(
        l10n.settingsRemoteControlClientsConnected(2),
        '2 clients connected',
      );
      expect(l10n.settingsCxpPeersConnected(1), '1 peer connected');
      expect(l10n.settingsCxpPeersConnected(4), '4 peers connected');
    });

    test('the memory-pressure snackbar', () {
      expect(
        l10n.memoryPressureWarningSnackbar(1),
        'Memory usage is high — 1 idle signal unloaded',
      );
      expect(
        l10n.memoryPressureWarningSnackbar(6),
        'Memory usage is high — 6 idle signals unloaded',
      );
    });

    // Spoken aloud, so "1 signals" is not just visible but audible.
    test('the accessibility labels', () {
      expect(
        l10n.accessibilityWaveformActive(1, '10 ns'),
        'Waveform viewer. 1 signal. Primary cursor at 10 ns.',
      );
      expect(
        l10n.accessibilityWaveformActive(5, '10 ns'),
        'Waveform viewer. 5 signals. Primary cursor at 10 ns.',
      );
      expect(
        l10n.stageSignalGraphSemanticLabel(1),
        'Signal graph with 1 sample',
      );
      expect(
        l10n.stageSignalGraphSemanticLabel(64),
        'Signal graph with 64 samples',
      );
    });

    // A signal that never left its reset value yields one state and zero
    // transitions — which is exactly the diagnosis the panel exists to make
    // legible, so the degenerate case must read correctly.
    test('the FSM panel stats', () {
      expect(l10n.fsmPanelStats(1, 0), '1 state · 0 transitions');
      expect(l10n.fsmPanelStats(2, 1), '2 states · 1 transition');
      expect(l10n.fsmPanelStats(4, 7), '4 states · 7 transitions');
    });

    test('the decoder auto-bind summary', () {
      expect(
        l10n.decoderAutoBindSummary(1, 0, 0, 1),
        'Found 1 exact, 0 fuzzy, 0 unmatched of 1 binding',
      );
      expect(
        l10n.decoderAutoBindSummary(4, 1, 1, 6),
        'Found 4 exact, 1 fuzzy, 1 unmatched of 6 bindings',
      );
    });
  });

  // Every pluralised message, in every locale, at the count that used to be
  // wrong. A missing `=1` arm, a malformed nested placeholder, or a locale
  // whose ARB was edited without regenerating shows up here as a throw or as
  // a leftover brace.
  group('every pluralised message resolves at a count of one', () {
    for (final locale in _locales) {
      test('$locale', () async {
        final l10n = await L10N.delegate.load(locale);
        final messages = <String>[
          l10n.gtkwImportSignalsMatched(1),
          l10n.gtkwImportGroupCount(1),
          l10n.gtkwImportMarkerCount(1),
          l10n.cocotbLogEntryCount(1),
          l10n.cocotbLogFilteredCount(1, 1),
          l10n.rtlGenerateSuccess(1, 'top'),
          l10n.rtlImportAstSuccess(1, 'top'),
          l10n.settingsRemoteControlClientsConnected(1),
          l10n.settingsCxpPeersConnected(1),
          l10n.memoryPressureWarningSnackbar(1),
          l10n.accessibilityWaveformActive(1, '10 ns'),
          l10n.stageSignalGraphSemanticLabel(1),
          l10n.fsmPanelStats(1, 1),
          l10n.decoderAutoBindSummary(1, 0, 0, 1),
        ];
        for (final message in messages) {
          expect(message, isNotEmpty);
          expect(
            message,
            isNot(contains('{')),
            reason: 'an unresolved ICU placeholder survived in $locale',
          );
          expect(message, isNot(contains('(s)')));
        }
      });
    }
  });
}
