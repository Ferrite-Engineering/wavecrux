// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/mobile/_mobile_fixture.dart
//
// Mobile-friendly fixture loading helper.
//
// The host-side `loadFixtureVcd` in `helpers/app_driver.dart` resolves the
// fixture path relative to `Directory.current.path` (the repo root). That
// works on desktop integration tests where the host filesystem is the
// simulator filesystem, but fails on iOS / Android simulators where
// `Directory.current.path` is the app sandbox and host paths like
// `/Users/jane/.../scalar_basics.vcd` do not exist.
//
// This helper writes an embedded VCD snippet to the platform's temporary
// directory and bootstraps the app with that on-device path. Identical
// behaviour on desktop (`getTemporaryDirectory()` returns a writable system
// temp directory there too), so a single test body works across all
// targets.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wavecrux/app.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import '../helpers/app_driver.dart';

/// Minimal 1 ns timescale VCD with three signals (`clk`, `rst`, `data`)
/// and a handful of transitions. Mirrors the structure of
/// `verification/fixtures/vcd/scalar_basics.vcd` so tests asserting on
/// generic viewer behaviour see the same shape on every target.
const String _scalarBasicsVcd = r'''
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! clk $end
$var wire 1 " rst $end
$var wire 8 # data $end
$upscope $end
$enddefinitions $end
$dumpvars
0!
1"
b00000000 #
$end
#10
1!
#20
0!
#30
1!
0"
b00000001 #
#40
0!
#50
1!
b00000010 #
#60
0!
#70
1!
#80
0!
#90
1!
b11111111 #
#100
0!
''';

/// Drains any pending RenderFlex / layout-overflow exceptions captured
/// during `setSurfaceSize` transitions on simulators whose native physical
/// screen is larger than the test surface.
///
/// The IdeController is created with visibility based on
/// `platformDispatcher.views.first.physicalSize` (which is fixed by the
/// host OS), so a phone-width test surface may briefly overflow before
/// the `deviceClassProvider` listener fires and force-hides side panes.
/// Tests that resize surfaces should call this before asserting
/// `takeException() == null`.
void drainTransientLayoutExceptions(WidgetTester tester) {
  // takeException returns the first pending exception and clears it.
  // Loop until no more are pending. Limit iterations as a guard.
  for (var i = 0; i < 32; i++) {
    final ex = tester.takeException();
    if (ex == null) break;
    final str = ex.toString();
    final isLayoutOverflow =
        str.contains('RenderFlex overflowed') ||
        str.contains('Flex overflowed');
    // Re-throw anything that is NOT a transient layout overflow so the
    // test still catches real defects.
    if (!isLayoutOverflow) {
      throw Exception(str);
    }
  }
}

/// Result of a synthetic-VCD load: the written file path, the root
/// `ProviderContainer`, and the active tab's per-tab container.
class SyntheticVcdLoad {
  /// Creates a record of a successful synthetic-VCD load.
  const SyntheticVcdLoad({
    required this.filePath,
    required this.rootContainer,
    required this.tabContainer,
  });

  /// Absolute path of the written `.vcd` file.
  final String filePath;

  /// Root `ProviderContainer` (app-global state).
  final ProviderContainer rootContainer;

  /// Active tab's per-tab `ProviderContainer` (file-specific state —
  /// cursor, time mapper, signal groups, waveform source). Per ARCHITECTURE.md
  /// §6.4 this is the container tests should read from for any waveform-
  /// specific provider.
  final ProviderContainer tabContainer;
}

/// Writes a small synthetic VCD to the platform's temp directory and
/// bootstraps the app pointing at the on-device path.
///
/// Polls the per-tab `waveformSourceProvider` until the source
/// reports `AsyncData<non-null>` so callers can immediately operate on
/// real waveform data. Returns the file path plus the root and active-tab
/// containers.
Future<SyntheticVcdLoad> loadSyntheticVcd(WidgetTester tester) async {
  // Tests share one application-support dir and run sequentially. Start from a
  // clean slate so leaked workspace/session state — or a leftover restore-guard
  // sentinel — from a prior test can't pollute this launch (e.g. trigger the
  // startup recovery banner, which then overflows the tablet layout assertion).
  await clearPersistedWorkspace();
  final dir = await getTemporaryDirectory();
  if (!dir.existsSync()) {
    await dir.create(recursive: true);
  }
  final filePath =
      '${dir.path}${Platform.pathSeparator}'
      'mobile_scalar_basics.vcd';
  await File(filePath).writeAsString(_scalarBasicsVcd);
  await seedFirstLaunchAnswers();
  await bootstrap(args: [filePath]);
  await tester.pump();
  // Settle the initial frames; the loop below is the real wait for the
  // background-isolate FFI parse (which schedules no frames until it
  // completes), so a bounded duration here would only burn wall-clock.
  await tester.pumpAndSettle();

  // The root container is provided by the outermost
  // `UncontrolledProviderScope` that bootstrap installs.
  final root = rootContainer(tester);
  // Resolve the active tab's per-tab container — that's where the
  // waveform source loads.
  final tcm = root.read(tabContainerManagerProvider);
  final activeTabId = root.read(activeTabIdProvider);
  final tabContainer = tcm.containerFor(activeTabId);

  // Poll for the source to finish loading. The FFI parses on a
  // background isolate; pumpAndSettle alone does not guarantee
  // completion because the isolate handshake involves multiple
  // microtask cycles.
  for (var i = 0; i < 40; i++) {
    final src = tabContainer.read(waveformSourceProvider);
    if (src.hasValue && src.value != null) break;
    await tester.pump(const Duration(milliseconds: 250));
  }

  return SyntheticVcdLoad(
    filePath: filePath,
    rootContainer: root,
    tabContainer: tabContainer,
  );
}
