// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Open-core extension point for Enterprise-tier collaborative viewing.
///
/// Open-core ships [NoopCollaborationService] as the default — no network
/// calls, no dependencies, every query returns a neutral value. The closed-
/// source Pro overlay replaces this binding via
/// [collaborationServiceProvider] with `CollaborationServiceImpl` that runs
/// real WebSocket sessions (LAN direct or WAN relay).
///
/// Callers must never assume the implementation is network-capable. All
/// interactive entry points route through `FeatureGate.isAvailable` with
/// `LicenseTier.enterprise` so that Open Core and Pro builds remain
/// unaffected when the no-op is active.
///
/// The transport — hybrid LAN direct or WAN relay, the message envelope,
/// participant colour assignment, follow-mode provider interception — lives
/// entirely in the Pro overlay; this file is only the contract it fills.
library;

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/domain/models/collab_view_composition.dart';
import 'package:wavecrux/domain/models/playback_state.dart';

/// Network mode for a collaborative session.
enum CollabMode {
  /// Not in a session.
  none,

  /// Peer-to-peer over LAN via mDNS + direct WebSocket.
  lan,

  /// Relay-routed via the Ferrite relay server.
  wan,
}

/// Snapshot of one participant's visible state.
///
/// [colorIndex] is a value 0–7 cycling through the palette defined by the Pro
/// overlay's `CollaborationServiceImpl`. The UI layer maps this index to an
/// actual [Color]; the domain layer stays free of `dart:ui`.
@immutable
final class ParticipantInfo {
  const ParticipantInfo({
    required this.id,
    required this.displayName,
    required this.colorIndex,
    required this.viewportStart,
    required this.viewportEnd,
    required this.isHost,
    this.joinSequence = 0,
    this.primaryCursorTime,
    this.secondaryCursorTime,
    this.waveformContentHash,
  });

  final String id;
  final String displayName;
  final int colorIndex;
  final int? primaryCursorTime;
  final int? secondaryCursorTime;
  final int viewportStart;
  final int viewportEnd;
  final bool isHost;

  /// Host-assigned, monotonically increasing arrival order. The host stamps
  /// each participant with the next sequence number as they join, so this is a
  /// **logical clock**, not a wall-clock timestamp — it stays deterministic and
  /// skew-free across machines.
  ///
  /// Presenter-Mode auto-promotion uses it to pick the *oldest
  /// remaining* participant when the host drops: sort by [joinSequence]
  /// ascending and take the first. Defaults to `0` for participants whose
  /// sequence has not yet been assigned (e.g. the open-core no-op path, which
  /// never runs a real session).
  final int joinSequence;

  /// SHA-256 content hash of the waveform file this participant has loaded, or
  /// `null` if they have not yet reported one (no file open, a streaming
  /// source, or the announcement has not arrived yet).
  ///
  /// Used by [CollabSessionState.hasWaveformMismatch] to detect participants
  /// who are looking at a *different* waveform than the rest of the room. Only
  /// the digest crosses the network — never sample data.
  final String? waveformContentHash;

  ParticipantInfo copyWith({
    String? id,
    String? displayName,
    int? colorIndex,
    int? joinSequence,
    int? primaryCursorTime,
    bool clearPrimaryCursor = false,
    int? secondaryCursorTime,
    bool clearSecondaryCursor = false,
    int? viewportStart,
    int? viewportEnd,
    bool? isHost,
    String? waveformContentHash,
    bool clearWaveformContentHash = false,
  }) => ParticipantInfo(
    id: id ?? this.id,
    displayName: displayName ?? this.displayName,
    colorIndex: colorIndex ?? this.colorIndex,
    joinSequence: joinSequence ?? this.joinSequence,
    primaryCursorTime: clearPrimaryCursor
        ? null
        : (primaryCursorTime ?? this.primaryCursorTime),
    secondaryCursorTime: clearSecondaryCursor
        ? null
        : (secondaryCursorTime ?? this.secondaryCursorTime),
    viewportStart: viewportStart ?? this.viewportStart,
    viewportEnd: viewportEnd ?? this.viewportEnd,
    isHost: isHost ?? this.isHost,
    waveformContentHash: clearWaveformContentHash
        ? null
        : (waveformContentHash ?? this.waveformContentHash),
  );

  @override
  bool operator ==(Object other) =>
      other is ParticipantInfo &&
      other.id == id &&
      other.displayName == displayName &&
      other.colorIndex == colorIndex &&
      other.joinSequence == joinSequence &&
      other.primaryCursorTime == primaryCursorTime &&
      other.secondaryCursorTime == secondaryCursorTime &&
      other.viewportStart == viewportStart &&
      other.viewportEnd == viewportEnd &&
      other.isHost == isHost &&
      other.waveformContentHash == waveformContentHash;

  @override
  int get hashCode => Object.hash(
    id,
    displayName,
    colorIndex,
    joinSequence,
    primaryCursorTime,
    secondaryCursorTime,
    viewportStart,
    viewportEnd,
    isHost,
    waveformContentHash,
  );
}

/// Whether the local participant has been admitted to the session by its host.
///
/// A session is joined in two steps: the transport connects and the joiner
/// announces itself, and only then does the **host** admit them. Until that
/// happens the joiner is connected but not a member — it adopts no room state
/// and appears in nobody's roster.
enum CollabAdmission {
  /// The local participant is a member of the session. Always the case for the
  /// host, which admits itself.
  approved,

