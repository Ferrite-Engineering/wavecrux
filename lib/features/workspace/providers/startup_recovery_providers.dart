// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'startup_recovery_providers.g.dart';

/// Why the current launch is in a recovery posture, if at all.
///
/// Drives the startup recovery banner (`RecoveryBannerHost`) and whether the
/// previous session's waveforms were auto-reopened. Configured once in
/// `bootstrap()`; [StartupRecoveryReason.none] everywhere else.
enum StartupRecoveryReason {
  /// Normal launch — the previous session (if any) restored as usual.
  none,

  /// The previous launch crashed or hung while reopening a waveform (detected
  /// via `RestoreGuardService`). Auto-load was suppressed this launch; the
  /// banner offers to open the last session anyway or reset.
  interrupted,

  /// The auto-managed `workspace.json` was unreadable and was quarantined to
  /// `workspace.json.corrupt-<timestamp>`; the workspace started empty. The
  /// banner explains what happened (nothing to auto-open, so no resume).
  workspaceCorrupt,
}

/// Immutable launch-recovery posture, set once at startup.
@immutable
class StartupRecoveryState {
  /// Creates a recovery posture. Defaults describe a normal launch.
  const StartupRecoveryState({
    this.reason = StartupRecoveryReason.none,
    this.suppressAutoLoad = false,
  });

  /// Why this launch is recovering (drives the banner).
  final StartupRecoveryReason reason;

  /// Whether the cold-start reconcile should skip eagerly reopening the
  /// previously-active waveform(s). True when `--no-restore` was passed or a
  /// previous launch was interrupted. Restored tab *chips* still appear
  /// (nothing is lost or deleted); only the waveform auto-load is held back.
  final bool suppressAutoLoad;
}

/// Holds the current launch's recovery posture. `bootstrap()` calls
/// [StartupRecovery.configure] before `runApp` after consulting the restore
/// guard and the workspace-load recovery record; everything else only reads it.
/// keepAlive so the value, set before the first frame, survives widget
/// rebuilds for the lifetime of the launch.
@Riverpod(keepAlive: true)
class StartupRecovery extends _$StartupRecovery {
  @override
  StartupRecoveryState build() => const StartupRecoveryState();

  /// Records the recovery posture for this launch. Called once from
  /// `bootstrap()`.
  // ignore: use_setters_to_change_properties
  void configure(StartupRecoveryState value) => state = value;
}

/// Coordinates the "Open last session" action on the recovery banner.
///
/// When auto-load is suppressed but restorable tabs exist, the cold-start
/// reconcile registers a [registerResume] handler that performs the held-back
/// load. The banner reads [StartupRestoreResume.build] (its `bool` state) to
/// decide whether to show the action and calls [resume] when tapped. A
/// keepAlive notifier so the handler registered from the app shell survives the
/// banner's rebuilds.
@Riverpod(keepAlive: true)
class StartupRestoreResume extends _$StartupRestoreResume {
  VoidCallback? _handler;

  /// True once a resume handler has been registered (i.e. there is a suppressed
  /// session that can be reopened on demand).
  @override
  bool build() => false;

  /// Registers the held-back load. Called by the app shell after the reconcile
  /// determines auto-load was suppressed yet tabs are restorable.
  void registerResume(VoidCallback handler) {
    _handler = handler;
    state = true;
  }

  /// Invokes the registered resume handler (reopening the suppressed session)
  /// and consumes it, so the banner's action collapses after one use.
  void resume() {
    final handler = _handler;
    _handler = null;
    state = false;
    handler?.call();
  }
}
