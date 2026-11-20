// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// The product name stamped in an export's educational-licence mark.
///
/// A brand name, so it is the same in every locale and is not an ARB string.
const String kWaveCruxEduMarkProductName = 'WaveCrux';

/// Adapter satisfying `crux_license`'s [CruxEduNoticeStrings] from WaveCrux's
/// ARB-generated [L10N]: the status-bar EDU chip's label and tooltip.
///
/// The export mark is not localized: exported files travel, so every export
/// carries the same English line whatever the exporting machine's locale (see
/// [waveCruxEduExportMark]).
///
/// The tooltip is built from whole sentences (holder, terms, expiry) rather
/// than one message with optional parts, so each locale orders the words
/// inside a sentence its own way.
class WaveCruxEduNoticeStrings extends CruxEduNoticeStrings {
  /// Creates an adapter that reads the notice strings from [_l10n].
  const WaveCruxEduNoticeStrings(this._l10n);

  final L10N _l10n;

  @override
  String get statusLabel => _l10n.eduNoticeStatusLabel;

  @override
  String statusTooltip({String? email, String? validUntil}) {
    final sentences = [
      if (email == null)
        _l10n.eduNoticeTooltipNoHolder
      else
        _l10n.eduNoticeTooltipHolder(email),
      _l10n.eduNoticeTooltipTerms,
      if (validUntil != null) _l10n.eduNoticeTooltipValidUntil(validUntil),
    ];
    final buf = StringBuffer();
    for (final sentence in sentences) {
      // A full-width stop (CJK) closes a sentence without a following space;
      // an ASCII one takes a space before the next sentence.
      if (buf.isNotEmpty && !buf.toString().endsWith('。')) buf.write(' ');
      buf.write(sentence);
    }
    return buf.toString();
  }

  @override
  String exportMark(String productName) =>
      const CruxEduNoticeStringsEn().exportMark(productName);
}

/// The mark to stamp on an image exported under [status], or `null` when the
/// licence is not educational.
///
/// Always English: an exported image travels to readers in any locale, so it
/// says the same thing everywhere.
///
/// For exports a person looks at (PNG, SVG). Never for data a tool reads
/// back: VCD, SAIF, CSV, JSON and session files stay exactly as written.
String? waveCruxEduExportMark(CruxLicenseStatus status) =>
    cruxEduExportMark(status, kWaveCruxEduMarkProductName);
