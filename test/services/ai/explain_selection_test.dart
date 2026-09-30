// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/interfaces/ai_model_client.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/ai/explain_selection.dart';

import '../../support/fake_waveform_source.dart';

Map<String, Variable> _variablesByRef(FakeWaveformSource source) => {
  for (final s in source.rootScopes)
    for (final v in s.variables) v.signalRef: v,
};

void main() {
  group('buildExplainSelectionRequest', () {
    test('is a single non-agentic call: system + user, no tools', () {
      final req = buildExplainSelectionRequest(const {'signalCount': 1});
      expect(req.tools, isEmpty);
      expect(req.messages.first.role, AiRole.system);
      expect(req.messages.last.role, AiRole.user);
      // The structured context is embedded verbatim for grounding.
      expect(
        req.messages.last.content,
        contains(jsonEncode(const {'signalCount': 1})),
      );
    });
  });

  group('parseExplanation', () {
    test('splits plain text and citation tokens in order', () {
      final segments = parseExplanation(
        'Reset deasserts [[cite:signal=top.clk,time=10]] then data changes '
        '[[cite:time=15]].',
      );
      expect(segments, hasLength(5));
      expect(segments[0], isA<ExplainText>());
      expect(
        (segments[1] as ExplainCitation).signal,
        'top.clk',
      );
      expect((segments[1] as ExplainCitation).time, 10);
      expect((segments[3] as ExplainCitation).time, 15);
      expect((segments[3] as ExplainCitation).signal, isNull);
    });

    test('text with no citations is one text segment', () {
      final segments = parseExplanation('Just prose.');
      expect(segments, [const ExplainText('Just prose.')]);
    });

    test('a malformed citation still parses (resolver rejects it later)', () {
      final segments = parseExplanation('x [[cite:nonsense]] y');
      final citation = segments[1] as ExplainCitation;
      expect(citation.signal, isNull);
      expect(citation.time, isNull);
    });
  });

  group('resolveExplainCitation (grounding)', () {
    late FakeWaveformSource source;
    late Map<String, Variable> byRef;

    setUp(() {
      source = FakeWaveformSource.reference();
      byRef = _variablesByRef(source);
    });

    test('a real (signal, time) resolves to the concrete coordinate', () {
      final r = resolveExplainCitation(
        const ExplainCitation(raw: '', signal: 'top.clk', time: 10),
        source: source,
        variablesByRef: byRef,
      );
      expect(r.resolved, isTrue);
      expect(r.signalRef, 's_clk');
      expect(r.signalPath, 'top.clk');
      expect(r.time, 10);
    });

    test('a signal can be cited by signalRef as well as by path', () {
      final r = resolveExplainCitation(
        const ExplainCitation(raw: '', signal: 's_state', time: 5),
        source: source,
        variablesByRef: byRef,
      );
      expect(r.resolved, isTrue);
      expect(r.signalPath, 'top.state');
    });

    test('a bare in-range time resolves (transaction/moment citation)', () {
      final r = resolveExplainCitation(
        const ExplainCitation(raw: '', time: 25),
        source: source,
        variablesByRef: byRef,
      );
      expect(r.resolved, isTrue);
      expect(r.time, 25);
      expect(r.signalRef, isNull);
    });

    test('an unknown signal does NOT resolve (could not locate)', () {
      final r = resolveExplainCitation(
        const ExplainCitation(raw: '', signal: 'top.ghost', time: 10),
        source: source,
        variablesByRef: byRef,
      );
      expect(r.resolved, isFalse);
      expect(r.time, isNull);
    });

    test('an out-of-range time does NOT resolve (no silent wrong jump)', () {
      final r = resolveExplainCitation(
        const ExplainCitation(raw: '', signal: 'top.clk', time: 9999),
        source: source,
        variablesByRef: byRef,
      );
      expect(r.resolved, isFalse);
    });

    test('an empty citation does not resolve', () {
      final r = resolveExplainCitation(
        const ExplainCitation(raw: ''),
        source: source,
        variablesByRef: byRef,
      );
      expect(r.resolved, isFalse);
    });

    test('no source loaded → nothing resolves', () {
      final r = resolveExplainCitation(
        const ExplainCitation(raw: '', signal: 'top.clk', time: 10),
        source: null,
        variablesByRef: byRef,
      );
      expect(r.resolved, isFalse);
    });
  });
}
