// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wavecrux/core/help_urls.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// The "Need help getting started? Visit docs.wavecrux.app" hint shown at the
/// bottom of the empty-canvas screen, with the `docs.wavecrux.app` portion
/// rendered as a tappable link that opens [HelpUrls.docs] in the system
/// browser.
///
/// The localized sentence is split around the bare domain literal rather than
/// an ICU placeholder: the domain is identical in every translation of
/// `emptyCanvasDocsHint`, so a substring split keeps the surrounding prose
/// localized while linking only the URL. If a future translation ever drops
/// the literal, the widget falls back to plain (non-linked) text.
class EmptyCanvasDocsHint extends StatefulWidget {
  const EmptyCanvasDocsHint({this.onTap, super.key});

  /// Test seam: when non-null, replaces the real `launchUrl` call so widget
  /// tests don't hit a platform channel.
  @visibleForTesting
  final VoidCallback? onTap;

  @override
  State<EmptyCanvasDocsHint> createState() => _EmptyCanvasDocsHintState();
}

class _EmptyCanvasDocsHintState extends State<EmptyCanvasDocsHint> {
  /// The clickable domain. Locale-independent — it appears verbatim in every
  /// translation of `emptyCanvasDocsHint`.
  static const _linkText = 'docs.wavecrux.app';

  late final TapGestureRecognizer _recognizer;

  @override
  void initState() {
    super.initState();
    _recognizer = TapGestureRecognizer()
      ..onTap =
          widget.onTap ?? () => unawaited(launchUrl(Uri.parse(HelpUrls.docs)));
  }

  @override
  void dispose() {
    _recognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final hint = l10n.emptyCanvasDocsHint;
    final baseStyle = TextStyle(
      fontSize: 12,
      color: colorScheme.onSurfaceVariant,
    );

    final index = hint.indexOf(_linkText);
    if (index < 0) {
      // Defensive fallback: a translation without the literal domain still
      // renders, just without a link, rather than throwing.
      return Text(hint, textAlign: TextAlign.center, style: baseStyle);
    }

    final before = hint.substring(0, index);
    final after = hint.substring(index + _linkText.length);

    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          if (before.isNotEmpty) TextSpan(text: before),
          TextSpan(
            text: _linkText,
            style: TextStyle(
              color: colorScheme.primary,
              decoration: TextDecoration.underline,
              decorationColor: colorScheme.primary,
            ),
            recognizer: _recognizer,
          ),
          if (after.isNotEmpty) TextSpan(text: after),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
