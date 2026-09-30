// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

/// Prints `package:logging` records to the console (`debugPrint`) at or above a
/// mutable [threshold].
///
/// Independent of the issue-reporter ring buffer: the buffer always captures
/// every level (so bug reports stay complete), while this sink honours the
/// user's Settings → Diagnostics "Log verbosity" choice for what shows up in
/// the terminal during `flutter run` / a beta session. Driven by
/// `logConsoleSinkProvider`, which updates [threshold] whenever the setting
/// changes.
class LogConsoleSink {
  /// Creates a sink. Call [attach] to start listening.
  LogConsoleSink({this.threshold = Level.INFO, this.ceiling});

  /// The minimum level a record must reach to be printed. Mutable so the
  /// driving provider can update it live when the setting changes.
  Level threshold;

  /// Records at or above this level are left to another sink and not printed
  /// here; null prints everything from [threshold] up. Set to SEVERE while
  /// the stderr sink is attached, so an error goes to stderr once rather than
  /// to both streams.
  final Level? ceiling;

  StreamSubscription<LogRecord>? _subscription;

  /// Subscribes to [Logger.root]. Idempotent — a second call is a no-op.
  void attach() {
    if (_subscription != null) return;
    _subscription = Logger.root.onRecord.listen((record) {
      if (record.level < threshold) return;
      final ceiling = this.ceiling;
      if (ceiling != null && record.level >= ceiling) return;
      debugPrint(format(record));
    });
  }

  /// Cancels the subscription.
  Future<void> detach() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  /// Formats one record as a single console line:
  /// `HH:MM:SS.mmm LEVEL logger: message`.
  static String format(LogRecord record) {
    final t = record.time;
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}'
        '.${t.millisecond.toString().padLeft(3, '0')}';
    final logger = record.loggerName.isEmpty ? 'root' : record.loggerName;
    return '$stamp ${record.level.name} $logger: ${record.message}';
  }
}
