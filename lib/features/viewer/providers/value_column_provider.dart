// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/interfaces/translator.dart';
import 'package:wavecrux/domain/models/bitfield_translator_config.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/translated_field.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/process_filter_provider.dart';
import 'package:wavecrux/features/viewer/providers/translate_filter_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/plugins/translator_registry.dart';

part 'value_column_provider.g.dart';

/// The formatted value and raw bit-string for a signal at cursor time.
@immutable
class SignalValue {
  const SignalValue({
    required this.formatted,
    required this.rawValue,
    this.isFiltered = false,
    this.isProcessFiltered = false,
    this.fields = const [],
    this.colorArgb,
  });

  /// Human-readable formatted string (e.g., `"0xFF"`, `"10110010"`).
  ///
  /// When [isFiltered] or [isProcessFiltered] is true this is the translated
  /// label rather than a numeric format.
  final String formatted;

  /// Raw VCD bit-string before formatting (e.g., `"11111111"`).
  final String rawValue;

  /// True when a static translate filter was applied and produced a label.
  final bool isFiltered;

  /// True when a process filter was applied and produced a cached label.
  final bool isProcessFiltered;

  /// Structured subfields produced by a struct/bitfield translator, empty for
  /// flat values. When non-empty the value column renders one expandable child
  /// row per field, aligned under the parent signal.
  final List<TranslatedField> fields;

  /// Optional ARGB colour hint (`0xAARRGGBB`) the translator attached to this
  /// value (e.g. the packed-pixel translator's decoded colour). The value
  /// column renders it as a [ValueColorSwatch] beside the value. `null` when
  /// the translator emitted no colour. Never carried for filter labels.
  final int? colorArgb;

  /// True if any bit in [rawValue] is unknown (X).
  bool get hasX => rawValue.toLowerCase().contains('x');

  /// True if any bit is high-impedance (Z) and none are unknown (X).
  bool get hasZ => !hasX && rawValue.toLowerCase().contains('z');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SignalValue &&
          formatted == other.formatted &&
          rawValue == other.rawValue &&
          isFiltered == other.isFiltered &&
          isProcessFiltered == other.isProcessFiltered &&
          colorArgb == other.colorArgb &&
          _fieldsEqual(fields, other.fields);

  @override
  int get hashCode => Object.hash(
    formatted,
    rawValue,
    isFiltered,
    isProcessFiltered,
    colorArgb,
    Object.hashAll(fields),
  );

