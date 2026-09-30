// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The open-core half of the beta issue reporter's privacy assertion.
//
// `wavecrux_pro`'s `pro_issue_data_provider_test.dart` says in its header that
// "the open-core suite owns the Session State privacy assertion". This file is
// what makes that true: the contract the doc comment on
// `buildWavecruxIssueSessionContext` describes had no test at either tier.

import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/issue_reporter/providers/wavecrux_issue_session_context.dart';

/// Renders the context the way the reporter dialog does — one markdown bullet
/// per field — so the privacy assertion runs over the text a user would paste.
String _renderBody(CruxIssueSessionContext context) =>
    context.fields.map((f) => '- **${f.label}:** ${f.value}').join('\n');

void main() {
  late CruxIssueSessionContext context;

  setUp(() {
    final container = ProviderContainer(
      overrides: <Override>[wavecruxIssueSessionContextOverride],
    );
    addTearDown(container.dispose);
    context = container.read(cruxIssueSessionContextProvider);
  });

  test('opens on a bare container rather than throwing', () {
    // The reporter exists to report a broken state; it must survive one.
    expect(context.fields, isNotEmpty);
  });

  test('renders the four Session State fields in order', () {
    // These labels are read by a human comparing four products' bug reports
    // side by side, and the Pro overlay's fixture repeats the first of them.
    // Byte-identical is the contract.
    expect(
      context.fields.map((f) => f.label).toList(),
      <String>[
        'Open tabs',
        'Active file format',
        'Signals in active tab',
        'Active decoders',
      ],
    );
  });

  test('substitutes the shared fallback vocabulary when nothing is loaded', () {
    final byLabel = <String, String>{
      for (final f in context.fields) f.label: f.value,
    };
    expect(byLabel['Open tabs'], '0');
    expect(byLabel['Active file format'], CruxIssueFallback.noneLoaded);
    expect(byLabel['Signals in active tab'], '0');
    expect(byLabel['Active decoders'], CruxIssueFallback.none);
  });

  test('publishes every attribute key the Pro overlay reads', () {
    // `wavecrux_pro/lib/services/issue_reporter/pro_issue_data_provider.dart`
    // reads these by name. Renaming one here silently empties the Pro State
    // category rather than failing a build.
    expect(
      context.attributes.keys.toSet(),
      <String>{
        kWavecruxIssueAttrOpenTabs,
        kWavecruxIssueAttrActiveFileFormat,
        kWavecruxIssueAttrActiveSignalCount,
        kWavecruxIssueAttrActiveDecoderIds,
        kWavecruxIssueAttrProDecoderIds,
        kWavecruxIssueAttrStagePanelCount,
        kWavecruxIssueAttrStageWidgetTypes,
      },
    );
  });

  test('attributes carry machine-readable values, not rendered strings', () {
    expect(context.attributes[kWavecruxIssueAttrOpenTabs], isA<int>());
    expect(context.attributes[kWavecruxIssueAttrActiveSignalCount], isA<int>());
    expect(context.attributes[kWavecruxIssueAttrStagePanelCount], isA<int>());
    expect(
      context.attributes[kWavecruxIssueAttrActiveDecoderIds],
      isA<List<String>>(),
    );
    expect(
      context.attributes[kWavecruxIssueAttrProDecoderIds],
      isA<List<String>>(),
    );
    expect(
      context.attributes[kWavecruxIssueAttrStageWidgetTypes],
      isA<List<String>>(),
    );
    // A file format that was never determined stays null rather than being
    // coerced to the placeholder — the placeholder is a display concern.
    expect(context.attributes[kWavecruxIssueAttrActiveFileFormat], isNull);
  });

  test('the rendered body contains no path separator', () {
    // THE privacy assertion. Every value is a count, a format name or a
    // decoder display name; nothing is derived from the user's filesystem or
    // from the values inside their waveform.
    final body = _renderBody(context);
    expect(body, isNot(contains('/')));
    expect(body, isNot(contains(r'\')));
  });
}
