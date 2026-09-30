// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/domain/interfaces/translator.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_signal_snapshot.dart';
import 'package:wavecrux/features/stage/providers/stage_signal_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/translator_registry.dart';
import 'package:wavecrux/services/value_format/builtin_value_translator.dart';

/// Pure logic: format a snapshot for the bus readout's main numeric display.
///
/// Returns a `(text, isError)` record. `isError` is true when the value is
/// X / Z, in which case the renderer should style the text in an error color.
({String text, bool isError}) formatBusReadout(
  StageSignalSnapshot snapshot, {
  required DisplayFormat format,
  Translator translator = const BuiltinValueTranslator(),
}) {
  if (!snapshot.hasValue) return (text: '–', isError: false);
  if (snapshot.hasX) return (text: 'X', isError: true);
  if (snapshot.hasZ) return (text: 'Z', isError: true);
  final width = snapshot.bitWidth == 0 ? 1 : snapshot.bitWidth;
  return (
    text: translator
        .translate(
          TranslationRequest(
            rawValue: snapshot.rawValue,
            bitWidth: width,
            format: format,
          ),
        )
        .text,
    isError: false,
  );
}

/// Definition for the bus-readout primitive.
class BusReadoutStageWidget extends StageWidget {
  const BusReadoutStageWidget();

  static const String widgetId = 'bus_readout';

  @override
  String get id => widgetId;

  @override
  String get displayName => 'Bus Readout';

  @override
  String? get displayNameKey => 'stageBusReadoutDisplayName';

  @override
  String get description =>
      'Large monospace numeric readout for vector signals.';

  @override
  StageWidgetCategory get category => StageWidgetCategory.primitive;

  @override
  List<SignalBinding> get requiredSignals => const [
    SignalBinding(
      name: 'value',
      description: 'Vector signal to display',
    ),
  ];

  @override
  (double, double) get defaultSize => (220, 80);

  @override
  (double, double) get minSize => (120, 48);
}

/// Renders a [BusReadoutStageWidget] instance.
class BusReadoutStageRenderer extends ConsumerWidget {
  const BusReadoutStageRenderer({
    required this.instance,
    this.format = DisplayFormat.hexadecimal,
    super.key,
  });

  final StageInstance instance;
  final DisplayFormat format;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final binding = instance.signalBindings['value'];
    final snapshot = ref.watch(stageBoundSignalProvider(binding));
    final translator = ref.watch(translatorRegistryProvider).resolve();
    final result = formatBusReadout(
      snapshot,
      format: format,
      translator: translator,
    );

    final prefix = switch (format) {
      DisplayFormat.hexadecimal => '0x',
      DisplayFormat.binary => '0b',
      DisplayFormat.octal => '0o',
      _ => '',
    };
    final fullText = result.isError ? result.text : '$prefix${result.text}';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0E1A24),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white24),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Center(
        child: Semantics(
          label: l10n.stageBusReadoutSemanticLabel(fullText),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              fullText,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 28,
                fontWeight: FontWeight.w600,
                color: result.isError
                    ? const Color(0xFFE53935)
                    : const Color(0xFF80DEEA),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
