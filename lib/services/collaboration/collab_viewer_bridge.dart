// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_async/crux_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:wavecrux/core/providers/collaboration_service_provider.dart';
import 'package:wavecrux/domain/interfaces/collaboration_service.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/domain/models/collab_view_composition.dart';
import 'package:wavecrux/domain/models/cursor_state.dart';
import 'package:wavecrux/domain/models/marker_state.dart';
import 'package:wavecrux/domain/models/playback_state.dart';
import 'package:wavecrux/domain/models/tab_id.dart';
import 'package:wavecrux/features/annotations/providers/annotation_adoption_provider.dart';
import 'package:wavecrux/features/annotations/providers/annotation_authoring_provider.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/collaboration/providers/collab_composition_degradation_provider.dart';
import 'package:wavecrux/features/collaboration/providers/composition_detached_provider.dart';
import 'package:wavecrux/features/collaboration/providers/follow_detached_provider.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/cursors/providers/playback_provider.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/settings/providers/custom_translators_provider.dart';
import 'package:wavecrux/features/stage/providers/stage_workspace_provider.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/fsm_provider.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_identity_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/collaboration/signal_identity_resolver.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

/// Debounce window applied to viewport changes before they are pushed to the
/// collaboration service. A drag-pan or zoom gesture fires a continuous stream
/// of viewport updates; the debounce coalesces them into one push per
/// quiescent burst so peers are not flooded. Cursor updates are NOT debounced
/// here because [CollaborationService.pushCursorUpdate] is already throttled
/// to 60 Hz inside the service.
const Duration kCollabViewportDebounce = Duration(milliseconds: 100);

/// Debounce window applied to **view-composition** mirroring. A
/// structural edit — adding several signals, dropping a decoder, dragging a
/// Stage widget — fires a burst of provider updates; the debounce coalesces
/// them into one recipe broadcast per quiescent burst. Longer than the viewport
/// debounce because a composition recipe is larger than a viewport pair and
/// structural edits are human-paced, not per-frame.
const Duration kCollabCompositionDebounce = Duration(milliseconds: 300);

/// Debounce window applied to **annotation** publishing.
///
/// Authoring fires a burst of provider updates that are one *gesture*: dragging
/// a balloon emits a `nudgeLabel` per pointer event, dragging a band edge one
/// per pixel of travel. The debounce coalesces each burst into a single frame,
/// which is what makes "broadcast on commit, never per keystroke" true of
/// pointer input as well as of typing. Matched to the composition debounce
/// because both are human-paced structural edits rather than per-frame state.
const Duration kCollabAnnotationDebounce = Duration(milliseconds: 300);

/// Resolves the [ProviderContainer] holding the *active tab's* waveform state,
/// or `null` to fall back to the root scope. Injected into [CollabViewerBridge]
/// so the per-tab binding is unit-testable without standing up the full tab
/// system. The production default is [defaultActiveTabContainerResolver].
typedef ActiveTabContainerResolver = ProviderContainer? Function(Ref ref);

/// Production resolver: the [ProviderContainer] for the active tab
/// (`activeTabIdProvider` → `TabContainerManager.containerFor`). Returns `null`
/// when the tab system is not installed (unit tests / a non-tabbed host), in
/// which case the bridge reads from the root [Ref].
ProviderContainer? defaultActiveTabContainerResolver(Ref ref) {
  try {
    final tabId = ref.read(activeTabIdProvider);
    // Only resolve a container for a tab that actually exists — at startup /
    // empty canvas `activeTabIdProvider` returns a freshly-generated id, and
    // `containerFor` would otherwise create a phantom per-tab container (with
    // its own autosave timer) for a tab that never opens. Re-binding fires when
    // a real tab is activated.
    final tabs = ref.read(tabListProvider);
    if (!tabs.any((tab) => tab.id == tabId)) return null;
    return ref.read(tabContainerManagerProvider).containerFor(tabId);
  } on Object {
    return null;
  }
}

/// Mirrors the local viewer's cursor, viewport, marker, and playback state into
/// the active [CollaborationService], and drives the local viewport / playhead
/// from the **presenter's** broadcast under Presenter Mode.
///
/// This is the *outbound* half of collaborative viewing — the counterpart to
/// the inbound [CollaboratorCursorOverlay], which renders the cursors of other
/// participants. Without this bridge nothing the local user does is ever
/// broadcast.
///
/// ## Presenter Mode control behavior
///
/// * **Inbound** — the local viewport mirrors the **presenter's** broadcast
///   viewport (not a chosen follow target), *suppressed* while the local
///   [followDetachedProvider] is set. The presenter's playback transport drives
///   a local ticker (the Stage Playback [PlaybackNotifier]) in lockstep, so
///   signal-bound Stage widgets animate for the whole room — again suppressed
///   while detached. The presenter's cursor itself is shown as a distinguished
///   overlay cursor, not by moving the local cursor.
/// * **Outbound** — the local viewport and playback transport are broadcast
///   **only while local-is-presenter**; the local cursor and any
///   locally-authored pointers are *always* mirrored regardless of who presents
///   (ambient presence).
/// * **Soft-follow** — a local pan / zoom / cursor move by a non-presenter marks
///   the follower [followDetachedProvider] *detached* (it does **not** end the
///   session or change the presenter). The bridge's echo guard distinguishes a
///   genuine local gesture from the bridge's own application of the presenter's
///   viewport, so applying the presenter's view never self-detaches.
///
/// The bridge watches four open-core providers and forwards changes:
///
/// * [cursorStateProvider] → [CollaborationService.pushCursorUpdate]
/// * [timeMapperProvider] → [CollaborationService.pushViewportUpdate]
///   (the source Notifier; the visible range is read from the mapper and the
///   push is debounced by [kCollabViewportDebounce])
/// * [markerStateProvider] → [CollaborationService.addSharedMarker] /
///   [CollaborationService.removeSharedMarker] (diffed against the last
///   snapshot)
/// * [waveformIdentityProvider] → [CollaborationService.updateWaveformIdentity]
///   (the SHA-256 hash of the loaded file, so the room can detect when
///   participants have *different* waveforms open)
/// * [annotationsProvider] → [CollaborationService.addAnnotation] /
///   [CollaborationService.updateAnnotation] /
///   [CollaborationService.removeAnnotation], and
///   [annotationBeingEditedProvider] →
///   [CollaborationService.setWritingAnnotation] (diffed against
///   what was published, debounced by [kCollabAnnotationDebounce], and blind by
///   construction to the notes that were already on the canvas when the session
///   began)
///
/// These providers are **per-tab** (each tab has its own waveform state in a
/// dedicated [ProviderContainer] — see `TabContainerManager`), so the bridge
/// binds to the **active tab's** container and re-binds whenever the active tab
/// changes (`activeTabIdProvider`). Collaboration therefore always mirrors the
/// waveform the user is actually looking at — one waveform/tab at a time, not
/// the whole app. (Binding at the root scope instead would read dead instances
/// the UI never updates, so nothing would ever broadcast.) When no tab system
/// is present (unit tests / a non-tabbed host) it falls back to the root [Ref].
///
/// It stays **inert until a session is active**: it subscribes directly to
/// [CollaborationService.sessionState] and forwards nothing until that stream
/// produces a state (the open-core [NoopCollaborationService] returns an empty
/// stream, so the bridge never sends anything). When a session starts it
/// establishes a marker baseline and pushes the current cursor + viewport once
/// so peers immediately see where this participant is looking.
///
/// The session stream is consumed directly rather than through
/// `collaborationSessionStateProvider` so the bridge owns its subscription and
/// does not depend on a widget (e.g. the collaborator-cursor overlay) keeping
/// that `StreamProvider` warm.
///
/// Construct via `collabViewerBridgeProvider`, which calls [start] and wires
/// [dispose] to the provider lifetime. The pattern mirrors
/// `CxpSelectionEmitter`.
class CollabViewerBridge {
  /// Creates a bridge bound to [ref]. Call [start] before it does any work.
  CollabViewerBridge({
    required Ref ref,
    Duration viewportDebounce = kCollabViewportDebounce,
    Duration compositionDebounce = kCollabCompositionDebounce,
    ActiveTabContainerResolver? activeTabContainerResolver,
  }) : _ref = ref,
       _viewportDebounce = Debouncer(duration: viewportDebounce),
       _compositionDebounce = Debouncer(duration: compositionDebounce),
       _resolveTabContainer =
           activeTabContainerResolver ?? defaultActiveTabContainerResolver;

