// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/services/riscv/rvfi_channel.dart';

/// How completely an RVFI bundle was recognized in a trace.
enum RvfiBindingCompleteness {
  /// One or more of the required channels (`rvfi_valid` / `rvfi_insn` /
  /// `rvfi_pc_rdata`) is missing. Nothing can be reconstructed.
  unusable,

  /// The reduced binding set is present (retire valid + pc + insn + rd) but
  /// the full channel set is not. Retirement, disassembly and register writes
  /// reconstruct; operand reads, memory effects, or trap detail may not.
  reduced,

  /// Every channel was found.
  full,
}

/// The signal references that make up one recognized RVFI bundle.
///
/// Indexed by channel and by *retirement channel index* — riscv-formal cores
/// that retire more than one instruction per cycle expose `rvfi_valid[0]`,
/// `rvfi_valid[1]`, … and the substrate treats each index as an independent
/// retirement port.
@immutable
class RvfiBindingSet {
  const RvfiBindingSet({
    required this.refs,
    required this.channelCount,
    this.scopePath = '',
    this.namePrefix = '',
  });

  /// An explicitly empty binding set.
  static const RvfiBindingSet empty = RvfiBindingSet(
    refs: {},
    channelCount: 0,
  );

  /// Signal ref per (channel, retirement-channel index). A channel absent
  /// from the map was not found in the trace.
  final Map<RvfiChannel, Map<int, String>> refs;

  /// Number of retirement channels found (1 for a single-issue core).
  final int channelCount;

  /// Hierarchical scope the bundle was found in (`""` at the top level).
  /// Reported so a trace containing more than one core can say *which* one
  /// was bound.
  final String scopePath;

  /// Leaf-name prefix the bundle carried, for designs that flatten the
  /// hierarchy into the signal name (`core0_rvfi_valid` → `core0_`).
  final String namePrefix;

  /// The signal ref for [channel] on retirement channel [index], or null.
  String? ref(RvfiChannel channel, {int index = 0}) => refs[channel]?[index];

  /// Every distinct signal ref in the set. This is the list a widget must
  /// watch through `stageBoundSignalProvider` — a bound-but-unloaded signal
  /// answers `valueAt` with null, which is indistinguishable from "no value
  /// yet" and silently produces an empty widget on a perfectly good trace.
  Set<String> get allRefs => {
    for (final byIndex in refs.values) ...byIndex.values,
  };

  /// Channels present in the set.
  Set<RvfiChannel> get foundChannels => refs.keys.toSet();

  /// Human-readable identity of the bundle, for a "bound to …" line.
  String get displayPath {
    if (scopePath.isEmpty) return '$namePrefix*';
    return '$scopePath.$namePrefix*';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RvfiBindingSet &&
          channelCount == other.channelCount &&
          scopePath == other.scopePath &&
          namePrefix == other.namePrefix &&
          _refsEqual(refs, other.refs);

  @override
  int get hashCode => Object.hash(
    channelCount,
    scopePath,
    namePrefix,
    refs.length,
    Object.hashAll(refs.keys),
  );

  @override
  String toString() =>
      'RvfiBindingSet(${refs.length} channels, '
      'channelCount: $channelCount, path: $displayPath)';

  static bool _refsEqual(
    Map<RvfiChannel, Map<int, String>> a,
    Map<RvfiChannel, Map<int, String>> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null || other.length != entry.value.length) return false;
      for (final inner in entry.value.entries) {
        if (other[inner.key] != inner.value) return false;
      }
    }
    return true;
  }
}

/// What was and was not recognized, alongside an [RvfiBindingSet].
///
/// The report is a first-class deliverable rather than a debug aid: a widget
/// bound to a partially-instrumented core must be able to say which views it
/// is degrading and why, instead of rendering an empty panel.
@immutable
class RvfiCompletenessReport {
  const RvfiCompletenessReport({
    required this.found,
    required this.missing,
    required this.completeness,
    required this.channelCount,
    this.packedVectorSuspected = false,
    this.candidateScopes = const [],
  });

  /// Grades an [RvfiBindingSet] that was assembled from somewhere other than
  /// [RvfiDetectionService] — in practice, from a Stage widget instance's
  /// hand- or auto-bound pins.
  ///
  /// The detection service produces its own report as a by-product of the
  /// name sweep. A widget whose pins the user bound by hand has the same
  /// question to answer — *which views must I degrade, and which checks
  /// cannot run?* — and no sweep to answer it from, so the grading lives
  /// here rather than being duplicated at every call site.
  factory RvfiCompletenessReport.forBindings(RvfiBindingSet bindings) {
    final found = bindings.foundChannels;
    final missing = RvfiChannel.values.toSet().difference(found);
    final RvfiBindingCompleteness completeness;
    if (RvfiChannel.values.any((c) => c.isRequired && !found.contains(c))) {
      completeness = RvfiBindingCompleteness.unusable;
    } else if (missing.isEmpty) {
      completeness = RvfiBindingCompleteness.full;
    } else {
      completeness = RvfiBindingCompleteness.reduced;
    }
    return RvfiCompletenessReport(
      found: found,
      missing: missing,
      completeness: completeness,
      channelCount: bindings.channelCount,
    );
  }

  /// Channels bound in the trace.
  final Set<RvfiChannel> found;

  /// Channels the trace does not expose.
  final Set<RvfiChannel> missing;

  /// Overall verdict.
  final RvfiBindingCompleteness completeness;

  /// Number of retirement channels bound.
  final int channelCount;

  /// True when `rvfi_valid` was found wider than one bit, which is how a
  /// superscalar core packs `NRET` retirement channels into a single port.
  ///
  /// The substrate does **not** slice a packed vector — it reports the
  /// suspicion so the user is told the trace looks multi-issue and that only
  /// per-index ports (`rvfi_valid[N]`) are auto-bound. Silently binding
  /// channel 0 to the whole vector would mis-attribute every retirement.
  final bool packedVectorSuspected;

  /// Every scope in which an `rvfi_` bundle was seen, best-scoring first.
  /// More than one entry means the trace holds more than one instrumented
  /// core and the user may want to pick a different one.
  final List<String> candidateScopes;

  /// Whether a retire stream can be reconstructed at all.
  bool get isUsable => completeness != RvfiBindingCompleteness.unusable;

  /// Whether the consumer must degrade its views and say so.
  bool get reducedBindingSetApplies =>
      completeness == RvfiBindingCompleteness.reduced;

  @override
  String toString() =>
      'RvfiCompletenessReport($completeness, ${found.length} found, '
      '${missing.length} missing, channels: $channelCount)';
}

/// An [RvfiBindingSet] paired with its [RvfiCompletenessReport].
@immutable
class RvfiDetectionResult {
  const RvfiDetectionResult({
    required this.bindings,
    required this.report,
  });

  /// A result for a trace with no RVFI bundle at all: nothing found, every
  /// channel missing.
  static final RvfiDetectionResult none = RvfiDetectionResult(
    bindings: RvfiBindingSet.empty,
    report: RvfiCompletenessReport(
      found: const {},
      missing: RvfiChannel.values.toSet(),
      completeness: RvfiBindingCompleteness.unusable,
      channelCount: 0,
    ),
  );

  final RvfiBindingSet bindings;
  final RvfiCompletenessReport report;

  @override
  String toString() => 'RvfiDetectionResult($report)';
}
