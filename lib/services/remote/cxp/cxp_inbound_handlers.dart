// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart'
    show kCruxInfoSnackDuration;
import 'package:crux_io/crux_io.dart' show SpawnHost;
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:crux_window_chrome/crux_window_chrome.dart';
import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/core/router.dart' show rootScaffoldMessengerKey;
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/stage/providers/riscv_commit_auto_stage.dart';
import 'package:wavecrux/features/stage/providers/riscv_commit_landing_provider.dart';
import 'package:wavecrux/features/stage/providers/stage_workspace_provider.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/remote/cxp/cxp_workspace_link.dart';
import 'package:wavecrux/services/remote/cxp/riscv_stream_coordinate_resolver.dart';
import 'package:wavecrux/services/remote/cxp/wavecrux_cxp_server.dart';
import 'package:wavecrux/services/remote/remote_control_notifier.dart';
import 'package:wavecrux/services/riscv/riscv_retire_stream_service.dart';
import 'package:wavecrux/services/riscv/rvfi_detection_service.dart';
import 'package:wavecrux/services/tabs/active_tab_container.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

part 'cxp_inbound_handlers.g.dart';

// Per-tab reads go through `readActive` (services/tabs/active_tab_container.dart).
//
// The CXP server is a root-scoped `keepAlive` notifier, so its `ref` is the
// root container — but `waveformSourceProvider`, `signalGroupsProvider`,
// `cursorStateProvider`, and `markerStateProvider` are per-tab, and reading
// them off the root ref hits dead instances the UI never updates.
// `selectedSignalProvider` is genuinely root, and resolves to root either way
// via child-scope fall-through. The editor-host bridge is the second caller of
// that helper, which is why it no longer lives here.

/// Adapts inbound CXP `request_highlight` payloads onto the same internal
/// code paths the WCP server uses for `add_items`, `set_cursor`, and
/// `focus_item`. One implementation, two front doors.
///
/// * [ElementKind.signal] — look the signal up by `signalRef`/`fullPath`
///   in the loaded waveform, add it to the signal list (idempotent if
///   already present), and focus it via `selectedSignalProvider`.
/// * [ElementKind.scope] — gather every variable whose path begins with
///   the requested scope and add them all at once. Mirrors the WCP
///   `add_items` recursive=true path.
/// * [ElementKind.marker] — interpret the path as a single lowercase
///   marker letter, look up its tick time, and place the primary cursor.
/// * [ElementKind.instance], [ElementKind.net], [ElementKind.port] —
///   treat as signal-like references and resolve through the same
///   pipeline as [ElementKind.signal].
/// * Other kinds (`rule`, `test`, `breakpoint`) — return honored=false.
/// * A kind this build does not know at all (the wire type is open, so a
///   newer peer may send one) — same graceful honored=false reply.
///
/// Failure modes:
/// * No file loaded → `honored: false`, `reason: "no waveform file loaded"`.
/// * Element not found in the current waveform → `honored: false`,
///   `reason: "element not found"`.
/// * Marker letter not currently set → `honored: false`,
///   `reason: "marker not set"`.
Future<CxpHandlerResult> dispatchCxpHighlight(
  Ref ref,
  ElementId element, [
  Map<String, Object?> metadata = const <String, Object?>{},
  CxpStreamCoordinate? coordinate,
]) async {
  final outcome = await _dispatchCxpHighlight(ref, element, metadata);
  // `element` said what to open; the optional CXP §9.9 coordinate says
  // where to land inside it. Applied after the element, because a coordinate
  // is resolved against the trace the element just opened.
  final placed = await _applyStreamCoordinate(
    ref,
    outcome.result,
    coordinate,
    openedTab: outcome.openedTab,
  );
  // An actionable inbound message was applied (a highlight landed or a
  // waveform was opened) — nudge the OS's attention affordance without stealing
  // focus. Gated by the user setting via the swappable `windowAttentionRequester`
  // seam, so this call is a no-op when the preference is off.
  if (placed.honored) unawaited(requestUserAttention());
  // Both outcomes are recorded, and that is the point of the `honored`
  // property: a cross-probe a peer sent and this app could not act on is the
  // failure mode the suite network-effect funnel exists to surface, so
  // dropping it would leave the metric reading healthy exactly when it is not.
  ref
      .read(telemetryServiceProvider)
      .record(
        TelemetryEvent(
          'cxp.crossprobe',
          properties: <String, Object?>{
            'direction': 'inbound',
            'honored': placed.honored,
          },
        ),
      );
  return placed;
}

/// Applies the inbound `request_highlight`'s optional semantic stream
/// coordinate (CXP §9.9, https://edacrux.app/cxp#sec-9-9) on top of the
/// element's own [elementResult].
///
/// **The honoured flag never moves.** CXP §9.4: *"A receiver that honours the
/// element but cannot resolve the coordinate MUST still honour the element,
/// and SHOULD say so in the acknowledgement's `reason`."* Landing at the top
/// of the right trace is a better outcome than refusing it, so every failure
/// below turns into a reason on an otherwise-honoured ack — which the
/// originating app surfaces as a toast — and never into `honored: false` and
/// never into a throw.
///
/// A null coordinate, and a coordinate in a stream this build does not
/// implement, both return [elementResult] essentially untouched. That
/// tolerance is the forward-compatibility path CXP §9.9.1 requires: the same
/// triple will one day address an AXI transaction or an Ethernet frame, and a
/// peer that sends one must not be answered with an error.
///
/// [openedTab] says whether the element hand-off **opened the trace's tab
/// itself**, and it is the whole basis of the auto-mount decision below. See
/// [_mountCommitInspector].
Future<CxpHandlerResult> _applyStreamCoordinate(
  Ref ref,
  CxpHandlerResult elementResult,
  CxpStreamCoordinate? coordinate, {
  required bool openedTab,
}) async {
  if (coordinate == null) return elementResult;
  // Nothing to land *inside* an element that was not honoured. The element's
  // own reason is the more useful one, so it stands unmodified.
  if (!elementResult.honored) return elementResult;
  if (!RiscvStreamCoordinateResolver.implementsStream(coordinate.streamId)) {
    return CxpHandlerResult(
      honored: true,
      reason: RiscvStreamCoordinateResolver.declineUnknownStream(
        coordinate.streamId,
      ).reason,
    );
  }

  final _StreamCoordinateOutcome outcome;
  try {
    outcome = await _resolveStreamCoordinate(ref, coordinate);
  } on Object catch (e) {
    // "Never throw" is the standing constraint on this whole path. A trace
    // that surprises the substrate degrades to an honoured element with an
    // explanation, exactly like every other unresolvable coordinate.
    return CxpHandlerResult(
      honored: true,
      reason: 'could not resolve the stream coordinate: $e',
    );
  }

  final resolution = outcome.resolution;
  final time = resolution.time;
  if (time == null) {
    return CxpHandlerResult(honored: true, reason: resolution.reason);
  }

  // The cursor IS the Commit Inspector's selection. Its history views show
  // the retirements at or before the primary cursor and mark the last of them
  // as current, so placing the cursor exactly on the retirement's tick
  // selects that retirement, folds the register file to it, and scopes the
  // memory and trap logs to it — one move, five consistent views.
  readActive(ref, cursorStateProvider.notifier).placePrimary(time);
  // …but a tab this hand-off opened a moment ago has no Stage panel, so there
  // is no Commit Inspector for the cursor to select *in*, and no banner to
  // explain the move. Mount one. Only into a tab we opened, and only now —
  // past every decline above, so this is reached only when the coordinate
  // genuinely resolved against an RVFI stream in this trace.
  final autoMounted =
      openedTab && _mountCommitInspector(ref, outcome.availableSignals);
  readActive(ref, riscvCommitLandingProvider.notifier).record(
    streamId: coordinate.streamId,
    sequenceIndex: coordinate.sequenceIndex,
    time: time,
    subId: coordinate.subId,
    order: resolution.retired?.order,
    channelIndex: resolution.channelIndex,
    attributes: coordinate.attributes,
    autoMounted: autoMounted,
  );
  if (resolution.retired != null) return CxpHandlerResult.honoredOk;
  // CXP §9.9.2's prescribed fallback: the step exists, nothing retired there.
  // Reported rather than dressed up as a hit — the sender asked for an
  // instruction and did not get one.
  return const CxpHandlerResult(
    honored: true,
    reason:
        'no instruction retired at that step; the cursor was placed there '
        'and nothing was selected',
  );
}

