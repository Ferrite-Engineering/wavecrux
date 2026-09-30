// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

/// Eight visually distinct colors (one per `colorIndex` value 0–7) for
/// collaboration presence — collaborator cursor lines, name labels, and
/// data-anchored pointers (pings / pins). Chosen to be distinguishable on dark
/// and light backgrounds and to avoid the default waveform signal colors
/// (green, cyan, yellow, magenta, orange, white).
///
/// Shared by the collaborator cursor overlay, the shared-pointer overlay and
/// the annotation overlay, so a participant's color is identical across every
/// collaboration surface.
///
/// Lives under `core/theme/` rather than beside the first overlay that needed
/// it: it is a palette, not a widget, and its consumers now span three
/// features. A feature reaching into a sibling's `widgets/` for it is exactly
/// what the import-layering guard refuses, and rightly — the guard caught this
/// when the annotation overlay became the third consumer.
const kCollaboratorPalette = <Color>[
  Color(0xFFFFB300), // amber
  Color(0xFF42A5F5), // light blue
  Color(0xFF66BB6A), // light green
  Color(0xFFEC407A), // pink/rose
  Color(0xFFAB47BC), // purple
  Color(0xFF26C6DA), // teal
  Color(0xFFD4E157), // lime
  Color(0xFFFF7043), // coral
];

/// The palette color for a participant's `colorIndex` (wraps modulo the palette
/// length so an out-of-range index can never throw).
Color collaboratorColor(int colorIndex) =>
    kCollaboratorPalette[colorIndex % kCollaboratorPalette.length];
