// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the Convert PCAP to VCD dialog.
///
/// The dialog itself is an Enterprise-tier feature implemented in the
/// closed-source Pro overlay; the open-core default is a no-op
/// so Open Core builds — which include the action in the menu bar /
/// overflow menu / command palette for discoverability — silently absorb
/// the action.
typedef PcapToVcdDialogOpener = void Function(BuildContext context);

/// Open-core extension point through which the Pro overlay registers a
/// callback for opening the Convert PCAP to VCD dialog.
///
/// Ethernet PCAP-to-VCD synthesis is an Enterprise-tier feature. The
/// open-core no-op default keeps `ShortcutAction.convertPcapToVcd`
/// discoverable in menus/palette without breaking Open Core builds; the
/// Pro overlay overrides this provider in `proOverrides` with a callback
/// that mounts the actual `PcapToVcdDialog`. Activation routes through
/// `FeatureGate.isAvailable(LicenseTier.enterprise, ref)` inside the
/// opener; during `kBetaPeriod` this short-circuits to allow.
final pcapToVcdDialogOpenerProvider = Provider<PcapToVcdDialogOpener>(
  (_) => (context) {
    // Open-core no-op. The Pro overlay overrides this with a callback
    // that mounts the Convert PCAP to VCD dialog.
  },
);