  /// The local participant has announced itself and is waiting for the host's
  /// approve-or-deny decision. The transport is up, but no room state has been
  /// adopted.
  awaitingApproval,
}

/// How the most recent [CollaborationService.joinSession] attempt ended.
///
/// Read after `joinSession` returns (and again once a pending admission
/// resolves) so the join UI can say what actually happened rather than
/// collapsing every failure into "couldn't connect".
enum CollabJoinOutcome {
  /// No join has been attempted in this app run.
  none,

  /// Connected and admitted — the local participant is in the session.
  connected,

  /// Connected and announced; the host has not yet approved or denied. The
  /// outcome moves to [connected], [denied] or [timedOut] when it resolves.
  awaitingApproval,

  /// The host explicitly denied the join request.
  denied,

  /// No admission decision arrived before the local deadline expired (a host
  /// that walked away, or one that dropped while the request was pending).
  timedOut,

  /// The transport never came up — relay unreachable, LAN host not found, port
  /// refused.
  connectFailed,

  /// The invite did not parse, so no socket was ever opened. A distinct
  /// outcome on purpose: an invite carries the session key, so a mistyped one
  /// is a *wrong key*, and once a socket is open a wrong key is
  /// indistinguishable from a network failure. Catching it before connecting is
  /// what lets the UI say "check the invite" instead of "check your network".
  invalidInvite,
}

/// A joiner awaiting the host's approve-or-deny admission decision.
///
/// Carried on the host's authoritative full-state snapshot so every client —
/// and a client that is auto-promoted to host mid-request — converges on the
/// same pending set. The joiner is deliberately **not** a [ParticipantInfo]:
/// membership of the roster *is* admission, so a pending joiner has no colour,
/// no join sequence and no cursor.
@immutable
final class CollabJoinRequest {
  const CollabJoinRequest({
    required this.participantId,
    required this.displayName,
  });

  /// The joiner's participant id, as announced in their `hello`.
  final String participantId;

  /// The name the joiner announced. Attacker-controlled text — render it as a
  /// name, never as markup, and never treat it as identity.
  final String displayName;

  @override
  bool operator ==(Object other) =>
      other is CollabJoinRequest &&
      other.participantId == participantId &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(participantId, displayName);
}

/// Complete state broadcast by the session on every participant or cursor
/// change.
@immutable
final class CollabSessionState {
  const CollabSessionState({
    required this.sessionId,
    required this.myParticipantId,
    required this.hostId,
    required this.participants,
    required this.sharedMarkers,
    String? presenterId,
    this.pendingControlRequests = const [],
    this.pendingJoinRequests = const [],
    this.admission = CollabAdmission.approved,
    this.hasUnreadableFrames = false,
    this.pointers = const [],
    this.annotations = const [],
    this.writingAnnotation = const [],
    this.removedAnnotationNotice,
    this.presenterTransport,
    this.incomingScrollRequest,
    this.viewComposition,
    this.followTargetId,
    this.isRecording = false,
  }) : _presenterId = presenterId;

  final String sessionId;
  final String myParticipantId;

  /// The session **initiator**. Immutable for the session's lifetime — the host
  /// owns the session, ends it, sets control policy, and is the authoritative
  /// arbiter of the presenter token. Distinct from [presenterId]:
  /// "host" is who owns the room, "presenter" is who is currently driving it.
  final String hostId;

  /// Backing store for [presenterId]. `null` means "no explicit presenter has
  /// been assigned yet", which resolves to [hostId] — the presenter *defaults
  /// to the host* at session start and the two are the same
  /// participant until the first handoff.
  final String? _presenterId;

  final List<ParticipantInfo> participants;
  final Map<String, int> sharedMarkers;

  /// Participant IDs with an outstanding "request control" prompt awaiting the
  /// presenter/host's approve-or-deny decision (the request → approve/deny
  /// transfer path). Empty when no request is pending. The host rebroadcasts
  /// this list as part of the authoritative full-state snapshot so every client
  /// — and late joiners — converge on the same pending set.
  final List<String> pendingControlRequests;

  /// Joiners who have announced themselves and are awaiting the host's
  /// approve-or-deny **admission** decision. Empty when none are pending, and
  /// always empty on a client that is not the host until the host's
  /// authoritative snapshot carries them.
  ///
  /// Distinct from [pendingControlRequests], which is about the presenter token
  /// among people who are *already* in the room.
  final List<CollabJoinRequest> pendingJoinRequests;

  /// Whether the **local** participant has been admitted. The host is
  /// always [CollabAdmission.approved]; a joiner starts
  /// [CollabAdmission.awaitingApproval] and stays there — connected, but
  /// adopting no room state — until the host approves.
  final CollabAdmission admission;

  /// Whether frames have arrived on this session that its key cannot open
  /// — in practice, someone in the room holding the wrong invite.
  ///
  /// Surfaced rather than swallowed: from the other side the symptom is a
  /// session that connects and then does nothing, and silence would leave both
  /// people who could fix it with no information. Always `false` on LAN, which
  /// has no key. Cleared via
  /// [CollaborationService.dismissUnreadableFramesNotice].
  final bool hasUnreadableFrames;

