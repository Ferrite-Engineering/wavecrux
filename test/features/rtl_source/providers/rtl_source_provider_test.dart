// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/rtl_source/providers/rtl_source_provider.dart';
import 'package:wavecrux/services/rtl_source/rtl_source_loader.dart';

class _FakeStemsReader implements StemsFileReader {
  _FakeStemsReader();
  final Map<String, String> contents = {};
  final Map<String, Exception> failures = {};

  @override
  Future<String> readAsString(String path) async {
    final fail = failures[path];
    if (fail != null) throw fail;
    final c = contents[path];
    if (c == null) throw Exception('not found: $path');
    return c;
  }
}

class _FakeFileReader extends FileReader {
  _FakeFileReader();
  final Map<String, String> contents = {};
  final Map<String, DateTime> mtimes = {};

  @override
  Future<RtlFileStat?> stat(String path) async {
    final m = mtimes[path];
    return m == null ? null : RtlFileStat(modified: m);
  }

  @override
  Future<String> readAsString(String path) async {
    final c = contents[path];
    if (c == null) throw Exception('missing $path');
    return c;
  }
}

const _stemsContent = '''
++ comp 0 file /src/cpu.v
++ module top.cpu 0 1
+++ var clk 0 5
+++ var rst 0 6
''';

const _cpuSource =
    'module cpu (input clk, input rst);\n'
    '  reg [7:0] state;\n'
    '  always @(posedge clk)\n'
    '    state <= state + 1;\n'
    'endmodule\n';

ProviderContainer _container({
  StemsFileReader? stemsReader,
  RtlSourceLoader? loader,
}) {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  c
      .read(rtlSourceProvider.notifier)
      .overrideForTest(
        reader: stemsReader,
        loader: loader,
      );
  return c;
}