/// Builds the retire stream of the active tab's trace and resolves
/// [coordinate] against it.
///
/// **The lazy-load trap applies here in full** (ARCHITECTURE §6.6). Resolving
/// a retirement means the substrate walks the source, and
/// `WaveformDataSource.valueAt` answers `null` both for "not loaded" and for
/// "no value yet" — so every ref the detected bundle names is loaded *before*
/// the walk. A CXP highlight is the worst case for this: the trace was opened
/// a moment ago by the hand-off itself and nothing has been added to the
/// viewer, so nothing is loaded.
///
/// The retire stream is built with a **null disassembler** on purpose.
/// Composing one costs an async asset load, and nothing the resolver reads —
/// tick, `rvfi_order`, PC, channel — comes from disassembly. The Commit
/// Inspector builds its own fully-disassembled stream when it renders.
Future<_StreamCoordinateOutcome> _resolveStreamCoordinate(
  Ref ref,
  CxpStreamCoordinate coordinate,
) async {
  final source = readActive(ref, waveformSourceProvider).value;
  if (source == null) {
    return const _StreamCoordinateOutcome(
      RiscvCoordinateResolution.declined(
        'no waveform file loaded, so the stream coordinate could not be '
        'resolved',
      ),
    );
  }
  final available = <String, Variable>{
    for (final v in source.findVariables(const SignalFilter())) v.fullPath: v,
  };
  final detection = const RvfiDetectionService().detect(available);
  if (detection.bindings.allRefs.isEmpty) {
    return const _StreamCoordinateOutcome(
      RiscvCoordinateResolution.declined(
        'the loaded trace exposes no RVFI bundle, so a RISC-V stream '
        'coordinate cannot be resolved in it',
      ),
    );
  }
  for (final signalRef in detection.bindings.allRefs) {
    if (source.isSignalLoaded(signalRef)) continue;
    try {
      await source.loadSignal(signalRef);
    } on Object {
      // A ref the source will not load degrades the stream rather than
      // failing the highlight; the resolver reports whatever it can and
      // cannot see from what did load.
    }
  }
  final retires = const RiscvRetireStreamService(null).build(
    source: source,
    bindings: detection.bindings,
    startTime: source.startTime,
    endTime: source.endTime,
  );
  return _StreamCoordinateOutcome(
    const RiscvStreamCoordinateResolver().resolve(
      coordinate: coordinate,
      source: source,
      bindings: detection.bindings,
      retires: retires,
    ),
    available,
  );
}

/// A coordinate resolution plus the variable map it was resolved against.
///
/// The map rides along because the auto-mount needs exactly the same
/// available-signal view the detection ran on, and re-deriving it would be a
/// second source of truth for "what is in this trace".
@immutable
class _StreamCoordinateOutcome {
  const _StreamCoordinateOutcome(
    this.resolution, [
    this.availableSignals = const <String, Variable>{},
  ]);

  final RiscvCoordinateResolution resolution;
  final Map<String, Variable> availableSignals;
}

/// Adds an RVFI Commit Inspector to the tab the cross-probe just opened, and
/// returns whether it did.
///
/// **This is the whole of the "only into a tab we opened" rule's teeth.** The
/// caller gates on `openedTab`; everything below assumes that gate has already
/// been passed and is concerned only with *not* mounting a second inspector
/// into a tab that already has one.
///
/// Routed through [_readActive] because the Stage workspace and the panel
/// layout are both per-tab: the mount must land in the tab holding the trace
/// this coordinate resolved in, not in the root scope.
bool _mountCommitInspector(Ref ref, Map<String, Variable> available) {
  try {
    return mountRiscvCommitInspector(
          workspace: readActive(ref, stageWorkspaceProvider.notifier),
          current: readActive(ref, stageWorkspaceProvider),
          layout: readActive(ref, panelLayoutProvider.notifier),
          availableSignals: available,
          panelName: _autoStagePanelName(),
        ) !=
        null;
  } on Object {
    // "Nothing on this path throws" holds for the mount too. A landing that
    // already placed the cursor correctly must not be turned into an error by
    // a convenience that failed — the user simply adds the inspector by hand.
    return false;
  }
}

/// The localized name for the Stage panel the cross-probe creates.
///
/// Resolved off the root messenger's context — the same non-widget
/// localization route [_showOpenWaveformSnackBar] uses — because this runs on
/// an inbound socket message with no `BuildContext` of its own. A panel name is
/// a plain persisted string chosen once at creation (exactly as the user's own
/// `stagePanelDefaultName` is), so resolving it here and storing the result is
/// the same contract a hand-created panel has.
///
/// Falls back to the English literal when no messenger is mounted — a
/// server-only startup or a unit test. A panel that exists with an
/// untranslated name beats a hand-off that does nothing.
String _autoStagePanelName() {
  final messenger = rootScaffoldMessengerKey.currentState;
  if (messenger == null || !messenger.mounted) return 'RVFI Commit';
  return Localizations.of<L10N>(
        messenger.context,
        L10N,
      )?.riscvCommitLandingPanelName ??
      'RVFI Commit';
}

/// An element hand-off's reply, plus whether honouring it **opened a tab that
/// was not open before**.
///
/// That second bit is not cosmetic. A tab the cross-probe opened is one the
/// user has never arranged, so filling it in is a service; a tab that was
/// already open is the user's own arrangement, and rearranging it underneath
/// them is not. Every path that can open a tab reports which of the two it
/// did, and [_applyStreamCoordinate] is the only consumer.
@immutable
class _ElementOutcome {
  const _ElementOutcome(this.result, {this.openedTab = false});

  /// The reply that rides back to the sender, unchanged by this wrapper.
  final CxpHandlerResult result;

