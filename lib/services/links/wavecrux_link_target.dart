// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart' show CxpPathContainment;
import 'package:crux_io/crux_io.dart' show canonicalPathKey;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// The waveform formats a link may open.
///
/// Only formats WaveCrux reads in-process: VCD, FST and GHW go straight to the
/// parser, LXT and LXT2 through the in-process converter. Left out on purpose:
/// `.fsdb` (opening one runs an external converter, and a link never runs
/// anything), and `.wavecrux` sessions, `.wavecruxpack` bundles and
/// `.crux-project` manifests, which are not waveforms and name further files.
const Set<String> kWaveCruxLinkExtensions = {
  '.vcd',
  '.fst',
  '.ghw',
  '.lxt',
  '.lxt2',
};

/// Why the file a link names was not opened.
enum WaveCruxLinkTargetRefusal {
  /// The path is not an absolute, well-formed local path: the CXP receive
  /// floor refused it (relative, empty, padded, carrying a NUL, or a network
  /// or device path on Windows), or it names a Windows device or stream.
  pathRefused,

  /// Not one of [kWaveCruxLinkExtensions], as named or once links resolve.
  notAWaveform,

  /// Nothing is there, or it is not a regular file.
  fileNotFound,

  /// Links are not handled on this platform.
  unsupportedPlatform,
}

/// The result of [vetWaveCruxLinkTarget].
sealed class WaveCruxLinkTargetResult {
  const WaveCruxLinkTargetResult();
}

/// The file may be opened, subject to the user's consent.
final class WaveCruxLinkTargetAccepted extends WaveCruxLinkTargetResult {
  /// Wraps the resolved [path].
  const WaveCruxLinkTargetAccepted(this.path);

  /// The file to open: the link's path with every symbolic link resolved.
  /// This is the value checked, shown to the user, and opened.
  final String path;
}

/// The file may not be opened.
final class WaveCruxLinkTargetRefused extends WaveCruxLinkTargetResult {
  /// Wraps the [refusal].
  const WaveCruxLinkTargetRefused(this.refusal);

  /// Why not.
  final WaveCruxLinkTargetRefusal refusal;
}

/// The rule a link's path is held to before the filesystem is asked anything.
///
/// The CXP receive floor, unrooted: absolute, well-formed, no NUL, no padding,
/// and on Windows no `\\server\share`, `\\?\` or `\\.\` path (judging one of
/// those would open an SMB connection to a server the link chose). It is the
/// same instance of the rule `request_open_artifact` applies.
///
/// Why the floor and not the open-directory roots: a link exists to open a
/// waveform WaveCrux has not opened yet, so a rooted rule would refuse what
/// the feature is for. What a CXP peer proves with its per-process token, a
/// link cannot prove at all, so a link the user has not opened before is
/// confirmed by the user instead (see `openWaveCruxLink`).
const CxpPathContainment kWaveCruxLinkContainment = CxpPathContainment();

/// Windows device names, which open a device rather than a file whatever the
/// extension after them.
const Set<String> _windowsDeviceNames = {
  'con', 'prn', 'aux', 'nul', //
  'com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'com8', 'com9',
  'lpt1', 'lpt2', 'lpt3', 'lpt4', 'lpt5', 'lpt6', 'lpt7', 'lpt8', 'lpt9',
};

