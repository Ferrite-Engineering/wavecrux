// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/app.dart';
import 'package:wavecrux/services/logging/severe_log_stderr_sink.dart';

class _Capture implements StreamConsumer<List<int>> {
  final buffer = StringBuffer();

  @override
  Future<void> addStream(Stream<List<int>> stream) =>
      stream.forEach((bytes) => buffer.write(utf8.decode(bytes)));

  @override
  Future<void> close() async {}
}

/// The uncaught-error path, end to end: what `bootstrap()` attaches must carry
/// a framework error and an uncaught async error to stderr.
///
/// Until the stderr sink existed, both reached only the issue reporter's
/// in-memory buffer, so on a user's machine they were gone with the session.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('uncaught framework and async errors reach stderr', () async {
    // The handlers `captureFlutterErrors` chains to. The test binding's own
    // would fail this test for the errors it reports on purpose.
    final previousFlutter = FlutterError.onError;
    final previousDispatcher = PlatformDispatcher.instance.onError;
    FlutterError.onError = (_) {};
    PlatformDispatcher.instance.onError = (_, _) => true;
    addTearDown(() {
      FlutterError.onError = previousFlutter;
      PlatformDispatcher.instance.onError = previousDispatcher;
    });

    final capture = _Capture();
    final sink = SevereLogStderrSink(sink: IOSink(capture));
    addTearDown(sink.detach);

    attachDiagnosticSinks(stderrSink: sink);
    FlutterError.onError!(
      FlutterErrorDetails(exception: StateError('frame failed')),
    );
    PlatformDispatcher.instance.onError!(
      StateError('async failed'),
      StackTrace.current,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final text = capture.buffer.toString();
    expect(text, contains('SEVERE flutter: Bad state: frame failed'));
    expect(text, contains('SEVERE flutter: Uncaught: Bad state: async failed'));
  });
}
