// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Brings the application window in front of the others, un-minimising it
/// first. Used when a `wavecrux://` link was handed to this running instance
/// on Windows or Linux, so the user sees the link open rather than a window
/// stay behind another.
///
/// The `window_manager` plugin the custom window chrome already runs on does
/// the work; it is behind this conditional export so it never reaches the web
/// build. Never throws: a window system that refuses to raise the window (a
/// Wayland compositor's focus-stealing prevention) leaves the link opened in
/// the window as it was.
library;

export 'bring_window_forward_stub.dart'
    if (dart.library.io) 'bring_window_forward_io.dart';
