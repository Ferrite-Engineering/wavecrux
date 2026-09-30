// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';
import 'package:wavecrux/domain/enums/display_format.dart';

/// The kind of a row in the waveform viewer's signal panel.
enum SignalEntryKind {
  /// A bound signal with a waveform trace.
  signal,

  /// A named group header. Child signals are in [SignalEntry.children].
  group,

  /// A blank horizontal separator line (GTKWave compat).
  separator,

  /// A non-signal text comment row (GTKWave compat).
  comment,
}

/// A single row in the waveform viewer's signal panel.
///
/// Meaningful fields by [kind]:
/// - [signal]: [signalRef], [displayName], [argbColor], [format], [laneHeight]
/// - [group]: [groupName], [collapsed], [children]
/// - [separator]: no additional fields
/// - [comment]: [text]
@immutable
class SignalEntry {
  /// Creates a signal row.
  ///
  /// Each instance gets a unique [id] by default — a per-process random run
  /// tag plus a monotonic counter. Supply an explicit [id] only when
  /// restoring a previously persisted entry so that identity is preserved
  /// across session save/load cycles.
  ///
  /// The id used to be a per-entry UUID v4, but generating 1M+ UUIDs is the
  /// dominant cost of a bulk "Add All in Scope" on a gate-level netlist
  /// (random draws + hex formatting per entry, all on the UI thread). The
  /// run tag (one UUID per process) keeps counter ids from colliding with
  /// ids persisted by earlier runs; the counter keeps them unique within
  /// this run. Old persisted UUID ids remain valid — ids are opaque.
  SignalEntry.signal({
    required this.signalRef,
    required this.displayName,
    this.signalPath,
    String? id,
    this.argbColor,
    this.format = DisplayFormat.hexadecimal,
    this.laneHeight = 30.0,
    this.translatorConfig,
    this.renderAsAnalog = false,
  }) : id = id ?? '$_runTag-${_idCounter++}',
       kind = SignalEntryKind.signal,
       groupName = null,
       collapsed = false,
       children = const [],
       text = null;

  const SignalEntry.group({
    required this.groupName,
    this.collapsed = false,
    this.children = const [],
  }) : id = '',
       kind = SignalEntryKind.group,
       signalRef = null,
       signalPath = null,
       displayName = null,
       argbColor = null,
       format = DisplayFormat.hexadecimal,
       laneHeight = 22.0,
       translatorConfig = null,
       renderAsAnalog = false,
       text = null;

  const SignalEntry.separator()
    : id = '',
      kind = SignalEntryKind.separator,
      signalRef = null,
      signalPath = null,
      displayName = null,
      argbColor = null,
      format = DisplayFormat.hexadecimal,
      laneHeight = 10.0,
      translatorConfig = null,
      renderAsAnalog = false,
      groupName = null,
      collapsed = false,
      children = const [],
      text = null;

  const SignalEntry.comment({required this.text})
    : id = '',
      kind = SignalEntryKind.comment,
      signalRef = null,
      signalPath = null,
      displayName = null,
      argbColor = null,
      format = DisplayFormat.hexadecimal,
      laneHeight = 22.0,
      translatorConfig = null,
      renderAsAnalog = false,
      groupName = null,
      collapsed = false,
      children = const [];

  /// One random tag per process — the collision guard between this run's
  /// counter-based ids and ids persisted by earlier runs. Lazily initialized
  /// on first signal-entry construction.
  static final String _runTag = const Uuid().v4().substring(0, 8);

  /// Monotonic suffix making each id unique within this process.
  static int _idCounter = 0;

  /// Stable unique identifier for this signal row instance.
  ///
  /// Generated at construction time for [SignalEntryKind.signal] entries
  /// (per-process run tag + counter — see the `.signal` constructor doc).
  /// Empty string for structural rows (group, separator, comment) which use
  /// content-based equality instead.
  final String id;

  final SignalEntryKind kind;

  /// Opaque signal reference used with [WaveformDataSource] (kind == signal).
  ///
  /// This is a *backend-local* lookup token — for the FFI backend it is the
  /// stringified wellen `u32` handle, for the pure-Dart parser it is the VCD
  /// identifier code (e.g. `"!"`). It is therefore NOT stable across backends
  /// or sessions: a session written under one backend may be re-opened under
  /// another, in which case this ref is stale and must be re-resolved from
  /// [signalPath] via [WaveformDataSource.findVariables].
  ///
  /// Always prefer [signalPath] as the canonical identifier when persisting.
  final String? signalRef;