  final Ref _ref;
  final ActiveTabContainerResolver _resolveTabContainer;

  StreamSubscription<CollabSessionState?>? _sessionSub;
  ProviderSubscription<TabId>? _activeTabSub;
  ProviderSubscription<CursorState>? _cursorSub;
  ProviderSubscription<TimeMapper>? _viewportSub;
  ProviderSubscription<MarkerState>? _markerSub;
  ProviderSubscription<String?>? _identitySub;
  ProviderSubscription<PlaybackState>? _playbackSub;
  ProviderSubscription<List<Annotation>>? _annotationSub;
  ProviderSubscription<String?>? _editingSub;
  final Debouncer _viewportDebounce;

  /// The per-tab [ProviderContainer] the cursor/viewport/marker/identity
  /// subscriptions are currently bound to — i.e. the active tab's waveform
  /// state. `null` means "no per-tab container available" (unit tests, or a
  /// host without the tab system), in which case the bridge reads from the root
  /// [_ref] instead. See [_resolveActiveContainer].
  ProviderContainer? _activeContainer;

  bool _inSession = false;
  MarkerState _lastMarkers = const MarkerState();
  bool _disposed = false;

  // ── presenter follow (inbound) ────────────────────────────────────────────
  //
  // Under Presenter Mode the bridge drives the local *viewport* to mirror the
  // **presenter's** broadcast viewport, and drives the local playback ticker
  // from the presenter's transport. To avoid a feedback loop — the mirrored
  // viewport change would otherwise be pushed straight back out, or
  // misclassified as a local navigation gesture and self-detach — the applied
  // viewport is recorded and the matching outbound/detect path is suppressed.
  // Two guards cover both Riverpod notification timings: `_applyingInbound`
  // (synchronous, wraps the apply) and the recorded `_afViewport` value
  // (asynchronous). Playback-ticker-driven cursor/viewport churn is recognised
  // separately via the active tab's live `isPlaying` flag (see `_onCursor`).
  bool _isLocalPresenter = false;
  bool _applyingInbound = false;
  (int, int)? _afViewport;

  // Last transport pushed (outbound, dedupe while presenting) / applied
  // (inbound, dedupe while following) so an unchanged transport is not
  // re-broadcast or re-applied on every full-state snapshot.
  CollabPlaybackTransport? _lastPushedTransport;
  CollabPlaybackTransport? _lastAppliedTransport;

  // ── view-composition sync ────────────────────────────────────────
  //
  // Outbound: while local-is-presenter, structural edits to the displayed
  // signals / decoders / translators / Stage / FSM / panels are coalesced
  // (debounced) into one recipe broadcast. Inbound: a follower applies the
  // presenter's recipe as a non-destructive overlay — the follower's own
  // composition is captured once (`_savedComposition`) before the first overlay
  // and restored verbatim on composition-detach or session-leave. Structural
  // composition is follow-or-fully-detached (`compositionDetachedProvider`),
  // independent of the navigation soft-follow.
  final List<ProviderSubscription<dynamic>> _compositionSubs = [];
  ProviderSubscription<bool>? _compositionDetachedSub;
  final Debouncer _compositionDebounce;

  /// Last recipe broadcast outbound (dedupe so an unchanged composition is not
  /// re-sent on every quiescent burst).
  CollabViewComposition? _lastMirroredComposition;

  /// Whether a presenter composition overlay is currently applied locally (i.e.
  /// [_savedComposition] holds the follower's own workspace, awaiting restore).
  bool _compositionApplied = false;

  /// The follower's own composition captured before the first overlay was
  /// applied, restored verbatim on detach / leave. Null when no overlay active.
  CollabViewComposition? _savedComposition;

  /// Last presenter composition applied inbound (dedupe so an unchanged recipe
  /// on a later full-state snapshot is not re-applied).
  CollabViewComposition? _lastAppliedComposition;

  /// The most recent presenter composition seen on the stream, re-applied when
  /// the follower resumes after a composition-detach.
  CollabViewComposition? _latestComposition;