  /// True only when a **new** tab was created for this hand-off. Activating a
  /// tab that already held the file (the P21 dedupe) is false: nothing was
  /// created, and the user arranged what is there.
  final bool openedTab;
}

Future<_ElementOutcome> _dispatchCxpHighlight(
  Ref ref,
  ElementId element,
  Map<String, Object?> metadata,
) async {
  // `ElementKind` is an open wire type; switch on the retained
  // `KnownElementKind` mirror so this stays an exhaustive switch, and let
  // the `null` case cover kinds minted by a peer built against a later
  // protocol revision.
  switch (element.kind.known) {
    case KnownElementKind.signal:
    case KnownElementKind.instance:
    case KnownElementKind.net:
    case KnownElementKind.port:
      return await _highlightSignalLikeOrOpen(ref, element.path, metadata);
    case KnownElementKind.scope:
      return _ElementOutcome(await _highlightScope(ref, element.path));
    case KnownElementKind.marker:
      return _ElementOutcome(await _highlightMarker(ref, element.path));
    case KnownElementKind.source:
      return await _highlightSource(ref, element.path);
    case KnownElementKind.rule:
    case KnownElementKind.test:
    case KnownElementKind.breakpoint:
    case null:
      // `null` = a kind this build has never heard of. Ignored gracefully,
      // with the same honored=false reply the known-but-unhandled kinds
      // get: the requester learns WaveCrux did nothing, and nothing throws.
      return _ElementOutcome(
        CxpHandlerResult(
          honored: false,
          reason: 'wavecrux does not handle ${element.kind.name} elements',
        ),
      );
  }
}

/// Highlights a signal-like [path] locally, and when that misses — no waveform
/// open, OR the signal isn't in the open waveform — falls back to the shared
/// workspace: reads `crux.design_id` from [metadata], resolves the
/// design's `waveform` artifact, opens it in a new tab (the same
/// [WaveformSourceNotifier.openFile] path the SimCrux `source` handoff uses),
/// and re-runs the highlight against the now-loaded source. This is the R8 fix:
/// a `notify_selection` / `request_highlight` that arrives with no matching
/// waveform open now resolves and opens the VCD instead of dead-ending on a
/// snackbar. Returns the original miss reason when nothing resolves, so the
/// caller can keep its existing actionable feedback.
Future<_ElementOutcome> _highlightSignalLikeOrOpen(
  Ref ref,
  String path,
  Map<String, Object?> metadata,
) async {
  final local = await _highlightSignalLike(ref, path);
  // The waveform was already open and the signal resolved in it — no tab was
  // created, so nothing downstream may rearrange this tab.
  if (local.honored) return _ElementOutcome(local);
  final opened = await _openDesignWaveformFromWorkspace(ref, metadata);
  if (!opened.loaded) return _ElementOutcome(local);
  // openFile creates AND activates the tab, so `_readActive` now resolves the
  // freshly-loaded source: re-run the same leaf-matching highlight against it.
  return _ElementOutcome(
    await _highlightSignalLike(ref, path),
    openedTab: opened.openedTab,
  );
}

/// Resolves `crux.design_id` from [metadata] against the shared workspace and,
/// if a `waveform` artifact is recorded for that design, opens it in a new tab.
/// Returns whether a waveform was opened. The join is one-directional: the
/// consumer never re-derives an id from the file it opens — it trusts the
/// sender's `crux.design_id` and lets [resolveWaveformArtifactPath] pick the
/// file, so out-of-tree outputs and tb-vs-DUT scope naming never break it.
Future<({bool loaded, bool openedTab})> _openDesignWaveformFromWorkspace(
  Ref ref,
  Map<String, Object?> metadata,
) async {
  const nothing = (loaded: false, openedTab: false);
  final designId = metadata[cxpDesignIdMetadataKey];
  if (designId is! String || designId.isEmpty) return nothing;
  final path = resolveWaveformArtifactPath(ref, designId);
  if (path == null) return nothing;
  return await _openWaveformInNewTab(ref, path);
}

/// Opens the waveform at absolute [path] via the same workspace-then-source
/// path File→Open and the SimCrux handoff use, and returns whether the source
/// is loaded without error (`loaded`) and whether a **new tab was created for
/// it** (`openedTab`).
///
/// The two are deliberately separate answers. Activating a tab that already
/// held the file loads a source without creating anything, and a caller that
/// conflated the two would treat the user's own arranged tab as fair game for
/// rearrangement.
///
/// P21 dedupe: BEFORE opening a new tab, check whether [path] is already open
/// in ANY tab — active or not. If it is, ACTIVATE that existing tab (rather
/// than opening a second instance of the same file) so the follow-up
/// add/select/reveal lands in it. Only when the file isn't open anywhere do we
/// open a fresh tab. File identity is matched on the tab's recorded
/// [WavecruxTab.filePath] via [tabListProvider] — the same "is this file open"
/// lookup File→Open's `_openOrFocusFile` uses — not an ad-hoc string compare.
Future<({bool loaded, bool openedTab})> _openWaveformInNewTab(
  Ref ref,
  String path,
) async {
  final alreadyOpen = ref
      .read(tabListProvider)
      .where((t) => t.filePath == path)
      .toList(growable: false);
  if (alreadyOpen.isNotEmpty) {
    // Activate the existing tab. `setActiveTab` switches both the tab AND its
    // pane, so a match in a non-active pane is focused too; awaiting the
    // mutation lets `_readActive`/`activeTabContainer` resolve to it on the
    // subsequent highlight re-run.
    final tabId = alreadyOpen.first.id;
    await ref.wavecruxWorkspace.setActiveTab(tabId);
    final container = ref.read(tabContainerManagerProvider).containerFor(tabId);
    // A restored-but-deferred tab may not have loaded its source yet; load it
    // so the follow-up highlight has variables to match against. A tab that is
    // already loaded is left untouched (no needless reload).
    if (container.read(waveformSourceProvider).value == null) {
      await container.read(waveformSourceProvider.notifier).openFile(path);
    }
    final loaded = container.read(waveformSourceProvider);
    // Reused, not created: the user arranged this tab.
    return (
      loaded: loaded is! AsyncError && loaded.value != null,
      openedTab: false,
    );
  }
  final tabId = await ref.wavecruxWorkspace.openFile(path);
  final container = ref.read(tabContainerManagerProvider).containerFor(tabId);
  await container.read(waveformSourceProvider.notifier).openFile(path);
  final loaded = container.read(waveformSourceProvider);
  return (
    loaded: loaded is! AsyncError && loaded.value != null,
    openedTab: true,
  );
}