  /// Stable canonical hierarchical path of this signal, e.g. `"top.cpu.clk"`.
  ///
  /// Survives across waveform-data-source backends (wellen FFI vs. pure-Dart
  /// VCD) because it is derived from the VCD/FST file's design hierarchy, not
  /// from any backend-specific signal handle. Session save persists this
  /// field; session load uses it to re-resolve [signalRef] against whichever
  /// backend opens the file next, via [WaveformDataSource.findVariables].
  ///
  /// Null for legacy session entries written before the path was introduced.
  /// Such entries fall back to using [signalRef] verbatim; if that ref is
  /// rejected by the current backend the entry is silently dropped by
  /// [SignalGroupsNotifier.reresolveSignalRefs].
  final String? signalPath;

  /// User-visible signal name (kind == signal).
  final String? displayName;

  /// Packed ARGB color matching [Color.value], or null to use the auto-palette.
  final int? argbColor;

  /// Display format for the signal value column (kind == signal).
  final DisplayFormat format;

  /// Per-format configuration payload (kind == signal).
  ///
  /// Non-null only for formats that require extra parameters:
  /// - [DisplayFormat.fixedPointQ]: keys 'm', 'n', 'signed' (see [QFormatConfig])
  /// - [DisplayFormat.namedEnum]: key 'entries' (see [NamedEnumConfig])
  ///
  /// Stored in the `.wavecrux` session file under the optional 'config' key.
  final Map<String, Object?>? translatorConfig;

  /// Draw this signal as an analog curve instead of a digital lane
  /// (kind == signal).
  ///
  /// **Deliberately orthogonal to [format], not a value of it.** The format
  /// answers *"what number are these bits"* — Q4.12, bf16, signed decimal — and
  /// this flag answers *"draw that number how"*. Folding the two together would
  /// double the format enum and break the existing format menu, and it would
  /// make "plot this as a curve" a different choice per numeric encoding, which
  /// is not how anyone thinks about it. GTKWave draws the same distinction
  /// (Data Format vs. Analog step/interpolated), so a `.gtkw` import maps onto
  /// it directly.
  ///
  /// Real-valued signals (`real`, `realtime`, `shortreal`) are analog whether
  /// or not this is set — they have no digital rendering. Setting it on one is
  /// harmless and changes nothing.
  final bool renderAsAnalog;

  /// Pixel height of this lane in the waveform canvas (kind == signal).
  ///
  /// Defaults to 30.0. Clamped to [16, 200] by [SignalGroupsNotifier.setLaneHeight].
  /// Non-signal entries store their fixed heights here as a convenience.
  final double laneHeight;

  /// Group label (kind == group).
  final String? groupName;

  /// Whether the group is collapsed in the UI (kind == group).
  final bool collapsed;

  /// Direct children of the group (kind == group).
  final List<SignalEntry> children;

  /// Comment text (kind == comment).
  final String? text;

  // ── copyWith ────────────────────────────────────────────────────────────────

  SignalEntry copyWith({
    String? signalRef,
    String? signalPath,
    String? displayName,
    int? argbColor,
    bool clearArgbColor = false,
    DisplayFormat? format,
    double? laneHeight,
    Map<String, Object?>? translatorConfig,
    bool clearTranslatorConfig = false,
    bool? renderAsAnalog,
    String? groupName,
    bool? collapsed,
    List<SignalEntry>? children,
    String? text,
  }) {
    switch (kind) {
      case SignalEntryKind.signal:
        return SignalEntry.signal(
          id: id,
          signalRef: signalRef ?? this.signalRef,
          signalPath: signalPath ?? this.signalPath,
          displayName: displayName ?? this.displayName,
          argbColor: clearArgbColor ? null : (argbColor ?? this.argbColor),
          format: format ?? this.format,
          laneHeight: laneHeight ?? this.laneHeight,
          translatorConfig: clearTranslatorConfig
              ? null
              : (translatorConfig ?? this.translatorConfig),
          renderAsAnalog: renderAsAnalog ?? this.renderAsAnalog,
        );
      case SignalEntryKind.group:
        return SignalEntry.group(
          groupName: groupName ?? this.groupName!,
          collapsed: collapsed ?? this.collapsed,
          children: children ?? this.children,
        );
      case SignalEntryKind.separator:
        return const SignalEntry.separator();
      case SignalEntryKind.comment:
        return SignalEntry.comment(text: text ?? this.text!);
    }
  }