  // ── collaborative annotations ─────────────────────────────────
  //
  // Outbound: notes authored *during* the session are published to the room;
  // notes that were already on the canvas when it started never are. That
  // asymmetry is the whole reason [_baselineAnnotationIds] exists, and it is
  // the same rule the colour semantics encode — your week-old private notes
  // are yours, not things said in this meeting.
  //
  // Inbound: the only local write is the host removing one of *your* notes,
  // which has to leave your canvas as well as the room's, or the notice in the
  // status bar would be reporting something you can still see.
  final _annotationDebounce = Debouncer(duration: kCollabAnnotationDebounce);

  /// Ids present locally when the session began. Never published, never
  /// updated, never removed — invisible to the room for its whole lifetime.
  final Set<String> _baselineAnnotationIds = {};

  /// What we last published, by id. Both the "have we published this" set and
  /// the dedupe baseline: an unchanged note is not re-sent when some other
  /// note in the list changes.
  final Map<String, Annotation> _publishedAnnotations = {};

  /// Ids we have actually seen in the room's annotation set.
  ///
  /// The gate on the inbound removal path, and not a formality: a publish that
  /// the service declined — no session yet, a closed tier gate, a frame lost on
  /// the way to the host — would otherwise look exactly like the host deleting
  /// the note, and the bridge would delete the author's own work off their
  /// canvas. Only a note the room is known to have had can be taken away by it.
  final Set<String> _confirmedInRoom = {};

  /// The note whose editor currently has focus, withheld from the room until
  /// it closes. While it is set the room sees a writing chip instead — that is
  /// the trade the design makes in place of streaming keystrokes.
  String? _writingAnnotationId;

  /// The last non-null session state seen, kept solely so the adoption prompt
  /// has something to offer.
  ///
  /// The session-ended signal is a `null` on the stream, which by construction
  /// carries no annotations, no roster and no palette slots — everything the
  /// prompt needs is gone by the time it is told to ask. So the last live
  /// snapshot is held one frame longer.
  CollabSessionState? _lastLiveSession;

  CollaborationService get _service => _ref.read(collaborationServiceProvider);

  /// Service instance the [onUserInteraction] callback was registered on,
  /// cached so [dispose] can clear it without calling `ref.read` (forbidden
  /// inside a Riverpod dispose lifecycle).
  CollaborationService? _registeredService;

  /// Wire up the subscriptions. Idempotent.
  void start() {
    if (_sessionSub != null) return;

    // A deliberate local gesture by a follower detaches soft-follow (peek
    // without leaving) — it does not end the session or change the presenter.
    _registeredService = _service..onUserInteraction = _onUserGesture;

    _sessionSub = _service.sessionState.listen(
      _onSession,
      onError: (Object _) {},
    );

    // Cursor / viewport / markers / waveform-identity live in the **active
    // tab's** ProviderContainer, not the root scope — each tab has its own
    // independent waveform state (see TabContainerManager). Bind to the active
    // tab and re-bind whenever it changes, so collaboration always mirrors the
    // waveform the user is actually looking at. (Reading these at the root
    // scope — the bug this fixes — sees dead instances the UI never updates, so
    // nothing was ever broadcast.)
    _activeTabSub = _ref.listen<TabId>(
      activeTabIdProvider,
      (_, _) => _bindActiveTab(),
      fireImmediately: true,
    );

    // Composition follow/detach is local UI state at the root scope (like
    // followDetachedProvider). Detaching restores the follower's own workspace;
    // resuming re-applies the presenter's latest composition.
    _compositionDetachedSub = _ref.listen<bool>(
      compositionDetachedProvider,
      (_, detached) => _onCompositionDetachedChanged(detached: detached),
    );
  }

  /// (Re)bind the cursor/viewport/marker/identity subscriptions to the active
  /// tab's container (or the root [_ref] when no tab container is available).
  /// Called on start and whenever the active tab changes.
  void _bindActiveTab() {
    if (_disposed) return;
    _cursorSub?.close();
    _viewportSub?.close();
    _markerSub?.close();
    _identitySub?.close();
    _playbackSub?.close();
    _annotationSub?.close();
    _editingSub?.close();

    final container = _resolveActiveContainer();
    _activeContainer = container;

    // Reading sources from the active tab's container when present, the root
    // [_ref] otherwise (unit tests / non-tabbed host). Both expose the same
    // listen<T> shape, so a single binding body covers both.
    if (container != null) {
      _cursorSub = container.listen<CursorState>(
        cursorStateProvider,
        (_, next) => _onCursor(next),
      );
      // Listen to the source [timeMapperProvider] (a Notifier) rather than the
      // derived [visibleTimeRangeProvider]: an autoDispose *computed* provider
      // listened only from another provider does not reliably recompute-and-
      // notify, whereas the source Notifier always does.
      _viewportSub = container.listen<TimeMapper>(
        timeMapperProvider,
        (_, mapper) => _scheduleViewport(
          (mapper.visibleStartTime, mapper.visibleEndTime),
        ),
      );
      _markerSub = container.listen<MarkerState>(
        markerStateProvider,
        _onMarkers,
      );
      _identitySub = container.listen<String?>(
        waveformIdentityProvider,
        (_, hash) => _service.updateWaveformIdentity(hash),
        fireImmediately: true,
      );
      _playbackSub = container.listen<PlaybackState>(
        playbackProvider,
        (_, next) => _onLocalPlayback(next),
      );
      _annotationSub = container.listen<List<Annotation>>(
        annotationsProvider,
        (_, _) => _scheduleAnnotationPublish(),
      );
      _editingSub = container.listen<String?>(
        annotationBeingEditedProvider,
        (_, next) => _onEditingChanged(next),
      );
    } else {
      // Root fallback (unit tests / non-tabbed host).
      _cursorSub = _ref.listen<CursorState>(
        cursorStateProvider,
        (_, next) => _onCursor(next),
      );
      _viewportSub = _ref.listen<TimeMapper>(
        timeMapperProvider,
        (_, mapper) => _scheduleViewport(
          (mapper.visibleStartTime, mapper.visibleEndTime),
        ),
      );
      _markerSub = _ref.listen<MarkerState>(markerStateProvider, _onMarkers);
      _identitySub = _ref.listen<String?>(
        waveformIdentityProvider,
        (_, hash) => _service.updateWaveformIdentity(hash),
        fireImmediately: true,
      );
      _playbackSub = _ref.listen<PlaybackState>(
        playbackProvider,
        (_, next) => _onLocalPlayback(next),
      );
      _annotationSub = _ref.listen<List<Annotation>>(
        annotationsProvider,
        (_, _) => _scheduleAnnotationPublish(),
      );
      _editingSub = _ref.listen<String?>(
        annotationBeingEditedProvider,
        (_, next) => _onEditingChanged(next),
      );
    }

    // Composition-relevant providers (per-tab, plus the root translator
    // library) drive the outbound presenter mirror on structural change.
    _bindCompositionListeners();

    // If a session is already live and the user just switched tabs, re-baseline
    // markers and re-push the now-active tab's cursor (presence, always) and —
    // only while presenting — its viewport, so peers see the waveform this
    // participant is now looking at.
    if (_inSession) {
      final container = _activeContainer;
      _lastMarkers = container != null
          ? container.read(markerStateProvider)
          : _ref.read(markerStateProvider);
      _resetAnnotationBaseline();
      final cursor = container != null
          ? container.read(cursorStateProvider)
          : _ref.read(cursorStateProvider);
      _service.pushCursorUpdate(
        cursor.primaryCursorTime,
        cursor.secondaryCursorTime,
      );
      if (_isLocalPresenter) {
        final mapper = container != null
            ? container.read(timeMapperProvider)
            : _ref.read(timeMapperProvider);
        _service.pushViewportUpdate(
          mapper.visibleStartTime,
          mapper.visibleEndTime,
        );
      }
    }
  }

