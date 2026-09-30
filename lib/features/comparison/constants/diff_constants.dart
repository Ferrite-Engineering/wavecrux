// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/painting.dart';

// ── Shared XOR diff lane constants ────────────────────────────────────────────
//
// These constants are used by WaveformCanvas._buildLaneData (canvas height),
// SignalListPanel (spacer row height), and ValueColumnPanel (spacer row height)
// so all three synchronized panels maintain identical vertical alignment.

/// Height in pixels of an injected XOR diff lane and its matching spacers.
const double diffXorLaneHeight = 24;

/// Background fill color for XOR diff lanes/spacers: amber at ~10% opacity.
const Color diffXorLaneBackground = Color(0x1AFF9800);

/// Label color for the "⊕" symbol in XOR diff lanes/spacers: amber at 70% opacity.
const Color diffXorLaneLabelColor = Color(0xB3FF9800);
