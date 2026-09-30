// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// ── Shared transaction lane constants ───────────────────────────────────────
//
// Used by [WaveformCanvas] (lane height + lane color), [SignalListPanel]
// (decoder rows), [DecoderListEntry] (row color), and [ValueColumnPanel]
// (bottom spacer height) so all four synchronized panels maintain identical
// scroll extents, stay vertically aligned, and assign the same color per
// decoder instance.
//
// Without the matching extents, the canvas's `SingleChildScrollView`
// extends past the signal list's `ReorderableListView` extent, the
// bidirectional scroll-controller sync in `WaveformViewCenter` clamps the
// signal list at its smaller max, and the resulting listener fires back to
// pull the canvas to that smaller offset — i.e. the user can scroll the
// canvas to reveal the transaction lane and it immediately bounces back.

import 'package:flutter/painting.dart';

/// Height in pixels of one transaction-lane row appended to the bottom of the
/// waveform canvas per active decoder.
const double transactionLaneHeight = 28;

/// Color palette used to assign one distinct color to each active decoder.
///
/// The signal-list decoder row, the canvas transaction-lane background, and
/// the canvas transaction blocks all read from this palette via
/// [transactionLaneColorForIndex] so the same decoder instance gets the same
/// color in every panel.  Indices wrap modulo the palette length when more
/// decoders are active than colors available.
const transactionLanePalette = [
  Color(0xFF1565C0), // Blue 800
  Color(0xFF00695C), // Teal 800
  Color(0xFFBF360C), // Deep Orange 800
  Color(0xFF4527A0), // Deep Purple 800
  Color(0xFF1B5E20), // Green 900
  Color(0xFF880E4F), // Pink 900
];

/// Returns the canonical color for the decoder at [index] in the active
/// decoder list.  Wraps modulo the palette length.
Color transactionLaneColorForIndex(int index) =>
    transactionLanePalette[index.abs() % transactionLanePalette.length];