  // ── equality ────────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SignalEntry) return false;
    if (kind != other.kind) return false;
    switch (kind) {
      case SignalEntryKind.signal:
        return id == other.id &&
            signalRef == other.signalRef &&
            signalPath == other.signalPath &&
            displayName == other.displayName &&
            argbColor == other.argbColor &&
            format == other.format &&
            laneHeight == other.laneHeight &&
            renderAsAnalog == other.renderAsAnalog &&
            _mapsEqual(translatorConfig, other.translatorConfig);
      case SignalEntryKind.group:
        if (groupName != other.groupName || collapsed != other.collapsed) {
          return false;
        }
        if (children.length != other.children.length) return false;
        for (var i = 0; i < children.length; i++) {
          if (children[i] != other.children[i]) return false;
        }
        return true;
      case SignalEntryKind.separator:
        return true;
      case SignalEntryKind.comment:
        return text == other.text;
    }
  }

  // Shallow key+value equality for the JSON-scalar config maps.
  // Domain layer has zero Flutter imports so we cannot use mapEquals.
  static bool _mapsEqual(Map<String, Object?>? a, Map<String, Object?>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      final av = a[key];
      final bv = b[key];
      if (av is List && bv is List) {
        if (av.length != bv.length) return false;
        for (var i = 0; i < av.length; i++) {
          if (av[i] != bv[i]) return false;
        }
      } else if (av != bv) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => switch (kind) {
    SignalEntryKind.signal => Object.hash(
      kind,
      id,
      signalRef,
      signalPath,
      displayName,
      argbColor,
      format,
      laneHeight,
      renderAsAnalog,
      translatorConfig?.length,
    ),
    SignalEntryKind.group => Object.hash(kind, groupName, collapsed),
    SignalEntryKind.separator => kind.hashCode,
    SignalEntryKind.comment => Object.hash(kind, text),
  };

  @override
  String toString() => switch (kind) {
    SignalEntryKind.signal =>
      'SignalEntry.signal(path=$signalPath, ref=$signalRef)',
    SignalEntryKind.group =>
      'SignalEntry.group($groupName, ${children.length} children)',
    SignalEntryKind.separator => 'SignalEntry.separator',
    SignalEntryKind.comment => 'SignalEntry.comment($text)',
  };
}

/// The waveform viewer's complete arranged signal list.
///
/// Top-level entries may include signals, groups, separators, and comments.
/// Group entries carry their own [SignalEntry.children] list recursively.
@immutable
class SignalGroup {
  const SignalGroup({this.entries = const []});

  /// All top-level rows in the viewer signal panel.
  final List<SignalEntry> entries;

  // ── computed ────────────────────────────────────────────────────────────────

  /// Total number of [SignalEntryKind.signal] rows (recursively through groups).
  int get signalCount => _countSignals(entries);

  static int _countSignals(List<SignalEntry> entries) {
    var count = 0;
    for (final e in entries) {
      if (e.kind == SignalEntryKind.signal) {
        count++;
      } else if (e.kind == SignalEntryKind.group) {
        count += _countSignals(e.children);
      }
    }
    return count;
  }

  /// Every [SignalEntry.signalRef] currently displayed, recursively through
  /// groups. Separators and comments are excluded.
  ///
  /// Used by idempotent bulk-add paths (the signal tree's "Add N Selected to
  /// Viewer") to skip signals already on the canvas. Deliberate duplicate
  /// rows of one signal (e.g. hex + Q8.8 views) remain possible through the
  /// single-add path, which does not consult this set.
  Set<String> get displayedSignalRefs => _collectRefs(entries);

  static Set<String> _collectRefs(List<SignalEntry> entries) {
    final refs = <String>{};
    for (final e in entries) {
      if (e.kind == SignalEntryKind.signal) {
        final ref = e.signalRef;
        if (ref != null) refs.add(ref);
      } else if (e.kind == SignalEntryKind.group) {
        refs.addAll(_collectRefs(e.children));
      }
    }
    return refs;
  }

  // ── mutation helpers ────────────────────────────────────────────────────────

  SignalGroup copyWith({List<SignalEntry>? entries}) =>
      SignalGroup(entries: entries ?? this.entries);

  /// Returns a new [SignalGroup] with [entry] appended to the top-level list.
  SignalGroup addEntry(SignalEntry entry) =>
      SignalGroup(entries: [...entries, entry]);

  /// Returns a new [SignalGroup] with all [newEntries] appended.
  SignalGroup addEntries(List<SignalEntry> newEntries) =>
      SignalGroup(entries: [...entries, ...newEntries]);

  // ── equality ────────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SignalGroup) return false;
    if (entries.length != other.entries.length) return false;
    for (var i = 0; i < entries.length; i++) {
      if (entries[i] != other.entries[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(entries);

  @override
  String toString() => 'SignalGroup(${entries.length} entries)';
}
