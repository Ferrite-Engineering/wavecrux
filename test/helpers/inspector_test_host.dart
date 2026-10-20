// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/inspector_openers.dart';
import 'package:wavecrux/features/viewer/providers/inspector_providers.dart';
import 'package:wavecrux/features/viewer/widgets/wavecrux_inspector_panel.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';

import 'product_telemetry_config.dart';

/// A one-bit (or [bitWidth]-bit) wire at [fullPath], its signalRef the path
/// itself unless [ref] is given.
Variable inspectorTestVar(String fullPath, {int bitWidth = 1, String? ref}) {
  final lastDot = fullPath.lastIndexOf('.');
  return Variable(
    name: lastDot < 0 ? fullPath : fullPath.substring(lastDot + 1),
    varType: VarType.wire,
    direction: VarDirection.unknown,
    signalRef: ref ?? fullPath,
    scopePath: lastDot < 0 ? '' : fullPath.substring(0, lastDot),
    bitWidth: bitWidth,
  );
}

/// [vars] keyed by signalRef, as `signalVariablesByPathProvider` lists them.
Map<String, Variable> inspectorTestSignals(List<Variable> vars) => {
  for (final v in vars) '${v.signalRef}@${v.fullPath}': v,
};

/// Registers [definition] for the test (its factory is never run: no
/// waveform is loaded, so decoding is a no-op) and removes it after.
void registerInspectorTestDecoder(DecoderDefinition definition) {
  DecoderRegistry.instance.register(
    definition,
    (_) => throw UnimplementedError('inspector test factory'),
  );
  addTearDown(() => DecoderRegistry.instance.unregister(definition.id));
}

/// Pumps the Inspector beside a stand-in waveform pane, in a container that
/// stands in for a tab, and returns the container.
///
/// The waveform pane is a focusable box on the tab's
/// `waveformPaneFocusNodeProvider` node, so Escape's return of focus is
/// observable.
Future<ProviderContainer> pumpInspectorHost(
  WidgetTester tester, {
  Map<String, Variable> signals = const <String, Variable>{},
  List<Override> overrides = const <Override>[],
  Locale? locale,
  Size surface = const Size(1000, 1000),
  bool showInspector = true,
  ProviderContainer? reuse,
  bool inSheet = false,
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final container =
      reuse ??
      ProviderContainer(
        overrides: <Override>[
          productTelemetryConfig,
          // The dock tab, as on the desktop; Android, the `flutter test`
          // platform, would host it in a bottom sheet.
          inspectorInBottomSheetProvider.overrideWithValue(inSheet),
          signalVariablesByPathProvider.overrideWith((ref) => signals),
          ...overrides,
        ],
      );
  if (reuse == null) addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: Row(
            children: <Widget>[
              Expanded(
                child: Focus(
                  focusNode: container.read(waveformPaneFocusNodeProvider),
                  // Named as the real pane's canvas is, so a focus walk
                  // reads it as a stop with a name.
                  child: Semantics(
                    label: 'Waveform',
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              SizedBox(
                width: 460,
                child: showInspector
                    ? const WaveCruxInspectorPanel()
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Starts a new decoder of [definition] in the Inspector the host shows,
/// as the decoder picker does.
Future<void> startNewDecoder(
  WidgetTester tester,
  ProviderContainer container,
  DecoderDefinition definition, {
  bool autoBind = false,
  Map<String, Variable>? autoBindSignals,
}) async {
  startNewDecoderInInspector(
    tester.element(find.byType(Scaffold)),
    container,
    definition: definition,
    autoBind: autoBind,
    autoBindSignals: autoBindSignals,
  );
  await tester.pumpAndSettle();
}

/// Presses Escape.
Future<void> pressEscape(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
}
