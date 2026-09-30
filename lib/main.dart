// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/app.dart';

/// Open-core entry point. Delegates to [runWaveCrux] in `app.dart`, which
/// runs `bootstrap` and exits after a headless invocation such as `--help`,
/// so the Pro overlay can reuse the same setup with `proOverrides`
/// layered on. See ARCHITECTURE.md §10.
Future<void> main(List<String> args) => runWaveCrux(args: args);
