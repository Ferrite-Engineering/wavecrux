// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/models/memory_stats.dart';
import 'package:wavecrux/domain/models/signal_group.dart';

/// Discrete memory pressure level assessed by [MobileMemoryGuardService].
enum MemoryPressureLevel {
  /// Memory usage is within normal operating range.
  ok,

  /// Memory usage is approaching the device limit. Consider unloading idle
  /// signals to prevent a hard memory limit being hit.
  warning,

  /// Memory usage is critically high. Unload idle signals immediately and
  /// notify the user so they can close the file if necessary.
  critical,
}

/// Stateless service that evaluates mobile memory management thresholds.
///
/// All methods are pure functions — supply the current [DeviceClass] and
/// [MemoryStats] obtained from [MemoryStatsService]. The service itself holds
/// no state; the [MobileMemoryGuardNotifier] Riverpod provider owns the state
/// and calls these methods on a polling interval.
///
/// **File-size thresholds** (shown before loading):
/// - Phone / phone-landscape: warn at files > 100 MB
/// - Tablet: warn at files > 250 MB
/// - Desktop: no warning (unconstrained)
///
/// **RSS-based pressure thresholds** (monitoring while viewer is open):
/// - Phone warning:  300 MB RSS
/// - Phone critical: 500 MB RSS
/// - Tablet warning:  600 MB RSS
/// - Tablet critical: 1 000 MB RSS
/// - Desktop: no limits
class MobileMemoryGuardService {
  const MobileMemoryGuardService({
    int phoneFileSizeLimitBytes = _defaultPhoneFileSizeLimit,
    int tabletFileSizeLimitBytes = _defaultTabletFileSizeLimit,
    int phoneRssWarningBytes = _defaultPhoneRssWarning,
    int phoneRssCriticalBytes = _defaultPhoneRssCritical,
    int tabletRssWarningBytes = _defaultTabletRssWarning,
    int tabletRssCriticalBytes = _defaultTabletRssCritical,
  }) : _phoneFileSizeLimit = phoneFileSizeLimitBytes,
       _tabletFileSizeLimit = tabletFileSizeLimitBytes,
       _phoneRssWarning = phoneRssWarningBytes,
       _phoneRssCritical = phoneRssCriticalBytes,
       _tabletRssWarning = tabletRssWarningBytes,
       _tabletRssCritical = tabletRssCriticalBytes;

  static const int _defaultPhoneFileSizeLimit = 100 * 1024 * 1024; // 100 MB
  static const int _defaultTabletFileSizeLimit = 250 * 1024 * 1024; // 250 MB
  static const int _defaultPhoneRssWarning = 300 * 1024 * 1024; // 300 MB
  static const int _defaultPhoneRssCritical = 500 * 1024 * 1024; // 500 MB
  static const int _defaultTabletRssWarning = 600 * 1024 * 1024; // 600 MB
  static const int _defaultTabletRssCritical = 1000 * 1024 * 1024; // 1 000 MB

  final int _phoneFileSizeLimit;
  final int _tabletFileSizeLimit;
  final int _phoneRssWarning;
  final int _phoneRssCritical;
  final int _tabletRssWarning;
  final int _tabletRssCritical;

  // ── File-size warning ──────────────────────────────────────────────────────

  /// File-size threshold (bytes) above which a pre-load warning dialog is
  /// shown for the given [deviceClass], or `null` when there is no limit
  /// (desktop).
  int? fileSizeThresholdBytes(DeviceClass deviceClass) {
    return switch (deviceClass) {
      DeviceClass.phone || DeviceClass.phoneLandscape => _phoneFileSizeLimit,
      DeviceClass.tablet => _tabletFileSizeLimit,
      DeviceClass.desktop => null,
    };
  }

  /// Returns `true` when [fileSizeBytes] exceeds the file-size warning
  /// threshold for [deviceClass].
  ///
  /// Always returns `false` for [DeviceClass.desktop].
  bool shouldWarnBeforeLoad(int fileSizeBytes, DeviceClass deviceClass) {
    final threshold = fileSizeThresholdBytes(deviceClass);
    if (threshold == null) return false;
    return fileSizeBytes > threshold;
  }

  // ── Memory pressure assessment ─────────────────────────────────────────────

  /// RSS-based warning threshold for [deviceClass], or `null` for desktop.
  int? rssWarningThresholdBytes(DeviceClass deviceClass) {
    return switch (deviceClass) {
      DeviceClass.phone || DeviceClass.phoneLandscape => _phoneRssWarning,
      DeviceClass.tablet => _tabletRssWarning,
      DeviceClass.desktop => null,
    };
  }

  /// RSS-based critical threshold for [deviceClass], or `null` for desktop.
  int? rssCriticalThresholdBytes(DeviceClass deviceClass) {
    return switch (deviceClass) {
      DeviceClass.phone || DeviceClass.phoneLandscape => _phoneRssCritical,
      DeviceClass.tablet => _tabletRssCritical,
      DeviceClass.desktop => null,
    };
  }

  /// Assesses the current [MemoryPressureLevel] from [stats] for
  /// [deviceClass].
  ///
  /// Uses [MemoryStats.dartProcessRssBytes] as the primary metric.
  /// Always returns [MemoryPressureLevel.ok] for [DeviceClass.desktop].
  MemoryPressureLevel assessPressure(
    MemoryStats stats,
    DeviceClass deviceClass,
  ) {
    final critical = rssCriticalThresholdBytes(deviceClass);
    if (critical == null) return MemoryPressureLevel.ok;
    final warning = rssWarningThresholdBytes(deviceClass)!;
    final rss = stats.dartProcessRssBytes;
    if (rss >= critical) return MemoryPressureLevel.critical;
    if (rss >= warning) return MemoryPressureLevel.warning;
    return MemoryPressureLevel.ok;
  }

  // ── Signal visibility helpers ──────────────────────────────────────────────

  /// Collects all signal refs currently visible in [group] (recursively).
  ///
  /// Collapsed groups are still traversed — a signal in a collapsed group is
  /// still conceptually "in the viewer" even if its lane is hidden.
  Set<String> visibleSignalRefs(SignalGroup group) {
    final refs = <String>{};
    _collectRefs(group.entries, refs);
    return refs;
  }

  void _collectRefs(List<SignalEntry> entries, Set<String> out) {
    for (final entry in entries) {
      if (entry.kind == SignalEntryKind.signal && entry.signalRef != null) {
        out.add(entry.signalRef!);
      } else if (entry.kind == SignalEntryKind.group) {
        _collectRefs(entry.children, out);
      }
    }
  }
}
