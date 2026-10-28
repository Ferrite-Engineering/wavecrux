// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/widgets/signal_format_section.dart'
    show displayFormatLabel;
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Basic formats, shown above the "Advanced" heading.
const List<DisplayFormat> kBasicDisplayFormats = [
  DisplayFormat.binary,
  DisplayFormat.hexadecimal,
  DisplayFormat.octal,
  DisplayFormat.unsignedDecimal,
  DisplayFormat.signedDecimal,
  DisplayFormat.ascii,
];

/// Advanced formats, shown below the "Advanced" heading.
const List<DisplayFormat> kAdvancedDisplayFormats = [
  DisplayFormat.ieee754Single,
  DisplayFormat.ieee754Double,
  DisplayFormat.fixedPointQ,
  DisplayFormat.signedMagnitude,
  DisplayFormat.grayCode,
  DisplayFormat.namedEnum,
];

/// The "Display Format", current format and chevron row of a context menu: the entry that
/// opens [showDisplayFormatMenu]. The value column and the signal-name
/// column both offer it, so a user finds the radix wherever they
/// right-click a signal.
Widget displayFormatMenuEntryLabel(
  BuildContext context,
  DisplayFormat current,
) {
  final l10n = L10N.of(context);
  final muted = Theme.of(context).colorScheme.onSurfaceVariant;
  return Row(
    children: [
      Expanded(
        child: Text(
          l10n.valueColumnFormatHeader,
          style: const TextStyle(fontSize: 13),
        ),
      ),
      Text(
        displayFormatLabel(l10n, current),
        style: TextStyle(fontSize: 12, color: muted),
      ),
      const SizedBox(width: 6),
      Icon(Icons.chevron_right, size: 18, color: muted),
    ],
  );
}

/// Opens the display-format picker at [position] for the viewer row
/// [entryId], whose format is [current], and applies the choice to that row.
///
/// A second menu rather than the twelve formats inline: `showMenu` does not
/// scroll on the desktop, so an inline list pushed later entries below the
/// window's bottom edge. This one fits within the 500 dp minimum window
/// height.
Future<void> showDisplayFormatMenu(
  BuildContext context,
  WidgetRef ref, {
  required String entryId,
  required DisplayFormat current,
  required RelativeRect position,
}) async {
  final l10n = L10N.of(context);
  final muted = Theme.of(context).colorScheme.onSurfaceVariant;
  PopupMenuItem<DisplayFormat> item(DisplayFormat fmt) =>
      PopupMenuItem<DisplayFormat>(
        value: fmt,
        height: 32,
        child: Row(
          children: [
            SizedBox(
              width: 18,
              child: fmt == current ? const Icon(Icons.check, size: 14) : null,
            ),
            const SizedBox(width: 4),
            Text(
              displayFormatLabel(l10n, fmt),
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      );
  final items = <PopupMenuEntry<DisplayFormat>>[
    PopupMenuItem<DisplayFormat>(
      enabled: false,
      height: 28,
      child: Text(
        l10n.valueColumnFormatHeader,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: muted,
        ),
      ),
    ),
    ...kBasicDisplayFormats.map(item),
    PopupMenuItem<DisplayFormat>(
      enabled: false,
      height: 24,
      child: Text(
        l10n.settingsAdvancedSection,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: muted,
        ),
      ),
    ),
    ...kAdvancedDisplayFormats.map(item),
  ];

  final selected = await showMenu<DisplayFormat>(
    context: context,
    position: position,
    items: items,
  );
  if (!context.mounted || selected == null) return;
  ref
      .read(signalGroupsProvider.notifier)
      .setSignalFormatById(entryId, selected);
  // Recorded here rather than in the notifier because the notifier's setters
  // are also the bulk path, which would emit one event per selected signal
  // for one keypress. A dismissed menu is an attempt and stays uncounted.
  ref
      .read(telemetryServiceProvider)
      .record(
        TelemetryEvent(
          'format.set',
          properties: <String, Object?>{
            'format': telemetryEnumToken(selected),
          },
        ),
      );
}
