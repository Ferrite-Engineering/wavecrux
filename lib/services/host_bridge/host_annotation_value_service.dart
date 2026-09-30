// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Answering the extension host's standing "what are these worth at the cursor?"
// query — the app half of the RTL annotation inversion.
//
// ### Why this is a service and not four lines in `_dispatch`
//
// Every other branch of [EditorHostBridge._dispatch] answers once and forgets.
// This one has to keep answering: the host is drawing decorations that follow
// the *waveform* cursor, and the waveform cursor is ours. Something has to hold
// the current path list, listen for cursor moves, re-bind that listen when the
// active tab changes, and debounce the result — which is a lifetime, and a
// lifetime does not belong in a switch.
//
// ### The scope trap this exists to avoid
//
// `cursorStateProvider`, `waveformSourceProvider`, `signalGroupsProvider` and
// `signalVariablesByPathProvider` are **per-tab**. Read off the root [Ref] they
// answer from the dead root-scope instances the UI never updates (the issue #44
// scope-leak class). So every read goes through the active tab's container and
// the cursor listen is re-bound on `activeTabIdProvider` — the same dance
// [CxpSelectionEmitter] does, for the same reason.
//
// ### What is deliberately not here
//
// No formatting of its own. The values are rendered by
// [TranslatorRegistry.translate] with the signal's own [DisplayFormat], so an
// annotation in the user's Verilog reads exactly like the value column two
// panes away. A second formatter here would be a second answer to "what does
// this signal say", and the first one to drift would be the one nobody looked
// at.

import 'dart:async';

import 'package:crux_async/crux_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/interfaces/translator.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/cursor_state.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/tab_id.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/plugins/translator_registry.dart';
import 'package:wavecrux/services/host_bridge/host_bridge_messages.dart';
import 'package:wavecrux/services/tabs/active_tab_container.dart';
import 'package:wavecrux/services/time_format/time_format_service.dart';
import 'package:wavecrux/services/value_format/value_format_service.dart';

/// Debounce applied to cursor moves before the standing query is re-answered.
///
/// A drag produces dozens of cursor updates a second and every one of them
/// would otherwise cost a hierarchy lookup per annotated path plus a frame
/// posted across the bridge. 100 ms matches [kCxpCursorDebounce] deliberately:
/// both are "coalesce a scrub gesture into one broadcast", and two different
/// answers to that would show up as the editor and a peer app disagreeing about
/// where the cursor is.
const Duration kHostAnnotationCursorDebounce = Duration(milliseconds: 100);

/// Holds the extension host's current annotation query and answers it.
///
/// One per [EditorHostBridge]; created eagerly and inert until the first query
/// arrives, because a build with no annotating host must not pay for a cursor
/// listener.
class HostAnnotationValueService {
  /// Creates the service. [post] is the bridge's outbound sink.
  HostAnnotationValueService({
    required Ref ref,
    required void Function(HostBridgeValueResponse response) post,
    Duration cursorDebounce = kHostAnnotationCursorDebounce,
  }) : _ref = ref,
       _post = post,
       _debounce = Debouncer(duration: cursorDebounce);

  final Ref _ref;
  final void Function(HostBridgeValueResponse response) _post;
  final Debouncer _debounce;

  String? _queryId;
  List<String> _paths = const <String>[];
  ProviderSubscription<CursorState>? _cursorSub;
  ProviderSubscription<AsyncValue<WaveformDataSource?>>? _sourceSub;
  ProviderSubscription<TabId>? _activeTabSub;
  ProviderContainer? _activeContainer;
  bool _disposed = false;

  /// Whether a standing query is currently being answered.
  bool get isActive => _queryId != null;

  /// Accept [query] as the standing query, answer it now, and keep answering
  /// it as the cursor moves.
  ///
  /// An empty path list **cancels**: it is what the host sends when the user
  /// turns annotation off or scrolls to a region with nothing resolvable, and
  /// treating it as "answer with nothing, forever" would leave a cursor
  /// listener running for a feature nobody is looking at. It is still answered
  /// once, so a host waiting on a response never hangs.
  Future<void> accept(HostBridgeValueQuery query) async {
    if (_disposed) return;
    _queryId = query.queryId;
    _paths = List<String>.unmodifiable(query.paths);
    if (_paths.isEmpty) {
      _unbind();
      _post(
        HostBridgeValueResponse(
          queryId: query.queryId,
          values: const <String, String>{},
        ),
      );
      _queryId = null;
      return;
    }
    _bind();
    await _answer();
  }