Future<CxpHandlerResult> _highlightSignalLike(
  Ref ref,
  String path,
) async {
  final source = readActive(ref, waveformSourceProvider).value;
  if (source == null) {
    // Actionable, user-facing reason: a net/signal reference carries no file
    // to open (unlike the `source` kind), so all WaveCrux can do is tell the
    // user to open a waveform first. On an inbound `notify_selection` this
    // reason is surfaced as a local snackbar (see [handleInboundSelection]);
    // on a `request_highlight` it rides back to the sender as the ack reason.
    return const CxpHandlerResult(
      honored: false,
      reason: _noWaveformReason,
    );
  }
  final allVars = source.findVariables(const SignalFilter());
  final match = _resolveSignalLike(path, allVars);
  if (match == null) {
    return CxpHandlerResult(
      honored: false,
      reason: 'element not found: $path',
    );
  }
  // Add the signal if it's not already in the viewer; focus it either way.
  final entries = readActive(ref, signalGroupsProvider).entries;
  final alreadyPresent = entries.any(
    (e) => e.signalRef == match.signalRef,
  );
  if (!alreadyPresent) {
    readActive(ref, signalGroupsProvider.notifier).addSignals([match]);
  }
  // selectedSignalProvider is the CXP server's own global focus — genuinely
  // root-scoped, so it is read off the root ref. The selection emitter reads
  // it to re-broadcast, so it must keep being written.
  ref.read(selectedSignalProvider.notifier).select(match.signalRef);
  // …but the VIEWER draws its selected/highlighted row from the PER-TAB
  // `selectedVariablesProvider` (a set keyed by fullPath / row identity), not
  // the root focus. Without also selecting it there the cross-probed signal
  // appears on the canvas but never visibly highlights — the payoff bug of the
  // CXP cross-probe path. Route through `_readActive` so it lands in the active
  // tab's container, and replace the selection with just this signal.
  readActive(
    ref,
    selectedVariablesProvider.notifier,
  ).selectOnly(match.fullPath);
  // Auto-reveal: bring the cross-probed signal's lane into view (expanding its
  // group if collapsed). Without this the selection highlights on the canvas
  // and in the side panes, but a signal below the fold gives the user no cue
  // to scroll. Reveal is gated to this inbound/programmatic path so a manual
  // click never yanks the viewport.
  readActive(
    ref,
    revealSignalRequestProvider.notifier,
  ).request(match.fullPath);
  return CxpHandlerResult.honoredOk;
}

/// The `reason` a signal-like highlight returns when no waveform is loaded.
/// Kept as a constant so the inbound-selection snackbar path can recognise
/// this specific failure without string-fragility.
const String _noWaveformReason = 'no waveform file loaded';

/// Resolves an inbound signal-like [path] against the loaded [allVars],
/// tiered so a cross-tool reference matches without introducing false
/// positives:
///
/// 1. **Exact** — `fullPath` or opaque `signalRef` equals [path]. Highest
///    priority; a WaveCrux-native reference always wins here.
/// 2. **Leaf suffix** — the trailing `.`-separated segment of [path] (e.g.
///    `sample_a` in NetCrux's `cdc_capture.sample_a`) matched against
///    `fullPath` ending in `.<leaf>`, `fullPath == leaf` (top-level signal),
///    or `signalRef == leaf`. This is what lets a NetCrux net name resolve
///    to the differently-rooted testbench path `tb_cdc_capture.dut.sample_a`.
///
/// When several variables tie at the leaf tier, the one whose own scope path
/// agrees with the INBOUND scope path over the most trailing segments wins;
/// shortest `fullPath` (then lexicographic) breaks a genuine tie so the choice
/// stays deterministic.
///
/// **Why scope agreement rather than plain shortest-path.** The peer sends a
/// full hierarchical path — `picorv32.genblk2.pcpi_div.pcpi_rd` — and taking
/// only the leaf throws away every segment that could disambiguate it. When a
/// submodule port name is *also* a net name in the parent (extremely common:
/// the parent declares `pcpi_rd` and connects the child's `pcpi_rd` to
/// `pcpi_div_rd`), shortest-path picks the parent's — which is a different wire
/// carrying a different value. The failure is silent and confident, which is
/// the worst shape a resolution bug can take: the user sees a plausible value
/// highlighted on the wrong signal and has no signal that anything went wrong.
///
/// Measured on picorv32 elaborated with ENABLE_MUL/ENABLE_DIV (two real
/// submodules behind `generate` blocks) cross-referenced against an Icarus VCD
/// of the full hierarchy — 229 public nets, three modules:
///
/// | matcher | exactly correct | wrong wire | unresolved |
/// |---|---|---|---|
/// | leaf + shortest path | 197 (86.0%) | 8 | 0 |
/// | leaf + scope agreement | 218 (95.2%) | 0 | 0 |
///
/// The 11 remaining non-exact matches under scope agreement are all top-level
/// boundary ports resolving to the testbench's own copy — the same wire seen
/// from one scope up, verified by identical value streams in the dump — so the
/// annotated value is right and only the label is one level off. That is 229 of
/// 229 value-correct.
///
/// Note what did NOT change: zero misses either way. The old matcher always
/// found *something*; it just sometimes found the wrong thing.
Variable? _resolveSignalLike(String path, List<Variable> allVars) {
  for (final v in allVars) {
    if (v.fullPath == path || v.signalRef == path) return v;
  }
  final leaf = _signalLikeLeaf(path);
  if (leaf.isEmpty) return null;
  final suffix = '.$leaf';
  final sentSegments = _signalLikeScopeTail(path);
  Variable? best;
  var bestAgreement = -1;
  for (final v in allVars) {
    final isLeafMatch =
        v.fullPath.endsWith(suffix) ||
        v.fullPath == leaf ||
        v.signalRef == leaf;
    if (!isLeafMatch) continue;
    final agreement = _trailingAgreement(v.fullPath.split('.'), sentSegments);
    if (best == null ||
        agreement > bestAgreement ||
        (agreement == bestAgreement &&
            (v.fullPath.length < best.fullPath.length ||
                (v.fullPath.length == best.fullPath.length &&
                    v.fullPath.compareTo(best.fullPath) < 0)))) {
      best = v;
      bestAgreement = agreement;
    }
  }
  return best;
}

/// How many trailing segments [candidate] and [sent] share.
///
/// Compared from the leaf backwards because the two hierarchies are rooted
/// differently by construction — the waveform is rooted at the testbench
/// (`testbench.uut.…`) and the netlist at the design top (`picorv32.…`) — so
/// only the tail can ever agree. Anchoring at the root would score every
/// candidate zero and reduce this to the old behaviour.
int _trailingAgreement(List<String> candidate, List<String> sent) {
  var n = 0;
  while (n < candidate.length &&
      n < sent.length &&
      candidate[candidate.length - 1 - n] == sent[sent.length - 1 - n]) {
    n++;
  }
  return n;
}

/// The inbound [path] split into scope segments, with any legacy
/// `:port:` / `:net:` / `:cell:` marker stripped first so a marked path from an
/// older peer contributes its scope segments too rather than scoring zero.
List<String> _signalLikeScopeTail(String path) {
  const markers = <String>[':port:', ':net:', ':cell:'];
  var cut = -1;
  var markerLen = 0;
  for (final marker in markers) {
    final idx = path.lastIndexOf(marker);
    if (idx > cut) {
      cut = idx;
      markerLen = marker.length;
    }
  }
  // Keep the segments BEFORE the marker as scope (`fsm_lock` in
  // `fsm_lock:port:state`) and the tail after it as the leaf.
  final head = cut >= 0 ? path.substring(0, cut) : '';
  final tail = cut >= 0 ? path.substring(cut + markerLen) : path;
  return <String>[
    if (head.isNotEmpty) ...head.split('.'),
    ...tail.split('.'),
  ];
}