  /// Live, data-anchored pointers (pings + pins) dropped by participants
  ///. Carried on the authoritative full-state snapshot so the
  /// [SharedPointerOverlay] renders them and late joiners converge on the same
  /// set. Each entry anchors to `(time, rowId)` — never pixels — so it tracks
  /// the presenter's pan/zoom. Empty when no pointers are live (the open-core
  /// no-op path never produces any).
  final List<CollabPointer> pointers;

  /// Annotations authored **inside this session**, carried on the host's
  /// authoritative full-state snapshot exactly as [pointers] are — so late
  /// joiners converge, and entries de-duplicate by id.
  ///
  /// Deliberately separate from a participant's own local annotations, which
  /// never enter this list and never change colour. Joining a session must not
  /// recolour somebody's week-old private notes into their participant colour;
  /// the room would read them as things said in this meeting.
  final List<CollabAnnotation> annotations;

  /// Participants currently composing an annotation, and where.
  ///
  /// A **boolean per participant plus an anchor**, never their text. Keystrokes
  /// are never streamed: a note takes eight seconds to write, nobody needs to
  /// watch it appear letter by letter, and broadcasting on commit avoids
  /// collaborative text editing entirely — no CRDT, no operational transform,
  /// no cursor-in-text-field sync. That is a very large scope saving for a very
  /// small UX cost, and this list is the whole of what replaces it.
  ///
  /// The anchor rides along because the chip that replaces the live text is
  /// drawn **at the anchor**, and until the note is committed there is nothing
  /// else in the room to hang it on — the note itself does not exist for
  /// anyone else yet. See [CollabWritingNote].
  final List<CollabWritingNote> writingAnnotation;

  /// The text of one of **your** annotations that somebody else removed, or
  /// null when there is nothing to report.
  ///
  /// The one place in a session where your own work can disappear without you
  /// doing anything: rights are author-only, so nobody can edit your note out
  /// from under you — but the **host may delete any**, and a note vanishing
  /// mid-sentence with no explanation reads as a bug in the app rather than as
  /// a decision somebody made.
  ///
  /// Local-only: never broadcast, never on the host's snapshot. It is a fact
  /// about what happened *to you*, and the rest of the room already knows.
  /// Cleared via [CollaborationService.dismissRemovedAnnotationNotice].
  final String? removedAnnotationNotice;

  /// The presenter's current playback transport state, or `null` when no
  /// presenter playback is active. Followers drive their own local ticker from
  /// this — "sync the clock, not the frames". Only transport *state*
  /// rides the snapshot; per-frame cursor positions never do.
  final CollabPlaybackTransport? presenterTransport;

  /// A non-presenter's pending "scroll here" nudge surfaced **only to the
  /// current presenter**, or `null` when none is pending. Local to the
  /// presenter's client — never part of the host's authoritative snapshot —
  /// because it is a transient ask, not shared room state. Cleared via
  /// [CollaborationService.dismissScrollRequest].
  final CollabScrollRequest? incomingScrollRequest;

  /// The presenter's current **view-composition recipe** — displayed
  /// signals, decoders, translators, Stage instances, FSM target, and panel
  /// intent — or `null` when no composition has been broadcast yet. Carried on
  /// the host's authoritative full-state snapshot so followers replay it as a
  /// non-destructive overlay and late joiners converge on the presenter's view.
  /// Only the *recipe* rides the snapshot; never sample data or pixels.
  final CollabViewComposition? viewComposition;

  final String? followTargetId;
  final bool isRecording;

  /// The participant currently driving the shared viewport. Defaults to
  /// [hostId] until the first handoff, so this never returns `null`
  /// for a live session.
  String get presenterId => _presenterId ?? hostId;

  /// The [ParticipantInfo] for the current [presenterId], or `null` if that
  /// participant is not present in [participants] (e.g. a transient window
  /// after a presenter drop, before auto-promotion converges).
  ParticipantInfo? get presenter {
    for (final p in participants) {
      if (p.id == presenterId) return p;
    }
    return null;
  }

  /// Whether the local participant is the one currently presenting.
  bool get isLocalPresenter => presenterId == myParticipantId;

  /// Whether the local participant is the session host.
  bool get isLocalHost => hostId == myParticipantId;

  /// Whether any participant is awaiting a control-request decision.
  bool get hasPendingControlRequests => pendingControlRequests.isNotEmpty;

  /// Whether anyone is waiting at the door for the host to let them in.
  bool get hasPendingJoinRequests => pendingJoinRequests.isNotEmpty;

  /// Whether the local participant is connected but not yet admitted.
  bool get isAwaitingAdmission => admission == CollabAdmission.awaitingApproval;

  /// The distinct waveform content hashes reported across all participants.
  ///
  /// Participants who have not announced a hash (no file open, streaming
  /// source, or announcement not yet received) contribute nothing — they are
  /// never treated as a difference, only as "unknown".
  Set<String> get reportedWaveformHashes => {
    for (final p in participants)
      if (p.waveformContentHash != null) p.waveformContentHash!,
  };

  /// Whether participants who *have* reported a waveform hash disagree — i.e.
  /// at least two distinct waveforms are loaded in the room.
  ///
  /// Drives the Pro "different waveform loaded" warning. Returns `false` while
  /// only one (or zero) hashes are known, so the brief window before every
  /// participant's identity propagates does not flash a false warning.
  bool get hasWaveformMismatch => reportedWaveformHashes.length > 1;

