// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Hands files dropped onto the desktop window to whoever can open them.
//
// The drop target covers the whole window, so it is mounted above the
// Navigator in `MaterialApp.builder` — around the Windows/Linux title bar and
// menu bar as well as the routed screen. Opening a file, though, is the
// viewer's job: format dispatch, the FSDB conversion offer, recent files and
// the new-tab rule all live on `ViewerScreen`. This router is the seam between
// the two. The viewer attaches a handler while it is mounted; the window-level
// target asks it whether a drop may land right now and delivers the paths.
//
// Pure Dart: no Flutter, no plugin. That is what lets the routing be tested by
// calling [DesktopFileDropRouter.deliver] directly, with no platform channel.

import 'package:path/path.dart' as p;

/// What the viewer supplies to receive window drops.
class DesktopFileDropHandler {
  /// Creates a handler.
  const DesktopFileDropHandler({required this.canAccept, required this.onDrop});

  /// Whether a drop may land now. False while a dialog, a modal gate (the
  /// licence agreement, the telemetry disclosure) or a native file dialog is
  /// in front of the viewer — a file must not open behind something the user
  /// has not answered.
  final bool Function() canAccept;

  /// Opens the dropped [paths], already in [DesktopFileDropRouter.openOrder].
  final Future<void> Function(List<String> paths) onDrop;
}

/// Routes window drops to the attached [DesktopFileDropHandler].
class DesktopFileDropRouter {
  DesktopFileDropHandler? _handler;

  /// Makes [handler] the drop destination, replacing any earlier one, and
  /// returns the call that detaches it again (see [detach]).
  void Function() attach(DesktopFileDropHandler handler) {
    _handler = handler;
    return () => detach(handler);
  }

  /// Removes [handler] if it is still the destination. A handler that was
  /// already replaced is left alone, so a screen disposed after its successor
  /// mounted cannot detach the successor.
  void detach(DesktopFileDropHandler handler) {
    if (identical(_handler, handler)) _handler = null;
  }

  /// Whether a drop would be accepted now. Asked when a drag enters the
  /// window, so the drop affordance only appears when the drop will land.
  bool get canAccept => _handler?.canAccept() ?? false;

  /// Delivers [paths] to the handler. Returns false, doing nothing, when there
  /// is no handler, nothing to open, or the handler cannot accept a drop now.
  Future<bool> deliver(List<String> paths) async {
    final handler = _handler;
    if (handler == null || paths.isEmpty || !handler.canAccept()) return false;
    await handler.onDrop(openOrder(paths));
    return true;
  }

  /// The order dropped files open in: everything else in drop order, then
  /// GTKWave `.gtkw` sessions.
  ///
  /// A `.gtkw` is imported into the active tab. Dragging a dump and its
  /// `.gtkw` from the same folder in one gesture should therefore land the
  /// session on that dump, whichever the file manager happened to list first.
  static List<String> openOrder(List<String> paths) => [
    ...paths.where((path) => !isGtkwPath(path)),
    ...paths.where(isGtkwPath),
  ];

  /// Whether [path] names a GTKWave save file.
  static bool isGtkwPath(String path) =>
      p.extension(path).toLowerCase() == '.gtkw';
}
