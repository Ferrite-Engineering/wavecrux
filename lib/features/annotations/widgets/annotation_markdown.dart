// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_menu_bar/crux_menu_bar.dart';
import 'package:flutter/gestures.dart'
    show computePanSlop, kDoubleTapSlop, kDoubleTapTimeout, kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
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
  ///
  /// Called on the release of a press that did not move, without waiting to
  /// see whether a second tap follows.
  final VoidCallback? onTap;

  /// A second tap on the text close in time and place to the first, for the
  /// same reason as [onTap]. The first tap has already called [onTap].
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

  // Set by a link's own Listener, which runs before the text's (deepest
  // first), so a press on a link is never also a row tap.
  bool _pressOnLink = false;

  @override
  void dispose() {
    CruxEditSelectionRegistry.instance.forget(this);
    _focus.dispose();
    super.dispose();
  }

  // Tells the Edit menu what is selected here, so its Copy reaches the
  // selection even when no key press found its way to the text. The area
  // reports null when its selection clears, as it does on losing focus.
  void _reportSelection(SelectedContent? content) =>
      CruxEditSelectionRegistry.instance.report(this, content?.plainText);

  void _markLinkPress() => _pressOnLink = true;

  bool _takeLinkPress() {
    final onLink = _pressOnLink;
    _pressOnLink = false;
    return onLink;
  }

  // Any press on the text gives it keyboard focus, so Cmd/Ctrl+C reaches the
  // selection whichever gesture made it. The area focuses itself only when
  // its own recognizer wins a single press.
  void _focusOnPress(PointerDownEvent _) {
    if (!_focus.hasFocus) _focus.requestFocus();
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
    //
    // Taps are read from raw pointer events (AnnotationTapListener), not a
    // GestureDetector: a tap or double tap recognizer around the area
    // competes with its selection recognizer. A click was won by the tap, so
    // the text never took focus, and a selection begun with a click (click
    // then drag, a trackpad tap-and-drag) was left on screen with nothing
    // behind it to copy. Cmd/Ctrl+C then went unhandled.
    return SelectionArea(
      focusNode: _focus,
      onSelectionChanged: _reportSelection,
      child: AnnotationTapListener(
        onPointerDown: _focusOnPress,
        ignorePress: _takeLinkPress,
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        child: MarkdownBody(
          data: widget.text,
          styleSheet: sheet,
          softLineBreak: true,
          builders: {
            'a': _NoteLinkBuilder(
              onLinkFailed: widget.onLinkFailed,
              onPress: _markLinkPress,
            ),
          },
          imageBuilder: (uri, title, alt) => Text(alt ?? '', style: base),
        ),
      ),
    );
  }
}

/// Draws an `a` element as plain text when its destination is not allowed,
/// and as a focusable link when it is.
class _NoteLinkBuilder extends MarkdownElementBuilder {
  _NoteLinkBuilder({required this.onPress, this.onLinkFailed});

  final VoidCallback? onLinkFailed;

  /// Tells the text a press landed on a link, so it is not also a row tap.
  final VoidCallback onPress;

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
    return Listener(
      onPointerDown: (_) => onPress(),
      child: _NoteLink(
        label: label,
        uri: uri,
        style: linkStyle,
        onLinkFailed: onLinkFailed,
      ),
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

/// Reports taps and double taps from raw pointer events.
///
/// Unlike a GestureDetector it joins no gesture arena, so it never competes
/// with a [SelectionArea] for a press. A tap or double tap recognizer above or
/// inside a selection area takes single clicks from it (the area is then
/// never focused) and breaks a selection begun with a click: the highlight
/// stays on screen, the area has nothing to copy, and Cmd/Ctrl+C goes
/// unhandled.
///
/// Nested listeners do not both count one press: the deepest one that sees
/// it claims it, so a row can carry one around its whole body while the text
/// inside carries its own.
///
/// A tap is a primary-button press released within the pan slop of where it
/// went down. [onTap] is called on its release, without waiting to see whether
/// a second tap follows; a second tap within the double tap timeout and slop
/// calls [onDoubleTap] instead.
class AnnotationTapListener extends StatefulWidget {
  /// Creates the listener.
  const AnnotationTapListener({
    required this.child,
    this.onTap,
    this.onDoubleTap,
    this.onPointerDown,
    this.ignorePress,
    super.key,
  });

  /// The widget the taps land on.
  final Widget child;

  /// A single tap.
  final VoidCallback? onTap;

  /// The second of two taps close in time and place.
  final VoidCallback? onDoubleTap;

  /// Every pointer press on [child], tap or not.
  final ValueChanged<PointerDownEvent>? onPointerDown;

  /// Asked on each press; true means the press is not a tap (it belongs to a
  /// control inside [child] that handles it).
  final bool Function()? ignorePress;

  @override
  State<AnnotationTapListener> createState() => _AnnotationTapListenerState();
}

class _AnnotationTapListenerState extends State<AnnotationTapListener> {
  // Pointers already claimed by a deeper listener. Listeners on one hit path
  // receive a press deepest first.
  static final Set<int> _claimed = <int>{};

  int? _pointer;
  int? _claimedHere;
  Offset _downAt = Offset.zero;
  // A timer, as the framework's recognizers use, rather than event time
  // stamps.
  Timer? _doubleTapWindow;
  Offset _lastTapAt = Offset.zero;

  @override
  void dispose() {
    _release();
    _doubleTapWindow?.cancel();
    super.dispose();
  }

  void _release() {
    final pointer = _claimedHere;
    if (pointer != null) _claimed.remove(pointer);
    _claimedHere = null;
  }

  void _down(PointerDownEvent event) {
    widget.onPointerDown?.call(event);
    final ignored = widget.ignorePress?.call() ?? false;
    _pointer = null;
    if (!_claimed.add(event.pointer)) return;
    _release();
    _claimedHere = event.pointer;
    if (ignored || event.buttons != kPrimaryButton) return;
    _pointer = event.pointer;
    _downAt = event.position;
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    // Past the slop it is a drag, which selects text and is not a tap.
    if ((event.position - _downAt).distance >
        computePanSlop(event.kind, null)) {
      _pointer = null;
    }
  }

  void _up(PointerUpEvent event) {
    if (event.pointer == _claimedHere) _release();
    if (event.pointer != _pointer) return;
    _pointer = null;
    final isDouble =
        (_doubleTapWindow?.isActive ?? false) &&
        (event.position - _lastTapAt).distance <= kDoubleTapSlop;
    _doubleTapWindow?.cancel();
    if (isDouble) {
      _doubleTapWindow = null;
      widget.onDoubleTap?.call();
    } else {
      _doubleTapWindow = Timer(kDoubleTapTimeout, () {});
      _lastTapAt = event.position;
      widget.onTap?.call();
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _down,
    onPointerMove: _move,
    onPointerUp: _up,
    onPointerCancel: (event) {
      if (event.pointer == _claimedHere) _release();
      _pointer = null;
    },
    child: widget.child,
  );
}
