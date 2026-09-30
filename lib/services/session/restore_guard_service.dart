// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

/// Crash-loop breaker for the cold-start session restore.
///
/// The restore that reopens the previously-active waveform is the one
/// operation at launch that can crash or hang the whole app — a pathological
/// capture that OOMs, a file that trips the Windows/Intel GPU-surface crash
/// (`docs/flutter-windows-gpu-crash-issue.md`), a decoder that loops. Quarantine
/// of a *malformed* `workspace.json` cannot help here: the document is
/// structurally valid; acting on it is what wedges startup.
///
/// This service writes a sentinel file (`{appSupportDir}/restore_in_progress`)
/// **before** that risky load begins ([arm]) and removes it **after** the first
/// successful content frame renders ([disarm]). The ordering is the whole
/// trick:
///
/// * A clean run arms then disarms — the next launch sees no sentinel and
///   restores normally.
/// * A crash *during* restore never reaches [disarm]; the OS relaunch sees the
///   sentinel still present.
/// * A *hang* during restore is force-quit by the user (swipe-kill on mobile,
///   Force Quit on desktop) — `dispose` never runs, so the sentinel also
///   survives. This is why the breaker covers hangs, not just crashes, and why
///   it is the primary recovery mechanism on mobile, where there is no command
///   line to pass `--reset` / `--no-restore`.
///
/// [wasInterrupted] reports whether the previous launch left the sentinel set.
/// The host reads it once at boot (then disarms) to decide whether to suppress
/// the auto-load and surface the recovery banner this launch.
///
/// All operations degrade to no-ops on web and wherever `path_provider` is
/// unavailable. Pass [directoryFactory] to point at a temp directory in tests.
class RestoreGuardService {
  /// Creates a restore-guard service. [directoryFactory] overrides the storage
  /// directory (tests); production resolves the application-support directory.
  const RestoreGuardService({Future<Directory> Function()? directoryFactory})
    : _directoryFactory = directoryFactory;

  final Future<Directory> Function()? _directoryFactory;

  static const _kFileName = 'restore_in_progress';

  /// Writes the sentinel, marking a restore as in progress. Call immediately
  /// before kicking off the active tab's deferred waveform load.
  Future<void> arm() async {
    try {
      final file = await _sentinelFile();
      if (file == null) return;
      await file.writeAsString('1', flush: true);
    } on Object {
      // Non-fatal: a failed arm only weakens crash-loop detection for this
      // launch — it must never block the restore it is guarding.
    }
  }

  /// Removes the sentinel, marking the restore as completed successfully. Call
  /// once the first content frame after the active tab's load has rendered.
  Future<void> disarm() async {
    try {
      final file = await _sentinelFile();
      if (file != null && file.existsSync()) await file.delete();
    } on Object {
      // Non-fatal.
    }
  }

  /// Returns true when a previous launch armed the sentinel and never disarmed
  /// — i.e. the last restore crashed or hung. Pure read; does not clear the
  /// sentinel (the caller disarms explicitly after deciding to skip restore).
  Future<bool> wasInterrupted() async {
    try {
      final file = await _sentinelFile();
      return file != null && file.existsSync();
    } on Object {
      return false;
    }
  }

  Future<File?> _sentinelFile() async {
    if (_directoryFactory == null && kIsWeb) return null;
    try {
      final factory = _directoryFactory;
      final dir = factory != null
          ? await factory()
          : await getApplicationSupportDirectory();
      return File('${dir.path}/$_kFileName');
    } on Object {
      return null;
    }
  }
}