/// Extracts the trailing signal leaf from an inbound signal-like [path].
///
/// A NetCrux net/port cross-probe now arrives as a clean dot-joined name
/// (`cdc_capture.sample_a`, `fsm_lock.state`), whose leaf is just the last
/// `.`-separated segment. But a peer built before that fix — or a code path
/// that still uses `buildElementPath`'s marked form — can send a MARKED path
/// like `fsm_lock:port:state`, `<scope>:net:<id>`, or `<scope>:cell:<name>`,
/// which has no dot before the leaf. Splitting such a path on `.` alone yields
/// the whole string, so it never leaf-matches. This tolerates those markers by
/// first taking the segment after the LAST `:port:` / `:net:` / `:cell:` marker,
/// then dot-splitting that tail. A clean, unmarked path has no marker and falls
/// straight through to the plain dot split, so exact/clean matching is unchanged.
String _signalLikeLeaf(String path) {
  const markers = <String>[':port:', ':net:', ':cell:'];
  var cut = -1;
  var markerLen = 0;
  for (final marker in markers) {
    final idx = path.lastIndexOf(marker);
    if (idx > cut) {
      cut = idx;
      markerLen = marker.length;
    }
  }
  final tail = cut >= 0 ? path.substring(cut + markerLen) : path;
  return tail.split('.').last;
}

Future<CxpHandlerResult> _highlightScope(
  Ref ref,
  String path,
) async {
  final source = readActive(ref, waveformSourceProvider).value;
  if (source == null) {
    return const CxpHandlerResult(
      honored: false,
      reason: 'no waveform file loaded',
    );
  }
  final allVars = source.findVariables(const SignalFilter());
  final scopeVars = allVars
      .where((v) => v.fullPath.startsWith('$path.'))
      .toList(growable: false);
  if (scopeVars.isEmpty) {
    return CxpHandlerResult(
      honored: false,
      reason: 'scope not found: $path',
    );
  }
  // Reuse the same addSignals path WCP's recursive add_items uses;
  // dedupe against already-present entries.
  final entries = readActive(ref, signalGroupsProvider).entries;
  final present = <String>{for (final e in entries) e.signalRef ?? ''};
  final toAdd = scopeVars
      .where((v) => !present.contains(v.signalRef))
      .toList(growable: false);
  if (toAdd.isNotEmpty) {
    readActive(ref, signalGroupsProvider.notifier).addSignals(toAdd);
  }
  return CxpHandlerResult.honoredOk;
}

Future<CxpHandlerResult> _highlightMarker(
  Ref ref,
  String path,
) async {
  // WaveCruxNameResolver guarantees a valid marker path (single lowercase
  // letter) before it reaches us, but be defensive — a peer that
  // bypassed the resolver may still send malformed input.
  if (path.length != 1 ||
      path.codeUnitAt(0) < 0x61 ||
      path.codeUnitAt(0) > 0x7A) {
    return CxpHandlerResult(
      honored: false,
      reason: 'invalid marker name: $path',
    );
  }
  final markerTime = readActive(ref, markerStateProvider).getMarker(path);
  if (markerTime == null) {
    return CxpHandlerResult(
      honored: false,
      reason: 'marker not set: $path',
    );
  }
  readActive(ref, cursorStateProvider.notifier).placePrimary(markerTime);
  return CxpHandlerResult.honoredOk;
}

/// Waveform-file extensions a CXP source highlight is allowed to open.
/// Compared case-insensitively against the tail of the element path.
const _waveformExtensions = ['.vcd', '.fst', '.ghw', '.wavecrux'];

/// The rule a `request_highlight(source)` waveform path is held to: the
/// containment floor only — absolute, well-formed, no NUL — and deliberately
/// not the open-directory roots [cxpPathContainmentProvider] applies to
/// `request_open_source`. `request_open_artifact` is held to the floor too
/// ([kCxpOpenArtifactContainment]).
///
/// This door is SimCrux's "Debug in WaveCrux" hand-off. The waveform it names
/// sits in a simulation run folder the user has never opened in WaveCrux, so
/// no tab and no recent-files entry covers it, and a roots check would refuse
/// every hand-off. The peer presenting it already holds this process's
/// per-process auth token, which makes it a same-user process; what the floor
/// still refuses is the shape a path must never take on its way into a file
/// open — a relative path resolved against whatever directory WaveCrux was
/// launched from, or a NUL that truncates it.
const CxpPathContainment _kSourceHandoffFloor = CxpPathContainment();

/// Handles a `request_highlight` for an [ElementKind.source] element.
///
/// Two distinct meanings share the `source` kind. When the path names a
/// waveform file (a recognized extension in [_waveformExtensions]), this is
/// the cross-app "Debug in WaveCrux" handoff: a sibling
/// product — e.g. SimCrux — points WaveCrux at a dump it produced and expects
/// WaveCrux to OPEN it. The handoff opens the waveform in a NEW tab titled by
/// the file's basename (never clobbering the user's current tab) and works
/// from the welcome screen too: [WaveCruxWorkspaceNotifier.openFile] creates
/// AND activates the tab, and the waveform is then loaded into that tab's own
/// container via the same [WaveformSourceNotifier.openFile] path File→Open
/// uses (`viewer_screen` `_openPath`), so convert-on-open, sandbox-bookmark,
/// and viewer-reset behaviour stays identical to a normal open.
///
/// If a `notify_selection` preceded this open (the "which signals to show"
/// hint the dispatcher sends first), its suggested signals are resolved
/// against the freshly-loaded source and placed on the new tab's canvas.
///
/// Any other source path is an RTL source citation (e.g. a `.v:line:col` lint
/// location a LintCrux cross-probe sends, or RTL source-code navigation). The
/// scenario intent — nudge the cursor to the signal near that source line —
/// needs a source-line→signal mapping WaveCrux does not have in v1: it holds a
/// waveform, never the RTL, and the citation carries no signal identifier (only
/// `file:line:column`), so there is nothing to resolve a lane from. Rather than
/// fake it, reply honored=false with a reason that (a) states that v1 limit so
/// an originator like LintCrux can surface "WaveCrux can't map a source
/// line to a signal yet", and (b) keeps the `request_open_source` retry hint for
/// the RTL-navigation caller. This honored=false-with-reason IS the documented
/// v1 behaviour for source citations.
///
/// Failure modes:
/// * A path that is not absolute and well-formed (relative, empty, carrying
///   a NUL) → `honored: false` with [CxpPathContainment]'s floor reason, and
///   nothing is opened. See [_kSourceHandoffFloor] for why this door gets the
///   floor and not the open-directory roots.
/// * Missing / unreadable / unparseable waveform → `honored: false`,
///   `reason: "failed to open waveform: …"` (the notifier lands in
///   [AsyncError]).
Future<_ElementOutcome> _highlightSource(
  Ref ref,
  String path,
) async {
  final lower = path.toLowerCase();
  final isWaveform = _waveformExtensions.any(lower.endsWith);
  if (!isWaveform) {
    return const _ElementOutcome(
      CxpHandlerResult(
        honored: false,
        reason:
            'no signal mapping for a source-line citation yet — '
            'retry as request_open_source to open the file',
      ),
    );
  }
  // Checked AFTER the extension test on purpose: the branch above opens
  // nothing, and its "retry as request_open_source" reply is the documented
  // answer to a source citation. The reason rides back in the ack and never
  // repeats the path.
  final refusal = _kSourceHandoffFloor.refuse(path);
  if (refusal != null) {
    return _ElementOutcome(CxpHandlerResult(honored: false, reason: refusal));
  }
  final tabId = await ref.wavecruxWorkspace.openFile(path);
  final container = ref.read(tabContainerManagerProvider).containerFor(tabId);
  await container.read(waveformSourceProvider.notifier).openFile(path);
  final loaded = container.read(waveformSourceProvider);
  if (loaded is AsyncError) {
    return _ElementOutcome(
      CxpHandlerResult(
        honored: false,
        reason: 'failed to open waveform: ${loaded.error}',
      ),
      // The tab exists — it just holds an error. Nothing may be mounted into
      // it: there is no trace to bind against.
      openedTab: true,
    );
  }
  _applySuggestedSignals(ref, container, loaded.value);
  // This is the SimCrux counterexample hand-off's own path, and it always
  // creates a tab: a `source` element names a file to OPEN, never a place in
  // something already open.
  return const _ElementOutcome(CxpHandlerResult.honoredOk, openedTab: true);
}

