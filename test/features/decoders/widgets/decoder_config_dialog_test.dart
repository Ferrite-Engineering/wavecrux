// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/decoders/widgets/decoder_config_dialog.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

// ── fixtures ──────────────────────────────────────────────────────────────────

const _spiDef = DecoderDefinition(
  id: 'spi',
  displayName: 'SPI',
  description: 'Serial Peripheral Interface',
  requiredSignals: [
    SignalBinding(name: 'sclk', description: 'Clock'),
    SignalBinding(name: 'mosi', description: 'Master Out'),
  ],
  optionalSignals: [
    SignalBinding(name: 'cs', description: 'Chip Select'),
  ],
);

// ── helpers ───────────────────────────────────────────────────────────────────

Widget _wrap(DecoderDefinition definition) => ProviderScope(
  overrides: [
    signalVariablesMapProvider.overrideWith((ref) => {}),
  ],
  child: MaterialApp(
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: Scaffold(body: DecoderConfigDialog(definition: definition)),
  ),
);

Future<void> _pumpViaShow(
  WidgetTester tester,
  DecoderDefinition definition,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        signalVariablesMapProvider.overrideWith((ref) => {}),
      ],
      child: MaterialApp(
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                DecoderConfigDialog.show(context, definition: definition),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('DecoderConfigDialog — locale sweep', () {
    for (final locale in ['en', 'zh', 'ja', 'ko']) {
      testWidgets('renders without exception in $locale', (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              signalVariablesMapProvider.overrideWith((ref) => {}),
            ],
            child: MaterialApp(
              locale: Locale(locale),
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: const Scaffold(
                body: DecoderConfigDialog(definition: _spiDef),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('DecoderConfigDialog — static structure', () {
    testWidgets('shows decoder name in title', (tester) async {
      await tester.pumpWidget(_wrap(_spiDef));
      await tester.pumpAndSettle();
      final l10n = L10N.of(tester.element(find.byType(DecoderConfigDialog)));
      expect(
        find.text(l10n.decoderConfigTitle(_spiDef.displayName)),
        findsOneWidget,
      );
    });

    testWidgets('shows signal bindings section header', (tester) async {
      await tester.pumpWidget(_wrap(_spiDef));
      await tester.pumpAndSettle();
      final l10n = L10N.of(tester.element(find.byType(DecoderConfigDialog)));
      expect(
        find.text(l10n.decoderConfigSignalBindingsSection),
        findsOneWidget,
      );
    });

    testWidgets('shows required signal names', (tester) async {
      await tester.pumpWidget(_wrap(_spiDef));
      await tester.pumpAndSettle();
      expect(find.text('sclk'), findsOneWidget);
      expect(find.text('mosi'), findsOneWidget);
    });

    testWidgets('shows required badge for each required signal', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(_spiDef));
      await tester.pumpAndSettle();
      final l10n = L10N.of(tester.element(find.byType(DecoderConfigDialog)));
      expect(find.text(l10n.decoderConfigRequiredLabel), findsNWidgets(2));
    });

    testWidgets('shows Add and Cancel buttons', (tester) async {
      await tester.pumpWidget(_wrap(_spiDef));
      await tester.pumpAndSettle();
      final l10n = L10N.of(tester.element(find.byType(DecoderConfigDialog)));
      expect(find.text(l10n.decoderConfigAddButton), findsOneWidget);
      expect(find.text(l10n.decoderConfigCancelButton), findsOneWidget);
    });

    testWidgets('hides parameters section when definition has no parameters', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(_spiDef));
      await tester.pumpAndSettle();
      final l10n = L10N.of(tester.element(find.byType(DecoderConfigDialog)));
      expect(find.text(l10n.decoderConfigParametersSection), findsNothing);
    });
  });

  group('DecoderConfigDialog — validation', () {
    testWidgets('shows validation error when Add pressed with no bindings', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(_spiDef));
      await tester.pumpAndSettle();
      final l10n = L10N.of(tester.element(find.byType(DecoderConfigDialog)));
      await tester.tap(find.text(l10n.decoderConfigAddButton));
      await tester.pumpAndSettle();
      expect(find.text(l10n.decoderConfigValidationError), findsOneWidget);
    });

    testWidgets('does not add decoder when required bindings missing', (
      tester,
    ) async {
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            signalVariablesMapProvider.overrideWith((ref) => {}),
          ],
          child: Builder(
            builder: (ctx) {
              container = ProviderScope.containerOf(ctx);
              return const MaterialApp(
                localizationsDelegates: L10N.localizationsDelegates,
                supportedLocales: L10N.supportedLocales,
                home: Scaffold(body: DecoderConfigDialog(definition: _spiDef)),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = L10N.of(tester.element(find.byType(DecoderConfigDialog)));
      await tester.tap(find.text(l10n.decoderConfigAddButton));
      await tester.pumpAndSettle();
      expect(container.read(activeDecodersProvider), isEmpty);
    });
  });

  group('DecoderConfigDialog — Cancel', () {
    testWidgets('Cancel closes the dialog without validation', (tester) async {
      await _pumpViaShow(tester, _spiDef);
      final l10n = L10N.of(tester.element(find.byType(DecoderConfigDialog)));
      await tester.tap(find.text(l10n.decoderConfigCancelButton));
      await tester.pumpAndSettle();
      expect(find.byType(DecoderConfigDialog), findsNothing);
    });
  });

  group('DecoderConfigDialog — show() helper', () {
    testWidgets('show() opens the dialog', (tester) async {
      await _pumpViaShow(tester, _spiDef);
      expect(find.byType(DecoderConfigDialog), findsOneWidget);
    });
  });

  group('DecoderConfigDialog — signal dropdown display', () {
    // Build a minimal Variable for testing.
    Variable makeVar(
      String scopePath,
      String name,
      String ref, {
      int? bitWidth,
    }) => Variable(
      name: name,
      varType: VarType.wire,
      direction: VarDirection.unknown,
      signalRef: ref,
      scopePath: scopePath,
      bitWidth: bitWidth,
    );

    testWidgets('dropdown shows fullPath not numeric ref', (tester) async {
      final signalMap = {
        '0': makeVar('spi_test', 'clk', '0', bitWidth: 1),
        '1': makeVar('spi_test', 'data', '1', bitWidth: 1),
      };
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            signalVariablesMapProvider.overrideWith((ref) => signalMap),
          ],
          child: const MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(body: DecoderConfigDialog(definition: _spiDef)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open the first dropdown to reveal its items.
      await tester.tap(find.byType(DropdownButton<String>).first);
      await tester.pumpAndSettle();

      // fullPaths should appear in items; raw numeric refs should not.
      expect(find.text('spi_test.clk'), findsWidgets);
      expect(find.text('spi_test.data'), findsWidgets);
      expect(find.text('0'), findsNothing);
      expect(find.text('1'), findsNothing);
    });

    testWidgets('dropdown items are sorted alphabetically by fullPath', (
      tester,
    ) async {
      final signalMap = {
        '0': makeVar('top', 'zzz', '0', bitWidth: 1),
        '1': makeVar('top', 'aaa', '1', bitWidth: 1),
        '2': makeVar('top', 'mmm', '2', bitWidth: 1),
      };
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            signalVariablesMapProvider.overrideWith((ref) => signalMap),
          ],
          child: const MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(body: DecoderConfigDialog(definition: _spiDef)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open the first dropdown (sclk binding)
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
          .toList();

      expect(items, ['top.aaa', 'top.mmm', 'top.zzz']);
    });

    testWidgets('bit-width filter hides signals with wrong width', (
      tester,
    ) async {
      const defWithBitWidth = DecoderDefinition(
        id: 'spi',
        displayName: 'SPI',
        description: 'SPI',
        requiredSignals: [
          SignalBinding(name: 'sclk', description: 'Clock', bitWidth: 1),
        ],
      );

      final signalMap = {
        '0': makeVar('top', 'clk', '0', bitWidth: 1),
        '1': makeVar('top', 'bus', '1', bitWidth: 8),
      };
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            signalVariablesMapProvider.overrideWith((ref) => signalMap),
          ],
          child: const MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(
              body: DecoderConfigDialog(definition: defWithBitWidth),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open the sclk dropdown
      await tester.tap(find.byType(DropdownButton<String>).first);
      await tester.pumpAndSettle();

      expect(find.text('top.clk'), findsWidgets);
      expect(find.text('top.bus'), findsNothing);
    });
  });

  group('DecoderConfigDialog — reconfigure (issue #47 regression)', () {
    Variable makeVar(
      String scopePath,
      String name,
      String ref, {
      int? bitWidth,
    }) => Variable(
      name: name,
      varType: VarType.wire,
      direction: VarDirection.unknown,
      signalRef: ref,
      scopePath: scopePath,
      bitWidth: bitWidth,
    );

    // A definition whose required pin constrains bit width, so the binding
    // dropdown filters candidate signals by width — the path that produced
    // the DropdownButton "exactly one item with value X" assertion when an
    // existing binding referenced a now-filtered signal.
    const widthConstrainedDef = DecoderDefinition(
      id: 'spi',
      displayName: 'SPI',
      description: 'SPI',
      requiredSignals: [
        SignalBinding(name: 'sclk', description: 'Clock', bitWidth: 1),
      ],
    );

    Widget editModeHost({
      required Map<String, Variable> signalMap,
      required DecoderConfig initialConfig,
    }) => ProviderScope(
      overrides: [
        signalVariablesMapProvider.overrideWith((ref) => signalMap),
      ],
      child: MaterialApp(
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: DecoderConfigDialog(
            definition: widthConstrainedDef,
            instanceId: 'spi-0',
            instanceNumber: 1,
            initialConfig: initialConfig,
            signalMap: signalMap,
          ),
        ),
      ),
    );

    testWidgets(
      'reopening edit mode does not throw when the bound signal is excluded '
      'by the bit-width filter',
      (tester) async {
        // The existing binding points at an 8-bit signal, but the pin is
        // constrained to 1 bit, so sortedRefs excludes it. Pre-fix, the
        // DropdownButton value matched zero items and asserted.
        final signalMap = {
          '0': makeVar('top', 'clk', '0', bitWidth: 1),
          '7': makeVar('top', 'data_bus', '7', bitWidth: 8),
        };
        await tester.pumpWidget(
          editModeHost(
            signalMap: signalMap,
            initialConfig: const DecoderConfig(signalBindings: {'sclk': '7'}),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(DecoderConfigDialog), findsOneWidget);
        // The current (filtered-out) binding stays visible and selected so the
        // user can see and change it rather than silently losing it.
        expect(find.byType(DropdownButton<String>), findsOneWidget);
        expect(find.text('top.data_bus'), findsWidgets);
      },
    );

    testWidgets(
      'reopening edit mode does not throw when the bound signal is absent '
      'from the current trace',
      (tester) async {
        // The bound ref no longer exists in signalMap (e.g. the waveform was
        // reloaded with a different hierarchy). Value matched zero items pre-fix.
        final signalMap = {
          '0': makeVar('top', 'clk', '0', bitWidth: 1),
        };
        await tester.pumpWidget(
          editModeHost(
            signalMap: signalMap,
            initialConfig: const DecoderConfig(
              signalBindings: {'sclk': 'stale_ref'},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(DropdownButton<String>), findsOneWidget);
        // No fullPath available for the stale ref, so the raw ref is shown.
        expect(find.text('stale_ref'), findsWidgets);
      },
    );
  });

  group('DecoderConfigDialog — dirty-cancel guard', () {
    Variable makeVar(
      String scopePath,
      String name,
      String ref, {
      int? bitWidth,
    }) => Variable(
      name: name,
      varType: VarType.wire,
      direction: VarDirection.unknown,
      signalRef: ref,
      scopePath: scopePath,
      bitWidth: bitWidth,
    );

    Future<void> pumpViaShowWithSignals(WidgetTester tester) async {
      final signalMap = {
        '0': makeVar('top', 'clk', '0', bitWidth: 1),
        '1': makeVar('top', 'mosi', '1', bitWidth: 1),
      };
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            signalVariablesMapProvider.overrideWith((ref) => signalMap),
          ],
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    DecoderConfigDialog.show(context, definition: _spiDef),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('dirty cancel prompts to discard; keep editing stays open', (
      tester,
    ) async {
      await pumpViaShowWithSignals(tester);

      // Dirty the form by binding the first signal.
      await tester.tap(find.byType(DropdownButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('top.clk').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);

      // "Keep editing" returns to the editor with the binding intact.
      await tester.tap(
        find.byKey(const ValueKey('editorDiscardConfirmKeepEditing')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.byType(DecoderConfigDialog), findsOneWidget);
      expect(find.text('top.clk'), findsWidgets);

      // "Discard" closes the editor.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('editorDiscardConfirmDiscard')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DecoderConfigDialog), findsNothing);
    });

    testWidgets('clean cancel closes without a prompt', (tester) async {
      await pumpViaShowWithSignals(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.byType(DecoderConfigDialog), findsNothing);
    });
  });
}
