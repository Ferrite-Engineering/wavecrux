// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Drag-and-drop zone shown on the empty-canvas state when running on Flutter
// Web.
//
// Uses [WebDropTarget] (dart:html conditional import) to listen for file-drop
// events at the document level. On non-web platforms [kIsWeb] is false, so
// this widget renders nothing and the [WebDropTarget] stub never emits.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wavecrux/core/theme/wavecrux_colors.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/platform/web_drop_target.dart';

/// A dashed-border drop zone displayed below the "Open File" button on web.
///
/// Attaches a [WebDropTarget] to the document on mount and tears it down on
/// dispose. When a file is dropped, [onFilesDropped] is called with the raw
/// bytes and the file's basename.
///
/// Renders as [SizedBox.shrink] on non-web platforms.
class WebDropZone extends StatefulWidget {
  const WebDropZone({required this.onFilesDropped, super.key});

  /// Called when the user drops a file onto the browser window.
  final void Function(Uint8List bytes, String name) onFilesDropped;

  @override
  State<WebDropZone> createState() => _WebDropZoneState();
}

class _WebDropZoneState extends State<WebDropZone> {
  final _target = WebDropTarget();
  StreamSubscription<WebDropFile>? _sub;
  bool _isDragOver = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _target.enable();
      _sub = _target.files.listen(_onDrop);
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _target.dispose();
    super.dispose();
  }

  void _onDrop(WebDropFile file) {
    if (!mounted) return;
    setState(() => _isDragOver = false);
    widget.onFilesDropped(file.bytes, file.name);
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return const SizedBox.shrink();

    final l10n = L10N.of(context);
    final label = _isDragOver
        ? l10n.webDropZoneActiveLabel
        : l10n.webDropZoneLabel;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        border: Border.all(
          color: _isDragOver
              ? WavecruxColors.signalGreen
              : Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
          width: _isDragOver ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
        color: _isDragOver
            ? WavecruxColors.signalGreen.withValues(alpha: 0.06)
            : Colors.transparent,
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isDragOver = true),
        onExit: (_) => setState(() => _isDragOver = false),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.upload_file_outlined,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