/// Drains the stashed `notify_selection` signal paths, resolves each against
/// [source], and adds the matches to [container]'s signal list via the same
/// `addSignals` path [_highlightSignalLike] uses. Consume-once: the stash is
/// emptied here so an unrelated later source-open starts with a clean canvas.
/// Unresolvable entries are skipped; an empty stash is a no-op.
void _applySuggestedSignals(
  Ref ref,
  ProviderContainer container,
  WaveformDataSource? source,
) {
  final suggested = ref.read(cxpSuggestedSignalsProvider.notifier).take();
  if (source == null || suggested.isEmpty) return;
  final allVars = source.findVariables(const SignalFilter());
  final resolved = resolveSuggestedSignals(suggested, allVars);
  if (resolved.isNotEmpty) {
    container.read(signalGroupsProvider.notifier).addSignals(resolved);
    // Give the handoff ONE clear focus rather than a wall of highlights: the
    // whole suggested set is added to the canvas above, but only the PRIMARY
    // suggestion is selected. `notify_selection` carries no explicit primary,
    // so the first resolved entry is the primary. Selecting the entire set (the
    // old behaviour) lit up every added lane at once and read as noise. The
    // per-tab selection is a set keyed by fullPath; `selectOnly` narrows it to
    // the primary. Written straight through the freshly-opened tab's own
    // [container].
    final primary = resolved.first;
    container
        .read(selectedVariablesProvider.notifier)
        .selectOnly(primary.fullPath);
    // Reveal the primary suggested signal so the handoff lands with its lane
    // scrolled into view, not merely selected somewhere below the fold.
    container
        .read(revealSignalRequestProvider.notifier)
        .request(primary.fullPath);
  }
}

/// Resolves the `notify_selection` [suggested] entries against [allVars],
/// returning the de-duplicated (by [Variable.signalRef]) variables in
/// first-match order. Exposed for testing; production callers reach it via
/// [_applySuggestedSignals].
@visibleForTesting
List<Variable> resolveSuggestedSignals(
  List<String> suggested,
  List<Variable> allVars,
) {
  final resolved = <Variable>[];
  final seen = <String>{};
  for (final wanted in suggested) {
    for (final v in _resolveSuggestion(wanted, allVars)) {
      if (seen.add(v.signalRef)) resolved.add(v);
    }
  }
  return resolved;
}

/// Resolves one `notify_selection` entry against [allVars].
///
/// SimCrux's "Debug in WaveCrux" handoff does NOT send exact signal names —
/// it sends a single glob, `'<topModule>.*'`, meaning "every signal under the
/// top module's scope" (SimCrux `deriveSuggestedSignalsFromTopModule`). An
/// entry is therefore interpreted as:
///
/// * A trailing-`.*` glob (`'<prefix>.*'`) → a SCOPE-SUBTREE match: every
///   variable whose [Variable.fullPath] is `<prefix>` itself or lives under
///   it (starts with `'<prefix>.'`). This is the same scope-prefix rule
///   [_highlightScope] uses, and pulls in nested instance signals too (e.g.
///   `<top>.dut.…`). WaveCrux spells the top scope as its bare module name
///   with `.`-separated components and no synthetic root (wellen
///   `_buildScope`), so `<prefix>` lines up with SimCrux's `topModule`.
/// * Any other glob (contains `*`) → a wildcard match of the whole pattern
///   against `fullPath` (`*` spans `.` separators).
/// * No `*` → the original exact match by opaque `signalRef` or `fullPath`.
Iterable<Variable> _resolveSuggestion(
  String wanted,
  List<Variable> allVars,
) {
  if (wanted.endsWith('.*')) {
    final prefix = wanted.substring(0, wanted.length - 2);
    return allVars.where(
      (v) => v.fullPath == prefix || v.fullPath.startsWith('$prefix.'),
    );
  }
  if (wanted.contains('*')) {
    final pattern = _globToRegExp(wanted);
    return allVars.where((v) => pattern.hasMatch(v.fullPath));
  }
  return allVars.where(
    (v) => v.signalRef == wanted || v.fullPath == wanted,
  );
}

/// Translates a glob into an anchored [RegExp]. Only `*` is special — it
/// matches any run of characters, `.` separators included; every other
/// character matches literally.
RegExp _globToRegExp(String glob) {
  final buf = StringBuffer('^');
  for (var i = 0; i < glob.length; i++) {
    final ch = glob[i];
    buf.write(ch == '*' ? '.*' : RegExp.escape(ch));
  }
  buf.write(r'$');
  return RegExp(buf.toString());
}

/// Metadata key SimCrux's "Debug in WaveCrux" handoff uses to carry the
/// signals-to-show glob(s) on its `notify_selection`. Mirrors SimCrux's
/// `kSimcruxSuggestedSignalsKey` — a SimCrux-local metadata key, not a
/// crux_cxp shared constant, so it is spelled out literally here.
const String _kSimcruxSuggestedSignalsKey = 'simcrux.suggested_signals';

