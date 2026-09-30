// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Whether a [CxpEventLogEntry] records an inbound or outbound message.
enum CxpEventDirection {
  /// A message we sent (broadcast or targeted via `sendTo`).
  outbound,

  /// A message we received from a peer.
  inbound,
}

/// A single entry in the cross-probe panel's rolling event buffer.
///
/// The buffer surfaces what cross-probe traffic looked like in the recent
/// past so the user can confirm that selection events are flowing as
/// expected. Each entry carries a timestamp, the direction of the message,
/// the message kind discriminator (e.g. `notify_selection`,
/// `request_highlight`), and the human-readable peer label the event was
/// to/from.
///
/// Optional [summary] gives a short one-line gloss the panel renders next
/// to the kind (e.g. the selected signal's path or the highlight target).
@immutable
class CxpEventLogEntry {
  /// Creates a log entry.
  const CxpEventLogEntry({
    required this.timestamp,
    required this.direction,
    required this.messageKind,
    required this.peerLabel,
    this.summary,
  });

  /// When the event happened, in local time.
  final DateTime timestamp;

  /// Whether the entry records an inbound or outbound message.
  final CxpEventDirection direction;

  /// Wire-format kind discriminator (one of `package:crux_cxp`'s
  /// `CxpMessageKind` constants, e.g. `notify_selection`).
  final String messageKind;

  /// Human-readable peer label — typically the peer's `productName`
  /// (another Crux product's short name or a third-party identifier).
  /// Equals `'(broadcast)'` for outbound broadcasts where no specific
  /// peer is targeted.
  final String peerLabel;

  /// Optional one-line gloss the cross-probe panel can render next to the
  /// kind (e.g. the selected signal's path).
  final String? summary;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CxpEventLogEntry &&
          other.timestamp == timestamp &&
          other.direction == direction &&
          other.messageKind == messageKind &&
          other.peerLabel == peerLabel &&
          other.summary == summary);

  @override
  int get hashCode =>
      Object.hash(timestamp, direction, messageKind, peerLabel, summary);

  @override
  String toString() =>
      'CxpEventLogEntry(${direction.name} '
      '$messageKind, peer=$peerLabel, summary=$summary, ts=$timestamp)';
}