  /// Release the cursor listen and the debounce. Safe to call repeatedly.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _unbind();
    _debounce.dispose();
    _queryId = null;
    _paths = const <String>[];
  }

  // ── Subscriptions ──────────────────────────────────────────────────────────

  void _bind() {
    _activeTabSub ??= _ref.listen<TabId>(
      activeTabIdProvider,
      (_, _) => _bindActiveTab(),
    );
    _bindActiveTab();
  }

  void _bindActiveTab() {
    if (_disposed) return;
    _cursorSub?.close();
    _sourceSub?.close();
    final container = activeTabContainer(_ref);
    _activeContainer = container;
    // No tab system (startup, empty canvas, flat-container tests): fall back to
    // the root ref, which is what `readActive` does and what keeps unit tests
    // driving the same code path production does.
    _cursorSub = container != null
        ? container.listen<CursorState>(
            cursorStateProvider,
            (_, _) => _scheduleAnswer(),
          )
        : _ref.listen<CursorState>(
            cursorStateProvider,
            (_, _) => _scheduleAnswer(),
          );
    // The waveform itself, not only the cursor. A query almost always arrives
    // *before* the parse finishes — the host asks as soon as the editor has
    // lines to annotate, and the extension's own transfer is what is still in
    // flight — so without this the first answer is empty and nothing arrives
    // to replace it until the user happens to move the cursor. That reads as
    // the feature being broken.
    _sourceSub = container != null
        ? container.listen<AsyncValue<WaveformDataSource?>>(
            waveformSourceProvider,
            (_, _) => _scheduleAnswer(),
          )
        : _ref.listen<AsyncValue<WaveformDataSource?>>(
            waveformSourceProvider,
            (_, _) => _scheduleAnswer(),
          );
  }

  void _unbind() {
    _debounce.cancel();
    _cursorSub?.close();
    _cursorSub = null;
    _sourceSub?.close();
    _sourceSub = null;
    _activeTabSub?.close();
    _activeTabSub = null;
    _activeContainer = null;
  }

  void _scheduleAnswer() {
    _debounce.run(() {
      if (_disposed || _queryId == null) return;
      unawaited(_answer());
    });
  }

  T _read<T>(ProviderListenable<T> provider) =>
      _activeContainer?.read(provider) ?? _ref.read(provider);

  // ── Answering ──────────────────────────────────────────────────────────────

  /// Sample every path in the standing query and post one response.
  ///
  /// Degrades per path rather than as a whole: a path that is not in the design,
  /// a signal that will not load, a signal with no transition at or before the
  /// cursor are all simply absent from [HostBridgeValueResponse.values]. One bad
  /// identifier on one visible line must not blank the other thirty-nine.
  Future<void> _answer() async {
    final queryId = _queryId;
    if (queryId == null || _disposed) return;
    final paths = _paths;

    final source = _read(waveformSourceProvider).value;
    if (source == null) {
      _post(
        HostBridgeValueResponse(
          queryId: queryId,
          values: const <String, String>{},
        ),
      );
      return;
    }

    final byPath = _read(signalVariablesByPathProvider);
    final formats = _formatsBySignalRef(_read(signalGroupsProvider).entries);
    final registry = _ref.read(translatorRegistryProvider);
    final time =
        _read(cursorStateProvider).primaryCursorTime ?? source.startTime;

    final values = <String, String>{};
    for (final path in paths) {
      if (_disposed || _queryId != queryId) return;
      final variable = byPath[path];
      if (variable == null) continue;
      final formatted = await _valueFor(
        source: source,
        registry: registry,
        variable: variable,
        format: formats[variable.signalRef],
        time: time,
      );
      if (formatted != null) values[path] = formatted;
    }

    if (_disposed || _queryId != queryId) return;
    _post(
      HostBridgeValueResponse(
        queryId: queryId,
        values: values,
        cursorLabel: TimeFormatService(
          timescale: source.timescale,
        ).format(time),
      ),
    );
  }

  Future<String?> _valueFor({
    required WaveformDataSource source,
    required TranslatorRegistry registry,
    required Variable variable,
    required DisplayFormat? format,
    required int time,
  }) async {
    final signalRef = variable.signalRef;
    if (!source.isSignalLoaded(signalRef)) {
      // A path the user never added to the viewer is the *normal* case here —
      // the host asks about whatever is on screen in their editor, not about
      // what is in the signal list. Loading it is what makes the annotation
      // work at all; failing to is not an error worth propagating.
      try {
        await source.loadSignal(signalRef);
      } on Object {
        return null;
      }
    }
    final raw = source.valueAt(signalRef, time);
    if (raw == null) return null;
    // `bitWidth` is null for a real/analog variable and for anything the parser
    // did not size; the raw bit string's own length is what the value column
    // falls back to, and using the same fallback is what keeps an annotation
    // and the column from disagreeing about a signal's width.
    final width = variable.bitWidth ?? raw.length;
    return registry
        .translate(
          TranslationRequest(
            rawValue: raw,
            bitWidth: width,
            format: format ?? ValueFormatService.defaultFormat(width),
          ),
        )
        .text;
  }

  /// The user's chosen radix per signal, flattened out of the group tree.
  ///
  /// Built once per response rather than scanned per path: the tree walk is
  /// O(entries) and doing it inside the path loop would make a full viewport
  /// O(paths × entries) for no gain.
  Map<String, DisplayFormat> _formatsBySignalRef(List<SignalEntry> entries) {
    final formats = <String, DisplayFormat>{};
    void scan(List<SignalEntry> list) {
      for (final entry in list) {
        if (entry.kind == SignalEntryKind.signal) {
          final signalRef = entry.signalRef;
          if (signalRef != null) formats[signalRef] = entry.format;
        } else if (entry.kind == SignalEntryKind.group) {
          scan(entry.children);
        }
      }
    }

    scan(entries);
    return formats;
  }
}