/// Records the suggested-signal globs carried by an inbound CXP
/// `notify_selection` so the next source-open handoff ([_highlightSource])
/// can place the matching signals on the freshly-opened tab's canvas. Called
/// by [handleInboundSelection] (which the provider layer wires into
/// [WaveCruxCxpServer.onSelection]).
///
/// The handoff's globs live in [metadata] under [_kSimcruxSuggestedSignalsKey]
/// (e.g. `['<topModule>.*']`), NOT in [elements] — for this handoff `elements`
/// is just the source-VCD reference. As a fallback for other senders that put
/// real signal elements on the selection, signal-like element paths are used
/// when the metadata key is absent.
/// Handles an inbound CXP `notify_selection` end-to-end.
///
/// Two things happen, in order:
///
/// 1. **Stash** the selection for a possible following source-open handoff
///    ([stashCxpSelectionSignals]) — unchanged behaviour, and all the
///    SimCrux "Debug in WaveCrux" flow relies on.
/// 2. **Live highlight** — when the peer's selection names a signal-like
///    element (net/signal/instance/port) and a waveform is already open in
///    the active tab, highlight it immediately instead of waiting for a
///    source-open that may never come. This is what makes a NetCrux → WaveCrux
///    cross-probe visibly *do something* the instant the user clicks a CDC
///    crossing. When signal-like elements are present but no waveform is
///    loaded, a snackbar tells the user to open one first (a net reference
///    carries no file WaveCrux could open on its behalf).
///
/// Wired into [WaveCruxCxpServer.onSelection] by the provider layer.
void handleInboundSelection(
  Ref ref,
  List<ElementId> elements,
  Map<String, Object?> metadata,
) {
  stashCxpSelectionSignals(ref, elements, metadata);
  final signalLike = <ElementId>[
    for (final e in elements)
      if (_isSignalLikeKind(e.kind.known)) e,
  ];
  if (signalLike.isEmpty) return;
  unawaited(_liveHighlightInboundSelection(ref, signalLike, metadata));
}

/// Highlights the first resolvable signal-like element from an inbound
/// selection. Each element is resolved through [_highlightSignalLikeOrOpen], so
/// a miss on a not-open (or wrong) waveform now falls back to opening the
/// design's waveform from the shared workspace using the
/// selection's `crux.design_id` [metadata]. Only when nothing resolves AND there
/// is still no waveform open do we nudge the user to open one — a net reference
/// carries no file WaveCrux could open on its own. Fire-and-forget from
/// [handleInboundSelection].
Future<void> _liveHighlightInboundSelection(
  Ref ref,
  List<ElementId> signalLike,
  Map<String, Object?> metadata,
) async {
  for (final element in signalLike) {
    final result = await _highlightSignalLikeOrOpen(
      ref,
      element.path,
      metadata,
    );
    if (result.result.honored) {
      // A highlight was applied (possibly after opening the waveform).
      unawaited(requestUserAttention());
      return;
    }
  }
  if (readActive(ref, waveformSourceProvider).value == null) {
    _showOpenWaveformSnackBar();
  }
}

/// Shows a transient snackbar asking the user to open a waveform, via the
/// root messenger — mirrors the idiom in `MarkerChordCoordinator`. A no-op
/// when no messenger is mounted (server-only startup). Only ever called on
/// the UI isolate where the widget binding is live.
void _showOpenWaveformSnackBar() {
  final messenger = rootScaffoldMessengerKey.currentState;
  if (messenger == null || !messenger.mounted) return;
  final l10n = Localizations.of<L10N>(messenger.context, L10N);
  if (l10n == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(l10n.cxpHighlightNoWaveform),
        behavior: SnackBarBehavior.floating,
        // Canon info duration is pinned by convention, not the framework
        // default — it must not drift if the default ever changes.
        // ignore: avoid_redundant_argument_values
        duration: kCruxInfoSnackDuration,
      ),
    );
}

void stashCxpSelectionSignals(
  Ref ref,
  List<ElementId> elements,
  Map<String, Object?> metadata,
) {
  // Primary channel: the SimCrux metadata globs. Guard the shape — the value
  // is untrusted wire data: it must be a List (a non-List value is ignored,
  // not cast), and only its String entries are usable.
  final rawGlobs = metadata[_kSimcruxSuggestedSignalsKey];
  if (rawGlobs is List) {
    final globs = rawGlobs.whereType<String>().toList();
    if (globs.isNotEmpty) {
      ref.read(cxpSuggestedSignalsProvider.notifier).set(globs);
      return;
    }
  }
  // Fallback: signal-like element paths (scopes, markers, source refs are
  // ignored). Empty for the SimCrux handoff, which carries no signal elements.
  final paths = <String>[
    for (final e in elements)
      if (_isSignalLikeKind(e.kind.known)) e.path,
  ];
  ref.read(cxpSuggestedSignalsProvider.notifier).set(paths);
}

bool _isSignalLikeKind(KnownElementKind? kind) =>
    kind == KnownElementKind.signal ||
    kind == KnownElementKind.instance ||
    kind == KnownElementKind.net ||
    kind == KnownElementKind.port;

/// Stash for the signal paths carried by the most-recent inbound CXP
/// `notify_selection`. The "Debug in WaveCrux" handoff sends a
/// `notify_selection` (the signals to show) immediately before the
/// `request_highlight(source)` that opens the waveform; [_highlightSource]
/// drains this stash once the file has loaded and places those signals on the
/// fresh tab's canvas. Consume-once so a later unrelated source-open starts
/// with an empty canvas.
@Riverpod(keepAlive: true)
class CxpSuggestedSignals extends _$CxpSuggestedSignals {
  @override
  List<String> build() => const [];

  /// Records the signal paths from an inbound `notify_selection`.
  void set(List<String> paths) {
    state = List<String>.unmodifiable(paths);
  }

  /// Returns the stashed paths and clears the stash (consume-once).
  List<String> take() {
    final paths = state;
    state = const [];
    return paths;
  }
}

/// Adapts inbound CXP `request_open_artifact` payloads onto WaveCrux's
/// waveform-open path. A peer names a shared *design* ([designId]) and the
/// *kind* of artifact it wants opened ([artifactKind]); WaveCrux consumes only
/// `waveform` artifacts, resolves the concrete file through its own shared
/// workspace store (preferring that over the sender's [hintPath], whose
/// absolute path may not exist on this machine's layout), opens it in a new
/// tab, and requests attention. Replies honored=false with a reason — rather
/// than silently ignoring — when the kind isn't a waveform, neither a record
/// nor a hint names a file, the path fails the floor
/// ([kCxpOpenArtifactContainment]: empty, relative, a NUL, or padded with
/// white space), it is not a file here, or the open fails.
///
/// A waveform WaveCrux has never opened is honoured: this route is not
/// rooted in the directories the user has opened, and
/// [kCxpOpenArtifactContainment] says why.
Future<CxpHandlerResult> dispatchCxpOpenArtifact(
  Ref ref,
  String designId,
  String artifactKind,
  String? hintPath,
) async {
  if (artifactKind != kCxpWaveformArtifactKind) {
    return CxpHandlerResult(
      honored: false,
      reason: 'wavecrux opens only waveform artifacts, not "$artifactKind"',
    );
  }
  final path = resolveOpenArtifactWaveformPath(ref, designId) ?? hintPath;
  if (path == null) {
    return CxpHandlerResult(
      honored: false,
      reason: 'no waveform artifact recorded for design "$designId"',
    );
  }
  // CXP §11: the same scrutiny the wire's `file_path` gets, applied to the
  // value about to be opened rather than to the value looked up. The sender
  // chose the `design_id` that selected this record, the hint that may have
  // supplied it, and — the workspace directory being user-writable —
  // possibly the record itself, so "we resolved it ourselves" is not a
  // provenance. On this route that scrutiny is the floor, judged on the
  // exact string opened below; see [kCxpOpenArtifactContainment] for why it
  // is not the open directories. The reason travels back in the ack and
  // never repeats the path (CXP §9.11).
  final refusal = kCxpOpenArtifactContainment.refuse(path);
  if (refusal != null) {
    return CxpHandlerResult(honored: false, reason: refusal);
  }
  // The hint can name a file that is not there — the sender's path on its
  // own machine layout, or a dump since deleted — or something that is not
  // a file at all. Opening it would leave a tab holding nothing but an
  // error, so decline instead. Checked only after the floor, so a malformed
  // path is refused without this process ever looking at it. (A workspace
  // record never gets here missing: the store drops records whose file is
  // gone.)
  if (FileSystemEntity.typeSync(path) != FileSystemEntityType.file) {
    return const CxpHandlerResult(
      honored: false,
      reason: 'the artifact is not a file here',
    );
  }
  final opened = await _openWaveformInNewTab(ref, path);
  if (!opened.loaded) {
    // No path in the reason: it travels back to the sender (CXP §9.11).
    return const CxpHandlerResult(
      honored: false,
      reason: 'failed to open the waveform',
    );
  }
  // An artifact was opened.
  unawaited(requestUserAttention());
  return CxpHandlerResult.honoredOk;
}

