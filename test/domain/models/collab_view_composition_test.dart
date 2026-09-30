// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/models/bitfield_translator_config.dart';
import 'package:wavecrux/domain/models/collab_view_composition.dart';
import 'package:wavecrux/domain/models/custom_translator_def.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/persisted_decoder.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_panel_config.dart';
import 'package:wavecrux/domain/models/stage_workspace_state.dart';

void main() {
  group('CollabViewComposition', () {
    SignalGroup signals() => SignalGroup(
      entries: [
        SignalEntry.signal(
          id: 'sig0',
          signalRef: 'top.clk',
          signalPath: 'top.clk',
          displayName: 'clk',
          format: DisplayFormat.binary,
        ),
      ],
    );

    const decoder = PersistedDecoder(
      decoderId: 'spi',
      instanceNumber: 1,
      config: DecoderConfig(signalBindings: {'mosi': 'top.spi.mosi'}),
    );

    const translator = CustomTranslatorDef(
      name: 'reg',
      config: BitfieldTranslatorConfig(),
    );

    const stage = StageWorkspaceState(
      panels: [
        StagePanelConfig(
          id: 'p0',
          name: 'Panel',
          instances: [StageInstance(id: 's0', widgetId: 'led')],
        ),
      ],
    );

    CollabViewComposition full() => CollabViewComposition(
      displayedSignals: signals(),
      decoders: const [decoder],
      translators: const [translator],
      stageWorkspace: stage,
      fsmTargetPath: 'top.fsm.state',
      panelVisibility: const CollabPanelVisibility(stageViewVisible: true),
    );

    test('defaults are empty / closed', () {
      const empty = CollabViewComposition();
      expect(empty.displayedSignals.entries, isEmpty);
      expect(empty.decoders, isEmpty);
      expect(empty.translators, isEmpty);
      expect(empty.stageWorkspace.panels, isEmpty);
      expect(empty.fsmTargetPath, isNull);
      expect(empty.panelVisibility, const CollabPanelVisibility());
    });

    test('value equality across all dimensions', () {
      expect(full(), full());
      expect(full().hashCode, full().hashCode);
    });

    test('inequality when any dimension differs', () {
      final base = full();
      expect(base == base.copyWith(decoders: const []), isFalse);
      expect(base == base.copyWith(translators: const []), isFalse);
      expect(
        base == base.copyWith(stageWorkspace: const StageWorkspaceState()),
        isFalse,
      );
      expect(base == base.copyWith(fsmTargetPath: 'other'), isFalse);
      expect(
        base ==
            base.copyWith(
              panelVisibility: const CollabPanelVisibility(),
            ),
        isFalse,
      );
    });

    test('copyWith clearFsmTargetPath wins over positional value', () {
      final cleared = full().copyWith(
        fsmTargetPath: 'ignored',
        clearFsmTargetPath: true,
      );
      expect(cleared.fsmTargetPath, isNull);
    });
  });

  group('CollabPanelVisibility', () {
    test('defaults: tree + value column open, transaction + stage closed', () {
      const v = CollabPanelVisibility();
      expect(v.signalTreeVisible, isTrue);
      expect(v.valueColumnVisible, isTrue);
      expect(v.transactionViewVisible, isFalse);
      expect(v.stageViewVisible, isFalse);
    });

    test('equality + copyWith', () {
      const a = CollabPanelVisibility();
      expect(a, const CollabPanelVisibility());
      expect(a == a.copyWith(stageViewVisible: true), isFalse);
      expect(
        a.copyWith(transactionViewVisible: true).transactionViewVisible,
        isTrue,
      );
    });
  });

  group('CollabCompositionDegradation', () {
    test('none has no missing references', () {
      expect(CollabCompositionDegradation.none.hasMissing, isFalse);
    });

    test('hasMissing when any list is non-empty', () {
      expect(
        const CollabCompositionDegradation(
          missingSignalPaths: ['top.x'],
        ).hasMissing,
        isTrue,
      );
      expect(
        const CollabCompositionDegradation(
          missingDecoderIds: ['axi'],
        ).hasMissing,
        isTrue,
      );
      expect(
        const CollabCompositionDegradation(
          missingWidgetIds: ['gauge'],
        ).hasMissing,
        isTrue,
      );
    });

    test('value equality', () {
      const a = CollabCompositionDegradation(
        missingSignalPaths: ['top.x'],
        missingDecoderIds: ['axi'],
      );
      const b = CollabCompositionDegradation(
        missingSignalPaths: ['top.x'],
        missingDecoderIds: ['axi'],
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == CollabCompositionDegradation.none, isFalse);
    });
  });
}
