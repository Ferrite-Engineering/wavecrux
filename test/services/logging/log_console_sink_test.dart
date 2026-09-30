// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:wavecrux/services/logging/log_console_sink.dart';

void main() {
  test('format renders one line: time, level, logger, message', () {
    final line = LogConsoleSink.format(
      LogRecord(Level.WARNING, 'boom', 'wavecrux.test'),
    );
    expect(
      line,
      matches(RegExp(r'^\d\d:\d\d:\d\d\.\d\d\d WARNING wavecrux\.test: boom$')),
    );
  });

  test('only prints records at or above the threshold', () async {
    final printed = <String>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) printed.add(message);
    };
    final originalLevel = Logger.root.level;
    Logger.root.level = Level.ALL;

    final sink = LogConsoleSink(threshold: Level.WARNING)..attach();
    addTearDown(() async {
      await sink.detach();
      debugPrint = original;
      Logger.root.level = originalLevel;
    });

    Logger('wavecrux.test')
      ..info('below-threshold')
      ..severe('above-threshold');
    // Logging delivers records asynchronously through a broadcast stream.
    await Future<void>.delayed(Duration.zero);

    expect(printed.any((l) => l.contains('below-threshold')), isFalse);
    expect(printed.any((l) => l.contains('above-threshold')), isTrue);
  });

  test('leaves records at or above the ceiling to another sink', () async {
    final printed = <String>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) printed.add(message);
    };
    final originalLevel = Logger.root.level;
    Logger.root.level = Level.ALL;

    final sink = LogConsoleSink(ceiling: Level.SEVERE)..attach();
    addTearDown(() async {
      await sink.detach();
      debugPrint = original;
      Logger.root.level = originalLevel;
    });

    Logger('wavecrux.test')
      ..warning('printed-here')
      ..severe('left-to-stderr');
    await Future<void>.delayed(Duration.zero);

    expect(printed.any((l) => l.contains('printed-here')), isTrue);
    expect(printed.any((l) => l.contains('left-to-stderr')), isFalse);
  });

  test('a raised threshold suppresses lower records live', () async {
    final printed = <String>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) printed.add(message);
    };
    final originalLevel = Logger.root.level;
    Logger.root.level = Level.ALL;

    final sink = LogConsoleSink(threshold: Level.ALL)..attach();
    addTearDown(() async {
      await sink.detach();
      debugPrint = original;
      Logger.root.level = originalLevel;
    });

    Logger('wavecrux.test').fine('verbose-line');
    await Future<void>.delayed(Duration.zero);
    expect(printed.any((l) => l.contains('verbose-line')), isTrue);

    printed.clear();
    sink.threshold = Level.SEVERE;
    Logger('wavecrux.test').fine('now-hidden');
    await Future<void>.delayed(Duration.zero);
    expect(printed.any((l) => l.contains('now-hidden')), isFalse);
  });
}