/// Decides whether the file a link names may be opened, and which file that
/// is once symbolic links resolve.
///
/// In order, and stopping at the first refusal:
///
/// 1. [kWaveCruxLinkContainment] judges the path as spelled, before anything
///    reads the filesystem.
/// 2. On Windows, an alternate data stream (`dump.vcd:x`) or a device name
///    (`NUL.vcd`) is refused, also by spelling.
/// 3. The extension, as spelled, must be a [kWaveCruxLinkExtensions] one.
/// 4. The path must exist and resolve, every link followed, to a regular file
///    whose own extension is one of them too: `dump.vcd` linking to
///    `~/.ssh/id_ed25519` is refused, not opened.
///
/// [windows] defaults to the host; tests pin it.
WaveCruxLinkTargetResult vetWaveCruxLinkTarget(
  String file, {
  bool? windows,
}) {
  if (kIsWeb) {
    return const WaveCruxLinkTargetRefused(
      WaveCruxLinkTargetRefusal.unsupportedPlatform,
    );
  }
  if (kWaveCruxLinkContainment.refuse(file) != null) {
    return const WaveCruxLinkTargetRefused(
      WaveCruxLinkTargetRefusal.pathRefused,
    );
  }
  if ((windows ?? Platform.isWindows) && _isWindowsDeviceOrStream(file)) {
    return const WaveCruxLinkTargetRefused(
      WaveCruxLinkTargetRefusal.pathRefused,
    );
  }
  if (!isWaveCruxLinkExtension(file)) {
    return const WaveCruxLinkTargetRefused(
      WaveCruxLinkTargetRefusal.notAWaveform,
    );
  }
  final String resolved;
  try {
    if (FileSystemEntity.typeSync(file) != FileSystemEntityType.file) {
      return const WaveCruxLinkTargetRefused(
        WaveCruxLinkTargetRefusal.fileNotFound,
      );
    }
    resolved = File(file).resolveSymbolicLinksSync();
    if (FileSystemEntity.typeSync(resolved, followLinks: false) !=
        FileSystemEntityType.file) {
      return const WaveCruxLinkTargetRefused(
        WaveCruxLinkTargetRefusal.fileNotFound,
      );
    }
  } on FileSystemException {
    return const WaveCruxLinkTargetRefused(
      WaveCruxLinkTargetRefusal.fileNotFound,
    );
  }
  if (!isWaveCruxLinkExtension(resolved)) {
    return const WaveCruxLinkTargetRefused(
      WaveCruxLinkTargetRefusal.notAWaveform,
    );
  }
  // The resolved path is opened, so it is held to the same rule as the path
  // the link spelled.
  if (kWaveCruxLinkContainment.refuse(resolved) != null) {
    return const WaveCruxLinkTargetRefused(
      WaveCruxLinkTargetRefusal.pathRefused,
    );
  }
  return WaveCruxLinkTargetAccepted(resolved);
}

/// Whether [path]'s extension is one a link may open, ignoring case.
bool isWaveCruxLinkExtension(String path) =>
    kWaveCruxLinkExtensions.contains(p.extension(path).toLowerCase());

/// Whether [path], a Windows path, names an alternate data stream or a
/// device.
@visibleForTesting
bool isWindowsDeviceOrStreamForTest(String path) =>
    _isWindowsDeviceOrStream(path);

bool _isWindowsDeviceOrStream(String path) {
  // A drive-letter path has its one legitimate colon at index 1.
  final afterDrive = path.length > 2 ? path.substring(2) : '';
  if (afterDrive.contains(':')) return true;
  final base = p.windows.basenameWithoutExtension(path).toLowerCase();
  final stem = base.split('.').first.trimRight();
  return _windowsDeviceNames.contains(stem);
}

/// Whether the user has opened [resolvedPath] in WaveCrux before: it is the
/// file of an open tab, or an entry in the recent-files list.
///
/// Compared by file identity (crux_io's [canonicalPathKey]: absolute,
/// normalized, symbolic links resolved, case folded where the filesystem
/// folds it), so a tab opened through one spelling matches a link through
/// another.
///
/// Only the user's own opens count. A link the user confirmed is not added to
/// recent files, so consenting once is not remembered: the next link to that
/// file asks again unless its tab is still open or the user has since opened
/// it themselves.
bool wasOpenedBefore(
  String resolvedPath, {
  required Iterable<String?> openTabPaths,
  required Iterable<String> recentPaths,
}) {
  final key = canonicalPathKey(resolvedPath);
  if (key.isEmpty) return false;
  for (final path in [...openTabPaths, ...recentPaths]) {
    if (path == null || path.isEmpty) continue;
    if (canonicalPathKey(path) == key) return true;
  }
  return false;
}