  static bool _fieldsEqual(List<TranslatedField> a, List<TranslatedField> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() =>
      'SignalValue(formatted: $formatted, raw: $rawValue, '
      'isFiltered: $isFiltered, isProcessFiltered: $isProcessFiltered)';
}

/// Derived provider returning the formatted value for every loaded signal
/// at the primary cursor time (or the waveform start when no cursor is set).
///
/// Keys are [SignalEntry.signalRef] strings. Non-signal entries and unloaded
/// signals are omitted. Recomputes on cursor move, signal list change, or
/// waveform source change.
///
/// **Process filter integration:** for signals with an assigned process filter,
/// this provider reads the *cached* translated label from
/// [processFilterProvider] and simultaneously fires an asynchronous
/// re-translation (fire-and-forget) so the cache stays current as the cursor
/// moves. The two-step flow means the first render after a cursor move shows
/// the previous cached label, which is replaced once the new translation
/// arrives — identical to GTKWave's own process filter behavior.
@Riverpod(
  dependencies: [
    SignalGroupsNotifier,
    WaveformSourceNotifier,
    CursorStateNotifier,
    signalVariablesMap,
    TranslateFilterNotifier,
    ProcessFilterNotifier,
  ],
)
Map<String, SignalValue> signalValuesAtCursor(Ref ref) {
  final signalGroup = ref.watch(signalGroupsProvider);
  final cursorState = ref.watch(cursorStateProvider);
  final sourceAsync = ref.watch(waveformSourceProvider);
  final variablesMap = ref.watch(signalVariablesMapProvider);
  final filtersMap = ref.watch(translateFilterProvider);
  final processFiltersState = ref.watch(processFilterProvider);

  final source = sourceAsync.value;
  if (source == null) return const {};

  final time = cursorState.primaryCursorTime ?? source.startTime;
  final registry = ref.watch(translatorRegistryProvider);
  final result = <String, SignalValue>{};

  // Grab the notifier reference once for fire-and-forget translation calls.
  final processFilterNotifier = ref.read(processFilterProvider.notifier);

  void processEntries(List<SignalEntry> entries) {
    for (final entry in entries) {
      switch (entry.kind) {
        case SignalEntryKind.signal:
          final signalRef = entry.signalRef!;
          if (!source.isSignalLoaded(signalRef)) break;
          final rawValue = source.valueAt(signalRef, time);
          if (rawValue == null) break;
          final variable = variablesMap[signalRef];
          final bitWidth = variable?.bitWidth ?? 1;

          // Strip the VCD 'b' prefix before lookup.
          final rawBits = rawValue.toLowerCase().replaceFirst(RegExp('^b'), '');

          // Priority 1 — process filter (async, uses cached label).
          if (processFiltersState.containsKey(signalRef)) {
            // Kick off async translation; state update triggers a rebuild.
            unawaited(
              processFilterNotifier.translateValue(signalRef, rawValue),
            );
            final cachedLabel = processFiltersState[signalRef];
            if (cachedLabel != null) {
              result[signalRef] = SignalValue(
                formatted: cachedLabel,
                rawValue: rawValue,
                isProcessFiltered: true,
              );
              break;
            }
            // No cache yet — fall through to static filter / formatter.
          }

          // Priority 2 — static translate filter.
          final filter = filtersMap[signalRef];
          final translated = filter?.translate(rawBits);

          // A per-signal custom-translator binding (e.g. a bitfield or RISC-V
          // disassembly translator) records its id in translatorConfig; the
          // registry resolves it, falling back to the built-in formatter.
          final tr = registry.translate(
            TranslationRequest(
              rawValue: rawValue,
              bitWidth: bitWidth,
              format: entry.format,
              config: entry.translatorConfig,
            ),
            translatorId:
                entry.translatorConfig?[kTranslatorIdConfigKey] as String?,
          );
          result[signalRef] = SignalValue(
            formatted: translated ?? tr.text,
            rawValue: rawValue,
            isFiltered: translated != null,
            fields: translated != null ? const [] : tr.fields,
            colorArgb: translated != null ? null : tr.colorArgb,
          );
        case SignalEntryKind.group:
          processEntries(entry.children);
        case SignalEntryKind.separator:
        case SignalEntryKind.comment:
          break;
      }
    }
  }

  processEntries(signalGroup.entries);
  return result;
}

/// Per-signal version of [signalValuesAtCursor].
///
/// Returns the formatted [SignalValue] for [signalRef] at the primary cursor
/// time, or null when the signal is not loaded / source is missing / value
/// lookup returns null.
///
/// This family provider is the cursor-scrub hot path: it lets row widgets
/// in [SignalListPanel] and [ValueColumnPanel] subscribe to *their own*
/// signal's value rather than to a global Map of every loaded signal. With
/// large files (1000+ signals) the global form forces 1000+ FFI `valueAt`
/// calls and 1000+ row rebuilds on every cursor frame, which blocks the
/// UI thread and makes the cursor visibly lag the pointer. The per-signal
/// form, combined with lazy list building (`ListView.builder`,
/// `ReorderableListView.builder`), restricts work to the ~20–40 rows
/// actually visible on screen.
///
/// [format] is passed in rather than re-derived from the signal entry so
/// this provider does not need to watch [signalGroupsProvider]
/// (which would invalidate every per-signal computation any time any
/// entry changed).
@Riverpod(
  dependencies: [
    WaveformSourceNotifier,
    CursorStateNotifier,
    signalVariablesMap,
    TranslateFilterNotifier,
    ProcessFilterNotifier,
  ],
)
SignalValue? signalValueAtCursor(
  Ref ref,
  String signalRef,
  DisplayFormat format,
  Map<String, Object?>? translatorConfig,
) {
  final cursorState = ref.watch(cursorStateProvider);
  final sourceAsync = ref.watch(waveformSourceProvider);
  final variablesMap = ref.watch(signalVariablesMapProvider);
  final filtersMap = ref.watch(translateFilterProvider);
  final processFiltersState = ref.watch(processFilterProvider);

  final source = sourceAsync.value;
  if (source == null) return null;
  if (!source.isSignalLoaded(signalRef)) return null;

  final time = cursorState.primaryCursorTime ?? source.startTime;
  final rawValue = source.valueAt(signalRef, time);
  if (rawValue == null) return null;

  final variable = variablesMap[signalRef];
  final bitWidth = variable?.bitWidth ?? 1;
  final rawBits = rawValue.toLowerCase().replaceFirst(RegExp('^b'), '');

  // Priority 1 — process filter (async; uses cached label).
  if (processFiltersState.containsKey(signalRef)) {
    final processFilterNotifier = ref.read(processFilterProvider.notifier);
    unawaited(processFilterNotifier.translateValue(signalRef, rawValue));
    final cachedLabel = processFiltersState[signalRef];
    if (cachedLabel != null) {
      return SignalValue(
        formatted: cachedLabel,
        rawValue: rawValue,
        isProcessFiltered: true,
      );
    }
    // No cache yet — fall through to static filter / formatter.
  }

  // Priority 2 — static translate filter.
  final filter = filtersMap[signalRef];
  final translated = filter?.translate(rawBits);

  final registry = ref.watch(translatorRegistryProvider);
  final tr = registry.translate(
    TranslationRequest(
      rawValue: rawValue,
      bitWidth: bitWidth,
      format: format,
      config: translatorConfig,
    ),
    translatorId: translatorConfig?[kTranslatorIdConfigKey] as String?,
  );
  return SignalValue(
    formatted: translated ?? tr.text,
    rawValue: rawValue,
    isFiltered: translated != null,
    fields: translated != null ? const [] : tr.fields,
    colorArgb: translated != null ? null : tr.colorArgb,
  );
}

/// Shared vertical scroll offset for the waveform viewer panels.
///
/// [WaveformViewCenter] writes this whenever its signal-list or canvas scroll
/// controllers move. [ValueColumnPanel] reads it to stay vertically aligned.
@Riverpod(keepAlive: true)
class WaveformScrollNotifier extends _$WaveformScrollNotifier {
  @override
  double build() => 0;

