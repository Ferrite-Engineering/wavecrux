// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// WaveCrux-side re-export of `TabId` from the cross-suite
/// `crux_workspace` package.
///
/// WaveCrux is the
/// reference adopter: the canonical `TabId` definition lives in
/// `package:crux_workspace/crux_workspace.dart`. This file used to define
/// `TabId` locally; it is now a thin shim that re-exports the package
/// symbol so existing import paths
/// (`package:wavecrux/domain/models/tab_id.dart`) keep resolving while we
/// minimize churn in the consumer files. A follow-on cleanup pass can
/// remove the shim and update consumer imports to point directly at the
/// package.
library;

export 'package:crux_workspace/crux_workspace.dart' show TabId;
