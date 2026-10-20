// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_dock/crux_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/decoder_parameter_type.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/domain/models/decoder_parameter.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/decoders/widgets/decoder_config_section.dart';
import 'package:wavecrux/features/viewer/inspector_openers.dart';
import 'package:wavecrux/features/viewer/providers/inspector_providers.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

import '../../../helpers/inspector_test_host.dart';

// ── fixtures ──────────────────────────────────────────────────────────────────

const _spiDef = DecoderDefinition(
  id: 'spi',
  displayName: 'SPI',
  description: 'Serial Peripheral Interface',
  requiredSignals: [
    SignalBinding(name: 'sclk', description: 'Clock'),
    SignalBinding(name: 'mosi', description: 'Master Out'),
  ],
  optionalSignals: [SignalBinding(name: 'cs', description: 'Chip Select')],
);

const _spiWidthDef = DecoderDefinition(
  id: 'spi',
  displayName: 'SPI',
  description: 'SPI',
  requiredSignals: [
    SignalBinding(name: 'sclk', description: 'Clock', bitWidth: 1),
    SignalBinding(name: 'mosi', description: 'Master Out', bitWidth: 1),
  ],
  optionalSignals: [
    SignalBinding(name: 'cs', description: 'Chip Select', bitWidth: 1),
  ],
);

const _uartDef = DecoderDefinition(
  id: 'uart_test',
  displayName: 'UART',
  description: 'UART',
  requiredSignals: [SignalBinding(name: 'rx', description: 'Receive')],
  parameters: [
    DecoderParameter(
      name: 'baud',
      type: DecoderParameterType.integer,
      defaultValue: 9600,
      description: 'Baud rate',
    ),
  ],
);

Map<String, Variable> _signals(Map<String, int> widthByPath) =>
    inspectorTestSignals([
      for (final e in widthByPath.entries)
        inspectorTestVar(e.key, bitWidth: e.value),
    ]);

/// Counts decoder runs instead of decoding.
class _CountingDecoders extends ActiveDecodersNotifier {
  int runs = 0;

  @override
  Future<void> decodeAll() async => runs++;
}

L10N _l10n(WidgetTester tester) =>
    L10N.of(tester.element(find.byType(DecoderConfigSection)));

Finder get _apply => find.descendant(
  of: find.byType(CruxInspectorApplyBar),
  matching: find.byType(FilledButton),
);

Finder get _revert => find.descendant(
  of: find.byType(CruxInspectorApplyBar),
  matching: find.byType(TextButton),
);

Future<ProviderContainer> _newDecoder(
  WidgetTester tester, {
  DecoderDefinition definition = _spiDef,
  Map<String, Variable> signals = const {},
  bool autoBind = false,
  Locale? locale,
  List<Override> overrides = const [],
}) async {
  registerInspectorTestDecoder(definition);
  final container = await pumpInspectorHost(
    tester,
    signals: signals,
    locale: locale,
    overrides: overrides,
  );
  await startNewDecoder(tester, container, definition, autoBind: autoBind);
  return container;
}

/// The Inspector on an existing decoder of [definition] with [config].
Future<(ProviderContainer, String)> _existingDecoder(
  WidgetTester tester, {
  required DecoderDefinition definition,
  required DecoderConfig config,
  Map<String, Variable> signals = const {},
  List<Override> overrides = const [],
}) async {
  registerInspectorTestDecoder(definition);
  final container = await pumpInspectorHost(
    tester,
    signals: signals,
    overrides: overrides,
  );
  final id = container
      .read(activeDecodersProvider.notifier)
      .addDecoder(definition.id, config);
  container.read(inspectedObjectProvider.notifier).select(InspectedDecoder(id));
  await tester.pumpAndSettle();
  return (container, id);
}

