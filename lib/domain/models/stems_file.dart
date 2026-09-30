// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/stems_entry.dart';

/// A parsed RTL stems file: a collection of variable and scope entries
/// keyed by full hierarchical path.
///
/// Lookup is performed in three tiers (similar to GTKWave session import):
/// 1. Exact match on the full path
/// 2. Case-insensitive match on the full path
/// 3. Match on the trailing path component (signal name) with bit-range
///    suffixes stripped (`data[7:0]` → `data`)
@immutable
class StemsFile {
  const StemsFile({this.entries = const []});

  /// All entries in declaration order.
  final List<StemsEntry> entries;

  /// Total entry count (variables + scopes).
  int get length => entries.length;

  /// True when this file has no entries.
  bool get isEmpty => entries.isEmpty;

  /// True when this file has at least one entry.
  bool get isNotEmpty => entries.isNotEmpty;

  /// Returns the [StemsEntry] for [signalPath] (e.g. `"top.cpu.clk"`),
  /// or null if no mapping exists.
  ///
  /// Performs a 3-tier match:
  /// 1. Exact path
  /// 2. Case-insensitive path
  /// 3. Suffix match on the local name with `[..]` bit-ranges stripped
  StemsEntry? lookup(String signalPath) {
    if (signalPath.isEmpty) return null;

    // Tier 1: exact match (variable preferred over scope).
    StemsEntry? scopeHit;
    for (final entry in entries) {
      if (entry.path == signalPath) {
        if (entry.kind == StemsEntryKind.variable) return entry;
        scopeHit ??= entry;
      }
    }
    if (scopeHit != null) return scopeHit;

    // Tier 2: case-insensitive exact match.
    final lowerTarget = signalPath.toLowerCase();
    for (final entry in entries) {
      if (entry.path.toLowerCase() == lowerTarget) return entry;
    }

    // Tier 3: match on local name (trailing path component), with bit-range
    // suffixes stripped. Prefer variables over scopes.
    final localName = _stripBitRange(_localNameOf(signalPath));
    if (localName.isEmpty) return null;
    final lowerLocal = localName.toLowerCase();

    StemsEntry? bestSuffix;
    for (final entry in entries) {
      final entryLocal = _stripBitRange(_localNameOf(entry.path));
      if (entryLocal.toLowerCase() == lowerLocal) {
        if (entry.kind == StemsEntryKind.variable) return entry;
        bestSuffix ??= entry;
      }
    }
    return bestSuffix;
  }

  /// Returns the [StemsEntry] for [scopePath] when the scope itself has been
  /// recorded. Variable entries are not considered.
  StemsEntry? lookupScope(String scopePath) {
    if (scopePath.isEmpty) return null;
    for (final entry in entries) {
      if (entry.kind == StemsEntryKind.scope && entry.path == scopePath) {
        return entry;
      }
    }
    final lower = scopePath.toLowerCase();
    for (final entry in entries) {
      if (entry.kind == StemsEntryKind.scope &&
          entry.path.toLowerCase() == lower) {
        return entry;
      }
    }
    return null;
  }

  /// All distinct source-file paths referenced by this stems file, in the
  /// order they first appear.
  List<String> get sourceFiles {
    final seen = <String>{};
    final result = <String>[];
    for (final entry in entries) {
      if (seen.add(entry.sourceFile)) {
        result.add(entry.sourceFile);
      }
    }
    return result;
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  static String _localNameOf(String path) {
    final dot = path.lastIndexOf('.');
    return dot < 0 ? path : path.substring(dot + 1);
  }

  static String _stripBitRange(String name) {
    final bracket = name.indexOf('[');
    return bracket < 0 ? name : name.substring(0, bracket);
  }

  // ── copyWith ───────────────────────────────────────────────────────────────

  StemsFile copyWith({List<StemsEntry>? entries}) =>
      StemsFile(entries: entries ?? this.entries);

  // ── equality ───────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! StemsFile) return false;
    if (entries.length != other.entries.length) return false;
    for (var i = 0; i < entries.length; i++) {
      if (entries[i] != other.entries[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(entries);

  @override
  String toString() => 'StemsFile(entries: ${entries.length})';
}
