// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// WaveCrux-side re-export of `PaneId` from the cross-suite
/// `crux_workspace` package.
///
/// WaveCrux is the
/// reference adopter: the canonical `PaneId` definition lives in
/// `package:crux_workspace/crux_workspace.dart`, including the
/// `PaneId.primary` sentinel used as the implicit pane id for live tabs
/// created before workspace hydration. This file used to define `PaneId`
/// locally; it is now a thin shim that re-exports the package symbol so
/// existing import paths
/// (`package:wavecrux/domain/models/pane_id.dart`) keep resolving while
/// we minimize churn in the consumer files. A follow-on cleanup pass can
/// remove the shim and update consumer imports.
library;

export 'package:crux_workspace/crux_workspace.dart' show PaneId;
