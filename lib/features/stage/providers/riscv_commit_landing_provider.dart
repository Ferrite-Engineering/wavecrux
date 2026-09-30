// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/remote/cxp/riscv_stream_coordinate_resolver.dart';

part 'riscv_commit_landing_provider.g.dart';

/// Where an inbound CXP §9.9 (https://edacrux.app/cxp#sec-9-9) stream
/// coordinate put the cursor, and everything
/// the sender said about it.
///
/// The RVFI Commit Inspector renders this as a banner. That banner is the
/// **only** place in WaveCrux that repeats a peer's claims about a proof, so
/// it carries the provenance obligation with it: when [isReplayedFixture] is
/// true the evidence came from a committed demo fixture and the banner says
/// so, because presenting replayed evidence as a measured solver run is the
/// one thing this whole hand-off must never do.
@immutable
class RiscvCommitLanding {
  /// Creates a landing record.
  const RiscvCommitLanding({
    required this.streamId,
    required this.sequenceIndex,
    required this.time,
    required this.token,
    this.subId,
    this.order,
    this.channelIndex,
    this.attributes = const <String, String>{},
    this.autoMounted = false,
  });

  /// CXP `stream_id` the coordinate was expressed in.
  final String streamId;

  /// CXP `sequence_index` — a bounded-proof step, or an `rvfi_order`,
  /// depending on [streamId].
  final int sequenceIndex;

  /// CXP `sub_id` — the RVFI channel (`ch0`) or hart id the sender named.
  final String? subId;

  /// Simulation tick the primary cursor was moved to.
  final int time;

  /// `rvfi_order` of the retirement that was selected, when one was. Null
  /// means the step resolved but no instruction retired there — the cursor
  /// moved and nothing was selected.
  final int? order;

  /// Retirement channel index the landing belongs to.
  final int? channelIndex;

  /// The sender's advisory attributes, verbatim and unfiltered.
  final Map<String, String> attributes;

  /// Whether the cross-probe **mounted the Stage panel this banner is being
  /// rendered inside** as part of landing.
  ///
  /// True only when the hand-off opened the trace's tab itself and then added
  /// an RVFI Commit Inspector to it, because a freshly-opened tab has no Stage
  /// panel and the landing would otherwise be invisible. False when the user
  /// already had this inspector open — nothing was rearranged and there is
  /// nothing to explain.
  ///
  /// The banner says so. A panel that appears unbidden with no explanation is
  /// worse than no panel: the user did not add it, and the only surface that
  /// can tell them who did is the one it appeared inside.
  final bool autoMounted;

  /// Monotonic request id, so a repeat landing on the same element still
  /// notifies listeners. Same idiom as `RevealSignalRequest`.
  final int token;

  /// Whether a retirement was actually selected.
  bool get selectedRetirement => order != null;

  /// The riscv-formal check the sender was proving, if it said.
  String? get check => attributes[RiscvCoordinateAttributes.check];

  /// The check group, if the sender said.
  String? get group => attributes[RiscvCoordinateAttributes.group];

  /// The configured bounded-proof depth — the *of 20* in "step 7 of 20" —
  /// when the sender reported one and it parses as a number.
  int? get depthConfigured =>
      int.tryParse(attributes[RiscvCoordinateAttributes.depthConfigured] ?? '');

  /// The ISA string the producer was configured with, if it said.
  String? get isa => attributes[CxpStreamCoordinate.riscvIsaAttribute];

  /// Whether this landing came from a **replayed committed fixture** rather
  /// than a live solver run. Displayed, always, when true.
  bool get isReplayedFixture =>
      attributes[CxpStreamCoordinate.riscvModeAttribute] ==
      RiscvCoordinateAttributes.demoMode;

  /// Whether [streamId] is the bounded-proof step stream, whose
  /// [sequenceIndex] reads as a *step* rather than an `rvfi_order`.
  bool get isFormalStep =>
      streamId == CxpStreamCoordinate.riscvFormalTraceStepStreamId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RiscvCommitLanding &&
          other.streamId == streamId &&
          other.sequenceIndex == sequenceIndex &&
          other.subId == subId &&
          other.time == time &&
          other.order == order &&
          other.channelIndex == channelIndex &&
          other.autoMounted == autoMounted &&
          other.token == token);

  @override
  int get hashCode => Object.hash(
    streamId,
    sequenceIndex,
    subId,
    time,
    order,
    channelIndex,
    autoMounted,
    token,
  );

  @override
  String toString() =>
      'RiscvCommitLanding($streamId#$sequenceIndex'
      '${subId == null ? '' : '/$subId'} → t=$time'
      '${order == null ? '' : ', order=$order'})';
}

/// Per-tab holder for the most recent [RiscvCommitLanding].
///
/// Per-tab for the same reason `revealSignalRequestProvider` is: an inbound
/// cross-probe opens the trace in **its own** tab, and a root-scope singleton
/// would caption every other tab's Commit Inspector with a landing that has
/// nothing to do with the file it is showing.
///
/// It also **self-clears when the tab's waveform changes**. A landing is a
/// statement about one trace; leaving it up after the user opens a different
/// file in the same tab would caption the new trace with the old trace's
/// proof — the same class of stale claim the substrate refuses everywhere
/// else. Overridden per tab in `wavecruxTabOverrides`.
@Riverpod(keepAlive: true)
class RiscvCommitLandingNotifier extends _$RiscvCommitLandingNotifier {
  int _token = 0;

  @override
  RiscvCommitLanding? build() {
    ref.listen(waveformSourceProvider, (prev, next) {
      if (prev == null) return;
      if (prev.value != next.value && state != null) state = null;
    });
    return null;
  }

  /// Records a landing. Each call bumps the token so a repeat cross-probe of
  /// the same element still notifies listeners.
  void record({
    required String streamId,
    required int sequenceIndex,
    required int time,
    String? subId,
    int? order,
    int? channelIndex,
    Map<String, String> attributes = const <String, String>{},
    bool autoMounted = false,
  }) {
    state = RiscvCommitLanding(
      streamId: streamId,
      sequenceIndex: sequenceIndex,
      time: time,
      subId: subId,
      order: order,
      channelIndex: channelIndex,
      attributes: Map<String, String>.unmodifiable(attributes),
      autoMounted: autoMounted,
      token: ++_token,
    );
  }

  /// Dismisses the banner. The cursor stays where the landing put it — this
  /// clears the caption, not the navigation.
  void clear() => state = null;
}
