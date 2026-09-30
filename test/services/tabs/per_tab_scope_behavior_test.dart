// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Behavioral companion to `test/static/per_tab_provider_scope_leak_test.dart`.
//
// The static guard proves the per-tab-seed invariant by source inspection.
// This test proves the *runtime* consequence the invariant protects: a
// provider that reads per-tab state resolves against the focused TAB's state
// when read from that tab's container, and against the empty ROOT state when
// read from root.
//
// Crucially this exercises a REAL parent/child container pair built by the
// real `TabContainerManager` — not the flat single `ProviderContainer` that
// every provider unit test uses and under which the scoping defect of issue
// #44 was invisible. Without the `stageBoundSignalProvider` override in
// `wavecruxTabOverrides`, the tab read below hoists to root and returns
// `noFile` — i.e. this test fails, exactly as the bug shipped.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/stage_signal_snapshot.dart';
import 'package:wavecrux/domain/models/tab_id.dart';
import 'package:wavecrux/features/cocotb/providers/cocotb_log_provider.dart';
import 'package:wavecrux/features/stage/providers/stage_signal_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

class _MockSource extends Mock implements WaveformDataSource {}

class _FakeSourceNotifier extends WaveformSourceNotifier {
  _FakeSourceNotifier(this._source);
  final WaveformDataSource? _source;

  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

void main() {
  group('per-tab provider scoping (issue #44 behavioral regression)', () {
    test(
      'stageBoundSignal reads the focused tab source, not the empty root',
      () {
        // A loaded source for the TAB: signal "0" is loaded and reads '1'.
        final source = _MockSource();
        when(() => source.rootScopes).thenReturn(const []);
        when(() => source.startTime).thenReturn(0);
        when(() => source.isSignalLoaded('0')).thenReturn(true);
        when(() => source.loadSignal('0')).thenAnswer((_) async {});
        when(() => source.valueAt('0', any())).thenReturn('1');

        // The TAB container gets the loaded source; ROOT stays empty (null
        // source) — the real-world state where files are always per-tab.
        final tcm = TabContainerManager(
          extraTabOverrides: [
            waveformSourceProvider.overrideWith(
              () => _FakeSourceNotifier(source),
            ),
          ],
        );
        final root = ProviderContainer(
          overrides: [
            tabContainerManagerProvider.overrideWithValue(tcm),
            waveformSourceProvider.overrideWith(
              () => _FakeSourceNotifier(null),
            ),
          ],
        );
        addTearDown(root.dispose);
        addTearDown(tcm.dispose);
        tcm.init(root);

        final tab = tcm.containerFor(TabId.generate());
        const binding = StageSignalBinding(signalRef: '0');

        // From the TAB: resolves the tab's loaded source -> a real value.
        // (Pre-fix this returned noFile because the provider fell through to
        // root.)
        final tabSnapshot = tab.read(stageBoundSignalProvider(binding));
        expect(
          tabSnapshot.kind,
          StageSignalSnapshotKind.value,
          reason:
              'Stage binding must resolve against the focused tab source. '
              'noFile here means stageBoundSignalProvider leaked to root '
              '(issue #44).',
        );

        // From ROOT: no file is ever loaded at root scope -> noFile.
        final rootSnapshot = root.read(stageBoundSignalProvider(binding));
        expect(rootSnapshot.kind, StageSignalSnapshotKind.noFile);
      },
    );

    test(
      'a cocotb log loaded into one tab does not bleed into another tab',
      () async {
        const sampleLog =
            '   100.00ns INFO     cocotb.test_basic   Applied reset\n';

        final tcm = TabContainerManager();
        final root = ProviderContainer(
          overrides: [tabContainerManagerProvider.overrideWithValue(tcm)],
        );
        addTearDown(root.dispose);
        addTearDown(tcm.dispose);
        tcm.init(root);

        final tabA = tcm.containerFor(TabId.generate());
        final tabB = tcm.containerFor(TabId.generate());

        // Load a log into tab A only, via the per-tab notifier (mirroring how
        // `_loadCocotbLog` writes through the active tab's container).
        final notifierA = tabA.read(cocotbLogProvider.notifier)
          ..reader = (_) async => sampleLog;
        await notifierA.loadFromFile('/tmp/a.log');

        // Tab A sees its own log; tab B and root stay empty — proving the log
        // is genuinely per-tab and no longer a shared root singleton.
        expect(tabA.read(cocotbLogProvider), isNotNull);
        expect(tabA.read(cocotbLogProvider)!.filePath, '/tmp/a.log');
        expect(
          tabB.read(cocotbLogProvider),
          isNull,
          reason:
              'cocotb log leaked across tabs — cocotbLogProvider is not '
              'per-tab.',
        );
        expect(root.read(cocotbLogProvider), isNull);
      },
    );
  });
}
