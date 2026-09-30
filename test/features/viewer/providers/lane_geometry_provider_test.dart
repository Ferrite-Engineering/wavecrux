// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/viewer/providers/lane_geometry_provider.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/services/waveform_geom/lane_geometry.dart';

const _touch = LaneMetrics(minLaneHeight: 44);
const _desktop = LaneMetrics(minLaneHeight: 16);

Variable _v(String name) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: 'ref_$name',
  scopePath: 'top',
  bitWidth: 1,
);

void main() {
  test('reflects the arranged signal list', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(signalGroupsProvider.notifier)
      ..addSignal(_v('clk'))
      ..addSignal(_v('data'));

    final geometry = c.read(laneGeometryProvider(_desktop));
    expect(geometry.rows.length, 2);
    expect(geometry.totalHeight, 60); // two 30 dp lanes
  });

  test('the same LaneMetrics returns one shared instance to every reader', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

    // All three columns resolve an equal LaneMetrics → the family hands back
    // the identical cached LaneGeometry, so they cannot diverge.
    final a = c.read(laneGeometryProvider(_touch));
    final b = c.read(
      laneGeometryProvider(const LaneMetrics(minLaneHeight: 44)),
    );
    expect(identical(a, b), isTrue);
  });

  test('different LaneMetrics produce independent geometry', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(signalGroupsProvider.notifier).addSignal(_v('clk'));

    final touch = c.read(laneGeometryProvider(_touch));
    final desktop = c.read(laneGeometryProvider(_desktop));
    expect(touch.rows.single.height, 44); // clamped up on touch
    expect(desktop.rows.single.height, 30); // stored value on desktop
  });

  test('recomputes when the signal list changes', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(signalGroupsProvider.notifier).addSignal(_v('clk'));
    expect(c.read(laneGeometryProvider(_desktop)).rows.length, 1);

    c.read(signalGroupsProvider.notifier).addSignal(_v('data'));
    expect(c.read(laneGeometryProvider(_desktop)).rows.length, 2);
  });

  test('resolves the per-tab signal list, not the empty root scope', () {
    // Regression guard. signalGroupsProvider is overridden per tab via an
    // UncontrolledProviderScope (wavecrux_tab_overrides). Model that with a
    // child container that re-hosts signalGroupsProvider and holds this tab's
    // signals while the root scope's list stays empty. Because the value column
    // sources its row list from `geometry.rows`, laneGeometry MUST resolve
    // signalGroupsProvider from the tab scope; before it declared
    // SignalGroupsNotifier as a dependency it was hoisted to the root container,
    // read the empty root list, returned zero rows, and the value column
    // rendered blank on every tab even though the canvas and names list (which
    // read signalGroupsProvider directly in the tab scope) showed data.
    final root = ProviderContainer();
    addTearDown(root.dispose);
    expect(root.read(signalGroupsProvider).entries, isEmpty);

    final tab = ProviderContainer(
      parent: root,
      overrides: [signalGroupsProvider.overrideWith(SignalGroupsNotifier.new)],
    );
    addTearDown(tab.dispose);
    tab.read(signalGroupsProvider.notifier)
      ..addSignal(_v('clk'))
      ..addSignal(_v('data'));

    expect(tab.read(laneGeometryProvider(_desktop)).rows.length, 2);
  });
}