  CollabSessionState copyWith({
    String? sessionId,
    String? myParticipantId,
    String? hostId,
    String? presenterId,
    List<ParticipantInfo>? participants,
    Map<String, int>? sharedMarkers,
    List<String>? pendingControlRequests,
    List<CollabJoinRequest>? pendingJoinRequests,
    CollabAdmission? admission,
    bool? hasUnreadableFrames,
    List<CollabPointer>? pointers,
    List<CollabAnnotation>? annotations,
    List<CollabWritingNote>? writingAnnotation,
    String? removedAnnotationNotice,
    bool clearRemovedAnnotationNotice = false,
    CollabPlaybackTransport? presenterTransport,
    bool clearPresenterTransport = false,
    CollabScrollRequest? incomingScrollRequest,
    bool clearIncomingScrollRequest = false,
    CollabViewComposition? viewComposition,
    bool clearViewComposition = false,
    String? followTargetId,
    bool clearFollowTarget = false,
    bool? isRecording,
  }) => CollabSessionState(
    sessionId: sessionId ?? this.sessionId,
    myParticipantId: myParticipantId ?? this.myParticipantId,
    hostId: hostId ?? this.hostId,
    presenterId: presenterId ?? _presenterId,
    participants: participants ?? this.participants,
    sharedMarkers: sharedMarkers ?? this.sharedMarkers,
    pendingControlRequests:
        pendingControlRequests ?? this.pendingControlRequests,
    pendingJoinRequests: pendingJoinRequests ?? this.pendingJoinRequests,
    admission: admission ?? this.admission,
    hasUnreadableFrames: hasUnreadableFrames ?? this.hasUnreadableFrames,
    pointers: pointers ?? this.pointers,
    annotations: annotations ?? this.annotations,
    writingAnnotation: writingAnnotation ?? this.writingAnnotation,
    removedAnnotationNotice: clearRemovedAnnotationNotice
        ? null
        : (removedAnnotationNotice ?? this.removedAnnotationNotice),
    presenterTransport: clearPresenterTransport
        ? null
        : (presenterTransport ?? this.presenterTransport),
    incomingScrollRequest: clearIncomingScrollRequest
        ? null
        : (incomingScrollRequest ?? this.incomingScrollRequest),
    viewComposition: clearViewComposition
        ? null
        : (viewComposition ?? this.viewComposition),
    followTargetId: clearFollowTarget
        ? null
        : (followTargetId ?? this.followTargetId),
    isRecording: isRecording ?? this.isRecording,
  );

  @override
  bool operator ==(Object other) =>
      other is CollabSessionState &&
      other.sessionId == sessionId &&
      other.myParticipantId == myParticipantId &&
      other.hostId == hostId &&
      other.presenterId == presenterId &&
      other.participants == participants &&
      other.sharedMarkers == sharedMarkers &&
      other.pendingControlRequests == pendingControlRequests &&
      other.pendingJoinRequests == pendingJoinRequests &&
      other.admission == admission &&
      other.hasUnreadableFrames == hasUnreadableFrames &&
      other.pointers == pointers &&
      other.annotations == annotations &&
      other.writingAnnotation == writingAnnotation &&
      other.removedAnnotationNotice == removedAnnotationNotice &&
      other.presenterTransport == presenterTransport &&
      other.incomingScrollRequest == incomingScrollRequest &&
      other.viewComposition == viewComposition &&
      other.followTargetId == followTargetId &&
      other.isRecording == isRecording;

  @override
  int get hashCode => Object.hash(
    sessionId,
    myParticipantId,
    hostId,
    presenterId,
    Object.hashAll(participants),
    sharedMarkers,
    Object.hashAll(pendingControlRequests),
    Object.hashAll(pendingJoinRequests),
    admission,
    hasUnreadableFrames,
    Object.hashAll(pointers),
    Object.hashAll(annotations),
    Object.hashAll(writingAnnotation),
    removedAnnotationNotice,
    presenterTransport,
    incomingScrollRequest,
    viewComposition,
    followTargetId,
    isRecording,
  );
}

/// Type of event captured in a session recording.
enum RecordingEventType {
  join,
  leave,
  cursorMove,
  viewportChange,
  markerAdd,
  markerRemove,

  /// A collaborative annotation was created, edited or deleted.
  ///
  /// The audit trail covers markers and cursors; without these it would have a
  /// hole exactly where the *substantive* content is — an annotation is the
  /// only thing in a session that carries an argument in words.
  annotationAdd,
  annotationEdit,
  annotationRemove,
  followStart,
  followEnd,
}

/// A single event captured during a collaborative session.
final class RecordingEvent {
  const RecordingEvent({
    required this.timestamp,
    required this.participantId,
    required this.displayName,
    required this.type,
    this.data = const {},
  });

  final DateTime timestamp;
  final String participantId;
  final String displayName;
  final RecordingEventType type;
  final Map<String, Object?> data;

  Map<String, Object?> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'participantId': participantId,
    'displayName': displayName,
    'type': type.name,
    'data': data,
  };
}

/// Exported recording of a completed or in-progress session.
final class SessionRecording {
  const SessionRecording({
    required this.sessionId,
    required this.startedAt,
    required this.events,
  });

  final String sessionId;
  final DateTime startedAt;
  final List<RecordingEvent> events;

