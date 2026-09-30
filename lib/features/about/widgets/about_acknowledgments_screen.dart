// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wavecrux/core/platform_utils.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Full-screen / modal view listing third-party open-source acknowledgments.
///
/// Call [openAdaptive] — it presents as a dialog on desktop and as a pushed
/// route on mobile.
class AboutAcknowledgmentsScreen extends StatelessWidget {
  const AboutAcknowledgmentsScreen({super.key});

  /// Opens the acknowledgments in a dialog on desktop, or as a route on mobile.
  static Future<void> openAdaptive(BuildContext context) async {
    if (isDesktopPlatform) {
      await showDialog<void>(
        context: context,
        builder: (_) => const _AcknowledgmentsDialog(),
      );
    } else {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => const AboutAcknowledgmentsScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.aboutAcknowledgmentsTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: MaterialLocalizations.of(context).closeButtonLabel,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: const _AcknowledgmentsBody(),
    );
  }
}

class _AcknowledgmentsDialog extends StatelessWidget {
  const _AcknowledgmentsDialog();

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);

    return Dialog(
      child: SizedBox(
        width: 560,
        height: 600,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Text(
                    l10n.aboutAcknowledgmentsTitle,
                    style: theme.textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: MaterialLocalizations.of(context).closeButtonLabel,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            const Expanded(child: _AcknowledgmentsBody()),
          ],
        ),
      ),
    );
  }
}

class _AcknowledgmentsBody extends StatelessWidget {
  const _AcknowledgmentsBody();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      children: const [
        _AcknowledgmentEntry(
          name: 'wellen',
          author: 'Kevin Laeufer',
          license: 'BSD 3-Clause',
          url: 'https://github.com/ekiwi/wellen',
        ),
        _AcknowledgmentEntry(
          name: 'Flutter',
          author: 'Google LLC',
          license: 'BSD 3-Clause',
          url: 'https://flutter.dev',
        ),
        _AcknowledgmentEntry(
          name: 'flutter_riverpod / riverpod',
          author: 'Remi Rousselet',
          license: 'MIT',
          url: 'https://riverpod.dev',
        ),
        _AcknowledgmentEntry(
          name: 'go_router',
          author: 'Flutter team',
          license: 'BSD 3-Clause',
          url: 'https://pub.dev/packages/go_router',
        ),
        _AcknowledgmentEntry(
          name: 'panes',
          author: 'Felix Angelov',
          license: 'MIT',
          url: 'https://pub.dev/packages/panes',
        ),
        _AcknowledgmentEntry(
          name: 'file_picker',
          author: 'Miguel Ruivo',
          license: 'MIT',
          url: 'https://pub.dev/packages/file_picker',
        ),
        _AcknowledgmentEntry(
          name: 'url_launcher',
          author: 'Flutter team',
          license: 'BSD 3-Clause',
          url: 'https://pub.dev/packages/url_launcher',
        ),
        _AcknowledgmentEntry(
          name: 'package_info_plus',
          author: 'Baseflow',
          license: 'MIT',
          url: 'https://pub.dev/packages/package_info_plus',
        ),
        _AcknowledgmentEntry(
          name: 'very_good_analysis',
          author: 'Very Good Ventures',
          license: 'MIT',
          url: 'https://pub.dev/packages/very_good_analysis',
        ),
        _AcknowledgmentEntry(
          name: 'yaml',
          author: 'Dart team',
          license: 'BSD 3-Clause',
          url: 'https://pub.dev/packages/yaml',
        ),
      ],
    );
  }
}

class _AcknowledgmentEntry extends StatelessWidget {
  const _AcknowledgmentEntry({
    required this.name,
    required this.author,
    required this.license,
    required this.url,
  });

  final String name;
  final String author;
  final String license;
  final String url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  author,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  license,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              InkWell(
                onTap: () => launchUrl(Uri.parse(url)),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    url.replaceFirst('https://', ''),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.primary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