/// Adapts inbound CXP `request_open_source` payloads onto a shell-out to
/// the editor command configured in [AppSettings.cxpEditorCommand]. An
/// empty command (the default) means CXP open-source is disabled — the
/// handler replies `honored: false`.
///
/// The runner is pluggable via [cxpEditorCommandRunnerProvider] so tests
/// can intercept the process invocation without launching a real editor.
///
/// [filePath] arrives over a socket, so this is the boundary at which it is
/// checked: [CxpPathContainment] refuses a path that is not absolute and
/// well-formed, and — once the session has directories open — one outside
/// them (CXP §11), before anything is spawned. The refusal reaches the peer
/// as the ack's `reason`. The header of `crux_io`'s spawn guards explains
/// why containment rather than escaping is the right instrument on a
/// `Process.run` argv.
///
/// This check is the one that keeps an editor to the directories the user
/// has opened. `LocalCxpServer` screens the wire value before dispatch, but
/// only with the floor: its one rule also screens a `request_open_artifact`
/// hint, which must not be rooted (see [kCxpOpenArtifactContainment]). The
/// rooted rule is applied here, on the value that becomes an editor argv,
/// whatever route reached this handler — it is also reachable from the WCP
/// front door.
Future<CxpHandlerResult> dispatchCxpOpenSource(
  Ref ref,
  String filePath,
  int line,
  int? column,
) async {
  final settings = ref.read(appSettingsProvider).value;
  final command = settings?.cxpEditorCommand ?? '';
  if (command.trim().isEmpty) {
    return const CxpHandlerResult(
      honored: false,
      reason: 'no editor command configured',
    );
  }
  final refusal = ref.read(cxpPathContainmentProvider).refuse(filePath);
  if (refusal != null) {
    return CxpHandlerResult(honored: false, reason: refusal);
  }
  final target = column == null ? '$filePath:$line' : '$filePath:$line:$column';
  final runner = ref.read(cxpEditorCommandRunnerProvider);
  return await runner(command, target);
}

/// Type of the editor-command runner injected via
/// [cxpEditorCommandRunnerProvider]. The default implementation shells
/// to `Process.run`. Override in tests to capture invocations.
typedef CxpEditorCommandRunner =
    Future<CxpHandlerResult> Function(
      String command,
      String target,
    );

/// Default editor-command runner: [runEditorCommand] against the live host.
Future<CxpHandlerResult> _defaultEditorCommandRunner(
  String command,
  String target,
) => runEditorCommand(command, target);

/// Spawns one process for the editor-command runner. Injectable so a test can
/// see the argv without starting anything.
typedef CxpEditorProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Splits [command] into argv tokens (whitespace-aware with single/double
/// quote handling), appends [target], and runs the process. Returns
/// `honored: true` on a zero exit code, otherwise a structured failure.
///
/// The editor name is resolved against [host] before the spawn. On Windows,
/// `CreateProcess` searches the calling process's current directory ahead of
/// PATH, and WaveCrux's current directory is whatever shell launched it — for
/// a developer, the repository being worked on — so a `code.exe` committed
/// there would otherwise win. An editor that nothing on PATH answers to is
/// refused as "editor not found" with nothing spawned, rather than handed on
/// bare to that same search. Off Windows the name is used as given.
///
/// [host] defaults to the live process and [run] to `Process.run`.
@visibleForTesting
Future<CxpHandlerResult> runEditorCommand(
  String command,
  String target, {
  SpawnHost? host,
  CxpEditorProcessRunner? run,
}) async {
  final tokens = _splitArgs(command);
  if (tokens.isEmpty) {
    return const CxpHandlerResult(
      honored: false,
      reason: 'editor command is empty',
    );
  }
  final args = <String>[...tokens.skip(1), target];
  try {
    final executable = (host ?? SpawnHost.current()).requireExecutable(
      tokens.first,
    );
    final result = await (run ?? Process.run)(executable, args);
    if (result.exitCode == 0) return CxpHandlerResult.honoredOk;
    return CxpHandlerResult(
      honored: false,
      reason: 'editor exited with ${result.exitCode}',
    );
  } on ProcessException catch (e) {
    return CxpHandlerResult(
      honored: false,
      reason: 'editor not found: ${e.message}',
    );
  } on Object catch (e) {
    return CxpHandlerResult(honored: false, reason: e.toString());
  }
}

/// Whitespace-aware argv splitter. Honors single and double quotes; does
/// not handle backslash escapes. Sufficient for typical editor command
/// shapes (`code -g`, `subl -a`, `nvr --remote-silent`, `emacsclient -n`).
@visibleForTesting
List<String> splitEditorCommandArgs(String command) => _splitArgs(command);

List<String> _splitArgs(String command) {
  final tokens = <String>[];
  final buf = StringBuffer();
  var quote = '';
  for (var i = 0; i < command.length; i++) {
    final ch = command[i];
    if (quote.isNotEmpty) {
      if (ch == quote) {
        quote = '';
      } else {
        buf.write(ch);
      }
      continue;
    }
    if (ch == '"' || ch == "'") {
      quote = ch;
      continue;
    }
    if (ch == ' ' || ch == '\t') {
      if (buf.isNotEmpty) {
        tokens.add(buf.toString());
        buf.clear();
      }
      continue;
    }
    buf.write(ch);
  }
  if (buf.isNotEmpty) tokens.add(buf.toString());
  return tokens;
}

/// Editor-command runner used by [dispatchCxpOpenSource]. Tests override
/// this provider to inject a capturing fake so they can assert call
/// shapes without launching an external process.
@Riverpod(keepAlive: true)
CxpEditorCommandRunner cxpEditorCommandRunner(Ref ref) =>
    _defaultEditorCommandRunner;