  Map<String, Object?> toJson() => {
    'sessionId': sessionId,
    'startedAt': startedAt.toIso8601String(),
    'events': events.map((e) => e.toJson()).toList(),
  };

  String toCsv() {
    final buf = StringBuffer(
      'timestamp,participantId,displayName,type,data\n',
    );
    for (final e in events) {
      final escaped = e.data.toString().replaceAll('"', '""');
      buf.writeln(
        '"${e.timestamp.toIso8601String()}",'
        '"${e.participantId}",'
        '"${e.displayName}",'
        '"${e.type.name}",'
        '"$escaped"',
      );
    }
    return buf.toString();
  }
}

/// Flavour of a non-presenter [CollabPointer].
enum CollabPointerKind {
  /// An ephemeral "laser pointer" that fades after its [CollabPointer.ttl];
  /// "look *here*, now."
  ping,

  /// A persistent marker that stays until its author deletes it; "there's a
  /// bug at this edge, leave it up."
  pin,
}

/// A pointer a non-presenter drops to communicate *without* taking control
///.
///
/// The anchor is **waveform-data coordinates** — `(time, rowId)`, never screen
/// pixels — so the pointer stays glued to the thing it marks when the presenter
/// pans or zooms. The renderer maps `(time, rowId)` back to pixels through the
/// existing time-mapper + signal-row geometry every frame.
@immutable
final class CollabPointer {
  const CollabPointer({
    required this.id,
    required this.authorId,
    required this.kind,
    required this.time,
    required this.rowId,
    this.ttl,
  });

  /// Stable identity for this pointer, assigned by its author. Used by
  /// [CollaborationService.removePointer] and to de-duplicate across the
  /// host's full-state rebroadcast.
  final String id;

  /// The participant who authored the pointer. Pins may be deleted only by
  /// their author.
  final String authorId;

  final CollabPointerKind kind;

  /// Data-anchored X coordinate: the waveform **tick** the pointer marks. Never
  /// a pixel — it survives the presenter's pan/zoom.
  final int time;

  /// Data-anchored Y coordinate: the **stable identity of the signal row**
  /// (scope path + name) the pointer marks. Never a pixel row index.
  final String rowId;

  /// Time-to-live for an ephemeral [CollabPointerKind.ping] before it fades;
  /// `null` for a persistent [CollabPointerKind.pin].
  ///
  /// Expressed as a *duration*, not an absolute wall-clock instant, so each
  /// client starts its own fade timer on receipt — consistent with the "sync
  /// the clock, not the frames" model and immune to cross-client clock skew.
  final Duration? ttl;

  /// Whether this pointer fades on its own (a ping) rather than persisting
  /// until deleted (a pin).
  bool get isEphemeral => kind == CollabPointerKind.ping;

  CollabPointer copyWith({
    String? id,
    String? authorId,
    CollabPointerKind? kind,
    int? time,
    String? rowId,
    Duration? ttl,
    bool clearTtl = false,
  }) => CollabPointer(
    id: id ?? this.id,
    authorId: authorId ?? this.authorId,
    kind: kind ?? this.kind,
    time: time ?? this.time,
    rowId: rowId ?? this.rowId,
    ttl: clearTtl ? null : (ttl ?? this.ttl),
  );

  @override
  bool operator ==(Object other) =>
      other is CollabPointer &&
      other.id == id &&
      other.authorId == authorId &&
      other.kind == kind &&
      other.time == time &&
      other.rowId == rowId &&
      other.ttl == ttl;

  @override
  int get hashCode => Object.hash(id, authorId, kind, time, rowId, ttl);
}

/// An [Annotation] as it travels through a collaborative session.
///
/// A thin pairing rather than a second annotation model: the note itself is the
/// same open-core [Annotation] the canvas, the panel, `.wavecrux` and the share
/// bundle all use, so nothing has to be converted at either end and a session
/// note is adoptable as a local one without translation.
///
/// What the wrapper adds is [authorId] — a *participant* id, which the
/// [Annotation] deliberately does not carry. `Annotation.authorName` is a
/// display string that persists in documents and survives long after the
/// session; rights (author-only edit and delete) have to key on the identity
/// the room actually knows, and two people called "Martin" must not inherit
/// each other's notes.
///
/// **Colour is resolved at render, not carried here.** A session note wears its
/// author's `collaboratorColor(colorIndex)`, and that index is a per-session
/// 0–7 slot; storing the resolved colour on the wire would freeze a slot that
/// only means something inside this session. The colour is frozen exactly once,
/// at *adoption*, where the annotation stops being a session artifact.
@immutable
final class CollabAnnotation {
  const CollabAnnotation({required this.authorId, required this.annotation});

  /// The participant who wrote it. Edit and delete are author-only, matching
  /// the pin rule; the host may additionally delete any, and that is recorded.
  final String authorId;

  /// The note itself, in the open-core model.
  final Annotation annotation;

  String get id => annotation.id;

  CollabAnnotation copyWith({String? authorId, Annotation? annotation}) =>
      CollabAnnotation(
        authorId: authorId ?? this.authorId,
        annotation: annotation ?? this.annotation,
      );

  @override
  bool operator ==(Object other) =>
      other is CollabAnnotation &&
      other.authorId == authorId &&
      other.annotation == annotation;

  @override
  int get hashCode => Object.hash(authorId, annotation);

  @override
  String toString() => 'CollabAnnotation($authorId, ${annotation.id})';
}