void main() {
  // ── initial state ──────────────────────────────────────────────────────────
  test('initial state is idle, no stems loaded', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final s = c.read(rtlSourceProvider);
    expect(s.status, RtlStemsStatus.idle);
    expect(s.stems, isNull);
    expect(s.hasStems, isFalse);
    expect(s.currentSourceFile, isNull);
    expect(s.currentLine, isNull);
    expect(c.read(rtlStemsLoadedProvider), isFalse);
  });

  // ── loadStemsFile ──────────────────────────────────────────────────────────
  group('loadStemsFile', () {
    test('parses successfully and transitions to ready', () async {
      final reader = _FakeStemsReader()..contents['/stems.txt'] = _stemsContent;
      final c = _container(stemsReader: reader);
      await c.read(rtlSourceProvider.notifier).loadStemsFile('/stems.txt');
      final s = c.read(rtlSourceProvider);
      expect(s.status, RtlStemsStatus.ready);
      expect(s.stemsPath, '/stems.txt');
      expect(s.stems!.length, 3);
      expect(s.hasStems, isTrue);
      expect(s.error, isNull);
      expect(c.read(rtlStemsLoadedProvider), isTrue);
    });

    test('IO failure transitions to error and preserves no stems', () async {
      final reader = _FakeStemsReader()
        ..failures['/missing.txt'] = Exception('denied');
      final c = _container(stemsReader: reader);
      await c.read(rtlSourceProvider.notifier).loadStemsFile('/missing.txt');
      final s = c.read(rtlSourceProvider);
      expect(s.status, RtlStemsStatus.error);
      expect(s.error, contains('denied'));
      expect(s.stems, isNull);
    });

    test('clears prior selection when new stems are loaded', () async {
      final fakeFs = _FakeFileReader()
        ..contents['/src/cpu.v'] = _cpuSource
        ..mtimes['/src/cpu.v'] = DateTime(2026);
      final loader = RtlSourceLoader(fileReader: fakeFs);
      final reader = _FakeStemsReader()..contents['/stems.txt'] = _stemsContent;
      final c = _container(stemsReader: reader, loader: loader);
      final n = c.read(rtlSourceProvider.notifier);
      await n.loadStemsFile('/stems.txt');
      await n.showSignal(signalRef: 'r1', signalPath: 'top.cpu.clk');
      expect(c.read(rtlSourceProvider).currentSourceFile, isNotNull);
      // Reload — selection should clear.
      await n.loadStemsFile('/stems.txt');
      final s = c.read(rtlSourceProvider);
      expect(s.currentSourceFile, isNull);
      expect(s.currentLine, isNull);
      expect(s.currentSignalRef, isNull);
    });
  });

  // ── showSignal ─────────────────────────────────────────────────────────────
  group('showSignal', () {
    test('navigates to a known signal', () async {
      final fakeFs = _FakeFileReader()
        ..contents['/src/cpu.v'] = _cpuSource
        ..mtimes['/src/cpu.v'] = DateTime(2026);
      final loader = RtlSourceLoader(fileReader: fakeFs);
      final reader = _FakeStemsReader()..contents['/stems.txt'] = _stemsContent;
      final c = _container(stemsReader: reader, loader: loader);
      final n = c.read(rtlSourceProvider.notifier);
      await n.loadStemsFile('/stems.txt');

      final ok = await n.showSignal(
        signalRef: 'sigA',
        signalPath: 'top.cpu.clk',
      );
      expect(ok, isTrue);
      final s = c.read(rtlSourceProvider);
      expect(s.currentSourceFile?.path, '/src/cpu.v');
      expect(s.currentLine, 5);
      expect(s.currentSignalRef, 'sigA');
      expect(s.currentSignalPath, 'top.cpu.clk');
      expect(s.error, isNull);
    });

    test('returns false and sets error when no stems loaded', () async {
      final c = _container();
      final ok = await c
          .read(rtlSourceProvider.notifier)
          .showSignal(signalRef: 'r', signalPath: 'top.x');
      expect(ok, isFalse);
      expect(c.read(rtlSourceProvider).error, contains('No stems file loaded'));
    });

    test('returns false and sets error on lookup miss', () async {
      final reader = _FakeStemsReader()..contents['/stems.txt'] = _stemsContent;
      final c = _container(stemsReader: reader);
      final n = c.read(rtlSourceProvider.notifier);
      await n.loadStemsFile('/stems.txt');
      final ok = await n.showSignal(
        signalRef: 'r',
        signalPath: 'no.such.signal',
      );
      expect(ok, isFalse);
      expect(c.read(rtlSourceProvider).error, contains('No stems mapping'));
    });

    test(
      'returns false on source-file load error and preserves error',
      () async {
        // Stems file loads fine but the referenced source file is missing.
        final fakeFs = _FakeFileReader(); // empty — every stat returns null.
        final loader = RtlSourceLoader(fileReader: fakeFs);
        final reader = _FakeStemsReader()
          ..contents['/stems.txt'] = _stemsContent;
        final c = _container(stemsReader: reader, loader: loader);
        final n = c.read(rtlSourceProvider.notifier);
        await n.loadStemsFile('/stems.txt');
        final ok = await n.showSignal(
          signalRef: 'r',
          signalPath: 'top.cpu.clk',
        );
        expect(ok, isFalse);
        final s = c.read(rtlSourceProvider);
        expect(s.error, isNotNull);
        // Previous (empty) selection is unchanged.
        expect(s.currentSourceFile, isNull);
      },
    );
  });

  // ── showByName ─────────────────────────────────────────────────────────────
  test('showByName resolves a bare signal name via suffix matching', () async {
    final fakeFs = _FakeFileReader()
      ..contents['/src/cpu.v'] = _cpuSource
      ..mtimes['/src/cpu.v'] = DateTime(2026);
    final loader = RtlSourceLoader(fileReader: fakeFs);
    final reader = _FakeStemsReader()..contents['/stems.txt'] = _stemsContent;
    final c = _container(stemsReader: reader, loader: loader);
    final n = c.read(rtlSourceProvider.notifier);
    await n.loadStemsFile('/stems.txt');
    final ok = await n.showByName('clk');
    expect(ok, isTrue);
    final s = c.read(rtlSourceProvider);
    expect(s.currentLine, 5);
    expect(s.currentSignalPath, 'top.cpu.clk');
    expect(s.currentSignalRef, isNull); // bare name path has no signalRef
  });

  test('showByName returns false when no stems loaded', () async {
    final c = _container();
    final ok = await c.read(rtlSourceProvider.notifier).showByName('clk');
    expect(ok, isFalse);
  });

  // ── clearStems / clearSelection ────────────────────────────────────────────
  group('clear', () {
    test('clearStems resets to initial state', () async {
      final reader = _FakeStemsReader()..contents['/stems.txt'] = _stemsContent;
      final c = _container(stemsReader: reader);
      final n = c.read(rtlSourceProvider.notifier);
      await n.loadStemsFile('/stems.txt');
      n.clearStems();
      expect(c.read(rtlSourceProvider), const RtlSourceState());
    });

    test('clearSelection drops selection but keeps stems', () async {
      final fakeFs = _FakeFileReader()
        ..contents['/src/cpu.v'] = _cpuSource
        ..mtimes['/src/cpu.v'] = DateTime(2026);
      final loader = RtlSourceLoader(fileReader: fakeFs);
      final reader = _FakeStemsReader()..contents['/stems.txt'] = _stemsContent;
      final c = _container(stemsReader: reader, loader: loader);
      final n = c.read(rtlSourceProvider.notifier);
      await n.loadStemsFile('/stems.txt');
      await n.showSignal(signalRef: 'r', signalPath: 'top.cpu.clk');
      n.clearSelection();
      final s = c.read(rtlSourceProvider);
      expect(s.stems, isNotNull);
      expect(s.currentSourceFile, isNull);
      expect(s.currentLine, isNull);
    });
  });

  // ── RtlSourceState equality / copyWith ─────────────────────────────────────
  group('RtlSourceState', () {
    test('equality and hashCode', () {
      const a = RtlSourceState();
      const b = RtlSourceState();
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('toString contains status and entry count', () {
      const a = RtlSourceState();
      expect(a.toString(), contains('idle'));
    });

    test('copyWith with clearError drops the error', () {
      const a = RtlSourceState(error: 'boom');
      final b = a.copyWith(clearError: true);
      expect(b.error, isNull);
    });

    test('copyWith with clearStems wipes everything except status', () {
      const a = RtlSourceState(
        status: RtlStemsStatus.ready,
        stemsPath: '/x',
        currentSignalRef: 'r',
      );
      final b = a.copyWith(clearStems: true);
      expect(b.stemsPath, isNull);
      expect(b.stems, isNull);
      expect(b.currentSignalRef, isNull);
    });
  });
}
