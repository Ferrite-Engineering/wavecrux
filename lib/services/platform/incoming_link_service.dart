// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:wavecrux/services/links/wavecrux_link.dart';

/// Receives `wavecrux://` links the operating system delivers to the running
/// app.
///
/// **macOS** delivers a link as an Apple event, to the one running instance
/// or to the instance it launches for the link. The native half is
/// `IncomingLinkPlugin` in `macos/Runner/AppDelegate.swift`, which buffers a
/// link that arrives before Dart listens (the cold-launch case) and replays
/// it when [incomingLinks] is first listened to.
///
/// **Windows and Linux** have no running-instance delivery: the operating
/// system starts a new process with the link as its argument, and `bootstrap`
/// takes it from the command line ([WaveCruxLaunchArgs]). This stream never
/// emits there, nor on the web, iOS or Android, which register no scheme.
class IncomingLinkService {
  IncomingLinkService._();

  static const _eventChannel = EventChannel('com.wavecrux/incoming_link');

  static bool get _isSupported => !kIsWeb && Platform.isMacOS;

  /// Links delivered while the app runs, and any that arrived before the
  /// first listen. Each event is the link exactly as the system delivered it;
  /// nothing here parses or trusts it. Anything that is not a non-empty
  /// string is dropped. A link over [kWaveCruxLinkMaxLength] still arrives,
  /// so the parser can refuse it and the user is told; the native side drops
  /// anything over eight times that.
  static Stream<String> get incomingLinks {
    if (!_isSupported) return const Stream.empty();
    return _eventChannel
        .receiveBroadcastStream()
        .where((dynamic event) => event is String && event.isNotEmpty)
        .cast<String>();
  }
}
