// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:wavecrux/domain/enums/cocotb_log_severity.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Visual styling shared across all cocotb log UI surfaces (entry row,
/// severity chips, timeline overlay markers).
///
/// Centralised so the colour palette and Material icons are consistent
/// everywhere the user sees a severity. Dark and light themes use the same
/// hue family — these are semantic engineering colours (debug/info/warn/
/// error/critical) rather than theme accents.
@immutable
class CocotbSeverityStyle {
  const CocotbSeverityStyle({
    required this.color,
    required this.icon,
  });

  factory CocotbSeverityStyle.of(CocotbLogSeverity severity) =>
      switch (severity) {
        // Dimmer than debug and a quieter icon: TRACE is the highest-volume
        // level cocotb emits, so it must not compete with the levels a reader
        // is actually scanning for.
        CocotbLogSeverity.trace => const CocotbSeverityStyle(
          color: Color(0xFF6E6E6E), // dim grey
          icon: Icons.more_horiz,
        ),
        CocotbLogSeverity.debug => const CocotbSeverityStyle(
          color: Color(0xFF9E9E9E), // grey
          icon: Icons.bug_report_outlined,
        ),
        CocotbLogSeverity.info => const CocotbSeverityStyle(
          color: Color(0xFF2196F3), // blue
          icon: Icons.info_outline,
        ),
        CocotbLogSeverity.warning => const CocotbSeverityStyle(
          color: Color(0xFFFFB300), // amber
          icon: Icons.warning_amber_outlined,
        ),
        CocotbLogSeverity.error => const CocotbSeverityStyle(
          color: Color(0xFFE53935), // red
          icon: Icons.error_outline,
        ),
        CocotbLogSeverity.critical => const CocotbSeverityStyle(
          color: Color(0xFFB71C1C), // deep red
          icon: Icons.dangerous_outlined,
        ),
      };

  final Color color;
  final IconData icon;

  /// Localized label for the severity used in chips and tooltips.
  static String labelFor(CocotbLogSeverity severity, L10N l10n) =>
      switch (severity) {
        CocotbLogSeverity.trace => l10n.cocotbLogSeverityTrace,
        CocotbLogSeverity.debug => l10n.cocotbLogSeverityDebug,
        CocotbLogSeverity.info => l10n.cocotbLogSeverityInfo,
        CocotbLogSeverity.warning => l10n.cocotbLogSeverityWarning,
        CocotbLogSeverity.error => l10n.cocotbLogSeverityError,
        CocotbLogSeverity.critical => l10n.cocotbLogSeverityCritical,
      };
}
