// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

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
/// **Windows and Linux** start a new process per link, with the link as its
/// argument. `bootstrap` takes the link a launch carries from its command line
/// ([WaveCruxLaunchArgs]), and, when another instance is already running,
/// hands it to that instance and exits (`crux_single_instance`). The running
/// instance's side of that hand-off is [attachForwardedLinks]: the links later
/// launches forwarded arrive on [incomingLinks], buffered until first listened
/// to, exactly as macOS replays one that arrived early.
///
/// The web, iOS and Android register no scheme: this stream never emits there.
class IncomingLinkService {
  IncomingLinkService._();

  static const _eventChannel = EventChannel('com.wavecrux/incoming_link');

  static Stream<String>? _forwarded;

  static bool get _isMacOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static bool get _handsOverByProcess =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  /// Takes the links other launches forward to this running instance
  /// (Windows and Linux). Call once, from `bootstrap`, with the stream the
  /// single-instance claim provides; a second call replaces the first.
  ///
  /// The claim's stream is single-subscription, but [incomingLinks] can be
  /// listened to more than once in one process: the app's state listens in
  /// `initState`, and that state is built again when the app is mounted
  /// again (a second `bootstrap` in the same process, which every
  /// integration-test file with more than one test does, finds the
  /// single-instance lock already held here and so attaches nothing new).
  /// The stream is shared so each of those listens succeeds. The source is
  /// not listened to until the first listen, so a link that arrives before
  /// it is still held, not lost.
  static void attachForwardedLinks(Stream<String> links) {
    _forwarded = links.isBroadcast ? links : links.asBroadcastStream();
  }

  /// Drops what [attachForwardedLinks] took. For tests.
  @visibleForTesting
  static void detachForwardedLinks() {
    _forwarded = null;
  }

  /// Links delivered while the app runs, and any that arrived before the
  /// first listen. Each event is the link exactly as the system delivered it;
  /// nothing here parses or trusts it. Anything that is not a non-empty
  /// string is dropped. A link over [kWaveCruxLinkMaxLength] still arrives
  /// on macOS, so the parser can refuse it and the user is told; the native
  /// side drops anything over eight times that. On Windows and Linux the
  /// single-instance policy refuses such a link before it is forwarded, and the
  /// launch that holds it opens it itself.
  static Stream<String> get incomingLinks {
    if (_isMacOS) {
      return _eventChannel
          .receiveBroadcastStream()
          .where((dynamic event) => event is String && event.isNotEmpty)
          .cast<String>();
    }
    final forwarded = _forwarded;
    if (_handsOverByProcess && forwarded != null) {
      return forwarded.where((link) => link.isNotEmpty);
    }
    return const Stream.empty();
  }
}
