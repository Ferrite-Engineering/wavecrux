// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

/// Opens a note's link in the system browser.
///
/// A mutable top-level seam rather than a direct `launchUrl` call so widget
/// tests can observe an activation without the `url_launcher` platform
/// channel, the same pattern `documentationLaunchUrl` uses. Only
/// [isSafeNoteLink] destinations ever reach it.
Future<bool> Function(Uri uri, {LaunchMode mode}) annotationLaunchUrl =
    launchUrl;

/// The URL a note link points at, or null when the link must not open.
///
/// Only `http` and `https` destinations with a host pass. A note arrives from
/// a file or a collaborator, so `file:`, `javascript:`, `mailto:`, custom
/// schemes and relative paths are all refused: they render as plain text.
Uri? safeNoteLink(String? href) {
  if (href == null) return null;
  final uri = Uri.tryParse(href.trim());
  if (uri == null) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  if (uri.host.isEmpty) return null;
  return uri;
}

/// Whether [href] may be opened from a note.
bool isSafeNoteLink(String? href) => safeNoteLink(href) != null;

/// A note's text drawn as Markdown, for the Annotations panel only.
///
/// Paragraphs, emphasis, inline code, code blocks, lists and links render;
/// raw HTML is ignored and images draw their alt text, so nothing loads
/// remote content. The text is selectable for copy, and a link opens only on
/// an explicit activation (a click, or Enter or Space once keyboard focus is
/// on it), never on render or hover.
///
/// The canvas balloon, arrow and band keep drawing the raw text; this widget
/// is not used there.
class AnnotationMarkdown extends StatefulWidget {
  const AnnotationMarkdown({
    required this.text,
    this.onLinkFailed,
    this.onTap,
    this.onDoubleTap,
    super.key,
  });

  /// The note's stored text, unchanged.
  final String text;

  /// Called when the system declines to open an activated link.
  final VoidCallback? onLinkFailed;

  /// A tap on the text itself (not on a link). Handled inside the selection
  /// area on purpose: the area's own tap recognizer sits deeper than any
  /// ancestor's and would otherwise swallow the tap before the row saw it.
  final VoidCallback? onTap;

  /// A double tap on the text itself, for the same reason as [onTap].
  final VoidCallback? onDoubleTap;

  @override
  State<AnnotationMarkdown> createState() => _AnnotationMarkdownState();
}

class _AnnotationMarkdownState extends State<AnnotationMarkdown> {
  // A click still focuses the text, so Ctrl or Cmd+C copies a selection, but
  // Tab skips it: one extra stop per note would bury the links and the row
  // controls in a long list.
  final FocusNode _focus = FocusNode(
    debugLabel: 'annotation text',
    skipTraversal: true,
  );

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyMedium?.copyWith(fontSize: 12);
    final mono = base?.copyWith(
      fontFamily: 'monospace',
      fontSize: 11,
      backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
    );
    final sheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: base,
      pPadding: EdgeInsets.zero,
      listBullet: base,
      code: mono,
      codeblockPadding: const EdgeInsets.all(6),
      codeblockDecoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(3),
      ),
      blockSpacing: 4,
      blockquote: base,
      h1: base?.copyWith(fontWeight: FontWeight.w700),
      h2: base?.copyWith(fontWeight: FontWeight.w700),
      h3: base?.copyWith(fontWeight: FontWeight.w700),
      h4: base?.copyWith(fontWeight: FontWeight.w700),
      h5: base?.copyWith(fontWeight: FontWeight.w700),
      h6: base?.copyWith(fontWeight: FontWeight.w700),
    );
    // SelectionArea rather than the package's `selectable` mode: it keeps the
    // link widgets selectable as text and gives one selection across blocks.
    return SelectionArea(
      focusNode: _focus,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        child: MarkdownBody(
          data: widget.text,
          styleSheet: sheet,
          softLineBreak: true,
          builders: {'a': _NoteLinkBuilder(onLinkFailed: widget.onLinkFailed)},
          imageBuilder: (uri, title, alt) => Text(alt ?? '', style: base),
        ),
      ),
    );
  }
}

/// Draws an `a` element as plain text when its destination is not allowed,
/// and as a focusable link when it is.
class _NoteLinkBuilder extends MarkdownElementBuilder {
  _NoteLinkBuilder({this.onLinkFailed});

  final VoidCallback? onLinkFailed;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final label = element.textContent;
    if (label.isEmpty) return null;
    final uri = safeNoteLink(element.attributes['href']);
    final style = (parentStyle ?? preferredStyle) ?? const TextStyle();
    if (uri == null) return Text(label, style: style);

    final linkStyle = style.copyWith(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
    );
    return _NoteLink(
      label: label,
      uri: uri,
      style: linkStyle,
      onLinkFailed: onLinkFailed,
    );
  }
}

class _NoteLink extends StatelessWidget {
  const _NoteLink({
    required this.label,
    required this.uri,
    required this.style,
    this.onLinkFailed,
  });

  final String label;
  final Uri uri;
  final TextStyle style;
  final VoidCallback? onLinkFailed;

  Future<void> _open() async {
    var opened = false;
    try {
      opened = await annotationLaunchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } on Object {
      opened = false;
    }
    if (!opened) onLinkFailed?.call();
  }

  @override
  Widget build(BuildContext context) => Tooltip(
    message: uri.toString(),
    child: Semantics(
      link: true,
      child: InkWell(
        onTap: _open,
        child: Text(label, style: style),
      ),
    ),
  );
}
