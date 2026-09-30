// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/decoders/widgets/decoder_config_dialog.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

import '../../../helpers/product_telemetry_config.dart';

// ── fixtures ──────────────────────────────────────────────────────────────────

const _spiDef = DecoderDefinition(
  id: 'spi',
  displayName: 'SPI',
  description: 'Serial Peripheral Interface',
  requiredSignals: [
    SignalBinding(name: 'sclk', description: 'Clock', bitWidth: 1),
    SignalBinding(name: 'mosi', description: 'Master Out', bitWidth: 1),
  ],
  optionalSignals: [
    SignalBinding(name: 'cs', description: 'Chip Select', bitWidth: 1),
  ],
);

Variable _v(String fullPath, {int bitWidth = 1}) {
  final lastDot = fullPath.lastIndexOf('.');
  final name = lastDot < 0 ? fullPath : fullPath.substring(lastDot + 1);
  final scope = lastDot < 0 ? '' : fullPath.substring(0, lastDot);
  return Variable(
    name: name,
    varType: VarType.wire,
    direction: VarDirection.unknown,
    signalRef: fullPath,
    scopePath: scope,
    bitWidth: bitWidth,
  );
}

Map<String, Variable> _signals(List<Variable> vars) => {
  for (final v in vars) v.signalRef: v,
};

const _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('ja'),
  Locale('ko'),
];

Widget _wrap({
  required Map<String, Variable> signalMap,
  required bool autoBindOnOpen,
  void Function(ProviderContainer container)? onContainer,
  Locale? locale,
}) => ProviderScope(
  overrides: [productTelemetryConfig],
  child: Builder(
    builder: (context) {
      onContainer?.call(ProviderScope.containerOf(context));
      return MaterialApp(
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        locale: locale,
        home: Scaffold(
          body: DecoderConfigDialog(
            definition: _spiDef,
            signalMap: signalMap,
            autoBindOnOpen: autoBindOnOpen,
          ),
        ),
      );
    },
  ),
);

void main() {
  group('DecoderConfigDialog autoBindOnOpen — locale sweep', () {
    for (final locale in _locales) {
      testWidgets('renders in $locale without exceptions', (tester) async {
        final signals = _signals([_v('tb.sclk'), _v('tb.mosi'), _v('tb.cs')]);
        await tester.pumpWidget(
          _wrap(
            signalMap: signals,
            autoBindOnOpen: true,
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('DecoderConfigDialog autoBindOnOpen prefill', () {
    testWidgets('pre-fills confident bindings on open', (tester) async {
      final signals = _signals([_v('tb.sclk'), _v('tb.mosi'), _v('tb.cs')]);
      late ProviderContainer container;
      await tester.pumpWidget(
        _wrap(
          signalMap: signals,
          autoBindOnOpen: true,
          onContainer: (c) => container = c,
        ),
      );
      await tester.pumpAndSettle();

      // All three dropdowns display their auto-bound signal path without any
      // user interaction.
      expect(find.text('tb.sclk'), findsOneWidget);
      expect(find.text('tb.mosi'), findsOneWidget);
      expect(find.text('tb.cs'), findsOneWidget);

      // And the prefill survives straight to activation.
      final l10n = L10N.of(tester.element(find.byType(DecoderConfigDialog)));
      await tester.tap(find.text(l10n.decoderConfigAddButton));
      await tester.pumpAndSettle();

      final actives = container.read(activeDecodersProvider);
      expect(actives, hasLength(1));
      expect(actives.first.config.signalBindings['sclk'], 'tb.sclk');
      expect(actives.first.config.signalBindings['mosi'], 'tb.mosi');
      expect(actives.first.config.signalBindings['cs'], 'tb.cs');
    });

    testWidgets('unresolvable bindings are left empty', (tester) async {
      // Only sclk is present; mosi/cs have no plausible candidate.
      final signals = _signals([_v('tb.sclk')]);
      await tester.pumpWidget(
        _wrap(signalMap: signals, autoBindOnOpen: true),
      );
      await tester.pumpAndSettle();

      expect(find.text('tb.sclk'), findsOneWidget);

      // Submitting must still hit required-binding validation for mosi.
      final l10n = L10N.of(tester.element(find.byType(DecoderConfigDialog)));
      await tester.tap(find.text(l10n.decoderConfigAddButton));
      await tester.pumpAndSettle();
      expect(find.text(l10n.decoderConfigValidationError), findsOneWidget);
    });

    testWidgets('default (autoBindOnOpen false) does not prefill', (
      tester,
    ) async {
      final signals = _signals([_v('tb.sclk'), _v('tb.mosi')]);
      await tester.pumpWidget(
        _wrap(signalMap: signals, autoBindOnOpen: false),
      );
      await tester.pumpAndSettle();

      // The dropdowns are unset — the paths only exist inside the (closed)
      // dropdown menus, not as selected values.
      expect(find.text('tb.sclk'), findsNothing);
      expect(find.text('tb.mosi'), findsNothing);
    });
  });
}