  /// The active tab's [ProviderContainer], or `null` when the tab system is not
  /// available (unit tests / non-tabbed host) — callers then fall back to
  /// [_ref] (the root container).
  ProviderContainer? _resolveActiveContainer() => _resolveTabContainer(_ref);

  /// Read [provider] from the active tab's container when present, the root
  /// [_ref] otherwise. Root-scoped providers (e.g. the translator library) read
  /// correctly through the per-tab container too — it delegates to the parent.
  T _read<T>(ProviderListenable<T> provider) => _activeContainer != null
      ? _activeContainer!.read(provider)
      : _ref.read(provider);

  /// The active tab's current [CursorState] (root fallback in tests).
  CursorState get _activeCursor => _activeContainer != null
      ? _activeContainer!.read(cursorStateProvider)
      : _ref.read(cursorStateProvider);

  /// The active tab's current [PlaybackState] (root fallback in tests).
  PlaybackState get _activePlayback => _activeContainer != null
      ? _activeContainer!.read(playbackProvider)
      : _ref.read(playbackProvider);

  /// The active tab's [PlaybackNotifier] (root fallback in tests).
  PlaybackNotifier get _activePlaybackNotifier => _activeContainer != null
      ? _activeContainer!.read(playbackProvider.notifier)
      : _ref.read(playbackProvider.notifier);

  /// The active tab's [CursorStateNotifier] (root fallback in tests).
  CursorStateNotifier get _activeCursorNotifier => _activeContainer != null
      ? _activeContainer!.read(cursorStateProvider.notifier)
      : _ref.read(cursorStateProvider.notifier);

  /// The active tab's [TimeMapperNotifier] (root fallback in tests).
  TimeMapperNotifier get _activeTimeMapperNotifier => _activeContainer != null
      ? _activeContainer!.read(timeMapperProvider.notifier)
      : _ref.read(timeMapperProvider.notifier);

