// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/features/workspace/providers/desktop_file_drop_provider.dart';
import 'package:wavecrux/features/workspace/widgets/file_drop_overlay.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

/// Builds the native drop target around [child].
///
/// [onEntered] and [onExited] bracket a drag over [child]; [onDropped]
/// receives the absolute paths of what was dropped. The production builder is
/// [pluginDesktopDropTarget]; widget tests pass a fake so they can drive a
/// drag without the `desktop_drop` platform channel.
typedef DesktopDropTargetBuilder =
    Widget Function({
      required Widget child,
      required VoidCallback onEntered,
      required VoidCallback onExited,
      required ValueChanged<List<String>> onDropped,
    });

/// The production [DesktopDropTargetBuilder], backed by `desktop_drop`.
Widget pluginDesktopDropTarget({
  required Widget child,
  required VoidCallback onEntered,
  required VoidCallback onExited,
  required ValueChanged<List<String>> onDropped,
}) => DropTarget(
  onDragEntered: (_) => onEntered(),
  onDragExited: (_) => onExited(),
  onDragDone: (details) =>
      onDropped([for (final item in details.files) item.path]),
  child: child,
);

/// Makes the whole desktop window a drop target for files.
///
/// Mounted once, in `MaterialApp.builder`, around everything the window
/// draws — the Windows/Linux title bar and menu bar included — so a file
/// released anywhere over the window opens. What a drop *does* is not decided
/// here: the paths go to the [desktopFileDropRouterProvider], and the viewer
/// behind it opens them through the same dispatch as File > Open.
///
/// While a drag is over the window and the viewer can accept it, a
/// [FileDropOverlay] covers the window. When it cannot — a dialog or a modal
/// gate is in front — no overlay appears and a drop does nothing, because
/// opening a file behind an unanswered dialog would be worse.
///
/// Native desktop only. The browser keeps its own drop zone on the welcome
/// screen (`WebDropZone`), and mobile has no window to drop onto, so on both
/// this renders [child] untouched and never builds the plugin's widget.
///
/// Native drags are OS drag sessions, not Flutter gestures, so the in-app
/// drags — tabs, signals, the Stage bindings pane's `DragTarget` — never reach
/// this widget and are unaffected by it.
class DesktopFileDropTarget extends ConsumerStatefulWidget {
  /// Creates the window drop target.
  const DesktopFileDropTarget({
    required this.child,
    this.dropTargetBuilder = pluginDesktopDropTarget,
    super.key,
  });

  /// The window content.
  final Widget child;

  /// Builds the native drop target; see [DesktopDropTargetBuilder].
  final DesktopDropTargetBuilder dropTargetBuilder;

  @override
  ConsumerState<DesktopFileDropTarget> createState() =>
      _DesktopFileDropTargetState();
}

class _DesktopFileDropTargetState extends ConsumerState<DesktopFileDropTarget> {
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    // `desktop_drop` also registers a browser implementation, which listens
    // on the whole page from the moment the app starts and posts every drag
    // to its channel. With no Dart handler those posts fail one by one while
    // a file is dragged over the page. Installing the handler makes them land
    // on a listener list that is empty on the web, where this widget never
    // builds a `DropTarget`.
    if (kIsWeb) DesktopDrop.instance.init();
  }

  void _setDragging(bool value) {
    if (!mounted || _dragging == value) return;
    setState(() => _dragging = value);
  }

  void _onEntered() =>
      _setDragging(ref.read(desktopFileDropRouterProvider).canAccept);

  void _onExited() => _setDragging(false);

  void _onDropped(List<String> paths) {
    _setDragging(false);
    // The router re-checks that the viewer can accept the drop, so a dialog
    // that opened mid-drag still wins.
    unawaited(ref.read(desktopFileDropRouterProvider).deliver(paths));
  }

  @override
  Widget build(BuildContext context) {
    if (!isDesktopHostPlatform) return widget.child;
    return widget.dropTargetBuilder(
      onEntered: _onEntered,
      onExited: _onExited,
      onDropped: _onDropped,
      // One structure in both states, so the app below is never remounted
      // when a drag enters or leaves.
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          Positioned.fill(
            child: _dragging ? const FileDropOverlay() : const SizedBox(),
          ),
        ],
      ),
    );
  }
}
