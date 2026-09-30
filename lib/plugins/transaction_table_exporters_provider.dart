// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/models/active_decoder.dart';

/// One additional transaction-table export action contributed by an overlay
/// build (typically the closed-source Pro overlay registering
/// the Ethernet PCAP exporter).
///
/// The transaction-table panel watches [transactionTableExportersProvider]
/// and surfaces an overflow popup menu in its filter bar with one entry per
/// `(exporter, applicable decoder)` pair. The exporter's [requiredTier] is
/// used by the panel to render a [`FeatureTierBadge`] next to the menu entry; the
/// exporter's own [export] callback is responsible for routing through
/// `FeatureGate.isAvailable` before performing any work, so the gate's
/// beta-period short-circuit and post-beta upgrade-dialog flow remain owned
/// by the implementation rather than the open-core panel.
typedef TransactionTableExporter = ({
  /// Stable identifier (e.g. `"ethernet_pcap"`). Used by tests and analytics.
  String id,

  /// Tier required to *activate* the exporter. The open-core panel uses this
  /// to render a [`FeatureTierBadge`] next to the menu entry — `LicenseTier.openCore`
  /// renders no badge.
  LicenseTier requiredTier,

  /// Returns the localized menu label for [decoder]. Called by the panel for
  /// every active decoder for which [isApplicable] returned `true`. The
  /// implementation typically includes the decoder's instance label so the
  /// user can disambiguate when several applicable decoders are active.
  ///
  /// Takes a [BuildContext] rather than open-core's `L10N` so an exporter can
  /// localize from whichever ARB owns its strings. The Pro overlay's strings
  /// live in the Pro ARB (`L10NPro`), and open-core must not carry — or, once
  /// this repository is public, advertise — strings it never renders.
  String Function(BuildContext context, ActiveDecoder decoder) labelFor,

  /// Returns `true` when this exporter applies to [decoder] — typically a
  /// check on `decoder.decoderId` (e.g. `decoder.decoderId.startsWith('ethernet_')`
  /// for the PCAP exporter).
  bool Function(ActiveDecoder decoder) isApplicable,

  /// Performs the export. The implementation owns showing the file picker,
  /// writing the file, surfacing snackbars, and routing through
  /// `FeatureGate.isAvailable` for tier enforcement.
  Future<void> Function({
    required BuildContext context,
    required WidgetRef ref,
    required ActiveDecoder decoder,
  })
  export,
});

/// Open-core extension point through which the Pro/Enterprise overlay
/// contributes additional transaction-table export actions without forking
/// the panel.
///
/// The open-core default returns an empty list — the panel renders only the
/// built-in CSV export button. The overlay's `proOverrides` replaces this
/// provider with one that returns the Pro/Enterprise exporters (currently
/// the Ethernet PCAP exporter).
final transactionTableExportersProvider =
    Provider<List<TransactionTableExporter>>((_) => const []);
