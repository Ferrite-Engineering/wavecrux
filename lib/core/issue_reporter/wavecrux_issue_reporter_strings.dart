// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Adapter that satisfies the cross-suite [CruxIssueReporterStrings] interface
/// from `package:crux_issue_reporter` using WaveCrux's ARB-generated [L10N]
/// strings.
///
/// Scope: these are the strings the *user* sees — the dialog chrome, the
/// category tiles, the buttons and the toasts. The markdown field labels inside
/// the generated GitHub issue body (`**App version:**`, `**Active decoders:**`,
/// …) stay English by design: that body is read by maintainers in the
/// repository, and a mixed-language report makes triage harder. See the
/// package's `CruxIssueReporterStrings` doc.
class WavecruxIssueReporterStrings extends CruxIssueReporterStrings {
  /// Wraps the supplied [L10N] so the shared reporter dialog renders in the
  /// active locale.
  const WavecruxIssueReporterStrings(this._l10n);

  final L10N _l10n;

  @override
  String get dialogTitle => _l10n.issueReporterTitle;

  @override
  String get titleFieldLabel => _l10n.issueReporterTitleFieldLabel;

  @override
  String get titleFieldHint => _l10n.issueReporterTitleFieldHint;

  @override
  String get privacyNotice => _l10n.issueReporterPrivacyNotice;

  @override
  String get previewHeader => _l10n.issueReporterPreviewHeader;

  @override
  String get categoryAppEnv => _l10n.issueReporterCategoryAppEnv;

  @override
  String get categoryAppEnvDescription =>
      _l10n.issueReporterCategoryAppEnvDescription;

  @override
  String get categorySession => _l10n.issueReporterCategorySession;

  @override
  String get categorySessionDescription =>
      _l10n.issueReporterCategorySessionDescription;

  @override
  String get categoryLog => _l10n.issueReporterCategoryLog;

  @override
  String get categoryLogDescription =>
      _l10n.issueReporterCategoryLogDescription;

  @override
  String get categoryScreenshot => _l10n.issueReporterCategoryScreenshot;

  @override
  String get categoryScreenshotDescription =>
      _l10n.issueReporterCategoryScreenshotDescription;

  @override
  String get lockedCategorySemantics =>
      _l10n.issueReporterLockedCategorySemantics;

  @override
  String get submitButton => _l10n.issueReporterSubmitButton;

  @override
  String get cancelButton => _l10n.issueReporterCancelButton;

  @override
  String get openedToast => _l10n.issueReporterOpenedToast;

  @override
  String get openedToastPrefilled => _l10n.issueReporterOpenedToastPrefilled;

  @override
  String screenshotSaved(String path) =>
      _l10n.issueReporterScreenshotSaved(path);

  @override
  String get emptyLogPlaceholder => _l10n.issueReporterEmptyLogPlaceholder;

  @override
  String get emptySessionLogPlaceholder =>
      _l10n.issueReporterEmptySessionLogPlaceholder;
}
