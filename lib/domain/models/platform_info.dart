// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Physical display metrics for a single screen or window.
@immutable
class ScreenInfo {
  const ScreenInfo({
    required this.physicalWidth,
    required this.physicalHeight,
    required this.devicePixelRatio,
  });

  /// Width in physical (device) pixels.
  final int physicalWidth;

  /// Height in physical (device) pixels.
  final int physicalHeight;

  /// Physical pixels per logical pixel (e.g. 2.0 for a Retina display).
  final double devicePixelRatio;

  /// Logical width in points (physicalWidth / devicePixelRatio).
  int get logicalWidth => (physicalWidth / devicePixelRatio).round();

  /// Logical height in points (physicalHeight / devicePixelRatio).
  int get logicalHeight => (physicalHeight / devicePixelRatio).round();

  ScreenInfo copyWith({
    int? physicalWidth,
    int? physicalHeight,
    double? devicePixelRatio,
  }) => ScreenInfo(
    physicalWidth: physicalWidth ?? this.physicalWidth,
    physicalHeight: physicalHeight ?? this.physicalHeight,
    devicePixelRatio: devicePixelRatio ?? this.devicePixelRatio,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScreenInfo &&
          runtimeType == other.runtimeType &&
          physicalWidth == other.physicalWidth &&
          physicalHeight == other.physicalHeight &&
          devicePixelRatio == other.devicePixelRatio;

  @override
  int get hashCode =>
      Object.hash(physicalWidth, physicalHeight, devicePixelRatio);

  @override
  String toString() =>
      'ScreenInfo(${physicalWidth}x$physicalHeight px, ${logicalWidth}x$logicalHeight logical, ${devicePixelRatio}x DPR)';
}

/// A snapshot of the host platform's environment, collected at report time.
///
/// All fields are populated on a best-effort basis. Fields that cannot be
/// determined on a given platform are set to null or empty strings.
@immutable
class PlatformInfo {
  const PlatformInfo({
    required this.operatingSystem,
    required this.osVersion,
    required this.cpuArchitecture,
    required this.cpuCores,
    required this.locale,
    required this.dartVersion,
    this.totalRamBytes,
    this.screens = const [],
  });

  /// OS identifier: "macos", "linux", "windows", "android", "ios", "web".
  final String operatingSystem;

  /// Full OS version string from the platform (e.g. "Version 15.4 (Build 24E248)").
  final String osVersion;

  /// CPU architecture: "arm64", "x64", "ia32", etc.
  final String cpuArchitecture;

  /// Number of logical CPU cores reported by the OS.
  final int cpuCores;

  /// Total physical RAM in bytes, or null if unavailable on this platform.
  final int? totalRamBytes;

  /// User's locale string (e.g. "en_US").
  final String locale;

  /// Dart VM version with channel (e.g. "3.5.3 (stable)").
  final String dartVersion;

  /// Display/window metrics for each screen Flutter can see.
  final List<ScreenInfo> screens;

  PlatformInfo copyWith({
    String? operatingSystem,
    String? osVersion,
    String? cpuArchitecture,
    int? cpuCores,
    int? totalRamBytes,
    String? locale,
    String? dartVersion,
    List<ScreenInfo>? screens,
  }) => PlatformInfo(
    operatingSystem: operatingSystem ?? this.operatingSystem,
    osVersion: osVersion ?? this.osVersion,
    cpuArchitecture: cpuArchitecture ?? this.cpuArchitecture,
    cpuCores: cpuCores ?? this.cpuCores,
    totalRamBytes: totalRamBytes ?? this.totalRamBytes,
    locale: locale ?? this.locale,
    dartVersion: dartVersion ?? this.dartVersion,
    screens: screens ?? this.screens,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PlatformInfo) return false;
    if (runtimeType != other.runtimeType) return false;
    if (operatingSystem != other.operatingSystem) return false;
    if (osVersion != other.osVersion) return false;
    if (cpuArchitecture != other.cpuArchitecture) return false;
    if (cpuCores != other.cpuCores) return false;
    if (totalRamBytes != other.totalRamBytes) return false;
    if (locale != other.locale) return false;
    if (dartVersion != other.dartVersion) return false;
    if (screens.length != other.screens.length) return false;
    for (var i = 0; i < screens.length; i++) {
      if (screens[i] != other.screens[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    operatingSystem,
    osVersion,
    cpuArchitecture,
    cpuCores,
    totalRamBytes,
    locale,
    dartVersion,
    Object.hashAll(screens),
  );

  @override
  String toString() =>
      'PlatformInfo('
      'os: $operatingSystem $osVersion, '
      'arch: $cpuArchitecture, '
      'cores: $cpuCores, '
      'ram: $totalRamBytes, '
      'locale: $locale, '
      'dart: $dartVersion, '
      'screens: ${screens.length}'
      ')';
}