/// A participant composing an annotation right now, and where they are doing
/// it.
///
/// The whole of what replaces streaming the text: **who**, and **which point on
/// the waveform** — never a character of what is being typed. See
/// [CollabSessionState.writingAnnotation].
///
/// The anchor is `(time, rowId)` in the same data coordinates every other
/// shared artifact uses ([CollabPointer], [Annotation]), so the chip lands on
/// the right edge at any zoom rather than at the author's pixels. Both halves
/// are nullable because a note can be composed against no row at all (a
/// full-height band), and a chip with no anchor is simply not drawn on the
/// canvas rather than being piled on the top edge.
@immutable
final class CollabWritingNote {
  const CollabWritingNote({required this.participantId, this.time, this.rowId});

  /// Who is writing.
  final String participantId;

  /// The tick their note is anchored to, or `null` when it has no anchor.
  final int? time;

  /// `SignalEntry.signalPath` of the annotated row, or `null` for a note that
  /// is not attached to one.
  final String? rowId;

  @override
  bool operator ==(Object other) =>
      other is CollabWritingNote &&
      other.participantId == participantId &&
      other.time == time &&
      other.rowId == rowId;

  @override
  int get hashCode => Object.hash(participantId, time, rowId);

  @override
  String toString() => 'CollabWritingNote($participantId, $time, $rowId)';
}

/// A non-presenter's request that the **presenter scroll** an off-screen
/// pointer into the shared viewport — a pin may optionally request that the
/// presenter scroll to it.
///
/// Unlike a [CollabPointer], this is **not** a persistent room-wide artifact: it
/// is a transient nudge surfaced **only to the current presenter**, who either
/// brings `(time, rowId)` into view (the whole room follows) or dismisses it.
/// It is therefore local to the presenter's client — never carried on the host's
/// authoritative full-state snapshot — and is cleared via
/// [CollaborationService.dismissScrollRequest].
@immutable
final class CollabScrollRequest {
  const CollabScrollRequest({
    required this.requesterId,
    required this.time,
    required this.rowId,
  });

  /// The participant who asked the presenter to scroll.
  final String requesterId;

  /// Data-anchored target the requester wants brought into view: the waveform
  /// **tick** ([time]) and the **stable signal-row identity** ([rowId]).
  final int time;
  final String rowId;

  @override
  bool operator ==(Object other) =>
      other is CollabScrollRequest &&
      other.requesterId == requesterId &&
      other.time == time &&
      other.rowId == rowId;

  @override
  int get hashCode => Object.hash(requesterId, time, rowId);
}

/// Shared-playhead transport state broadcast by the presenter.
///
/// Playback is **ephemeral focus**: the presenter broadcasts the transport
/// *state* and every follower runs its own local ticker in lockstep — "sync the
/// clock, not the frames". Per-frame cursor positions never cross the wire; the
/// playhead rides the already-synced primary cursor.
@immutable
final class CollabPlaybackTransport {
  const CollabPlaybackTransport({
    required this.isPlaying,
    required this.speed,
    required this.loopMode,
    required this.anchorTime,
    this.loopStart,
    this.loopEnd,
  });

  /// Whether the playhead is currently advancing.
  final bool isPlaying;

  /// File-independent playback speed preset (reuses the open-core
  /// [PlaybackSpeed]).
  final PlaybackSpeed speed;

  /// What the playhead does at the end of the active range.
  final PlaybackLoopMode loopMode;

  /// The playhead's start anchor tick — the cursor position playback resumes
  /// from. Synced so every client's local ticker starts from the same tick.
  final int anchorTime;

  /// Inclusive lower A–B loop bound (tick) when [loopMode] is
  /// [PlaybackLoopMode.aToB]; `null` otherwise.
  final int? loopStart;

  /// Inclusive upper A–B loop bound (tick) when [loopMode] is
  /// [PlaybackLoopMode.aToB]; `null` otherwise.
  final int? loopEnd;

  @override
  bool operator ==(Object other) =>
      other is CollabPlaybackTransport &&
      other.isPlaying == isPlaying &&
      other.speed == speed &&
      other.loopMode == loopMode &&
      other.anchorTime == anchorTime &&
      other.loopStart == loopStart &&
      other.loopEnd == loopEnd;

  @override
  int get hashCode =>
      Object.hash(isPlaying, speed, loopMode, anchorTime, loopStart, loopEnd);
}

/// Extension-point interface for Enterprise collaborative viewing.
///
/// All methods must complete without throwing — failures are surfaced through
/// [sessionState] stream events, not exceptions.
abstract class CollaborationService {
  // ── session lifecycle ──────────────────────────────────────────────────────

  /// Create a new session. Returns the room code for WAN mode; returns an
  /// empty string for LAN mode (LAN uses mDNS discovery, not room codes).
  Future<String> createSession({
    required String displayName,
    required CollabMode mode,
  });

  /// Join an existing session. The combination of [roomCode] and [lanHost]
  /// selects the transport:
  ///
  /// - **WAN** — non-empty [roomCode]: connect through the relay to that room.
  /// - **LAN, auto-discovery** — empty [roomCode] and `lanHost == null`: find
  ///   the host on the local network via mDNS and connect to it.
  /// - **LAN, manual** — empty [roomCode] and a non-null [lanHost] (a
  ///   `host` or `host:port` string): connect directly to that address,
  ///   skipping discovery. This is the fallback for networks where mDNS is
  ///   blocked.
  Future<void> joinSession({
    required String roomCode,
    required String displayName,
    String? lanHost,
  });

