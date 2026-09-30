// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui';

/// The amber a **drifted** annotation wears.
///
/// Lives in `core/theme/` rather than beside the overlay because three
/// unrelated layers need the same value: the canvas overlay, the annotations
/// panel, and the hand-written SVG emitter under `services/export/`. A services
/// file cannot import a feature's widgets — the import-layering guard stops it,
/// and rightly — so the constant they share has to sit below all three. The
/// collaborator palette lives here for the same reason.
///
/// **Deliberately not a theme colour.** Drift is a statement about the *design*
/// — this note described something that is no longer true — rather than about
/// the UI, so it must read the same in every palette the user picks, and the
/// same on screen as in an exported document. Three surfaces disagreeing about
/// which notes still hold would be worse than none of them saying so.
const Color kAnnotationDriftedColor = Color(0xFFE8A33D);
