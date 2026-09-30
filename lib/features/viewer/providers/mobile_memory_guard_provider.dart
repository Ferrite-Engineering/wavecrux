// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/diagnostics/memory_stats_service.dart';
import 'package:wavecrux/services/mobile/mobile_memory_guard_service.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

part 'mobile_memory_guard_provider.g.dart';

/// State exposed by [MobileMemoryGuardNotifier].
@immutable
class MemoryGuardState {
  const MemoryGuardState({
    this.pressureLevel = MemoryPressureLevel.ok,
    this.lastUnloadedCount = 0,
    this.osMemoryPressureReceived = false,
  });

  /// Current RSS-based memory pressure level for the active device class.
  final MemoryPressureLevel pressureLevel;

  /// Number of signals unloaded in the most recent pressure-relief pass.
  /// Reset to 0 when pressure returns to [MemoryPressureLevel.ok].
  final int lastUnloadedCount;

  /// Set to `true` when the OS delivers a `didHaveMemoryPressure` callback
  /// (iOS `didReceiveMemoryWarning` / Android `onTrimMemory`).
  /// Cleared after each pressure-relief pass completes.
  final bool osMemoryPressureReceived;

  MemoryGuardState copyWith({
    MemoryPressureLevel? pressureLevel,
    int? lastUnloadedCount,
    bool? osMemoryPressureReceived,
  }) => MemoryGuardState(
    pressureLevel: pressureLevel ?? this.pressureLevel,
    lastUnloadedCount: lastUnloadedCount ?? this.lastUnloadedCount,
    osMemoryPressureReceived:
        osMemoryPressureReceived ?? this.osMemoryPressureReceived,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MemoryGuardState &&
          runtimeType == other.runtimeType &&
          pressureLevel == other.pressureLevel &&
          lastUnloadedCount == other.lastUnloadedCount &&
          osMemoryPressureReceived == other.osMemoryPressureReceived;

  @override
  int get hashCode => Object.hash(
    pressureLevel,
    lastUnloadedCount,
    osMemoryPressureReceived,
  );

  @override
  String toString() =>
      'MemoryGuardState('
      'pressureLevel: $pressureLevel, '
      'lastUnloaded: $lastUnloadedCount, '
      'osPressure: $osMemoryPressureReceived'
      ')';
}

/// Monitors memory pressure on mobile device classes and unloads idle signal
/// data when the process RSS approaches device limits.
///
/// **Activation:** Only active on [DeviceClass.phone], [DeviceClass.phoneLandscape],
/// and [DeviceClass.tablet].  On [DeviceClass.desktop] it is a no-op.
///
/// **Polling:** Checks RSS every 5 seconds. On [MemoryPressureLevel.warning]
/// or above, signals that are loaded but not visible in the signal panel are
/// unloaded (least-recently-added first, preserving visible signals).
///
/// **OS callbacks:** Registers as a [WidgetsBindingObserver] to handle
/// `didHaveMemoryPressure`, which Flutter surfaces for both iOS
/// `didReceiveMemoryWarning` and Android `onTrimMemory`. An OS callback
/// triggers an immediate pressure-relief pass at [MemoryPressureLevel.critical]
/// severity, regardless of the polling interval.
@Riverpod(keepAlive: true)
class MobileMemoryGuardNotifier extends _$MobileMemoryGuardNotifier
    with WidgetsBindingObserver {
  static const _pollInterval = Duration(seconds: 5);
  static const _service = MobileMemoryGuardService();
  static const _statsService = MemoryStatsService();

  Timer? _timer;
  bool _disposed = false;

  @override
  MemoryGuardState build() {
    _disposed =
        false; // Reset on each rebuild (keepAlive notifiers reuse the instance).
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
      WidgetsBinding.instance.removeObserver(this);
    });

    final deviceClass = ref.watch(deviceClassProvider);

    // Only activate monitoring on mobile device classes.
    if (deviceClass == DeviceClass.desktop) {
      return const MemoryGuardState();
    }

    WidgetsBinding.instance.addObserver(this);
    _startPolling(deviceClass);
    return const MemoryGuardState();
  }

  void _startPolling(DeviceClass deviceClass) {
    _timer?.cancel();
    _timer = Timer.periodic(_pollInterval, (_) {
      if (!_disposed) {
        unawaited(_runPressureCheck(deviceClass, isOsCallback: false));
      }
    });
  }

  // ── WidgetsBindingObserver ─────────────────────────────────────────────────

  @override
  void didHaveMemoryPressure() {
    super.didHaveMemoryPressure();
    final deviceClass = ref.read(deviceClassProvider);
    if (deviceClass == DeviceClass.desktop || _disposed) return;
    state = state.copyWith(osMemoryPressureReceived: true);
    unawaited(_runPressureCheck(deviceClass, isOsCallback: true));
  }

  // ── Pressure check ─────────────────────────────────────────────────────────

  Future<void> _runPressureCheck(
    DeviceClass deviceClass, {
    required bool isOsCallback,
  }) async {
    // This is a root keepAlive notifier, but waveformSourceProvider and
    // signalGroupsProvider are per-tab. Resolve them through the ACTIVE tab's
    // container — reading them from this root scope always sees a null source,
    // so the guard would never unload anything. Memory pressure is
    // process-wide; the active tab is where signals are interactively loaded
    // (and on phone there is only ever one tab). A future refinement could
    // sweep idle signals across every tab's container.
    final ProviderContainer tabContainer;
    try {
      final tcm = ref.read(tabContainerManagerProvider);
      tabContainer = tcm.containerFor(ref.read(activeTabIdProvider));
    } on Object {
      return;
    }
    final sourceAsync = tabContainer.read(waveformSourceProvider);
    final source = sourceAsync.value;
    if (source == null) return;

    // Collect current RSS.
    int? wellenBytes;
    if (source is WellenProvider) {
      wellenBytes = await source.memoryUsageBytes();
    }
    if (_disposed) return;

    final stats = _statsService.collect(
      source: source,
      wellenMemoryBytes: wellenBytes,
    );

    // Determine the pressure level (or force critical on OS callback).
    final level = isOsCallback
        ? MemoryPressureLevel.critical
        : _service.assessPressure(stats, deviceClass);

    if (level == MemoryPressureLevel.ok) {
      if (!_disposed) {
        state = state.copyWith(
          pressureLevel: MemoryPressureLevel.ok,
          lastUnloadedCount: 0,
          osMemoryPressureReceived: false,
        );
      }
      return;
    }

    // Unload signals that are loaded but not in the current signal group.
    // Read `signalGroupsProvider` from the ACTIVE tab's container, not this
    // root scope — same reason `waveformSourceProvider` is read via
    // `tabContainer` above. Reading it from root returns the empty root signal
    // group, so `visibleSignalRefs` would be empty and the guard would treat
    // every loaded signal as non-visible and unload signals the user is
    // actively viewing. (Scope-leak class of issue #44.)
    final signalGroup = tabContainer.read(signalGroupsProvider);
    final visibleRefs = _service.visibleSignalRefs(signalGroup);
    final allVariables = source.findVariables(const SignalFilter());

    var unloadedCount = 0;
    for (final variable in allVariables) {
      final signalRef = variable.signalRef;
      if (!visibleRefs.contains(signalRef) &&
          source.isSignalLoaded(signalRef)) {
        await source.unloadSignal(signalRef);
        unloadedCount++;
        if (_disposed) return;
      }
    }

    if (!_disposed) {
      state = state.copyWith(
        pressureLevel: level,
        lastUnloadedCount: unloadedCount,
        osMemoryPressureReceived: false,
      );
    }
  }
}