  /// Leave (or stop hosting) the current session.
  Future<void> leaveSession();

  // ── admission control ─────────────────────────────────────────────────

  /// How the most recent [joinSession] ended.
  ///
  /// `joinSession` degrades rather than throwing, so this is what separates
  /// "the relay was unreachable" from "the host said no" from "the host never
  /// answered". Read it after `joinSession` returns; when it reads
  /// [CollabJoinOutcome.awaitingApproval] the decision is still outstanding and
  /// resolves through the [sessionState] stream — approval flips
  /// [CollabSessionState.admission] to [CollabAdmission.approved], while a
  /// denial or timeout ends the session with a terminal `null` and leaves the
  /// final outcome here.
  CollabJoinOutcome get lastJoinOutcome;

  /// Approve ([approve] is `true`) or deny a pending **admission** request from
  /// [participantId] — the host's answer to "Bob wants to join".
  ///
  /// Host-only: the host is the sole admission authority, so a call on any
  /// other client is a no-op. On approval the joiner enters the roster and
  /// receives the authoritative full-state snapshot; on denial they receive an
  /// explicit refusal, are never added to the roster, and (on LAN, where the
  /// host is the router) have their connection closed. No-op when there is no
  /// matching pending request.
  //
  // `approve` reads naturally as the second positional argument at the call
  // site, matching [respondToPresenterRequest]'s `grant`.
  // ignore: avoid_positional_boolean_parameters
  void respondToJoinRequest(String participantId, bool approve);

  // ── end-to-end encryption ─────────────────────────────────────────────

  /// Clear [CollabSessionState.hasUnreadableFrames] after the host has seen and
  /// acted on the notice. Local-only — nothing crosses the wire.
  void dismissUnreadableFramesNotice();

  /// The current session's shareable **invite**, or `null` when there is no
  /// session or the session is LAN (which has no invite — joiners find the host
  /// over mDNS).
  ///
  /// Deliberately a service getter rather than a field on
  /// [CollabSessionState]: the invite's second half is the session key, and the
  /// session state is a value object that flows into UI, is compared, and is
  /// exactly the kind of thing a future diagnostics or issue-reporter category
  /// would serialize wholesale. Keeping the key off it means that cannot happen
  /// by accident.
  ///
  /// **Never log this, and never include it in a bug report or telemetry
  /// event.** It is the credential for the session's lifetime.
  String? get sessionInvite;

  // ── state stream ────────────────────────────────────────────────────────────

  /// Emits a new [CollabSessionState] on every participant or cursor change,
  /// and emits `null` when the session ends (left, stopped, or the transport
  /// dropped) so consumers can return to a no-session UI.
  ///
  /// The implementation reuses one long-lived broadcast stream across sessions
  /// — it does **not** close between sessions — so a fresh listener after a
  /// session has ended sees nothing until the next session starts (treated as
  /// "no session"). The open-core [NoopCollaborationService] returns an empty
  /// stream that never emits.
  Stream<CollabSessionState?> get sessionState;

  // ── cursor / viewport sync ──────────────────────────────────────────────────

  /// Report a local cursor change. Throttled internally to 60 Hz.
  void pushCursorUpdate(int? primaryTime, int? secondaryTime);

  /// Report a local viewport change.
  void pushViewportUpdate(int startTime, int endTime);

  // ── waveform identity ───────────────────────────────────────────────────────

  /// Announce the SHA-256 content hash of the waveform the local participant
  /// has loaded (or `null` when no file is open). The implementation propagates
  /// it to peers via the session handshake so the room can detect when
  /// participants are looking at *different* waveforms (see
  /// [CollabSessionState.hasWaveformMismatch]). Only the digest crosses the
  /// network — never sample data. Throttling is unnecessary: file loads are
  /// rare, human-paced events.
  void updateWaveformIdentity(String? contentHash);

  // ── shared markers ──────────────────────────────────────────────────────────

  Future<void> addSharedMarker(String name, int time);
  Future<void> removeSharedMarker(String name);

  // ── follow mode ─────────────────────────────────────────────────────────────

  /// Follow a participant (null = stop following). While following, the
  /// implementation drives [cursorStateProvider] and the viewport
  /// provider with the target's values. Any local user gesture breaks follow
  /// mode via [onUserInteraction].
  void setFollowTarget(String? participantId);

  // ── presenter control (Presenter Mode) ──────────────────────────────────────

  /// Hand the presenter role to [participantId] (direct assignment). Valid for
  /// the current presenter or the host. The host is the authoritative token
  /// arbiter, so the change serializes through the host's full-state
  /// rebroadcast — no distributed lock, no control thrash.
  void handoffPresenter(String participantId);

  /// Request the presenter role as a non-presenter (the request → approve/deny
  /// transfer path). Surfaces to the current presenter/host as an approve-or-
  /// deny prompt; see [respondToPresenterRequest]. The local participant is
  /// added to [CollabSessionState.pendingControlRequests] on the host's
  /// authoritative state.
  void requestPresenter();