  /// Updates the shared offset; no-op when the value is unchanged.
  void setOffset(double offset) {
    if (state != offset) state = offset;
  }
}

/// The pixel height of the waveform canvas's vertical scroll viewport
/// (`WaveformCanvas`'s `Expanded`), published by [WaveformViewCenter].
///
/// The canvas lives in the `IdeLayout` **center** pane, which the
/// center↔bottom resizer (and the bottom panel, when shown) makes *shorter*
/// than the full-height **right** pane that hosts [ValueColumnPanel]. If the
/// value column simply filled its own (taller) pane, its scroll viewport would
/// be taller than the canvas's → a smaller `maxScrollExtent` → the synchronized
/// vertical scroll would clamp at the bottom and bounce back, clipping the last
/// lane. The value column reads this and sizes its scroll region to *exactly*
/// the canvas viewport so all three viewports share one `maxScrollExtent`.
///
/// `0` until the canvas has laid out; the value column falls back to filling
/// its pane (the pre-measurement behavior) while the value is unknown.
@Riverpod(keepAlive: true)
class CanvasViewportHeightNotifier extends _$CanvasViewportHeightNotifier {
  @override
  double build() => 0;

  /// Updates the published viewport height; no-op when unchanged.
  void setHeight(double height) {
    if (state != height) state = height;
  }
}
