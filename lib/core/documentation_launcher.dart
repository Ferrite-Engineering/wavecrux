// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart' show cruxOpenUrl;

/// Opens the online documentation in the user's browser.
///
/// A mutable top-level seam rather than a direct `launchUrl` call so widget
/// tests can exercise the Help → Documentation menu item without the
/// `url_launcher` platform channel — the same pattern
/// `betaExpiryLaunchUrl` and `decoderPluginsLaunchUrl` use.
Future<bool> Function(Uri uri) documentationLaunchUrl = cruxOpenUrl;
