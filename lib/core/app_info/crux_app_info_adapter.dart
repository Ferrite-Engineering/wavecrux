// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_app_info/crux_app_info.dart' as app_info;
import 'package:wavecrux/core/app_info/application_build_info.dart';

/// Maps WaveCrux's in-tree [ApplicationBuildInfo] onto the cross-suite
/// [app_info.ApplicationBuildInfo] the `crux_shared` packages consume.
///
/// WaveCrux keeps its own build-info model (populated from the generated
/// `build_info.dart` + `package_info_plus`) because the About box, the
/// diagnostics report, and several other surfaces read it directly. The
/// `crux_updates` and `crux_issue_reporter` packages, however, speak
/// `crux_app_info`'s shape — so the update / issue-reporter overrides bridge
/// through this single adapter rather than repeating the field mapping (the
/// same mapping the About dialog performs inline for the version section).
extension WavecruxBuildInfoCruxAdapter on ApplicationBuildInfo {
  /// Returns the `crux_app_info` view of this build info.
  app_info.ApplicationBuildInfo toCruxAppInfo() =>
      app_info.ApplicationBuildInfo(
        version: version,
        buildNumber: buildNumber,
        gitShortSha: gitSha,
        os: os,
        architecture: architecture,
        flutterSdkVersion: flutterVersion,
        dartSdkVersion: dartVersion,
      );
}