  /// Release subscriptions + cancel the debounce timer. Safe to call repeatedly.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _registeredService?.onUserInteraction = null;
    _registeredService = null;
    unawaited(_sessionSub?.cancel());
    _sessionSub = null;
    _activeTabSub?.close();
    _activeTabSub = null;
    _cursorSub?.close();
    _cursorSub = null;
    _viewportSub?.close();
    _viewportSub = null;
    _markerSub?.close();
    _markerSub = null;
    _identitySub?.close();
    _identitySub = null;
    _playbackSub?.close();
    _playbackSub = null;
    _annotationSub?.close();
    _annotationSub = null;
    _editingSub?.close();
    _editingSub = null;
    _annotationDebounce.dispose();
    for (final sub in _compositionSubs) {
      sub.close();
    }
    _compositionSubs.clear();
    _compositionDetachedSub?.close();
    _compositionDetachedSub = null;
    _viewportDebounce.dispose();
    _compositionDebounce.dispose();
    _activeContainer = null;
  }

  // ── session lifecycle ───────────────────────────────────────────────────────

  void _onSession(CollabSessionState? state) {
    if (state == null) {
      // Session ended (left / stopped / transport dropped). Stop mirroring and
      // clear presenter/transport tracking so a later session starts from a
      // clean baseline. Soft-follow detach is local UI state — clear it too so
      // the next session starts following.
      _inSession = false;
      _isLocalPresenter = false;
      _afViewport = null;
      _lastPushedTransport = null;
      _lastAppliedTransport = null;
      _ref.read(followDetachedProvider.notifier).resume();
      // Composition overlay is a transient session scope: restore the
      // follower's own workspace and clear all composition tracking so the next
      // session starts from a clean baseline following the presenter again.
      _restoreSavedComposition();
      _ref.read(compositionDetachedProvider.notifier).resume();
      _latestComposition = null;
      _lastMirroredComposition = null;
      _compositionDebounce.cancel();
      // Annotations authored in the session stay on the local canvas; what is
      // dropped is only the bookkeeping about what the *room* knew. The adoption
      // prompt decides
      // what happens to everyone else's notes when a session ends.
      _annotationDebounce.cancel();
      _offerAnnotationAdoption();
      _baselineAnnotationIds.clear();
      _publishedAnnotations.clear();
      _confirmedInRoom.clear();
      _writingAnnotationId = null;
      _lastLiveSession = null;
      return;
    }
    _lastLiveSession = state;
    final wasLocalPresenter = _isLocalPresenter;
    _isLocalPresenter = state.isLocalPresenter;

    // Becoming the presenter (handoff to us) makes soft-follow meaningless — we
    // drive now, not follow — so clear any local detach. We now broadcast our
    // own composition ("let me show you my setup"), so reset the mirror dedupe
    // and re-send even if it matches the prior presenter's recipe.
    if (_isLocalPresenter && !wasLocalPresenter) {
      _ref.read(followDetachedProvider.notifier).resume();
      _lastMirroredComposition = null;
      _scheduleCompositionMirror();
    }

    if (!_inSession) {
      // First state on the stream = session just started. Reset the marker
      // baseline to the current markers so pre-existing markers are not
      // replayed as fresh adds, then push the current cursor (presence) and —
      // only while presenting — the viewport, so peers see this participant's
      // starting position immediately.
      _inSession = true;
      final container = _activeContainer;
      _lastMarkers = container != null
          ? container.read(markerStateProvider)
          : _ref.read(markerStateProvider);
      // Same idea as the marker baseline, and load-bearing for the colour rule:
      // every note already on the canvas is invisible to the room forever.
      _resetAnnotationBaseline();
      final cursor = container != null
          ? container.read(cursorStateProvider)
          : _ref.read(cursorStateProvider);
      _service.pushCursorUpdate(
        cursor.primaryCursorTime,
        cursor.secondaryCursorTime,
      );
      if (_isLocalPresenter) {
        final mapper = container != null
            ? container.read(timeMapperProvider)
            : _ref.read(timeMapperProvider);
        _service.pushViewportUpdate(
          mapper.visibleStartTime,
          mapper.visibleEndTime,
        );
        // Broadcast the presenter's initial composition so followers (and late
        // joiners, via the host snapshot) converge on the starting view.
        _scheduleCompositionMirror();
      }
    }
    _applyPresenter(state);
    _applyTransport(state.presenterTransport);
    _applyPresenterComposition(state);
    _applyRemovedAnnotations(state);
  }

  // ── collaborative annotations ─────────────────────────────────

  /// The active tab's annotation list (root fallback in tests).
  List<Annotation> get _localAnnotations => _activeContainer != null
      ? _activeContainer!.read(annotationsProvider)
      : _ref.read(annotationsProvider);

  AnnotationsNotifier get _localAnnotationsNotifier => _activeContainer != null
      ? _activeContainer!.read(annotationsProvider.notifier)
      : _ref.read(annotationsProvider.notifier);

  /// Declare every note currently on the canvas pre-existing, and forget what
  /// was published before.
  ///
  /// Called when a session starts and whenever the active tab changes — the
  /// same treatment [_onMarkers] gives the marker baseline, for the same
  /// reason: the bridge mirrors one tab at a time, and a diff taken across a
  /// tab switch would read the other tab's notes as a mass deletion. The cost
  /// is that notes published from a tab you have since left cannot be retracted
  /// until the session ends, which is exactly what already happens to shared
  /// markers.
  void _resetAnnotationBaseline() {
    _annotationDebounce.cancel();
    _baselineAnnotationIds
      ..clear()
      ..addAll(_localAnnotations.map((a) => a.id));
    _publishedAnnotations.clear();
    _confirmedInRoom.clear();
    _writingAnnotationId = null;
  }

  /// Coalesce a burst of authoring edits into one publish pass.
  ///
  /// Every mutation path funnels through `annotationsProvider`, so this one
  /// listener covers create, text commit, balloon drag, band-edge drag,
  /// keyboard nudge, collapse and delete — including any path added later,
  /// which is the reason it diffs state rather than being called from each of
  /// them.
  void _scheduleAnnotationPublish() {
    if (!_inSession) return;
    _annotationDebounce.run(_publishAnnotations);
  }

  /// Publish the outbound diff: notes authored since the session began that the
  /// room does not have or no longer matches, and retractions for ones deleted.
  void _publishAnnotations() {
    if (_disposed || !_inSession) return;

    final local = _localAnnotations;
    final seen = <String>{};
    for (final annotation in local) {
      seen.add(annotation.id);
      // Pre-existing notes are the room's business never; the note whose editor
      // is open is its business not yet.
      if (_baselineAnnotationIds.contains(annotation.id)) continue;
      if (annotation.id == _writingAnnotationId) continue;

      final published = _publishedAnnotations[annotation.id];
      if (published == null) {
        _publishedAnnotations[annotation.id] = annotation;
        // authorId is stamped by the service from the session identity — a note
        // arriving with somebody else's id would inherit their rights.
        _service.addAnnotation(
          CollabAnnotation(authorId: '', annotation: annotation),
        );
      } else if (published != annotation) {
        _publishedAnnotations[annotation.id] = annotation;
        _service.updateAnnotation(
          CollabAnnotation(authorId: '', annotation: annotation),
        );
      }
    }

    for (final id in _publishedAnnotations.keys.toList()) {
      if (seen.contains(id)) continue;
      _publishedAnnotations.remove(id);
      _confirmedInRoom.remove(id);
      _service.removeAnnotation(id);
    }
  }

  /// Announce (or retract) the writing chip, and publish the note the moment
  /// its editor closes.
  ///
  /// This is the whole of "broadcast on commit": while the field has focus the
  /// room gets one frame saying *who* and *where*, and when focus leaves it
  /// gets the note. Nothing in between — an editor that wired `onChanged`
  /// through to the service would be the defect this shape exists to prevent.
  void _onEditingChanged(String? next) {
    if (!_inSession) {
      _writingAnnotationId = next;
      return;
    }
    final previous = _writingAnnotationId;
    _writingAnnotationId = next;

    if (previous != null && previous != next) {
      _service.setWritingAnnotation(writing: false);
      // Flush immediately rather than on the debounce: the commit *is* the
      // moment, and a note that appears in the room a third of a second after
      // the author pressed Enter reads as lag.
      _publishAnnotations();
    }
    if (next == null) return;

    Annotation? target;
    for (final annotation in _localAnnotations) {
      if (annotation.id == next) {
        target = annotation;
        break;
      }
    }
    // A note that existed before the session began is not the room's, so
    // editing it announces nothing either.
    if (target == null || _baselineAnnotationIds.contains(next)) return;
    _service.setWritingAnnotation(
      writing: true,
      time: target.sortTime,
      rowId: target.rowId,
    );
  }

  /// Drop a note the **host** removed from the local canvas too.
  ///
  /// Rights are author-only with the host as the sole exception, so this is the
  /// one way your own work disappears without you doing anything. The status-bar
  /// notice already tells you it happened
  /// ([CollabSessionState.removedAnnotationNotice]); leaving the note on your
  /// canvas would make that notice describe something you can still see, and
  /// the next edit would republish it into a room that had just rejected it.
  /// Hand the just-ended session's notes to the adoption prompt.
  ///
  /// Runs on the `null` that ends the session, from [_lastLiveSession] — the
  /// terminal state carries nothing. Two things are resolved here and nowhere
  /// downstream: **whose note it is**, by participant id rather than by the
  /// display name on the note (two people called Martin must not inherit each
  /// other's work), and **which palette slot each author held**, which stops
  /// being knowable the moment the roster is gone.
  ///
  /// The local participant's own notes are included. They are already on the
  /// canvas as loose local notes, so adoption *moves* them into the layer
  /// rather than duplicating them — [AnnotationsNotifier.add] ignores a
  /// duplicate id, which is what makes "Keep all" idempotent against the copy
  /// the author already has.
  void _offerAnnotationAdoption() {
    final session = _lastLiveSession;
    if (session == null || session.annotations.isEmpty) return;

    final slots = {for (final p in session.participants) p.id: p.colorIndex};
    final candidates = [
      for (final entry in session.annotations)
        AdoptableAnnotation(
          annotation: entry.annotation,
          isMine: entry.authorId == session.myParticipantId,
          colorIndex: slots[entry.authorId],
        ),
    ];

    _readAdoptionNotifier().offer(
      PendingAdoption(
        candidates: candidates,
        participantCount: session.participants.length,
        endedAt: DateTime.now(),
        sessionId: session.sessionId,
      ),
    );
  }

  AnnotationAdoption _readAdoptionNotifier() => _activeContainer != null
      ? _activeContainer!.read(annotationAdoptionProvider.notifier)
      : _ref.read(annotationAdoptionProvider.notifier);

  void _applyRemovedAnnotations(CollabSessionState state) {
    final roomIds = {for (final entry in state.annotations) entry.id};
    for (final id in _publishedAnnotations.keys.toList()) {
      if (roomIds.contains(id)) {
        _confirmedInRoom.add(id);
        continue;
      }
      // Never seen in the room: the publish did not land, which is not the same
      // event and must not cost the author their note.
      if (!_confirmedInRoom.remove(id)) continue;
      // Dropped from our own bookkeeping BEFORE the local delete, so the
      // resulting `annotationsProvider` change does not diff into a second,
      // outbound removal of a note the room has already forgotten.
      _publishedAnnotations.remove(id);
      _localAnnotationsNotifier.remove(id);
    }
  }

  // ── presenter follow (inbound) ───────────────────────────────────────────────

  /// Drive the local viewport to mirror the **presenter's** broadcast viewport.
  ///
  /// No-op when local-is-presenter (we drive, not follow) or while the local
  /// follower is [followDetachedProvider] detached (soft-follow peek). The
  /// presenter's *cursor* is shown as a distinguished overlay cursor rather than
  /// moving the local cursor; only the viewport is mirrored here (the shared
  /// playhead syncs via [_applyTransport]). The applied viewport is recorded in
  /// [_afViewport] so the outbound listener recognises and ignores its own echo
  /// (and does not misclassify it as a local navigation that would detach).
  void _applyPresenter(CollabSessionState state) {
    if (_isLocalPresenter) {
      _afViewport = null;
      return;
    }
    if (_ref.read(followDetachedProvider)) {
      // Detached: leave the local viewport alone. Drop the echo record so a
      // later genuine local gesture is correctly seen as local.
      _afViewport = null;
      return;
    }

    final presenter = state.presenter;
    if (presenter == null) return;
    if (presenter.viewportEnd <= presenter.viewportStart) return;

    _applyingInbound = true;
    try {
      _activeTimeMapperNotifier.zoomToRange(
        presenter.viewportStart,
        presenter.viewportEnd,
      );
      final mapper = _activeContainer != null
          ? _activeContainer!.read(timeMapperProvider)
          : _ref.read(timeMapperProvider);
      _afViewport = (mapper.visibleStartTime, mapper.visibleEndTime);
    } finally {
      _applyingInbound = false;
    }
  }

  // ── shared playhead (inbound) ────────────────────────────────────────────────

  /// Drive the local playback ticker from the presenter's [transport] so the
  /// whole room animates in lockstep — "sync the clock, not the frames".
  ///
  /// No-op when local-is-presenter (we are the source) or while detached. The
  /// transport *state* is applied to the local [PlaybackNotifier]; its ticker
  /// then advances the primary cursor locally (recognised as
  /// non-local-navigation by [_onCursor]'s playing-guard, so it never
  /// self-detaches or re-broadcasts per-frame positions).
  void _applyTransport(CollabPlaybackTransport? transport) {
    if (transport == null) return;
    if (_isLocalPresenter) return;
    if (_ref.read(followDetachedProvider)) return;
    if (transport == _lastAppliedTransport) return;
    _lastAppliedTransport = transport;

    _applyingInbound = true;
    try {
      final playback = _activePlaybackNotifier
        ..setSpeed(transport.speed)
        ..setLoopMode(transport.loopMode);

      if (transport.isPlaying) {
        // Seed the room's shared anchor before starting the local ticker so
        // every client's playhead starts from the same tick. For an A–B loop,
        // seed the secondary cursor to the upper bound too so the local
        // PlaybackNotifier computes the identical active range.
        if (transport.loopMode == PlaybackLoopMode.aToB &&
            transport.loopStart != null &&
            transport.loopEnd != null) {
          _activeCursorNotifier.placeSecondary(transport.loopEnd!);
        }
        _activeCursorNotifier.placePrimary(transport.anchorTime);
        if (!_activePlayback.isPlaying) playback.play();
      } else {
        if (_activePlayback.isPlaying) playback.pause();
      }
    } finally {
      _applyingInbound = false;
    }
  }

  // ── shared playhead (outbound) ───────────────────────────────────────────────

  /// Mirror the local playback transport to the room — **only while
  /// local-is-presenter**. Deduped against the last pushed transport so an
  /// unchanged state is not re-broadcast. Followers never broadcast transport
  /// (their playback is inbound-driven).
  void _onLocalPlayback(PlaybackState playback) {
    if (!_inSession || !_isLocalPresenter) return;
    if (_applyingInbound) return;
    final cursor = _activeCursor;
    int? loopStart;
    int? loopEnd;
    if (playback.loopMode == PlaybackLoopMode.aToB) {
      final primary = cursor.primaryCursorTime;
      final secondary = cursor.secondaryCursorTime;
      if (primary != null && secondary != null) {
        loopStart = primary < secondary ? primary : secondary;
        loopEnd = primary < secondary ? secondary : primary;
      }
    }
    final transport = CollabPlaybackTransport(
      isPlaying: playback.isPlaying,
      speed: playback.speed,
      loopMode: playback.loopMode,
      // The anchor is where playback resumes from — the current primary cursor.
      anchorTime: cursor.primaryCursorTime ?? 0,
      loopStart: loopStart,
      loopEnd: loopEnd,
    );
    if (transport == _lastPushedTransport) return;
    _lastPushedTransport = transport;
    _service.pushPlaybackTransport(transport);
  }

  /// Called by the service after a local gesture (registered as
  /// [CollaborationService.onUserInteraction]). A non-presenter gesture marks
  /// soft-follow detached — peek without leaving. It never ends the session or
  /// changes the presenter. The cursor/viewport listeners detect navigation
  /// too; this covers gestures that don't move either (e.g. a press).
  void _onUserGesture() {
    if (!_inSession || _isLocalPresenter || _applyingInbound) return;
    _ref.read(followDetachedProvider.notifier).detach();
  }

  // ── cursor ──────────────────────────────────────────────────────────────────

  void _onCursor(CursorState next) {
    if (!_inSession) return;
    // Suppress the echo of a cursor we just applied while mirroring inbound
    // state (seeding the playhead anchor).
    if (_applyingInbound) return;
    // While the local playhead is advancing (presenter playing, or follower
    // driven by the presenter's transport) the cursor churns every frame: never
    // broadcast per-frame positions, and never treat the ticker's own advances
    // as a local-navigation detach. The shared transport keeps the room in
    // lockstep instead.
    if (_activePlayback.isPlaying) return;

    // A genuine local cursor move by a follower is local navigation → detach
    // soft-follow (peek without leaving).
    if (!_isLocalPresenter) {
      _ref.read(followDetachedProvider.notifier).detach();
    }
    // Always mirror the local cursor regardless of who presents (presence).
    _service.pushCursorUpdate(next.primaryCursorTime, next.secondaryCursorTime);
  }

  // ── viewport (debounced) ──────────────────────────────────────────────────

  void _scheduleViewport((int, int) range) {
    if (!_inSession) return;
    // Suppress the echo of a viewport we just applied from the presenter.
    if (_applyingInbound) return;
    if (range == _afViewport) return;

    if (!_isLocalPresenter) {
      // Followers never broadcast their viewport. A local pan/zoom that is not
      // the playback ticker's own recentre is local navigation → detach.
      if (!_activePlayback.isPlaying) {
        _ref.read(followDetachedProvider.notifier).detach();
      }
      return;
    }

    // Presenter: broadcast the viewport (debounced), including playback
    // auto-recentres so followers track the playhead.
    _viewportDebounce.run(() {
      if (_disposed || !_inSession || !_isLocalPresenter) return;
      _service.pushViewportUpdate(range.$1, range.$2);
    });
  }

  // ── markers ─────────────────────────────────────────────────────────────────

  void _onMarkers(MarkerState? previous, MarkerState next) {
    if (!_inSession) {
      // Keep the baseline current so the first in-session diff only reports
      // changes made *after* the session began.
      _lastMarkers = next;
      return;
    }
    final prev = _lastMarkers;
    final allNames = <String>{...prev.markers.keys, ...next.markers.keys};
    for (final name in allNames) {
      final prevTime = prev.markers[name];
      final nextTime = next.markers[name];
      if (prevTime == nextTime) continue;
      if (nextTime == null) {
        unawaited(_service.removeSharedMarker(name));
      } else {
        unawaited(_service.addSharedMarker(name, nextTime));
      }
    }
    _lastMarkers = next;
  }

  // ── view composition (outbound mirror) ────────────────────────────────────

  /// (Re)bind the composition listeners to the active tab's per-tab providers
  /// (signals / decoders / Stage / FSM / panel) plus the root translator
  /// library. A structural change to any of them schedules a debounced mirror
  /// of the local composition — but only while local-is-presenter.
  void _bindCompositionListeners() {
    for (final sub in _compositionSubs) {
      sub.close();
    }
    _compositionSubs.clear();
    void onChange() => _scheduleCompositionMirror();

    final container = _activeContainer;
    if (container != null) {
      _compositionSubs.addAll([
        container.listen(signalGroupsProvider, (_, _) => onChange()),
        container.listen(activeDecodersProvider, (_, _) => onChange()),
        container.listen(stageWorkspaceProvider, (_, _) => onChange()),
        container.listen(fsmProvider, (_, _) => onChange()),
        container.listen(panelLayoutProvider, (_, _) => onChange()),
      ]);
    } else {
      _compositionSubs.addAll([
        _ref.listen(signalGroupsProvider, (_, _) => onChange()),
        _ref.listen(activeDecodersProvider, (_, _) => onChange()),
        _ref.listen(stageWorkspaceProvider, (_, _) => onChange()),
        _ref.listen(fsmProvider, (_, _) => onChange()),
        _ref.listen(panelLayoutProvider, (_, _) => onChange()),
      ]);
    }
    // The translator library is root-scoped (not per-tab); always via _ref.
    _compositionSubs.add(
      _ref.listen(customTranslatorsProvider, (_, _) => onChange()),
    );
  }

  /// Coalesce a burst of structural edits into one outbound composition
  /// broadcast. No-op unless in a session and local-is-presenter; deduped
  /// against the last mirrored recipe so an unchanged composition is not
  /// re-sent.
  void _scheduleCompositionMirror() {
    if (!_inSession || !_isLocalPresenter) return;
    _compositionDebounce.run(() {
      if (_disposed || !_inSession || !_isLocalPresenter) return;
      final composition = _serializeLocalComposition();
      if (composition == null) return;
      if (composition == _lastMirroredComposition) return;
      _lastMirroredComposition = composition;
      _service.updateViewComposition(composition);
    });
  }

  /// Serialize the active tab's view composition into a signal-identity-based
  /// recipe, or `null` when no waveform is loaded (nothing to describe).
  CollabViewComposition? _serializeLocalComposition() {
    final source = _read(waveformSourceProvider).value;
    if (source == null) return null;
    final resolver = SignalIdentityResolver.fromSource(source);
    return CollabViewComposition(
      displayedSignals: _read(
        signalGroupsProvider.notifier,
      ).toCompositionRecipe(),
      decoders: _read(
        activeDecodersProvider.notifier,
      ).toCompositionRecipe(resolver),
      translators: _read(
        customTranslatorsProvider.notifier,
      ).toCompositionRecipe(),
      stageWorkspace: _read(
        stageWorkspaceProvider.notifier,
      ).toCompositionRecipe(resolver),
      fsmTargetPath: _read(fsmProvider.notifier).toCompositionRecipe(resolver),
      panelVisibility: _read(
        panelLayoutProvider.notifier,
      ).toCompositionRecipe(),
    );
  }

  // ── view composition (inbound overlay) ────────────────────────────────────

  /// Apply the presenter's composition from [state] as a non-destructive
  /// overlay, capturing the follower's own workspace before the first overlay
  /// and re-applying nothing while composition-detached. No-op (with a restore)
  /// when local-is-presenter — a presenter drives rather than follows.
  void _applyPresenterComposition(CollabSessionState state) {
    if (_isLocalPresenter) {
      // We now drive. The overlay currently on screen — the *previous*
      // presenter's composition — is the correct starting point for the new
      // driver ("you take it from here"), so keep it and only drop the overlay
      // bookkeeping. Reverting to our pre-overlay workspace here was a bug: a
      // follower who joined and immediately adopted the presenter's view has an
      // *empty* saved workspace, so restoring it wiped the room's signals — and
      // the becoming-presenter mirror (scheduled in [_onSession]) then
      // broadcast that empty list to every follower 300 ms later.
      _clearOverlayBookkeeping();
      return;
    }
    final composition = state.viewComposition;
    if (composition == null) return;
    _latestComposition = composition;
    if (_ref.read(compositionDetachedProvider)) return;
    if (_compositionApplied && composition == _lastAppliedComposition) return;

    if (!_compositionApplied) {
      _savedComposition = _serializeLocalComposition();
      _compositionApplied = true;
    }
    _applyComposition(composition, reportDegradation: true);
    _lastAppliedComposition = composition;
  }

  /// Reconstruct [composition] against the local waveform inside the transient
  /// session scope: apply each dimension's recipe via its provider's apply
  /// seam, then decode the applied decoders against local data. Missing
  /// references are collected and (when [reportDegradation]) surfaced through
  /// [collabCompositionDegradationProvider] for the Pro mismatch banner.
  void _applyComposition(
    CollabViewComposition composition, {
    required bool reportDegradation,
  }) {
    final source = _read(waveformSourceProvider).value;
    if (source == null) return;
    final resolver = SignalIdentityResolver.fromSource(source);

    final missingSignals = <String>{};
    final missingDecoders = <String>{};
    final missingWidgets = <String>{};

    // Translators first so per-signal translator bindings resolve.
    _read(
      customTranslatorsProvider.notifier,
    ).applyCompositionRecipe(composition.translators);
    missingSignals.addAll(
      _read(
        signalGroupsProvider.notifier,
      ).applyCompositionRecipe(composition.displayedSignals, resolver),
    );
    final decoderResult = _read(
      activeDecodersProvider.notifier,
    ).applyCompositionRecipe(composition.decoders, resolver);
    missingDecoders.addAll(decoderResult.missingDecoderIds);
    missingSignals.addAll(decoderResult.missingSignalPaths);
    final stageResult = _read(
      stageWorkspaceProvider.notifier,
    ).applyCompositionRecipe(composition.stageWorkspace, resolver);
    missingWidgets.addAll(stageResult.missingWidgetIds);
    missingSignals
      ..addAll(stageResult.missingSignalPaths)
      ..addAll(
        _read(
          fsmProvider.notifier,
        ).applyCompositionRecipe(composition.fsmTargetPath, resolver),
      );
    _read(
      panelLayoutProvider.notifier,
    ).applyCompositionRecipe(composition.panelVisibility);

    // Re-run the just-applied decoders against the follower's own data.
    unawaited(_read(activeDecodersProvider.notifier).decodeAll());

    if (reportDegradation) {
      _ref
          .read(collabCompositionDegradationProvider.notifier)
          .report(
            CollabCompositionDegradation(
              missingSignalPaths: missingSignals.toList(),
              missingDecoderIds: missingDecoders.toList(),
              missingWidgetIds: missingWidgets.toList(),
            ),
          );
    }
  }

  /// Restore the follower's own composition (captured before the first overlay)
  /// and clear all overlay bookkeeping + degradation. No-op when no overlay is
  /// applied.
  void _restoreSavedComposition() {
    if (!_compositionApplied) return;
    final saved = _savedComposition;
    if (saved != null) {
      _applyComposition(saved, reportDegradation: false);
    }
    _clearOverlayBookkeeping();
  }

  /// Drop the overlay bookkeeping (and clear any degradation report) **without**
  /// reverting the on-screen composition. Used when a follower becomes the
  /// presenter: the overlay they were following is kept as their new
  /// authoritative workspace rather than being restored away. Safe to call when
  /// no overlay is active (it just resets already-clear state).
  void _clearOverlayBookkeeping() {
    _ref.read(collabCompositionDegradationProvider.notifier).clear();
    _compositionApplied = false;
    _savedComposition = null;
    _lastAppliedComposition = null;
  }

  /// Driven by [compositionDetachedProvider]: a follower detaching fully
  /// restores their own workspace; resuming re-applies the presenter's latest
  /// composition as a fresh overlay.
  void _onCompositionDetachedChanged({required bool detached}) {
    if (!_inSession || _isLocalPresenter) return;
    if (detached) {
      _restoreSavedComposition();
      return;
    }
    // Resume following: re-overlay the presenter's most recent composition.
    final composition = _latestComposition;
    if (composition == null) return;
    _savedComposition = _serializeLocalComposition();
    _compositionApplied = true;
    _applyComposition(composition, reportDegradation: true);
    _lastAppliedComposition = composition;
  }
}