void main() {
  group('locale sweep', () {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('zh'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('renders a new decoder in ${locale.toLanguageTag()}', (
        tester,
      ) async {
        await _newDecoder(
          tester,
          definition: _uartDef,
          signals: _signals({'tb.rx': 1}),
          autoBind: true,
          locale: locale,
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(DecoderConfigSection), findsOneWidget);
      });
    }
  });

  group('a new decoder', () {
    testWidgets('is headed, lists its bindings and offers Add and Cancel', (
      tester,
    ) async {
      final container = await _newDecoder(tester);
      final l10n = _l10n(tester);
      expect(find.text(l10n.decoderConfigTitle('SPI')), findsOneWidget);
      expect(
        find.text(l10n.decoderConfigSignalBindingsSection),
        findsOneWidget,
      );
      expect(find.text('sclk'), findsOneWidget);
      expect(find.text('mosi'), findsOneWidget);
      expect(
        find.textContaining(l10n.decoderConfigRequiredLabel),
        findsNWidgets(2),
      );
      expect(find.text(l10n.decoderConfigAddButton), findsOneWidget);
      expect(find.text(l10n.decoderConfigCancelButton), findsOneWidget);
      expect(find.text(l10n.decoderConfigParametersSection), findsNothing);
      // Revealed in the right dock.
      final layout = container.read(panelLayoutProvider);
      expect(layout.inspectorVisible, isTrue);
      expect(layout.effectiveRightDockTab, kRightDockTabInspector);
    });

    testWidgets('Add with a required binding missing says so and adds '
        'nothing', (tester) async {
      final container = await _newDecoder(tester);
      final l10n = _l10n(tester);
      await tester.tap(_apply);
      await tester.pumpAndSettle();
      expect(find.text(l10n.decoderConfigValidationError), findsOneWidget);
      expect(container.read(activeDecodersProvider), isEmpty);
    });

    testWidgets('Cancel drops the draft and empties the Inspector', (
      tester,
    ) async {
      final container = await _newDecoder(tester);
      final l10n = _l10n(tester);
      await tester.tap(find.text(l10n.decoderConfigCancelButton));
      await tester.pumpAndSettle();
      expect(container.read(decoderDraftsProvider), isEmpty);
      expect(container.read(inspectedObjectProvider), isNull);
      expect(find.text(l10n.inspectorEmpty), findsOneWidget);
    });

    testWidgets('Add runs the decoders once and shows the new instance', (
      tester,
    ) async {
      final counting = _CountingDecoders();
      final container = await _newDecoder(
        tester,
        definition: _spiWidthDef,
        signals: _signals({'tb.sclk': 1, 'tb.mosi': 1}),
        autoBind: true,
        overrides: [activeDecodersProvider.overrideWith(() => counting)],
      );
      final l10n = _l10n(tester);
      await tester.tap(_apply);
      await tester.pumpAndSettle();
      final actives = container.read(activeDecodersProvider);
      expect(actives, hasLength(1));
      expect(actives.single.config.signalBindings['sclk'], 'tb.sclk');
      expect(counting.runs, 1);
      expect(
        container.read(inspectedObjectProvider),
        InspectedDecoder(actives.single.id),
      );
      expect(find.text(l10n.inspectorDecoderTitle('SPI', 1)), findsOneWidget);
      expect(container.read(decoderDraftsProvider), isEmpty);
    });
  });

  group('auto-bind prefill', () {
    testWidgets('pre-fills confident bindings and they reach activation', (
      tester,
    ) async {
      final container = await _newDecoder(
        tester,
        definition: _spiWidthDef,
        signals: _signals({'tb.sclk': 1, 'tb.mosi': 1, 'tb.cs': 1}),
        autoBind: true,
      );
      expect(find.text('tb.sclk'), findsOneWidget);
      expect(find.text('tb.mosi'), findsOneWidget);
      expect(find.text('tb.cs'), findsOneWidget);
      await tester.tap(_apply);
      await tester.pumpAndSettle();
      final config = container.read(activeDecodersProvider).single.config;
      expect(config.signalBindings['cs'], 'tb.cs');
    });

    testWidgets('unresolvable bindings are left empty', (tester) async {
      await _newDecoder(
        tester,
        definition: _spiWidthDef,
        signals: _signals({'tb.sclk': 1}),
        autoBind: true,
      );
      expect(find.text('tb.sclk'), findsOneWidget);
      await tester.tap(_apply);
      await tester.pumpAndSettle();
      expect(
        find.text(_l10n(tester).decoderConfigValidationError),
        findsOneWidget,
      );
    });

    testWidgets('Apply Decoder to Selection offers only the selection', (
      tester,
    ) async {
      registerInspectorTestDecoder(_spiWidthDef);
      final all = _signals({'tb.sclk': 1, 'tb.mosi': 1, 'tb.other': 1});
      final container = await pumpInspectorHost(tester, signals: all);
      await startNewDecoder(
        tester,
        container,
        _spiWidthDef,
        autoBind: true,
        autoBindSignals: signalsByFullPath(
          _signals({'tb.sclk': 1, 'tb.mosi': 1}),
        ),
      );
      expect(find.text('tb.sclk'), findsOneWidget);
      await tester.tap(find.byType(DropdownButton<String>).last);
      await tester.pumpAndSettle();
      expect(find.text('tb.other'), findsNothing);
    });

    testWidgets('without auto-bind nothing is pre-filled', (tester) async {
      await _newDecoder(
        tester,
        definition: _spiWidthDef,
        signals: _signals({'tb.sclk': 1, 'tb.mosi': 1}),
      );
      expect(find.text('tb.sclk'), findsNothing);
      expect(find.text('tb.mosi'), findsNothing);
    });
  });

  group('signal pickers', () {
    testWidgets('list full paths, sorted, never the raw ref', (tester) async {
      await _newDecoder(
        tester,
        signals: inspectorTestSignals([
          inspectorTestVar('top.zzz', ref: '0'),
          inspectorTestVar('top.aaa', ref: '1'),
          inspectorTestVar('top.mmm', ref: '2'),
        ]),
      );
      await tester.tap(find.byType(DropdownButton<String>).first);
      await tester.pumpAndSettle();
      final items = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(DropdownMenuItem<String>),
              matching: find.byType(Text),
            ),
          )
          .map((t) => t.data ?? '')
          .where((s) => s.startsWith('top.'))
          .toSet()
          .toList();
      expect(items, ['top.aaa', 'top.mmm', 'top.zzz']);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('a bit-width filter hides signals of the wrong width', (
      tester,
    ) async {
      await _newDecoder(
        tester,
        definition: _spiWidthDef,
        signals: _signals({'top.clk': 1, 'top.bus': 8}),
      );
      await tester.tap(find.byType(DropdownButton<String>).first);
      await tester.pumpAndSettle();
      expect(find.text('top.clk'), findsWidgets);
      expect(find.text('top.bus'), findsNothing);
    });

    testWidgets('a width_param binding filters by the width the parameter '
        'sets', (tester) async {
      const def = DecoderDefinition(
        id: 'plugin.pipe',
        displayName: 'PIPE',
        description: 'PIPE',
        requiredSignals: [
          SignalBinding(
            name: 'data',
            description: 'Data',
            bitWidth: 64,
            widthParam: 'data_width',
          ),
        ],
        parameters: [
          DecoderParameter(
            name: 'data_width',
            type: DecoderParameterType.integer,
            defaultValue: 16,
            description: 'Data width',
          ),
        ],
      );
      await _newDecoder(
        tester,
        definition: def,
        signals: _signals({'top.pipe16': 16, 'top.pipe64': 64}),
      );
      await tester.tap(find.byType(DropdownButton<String>).first);
      await tester.pumpAndSettle();
      expect(find.text('top.pipe16'), findsWidgets);
      expect(find.text('top.pipe64'), findsNothing);
    });
  });

  group('an existing decoder (issue #47 regression)', () {
    testWidgets('shows a binding the width filter excludes without throwing', (
      tester,
    ) async {
      await _existingDecoder(
        tester,
        definition: _spiWidthDef,
        config: const DecoderConfig(signalBindings: {'sclk': '7'}),
        signals: inspectorTestSignals([
          inspectorTestVar('top.clk', ref: '0'),
          inspectorTestVar('top.data_bus', bitWidth: 8, ref: '7'),
        ]),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('top.data_bus'), findsWidgets);
    });

    testWidgets('shows a binding the trace no longer has by its raw ref', (
      tester,
    ) async {
      await _existingDecoder(
        tester,
        definition: _spiWidthDef,
        config: const DecoderConfig(signalBindings: {'sclk': 'stale_ref'}),
        signals: inspectorTestSignals([inspectorTestVar('top.clk', ref: '0')]),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('stale_ref'), findsWidgets);
    });
  });

  group('drafts', () {
    testWidgets('an edit is held when another decoder is chosen, and Update '
        'runs the decoders once', (tester) async {
      final counting = _CountingDecoders();
      final (container, id) = await _existingDecoder(
        tester,
        definition: _uartDef,
        config: const DecoderConfig(
          signalBindings: {'rx': 'tb.rx'},
          parameters: {'baud': 9600},
        ),
        signals: _signals({'tb.rx': 1}),
        overrides: [activeDecodersProvider.overrideWith(() => counting)],
      );
      final l10n = _l10n(tester);
      // Clean: nothing to apply.
      expect(tester.widget<FilledButton>(_apply).onPressed, isNull);

      await tester.enterText(find.byType(TextFormField), '115200');
      await tester.pumpAndSettle();
      expect(counting.runs, 0, reason: 'never per keystroke');

      // Another decoder is chosen: the edit holds this one on screen.
      final other = container
          .read(activeDecodersProvider.notifier)
          .addDecoder(_uartDef.id, const DecoderConfig(signalBindings: {}));
      container
          .read(inspectedObjectProvider.notifier)
          .select(InspectedDecoder(other));
      await tester.pumpAndSettle();
      final heading = l10n.inspectorDecoderTitle('UART', 1);
      expect(find.text(l10n.inspectorHeldMessage(heading)), findsOneWidget);

      await tester.tap(_apply);
      await tester.pumpAndSettle();
      final updated = container
          .read(activeDecodersProvider)
          .firstWhere((d) => d.id == id);
      expect(updated.config.parameters['baud'], 115200);
      expect(counting.runs, 1);
      // Applied: the Inspector follows the selection again.
      expect(find.text(l10n.inspectorDecoderTitle('UART', 2)), findsOneWidget);
    });

    testWidgets('Revert restores the stored values', (tester) async {
      final (container, id) = await _existingDecoder(
        tester,
        definition: _uartDef,
        config: const DecoderConfig(
          signalBindings: {'rx': 'tb.rx'},
          parameters: {'baud': 9600},
        ),
        signals: _signals({'tb.rx': 1}),
      );
      await tester.enterText(find.byType(TextFormField), '4800');
      await tester.pumpAndSettle();
      await tester.tap(_revert);
      await tester.pumpAndSettle();
      expect(container.read(decoderDraftsProvider), isEmpty);
      expect(find.text('9600'), findsOneWidget);
      expect(
        container
            .read(activeDecodersProvider)
            .firstWhere((d) => d.id == id)
            .config
            .parameters['baud'],
        9600,
      );
    });

    testWidgets('a new decoder survives the dock showing another tab', (
      tester,
    ) async {
      final container = await _newDecoder(
        tester,
        definition: _spiWidthDef,
        signals: _signals({'tb.sclk': 1, 'tb.mosi': 1}),
        autoBind: true,
      );
      await pumpInspectorHost(tester, reuse: container, showInspector: false);
      container
          .read(inspectedObjectProvider.notifier)
          .select(const InspectedSignal('nowhere'));
      await pumpInspectorHost(tester, reuse: container);
      // Still held, still pre-filled.
      expect(find.text('tb.sclk'), findsOneWidget);
      expect(find.byType(DecoderConfigSection), findsOneWidget);
    });

    testWidgets('Escape returns focus to the waveform pane and keeps the '
        'draft', (tester) async {
      final container = await _newDecoder(
        tester,
        definition: _spiWidthDef,
        signals: _signals({'tb.sclk': 1, 'tb.mosi': 1}),
      );
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<DecoderConfigSection>(),
        isNotNull,
        reason: 'open() focuses the first control',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus,
        container.read(waveformPaneFocusNodeProvider),
      );
      expect(container.read(decoderDraftsProvider), isNotEmpty);
    });
  });
}
