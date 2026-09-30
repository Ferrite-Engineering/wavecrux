// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart' show CruxHelpLink;
import 'package:flutter/material.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// A small, unobtrusive help icon that opens [url] in the system browser.
///
/// Thin WaveCrux wrapper over the shared [CruxHelpLink] (`crux_ide_layout`):
/// the shared widget requires a caller-supplied localized tooltip, so this
/// wrapper exists to inject the localized "Learn more" default from WaveCrux's
/// ARB strings when [tooltip] is null. Pass [tooltip] to override it. In
/// tests, supply [onTap] to intercept the launch call without requiring a
/// platform channel.
class HelpLink extends StatelessWidget {
  const HelpLink({
    required this.url,
    this.tooltip,
    this.onTap,
    super.key,
  });

  /// The documentation URL to open.
  final String url;

  /// Tooltip text shown on hover / long-press. Defaults to the localised
  /// "Learn more" string when null.
  final String? tooltip;

  /// Optional tap handler for tests. When non-null, [url] is not launched.
  @visibleForTesting
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return CruxHelpLink(
      url: url,
      tooltip: tooltip ?? L10N.of(context).helpLinkLearnMore,
      onTap: onTap,
    );
  }
}