  /// Approve ([grant] is `true`) or deny a pending presenter request from
  /// [participantId]. On approval the host performs the handoff and clears the
  /// request; on denial it simply clears the request. No-op when there is no
  /// matching pending request.
  //
  // `grant` reads naturally as the second positional argument at every call
  // site (`respondToPresenterRequest(id, true)`); a named flag would add noise
  // without clarity for this two-argument approve/deny verb.
  // ignore: avoid_positional_boolean_parameters
  void respondToPresenterRequest(String participantId, bool grant);

  // ── shared playhead ("sync the clock, not the frames") ──────────────────────

  /// Broadcast the local playback [transport] state so every follower runs its
  /// own ticker in lockstep. Sent only while local-is-presenter. Transport
  /// *state* crosses the wire — never per-frame cursor positions.
  void pushPlaybackTransport(CollabPlaybackTransport transport);

  // ── data-anchored pointers ─────────────────────────────────────────

  /// Drop a locally-authored [pointer] (ping or pin) for the room. The pointer
  /// is data-anchored `(time, rowId)` so it tracks the presenter's pan/zoom.
  /// Dropping a pointer does **not** take control or change the presenter.
  void addPointer(CollabPointer pointer);

  /// Remove a pointer by [pointerId]. Pins may be removed only by their author
  /// (the implementation enforces author-only delete); pings also expire on
  /// their own [CollabPointer.ttl].
  void removePointer(String pointerId);

  // ── collaborative annotations ───────────────────────────────────

  /// Publish an annotation to the session.
  ///
  /// Broadcast **on commit**, never per keystroke — see
  /// [CollabSessionState.writingAnnotation] for what replaces live text.
  void addAnnotation(CollabAnnotation annotation);

  /// Publish an edit to an annotation already in the session.
  ///
  /// Author-only: an update for a note the local participant did not write is
  /// dropped rather than applied. Conflicts are last-write-wins at the host,
  /// which is sufficient for artifacts that are small, single-author and rarely
  /// co-edited — anything stronger is machinery nobody here needs.
  void updateAnnotation(CollabAnnotation annotation);

  /// Delete a session annotation.
  ///
  /// Author-only, matching the pin rule, **except** the host, who may delete
  /// any — and whose deletion is recorded in the session log.
  void removeAnnotation(String annotationId);

  /// Announce that the local participant is composing an annotation at
  /// `(time, rowId)`.
  ///
  /// A boolean and an anchor, never the text. Recipients show a transient
  /// "someone is writing a note…" chip naming the participant, drawn at that
  /// anchor; nothing about what is being typed crosses the wire.
  ///
  /// The anchor is ignored when [writing] is false, and may be omitted for a
  /// note that has none — the chip is then simply not drawn.
  void setWritingAnnotation({required bool writing, int? time, String? rowId});

  /// Clear [CollabSessionState.removedAnnotationNotice] once the local user has
  /// seen it. Local-only — nothing crosses the wire.
  void dismissRemovedAnnotationNotice();

  // ── presenter scroll request (off-screen pointer affordance) ────────────────

  /// Ask the **current presenter** to bring the data-anchored target
  /// `(time, rowId)` into the shared viewport. Used by the off-screen pointer
  /// affordance's "ask presenter to scroll" action when a follower spots a
  /// pointer outside the room's current view. Surfaces to the presenter as
  /// [CollabSessionState.incomingScrollRequest]; every non-presenter recipient
  /// ignores it. Does **not** take control or change the presenter.
  void requestPresenterScroll(int time, String rowId);

  /// Clear the local [CollabSessionState.incomingScrollRequest] after the
  /// presenter has acted on it (scrolled there) or dismissed it. Local-only —
  /// nothing crosses the wire.
  void dismissScrollRequest();

  // ── view composition ("describe what's on screen") ──────────────────────────

  /// Broadcast the local **view-composition recipe** so followers replay it as
  /// a non-destructive overlay. Sent only while local-is-presenter, debounced
  /// on structural change (a signal added, a decoder bound, a Stage edit, a
  /// panel toggled) — never on a cursor tick. The recipe references signals by
  /// canonical path; only the description crosses the wire, never sample data.
  /// On the implementation side it also extends the host's authoritative
  /// full-state snapshot so late joiners converge on the presenter's view.
  void updateViewComposition(CollabViewComposition composition);

  // ── recording ───────────────────────────────────────────────────────────────

  Future<SessionRecording> exportRecording();

  /// Whether a recording exists to export, **including after the session that
  /// produced it has ended**.
  ///
  /// Minutes are written up after a meeting, not during one. Gating the export
  /// on a live session meant the one moment you actually want them — just after
  /// everyone has left — was the moment the action greyed out.
  ///
  /// Concrete, defaulting to `false`: a service that records nothing has
  /// nothing to export, which is the right answer for the no-op implementation
  /// and for every test double. Only a service that actually keeps a buffer
  /// needs to say otherwise.
  bool get hasRecordedEvents => false;

  // ── status ───────────────────────────────────────────────────────────────────

  bool get isInSession;
  bool get isHost;
  CollabMode get activeMode;

  /// Set by the canvas so that any user gesture automatically breaks follow
  /// mode. The implementation calls this after the current frame to avoid
  /// re-entrant provider updates.
  ///
  /// Setter-only by design: the service owns the callback slot; callers
  /// register it and the service fires it. Exposing a getter would leak the
  /// callback reference outside the service boundary.
  // ignore: avoid_setters_without_getters
  set onUserInteraction(void Function()? callback);
}
