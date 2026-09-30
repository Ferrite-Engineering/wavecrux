// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:wavecrux/core/theme/wavecrux_colors.dart';
import 'package:wavecrux/core/theme/wavecrux_theme.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/waveform_geom/lane_geometry.dart';

/// Renders a blank separator or an editable comment row in the signal list panel.
///
/// When [isComment] is false, shows a thin horizontal divider (10 px tall).
/// When [isComment] is true, shows the comment text with a pencil button that
/// switches to an inline [TextField] for editing. Submitting or losing focus
/// commits the new text via [onCommentChanged].
class SignalSeparator extends StatefulWidget {
  const SignalSeparator({
    required this.isComment,
    this.commentText,
    this.onCommentChanged,
    super.key,
  });

  /// Whether this row is a comment (true) or a blank separator (false).
  final bool isComment;

  /// Current comment text (only meaningful when [isComment] is true).
  final String? commentText;

  /// Called with the new text when the user finishes editing a comment.
  final ValueChanged<String>? onCommentChanged;

  @override
  State<SignalSeparator> createState() => _SignalSeparatorState();
}

class _SignalSeparatorState extends State<SignalSeparator> {
  bool _editing = false;
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.commentText ?? '');
    _focusNode = FocusNode()
      ..addListener(() {
        if (!_focusNode.hasFocus && _editing) {
          _commitEdit();
        }
      });
  }

  @override
  void didUpdateWidget(SignalSeparator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && oldWidget.commentText != widget.commentText) {
      _controller.text = widget.commentText ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startEdit() {
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  void _commitEdit() {
    setState(() => _editing = false);
    widget.onCommentChanged?.call(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isComment) {
      return _Separator();
    }
    return _CommentRow(
      controller: _controller,
      focusNode: _focusNode,
      editing: _editing,
      onStartEdit: _startEdit,
      onSubmit: (_) => _commitEdit(),
    );
  }
}

// ── Separator (blank row) ─────────────────────────────────────────────────────

class _Separator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors =
        Theme.of(context).extension<WavecruxColorExtension>() ??
        const WavecruxColorExtension.dark();
    return SizedBox(
      height: kSeparatorHeight,
      child: Center(
        child: Container(
          height: 1,
          color: colors.timeRulerTick.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}

// ── Comment row ───────────────────────────────────────────────────────────────

class _CommentRow extends StatelessWidget {
  const _CommentRow({
    required this.controller,
    required this.focusNode,
    required this.editing,
    required this.onStartEdit,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool editing;
  final VoidCallback onStartEdit;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final colors =
        Theme.of(context).extension<WavecruxColorExtension>() ??
        const WavecruxColorExtension.dark();

    if (editing) {
      return SizedBox(
        height: kCommentHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            style: TextStyle(
              fontFamily: WavecruxColors.monoFontFamily,
              fontFamilyFallback: WavecruxColors.monoFontFamilyFallback,
              fontSize: 11,
              color: colors.timeRulerMajorTick,
            ),
            decoration: InputDecoration(
              hintText: l10n.signalSeparatorCommentHint,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 2,
              ),
              border: InputBorder.none,
            ),
            onSubmitted: onSubmit,
          ),
        ),
      );
    }

    return SizedBox(
      height: kCommentHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            Tooltip(
              message: l10n.signalSeparatorEditCommentTooltip,
              child: GestureDetector(
                onTap: onStartEdit,
                child: Icon(
                  Icons.edit_note,
                  size: 12,
                  color: colors.timeRulerTick,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                controller.text.isEmpty ? '—' : controller.text,
                style: TextStyle(
                  fontFamily: WavecruxColors.monoFontFamily,
                  fontFamilyFallback: WavecruxColors.monoFontFamilyFallback,
                  fontSize: 11,
                  color: colors.timeRulerTick,
                  fontStyle: FontStyle.italic,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
