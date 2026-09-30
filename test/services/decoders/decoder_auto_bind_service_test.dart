// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/auto_bind_candidate.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/decoders/apb_decoder.dart';
import 'package:wavecrux/services/decoders/axi4lite_decoder.dart';
import 'package:wavecrux/services/decoders/decoder_auto_bind_service.dart';
import 'package:wavecrux/services/decoders/spi_decoder.dart';

// ── test helpers ──────────────────────────────────────────────────────────────

/// Builds a [Variable] with the given full path and bit-width. The signal
/// reference is the full path so tests can assert on it directly.
Variable makeVar(
  String fullPath, {
  int? bitWidth = 1,
  VarType type = VarType.wire,
}) {
  final lastDot = fullPath.lastIndexOf('.');
  final name = lastDot < 0 ? fullPath : fullPath.substring(lastDot + 1);
  final scope = lastDot < 0 ? '' : fullPath.substring(0, lastDot);
  return Variable(
    name: name,
    varType: type,
    direction: VarDirection.unknown,
    signalRef: fullPath,
    scopePath: scope,
    bitWidth: bitWidth,
  );
}

/// Builds the available-signals map keyed by full path.
Map<String, Variable> availableFromPaths(List<Variable> variables) => {
  for (final v in variables) v.signalRef: v,
};

/// Convenience accessor: looks up the candidate for [name] and asserts
/// it exists, returning it.
AutoBindCandidate findCandidate(
  Map<String, AutoBindCandidate> candidates,
  String name,
) {
  final c = candidates[name];
  expect(c, isNotNull, reason: 'expected candidate for $name');
  return c!;
}

/// Builds the standard 17-signal AXI4-Lite required-binding fixture under a
/// given prefix and scope.
List<Variable> makeAxi4LiteSignals({
  required String prefix,
  required String scope,
  int addrWidth = 32,
  int dataWidth = 32,
}) {
  String path(String leaf) => '$scope.$prefix$leaf';
  return [
    makeVar(path('aclk')),
    makeVar(path('aresetn')),
    makeVar(path('awaddr'), bitWidth: addrWidth),
    makeVar(path('awvalid')),
    makeVar(path('awready')),
    makeVar(path('wdata'), bitWidth: dataWidth),
    makeVar(path('wvalid')),
    makeVar(path('wready')),
    makeVar(path('bresp'), bitWidth: 2),
    makeVar(path('bvalid')),
    makeVar(path('bready')),
    makeVar(path('araddr'), bitWidth: addrWidth),
    makeVar(path('arvalid')),
    makeVar(path('arready')),
    makeVar(path('rdata'), bitWidth: dataWidth),
    makeVar(path('rresp'), bitWidth: 2),
    makeVar(path('rvalid')),
    makeVar(path('rready')),
  ];
}

void main() {
  const service = DecoderAutoBindService();
  const axi = Axi4LiteDecoder.decoderDefinition;
  const spi = SpiDecoder.decoderDefinition;
  const apb = ApbDecoder.decoderDefinition;

  // ──────────────────────────────────────────────────────────────────────────
  // Bus coherence — Tier D fuzzy must not cross scope from the Tier A winner
  // ──────────────────────────────────────────────────────────────────────────

  group('Bus coherence guard', () {
    test('Tier D fuzzy does not reach into a different scope than Tier A', () {
      // tb.dut holds the whole m_axi_ bus EXCEPT rready; a 1-edit fuzzy match
      // for rready ("rredy") exists only in a DIFFERENT scope (tb.mon). Tier A
      // locks tb.dut, so the fuzzy match must be suppressed (binding two scopes
      // is never a coherent bus — this is the captured-trace failure where a
      // master interface and the DUT internals expose the same signal names).
      final dutSignals = makeAxi4LiteSignals(
        prefix: 'm_axi_',
        scope: 'tb.dut',
      ).where((v) => v.name.toLowerCase() != 'm_axi_rready').toList();
      final available = availableFromPaths([
        ...dutSignals,
        makeVar('tb.mon.rredy'),
      ]);

      final result = service.computeBindings(
        definition: axi,
        availableSignals: available,
        currentParameters: const {'addr_width': 32, 'data_width': 32},
      );

      // Tier A locked onto tb.dut.
      expect(result.detectedScopePath, 'tb.dut');
      // rready stays unbound — the cross-scope fuzzy candidate is rejected.
      expect(
        findCandidate(result.candidates, 'rready').confidence,
        AutoBindConfidence.noMatch,
      );
      // In-scope bindings are unaffected.
      expect(
        findCandidate(result.candidates, 'awaddr').signalRef,
        'tb.dut.m_axi_awaddr',
      );
    });

    test('fuzzy still resolves within the Tier A winning scope', () {
      // Same bus, but the fuzzy candidate "rredy" is in the SAME scope as the
      // winner — it must still bind (the guard only blocks CROSS-scope fuzzy).
      final dutSignals = makeAxi4LiteSignals(
        prefix: 'm_axi_',
        scope: 'tb.dut',
      ).where((v) => v.name.toLowerCase() != 'm_axi_rready').toList();
      final available = availableFromPaths([
        ...dutSignals,
        makeVar('tb.dut.rredy'),
      ]);

      final result = service.computeBindings(
        definition: axi,
        availableSignals: available,
        currentParameters: const {'addr_width': 32, 'data_width': 32},
      );

      final rready = findCandidate(result.candidates, 'rready');
      expect(rready.confidence, AutoBindConfidence.fuzzyMatch);
      expect(rready.signalRef, 'tb.dut.rredy');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Tier A — full prefix propagation
  // ──────────────────────────────────────────────────────────────────────────

  group('AXI4-Lite full prefix propagation', () {
    test('m_axi_ prefix in tb.dut binds every required signal exactly', () {
      final available = availableFromPaths(
        makeAxi4LiteSignals(prefix: 'm_axi_', scope: 'tb.dut'),
      );

      final result = service.computeBindings(
        definition: axi,
        availableSignals: available,
        currentParameters: const {'addr_width': 32, 'data_width': 32},
      );

      // Every required binding got a candidate.
      for (final binding in axi.requiredSignals) {
        final c = findCandidate(result.candidates, binding.name);
        expect(
          c.confidence,
          AutoBindConfidence.exactSuffix,
          reason:
              'binding ${binding.name} should be exactSuffix, got '
              '${c.confidence} (${c.matchReason})',
        );
        expect(c.signalRef, 'tb.dut.m_axi_${binding.name}');
      }

      expect(result.detectedPrefix, 'm_axi_');
      expect(result.detectedScopePath, 'tb.dut');
      expect(result.hasAmbiguity, isFalse);
      expect(result.exactMatchCount, axi.requiredSignals.length);
    });

    test(
      'mixed-case M_AXI_ prefix resolves identically (case-insensitive)',
      () {
        final available = availableFromPaths([
          makeVar('tb.dut.M_AXI_ACLK'),
          makeVar('tb.dut.M_AXI_ARESETN'),
          makeVar('tb.dut.M_AXI_AWADDR', bitWidth: 32),
          makeVar('tb.dut.M_AXI_AWVALID'),
          makeVar('tb.dut.M_AXI_AWREADY'),
          makeVar('tb.dut.M_AXI_WDATA', bitWidth: 32),
          makeVar('tb.dut.M_AXI_WVALID'),
          makeVar('tb.dut.M_AXI_WREADY'),
          makeVar('tb.dut.M_AXI_BRESP', bitWidth: 2),
          makeVar('tb.dut.M_AXI_BVALID'),
          makeVar('tb.dut.M_AXI_BREADY'),
          makeVar('tb.dut.M_AXI_ARADDR', bitWidth: 32),
          makeVar('tb.dut.M_AXI_ARVALID'),
          makeVar('tb.dut.M_AXI_ARREADY'),
          makeVar('tb.dut.M_AXI_RDATA', bitWidth: 32),
          makeVar('tb.dut.M_AXI_RRESP', bitWidth: 2),
          makeVar('tb.dut.M_AXI_RVALID'),
          makeVar('tb.dut.M_AXI_RREADY'),
        ]);

        final result = service.computeBindings(
          definition: axi,
          availableSignals: available,
          currentParameters: const {'addr_width': 32, 'data_width': 32},
        );

        for (final binding in axi.requiredSignals) {
          final c = findCandidate(result.candidates, binding.name);
          expect(c.confidence, AutoBindConfidence.exactSuffix);
        }
        // Display prefix preserves the first-seen casing.
        expect(result.detectedPrefix?.toLowerCase(), 'm_axi_');
        expect(result.detectedScopePath, 'tb.dut');
      },
    );

    test('Vivado-style S00_AXI_ prefix resolves all bindings', () {
      final available = availableFromPaths(
        makeAxi4LiteSignals(prefix: 'S00_AXI_', scope: 'tb.dut.slave'),
      );

      final result = service.computeBindings(
        definition: axi,
        availableSignals: available,
        currentParameters: const {'addr_width': 32, 'data_width': 32},
      );

      for (final binding in axi.requiredSignals) {
        final c = findCandidate(result.candidates, binding.name);
        expect(c.confidence, AutoBindConfidence.exactSuffix);
        expect(c.signalRef, 'tb.dut.slave.S00_AXI_${binding.name}');
      }
      expect(result.detectedPrefix, 'S00_AXI_');
      expect(result.detectedScopePath, 'tb.dut.slave');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Bit-width filtering with addr_width parameter
  // ──────────────────────────────────────────────────────────────────────────

  group('Bit-width filtering with addr_width parameter', () {
    test('addr_width=64 picks the 64-bit awaddr over the 32-bit one', () {
      final base = makeAxi4LiteSignals(
        prefix: 'm_axi_',
        scope: 'tb.dut',
        addrWidth: 64,
        dataWidth: 64,
      );
      // Add a bogus 32-bit awaddr in a *different* scope/prefix so it has a
      // chance to be Tier-A picked if we don't filter on width.
      final extras = [
        makeVar('tb.alt.m_axi_awaddr', bitWidth: 32),
        makeVar('tb.alt.m_axi_araddr', bitWidth: 32),
      ];
      final available = availableFromPaths([...base, ...extras]);

      final result = service.computeBindings(
        definition: axi,
        availableSignals: available,
        currentParameters: const {'addr_width': 64, 'data_width': 64},
      );

      final aw = findCandidate(result.candidates, 'awaddr');
      expect(aw.signalRef, 'tb.dut.m_axi_awaddr');
      expect(aw.confidence, AutoBindConfidence.exactSuffix);

      final ar = findCandidate(result.candidates, 'araddr');
      expect(ar.signalRef, 'tb.dut.m_axi_araddr');
    });

    test('data_width=64 with only 32-bit wdata returns noMatch for wdata', () {
      // Provide complete 64-bit fixture, then *remove* wdata, then add a
      // 32-bit wdata. Other bindings should still resolve via Tier A; wdata
      // should fall to noMatch because no width-compatible signal exists.
      final base = makeAxi4LiteSignals(
        prefix: 'm_axi_',
        scope: 'tb.dut',
        dataWidth: 64,
      ).where((v) => v.name != 'm_axi_wdata').toList();
      final extras = [
        makeVar('tb.dut.m_axi_wdata', bitWidth: 32),
      ];
      final available = availableFromPaths([...base, ...extras]);

      final result = service.computeBindings(
        definition: axi,
        availableSignals: available,
        currentParameters: const {'addr_width': 32, 'data_width': 64},
      );

      final wdata = findCandidate(result.candidates, 'wdata');
      expect(wdata.confidence, AutoBindConfidence.noMatch);
      expect(wdata.signalRef, isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Manual bindings act as anchors and are preserved
  // ──────────────────────────────────────────────────────────────────────────

  group('Manual bindings act as anchors and are preserved', () {
    test('preserves manual aclk binding without rerunning Tier A on it', () {
      // Design uses an unconventional name for the clock. The user manually
      // binds aclk to that, and the rest of the bus uses 'foo_' as its prefix.
      final available = availableFromPaths([
        makeVar('tb.dut.foo_clk'),
        makeVar('tb.dut.foo_aresetn'),
        makeVar('tb.dut.foo_awaddr', bitWidth: 32),
        makeVar('tb.dut.foo_awvalid'),
        makeVar('tb.dut.foo_awready'),
        makeVar('tb.dut.foo_wdata', bitWidth: 32),
        makeVar('tb.dut.foo_wvalid'),
        makeVar('tb.dut.foo_wready'),
        makeVar('tb.dut.foo_bresp', bitWidth: 2),
        makeVar('tb.dut.foo_bvalid'),
        makeVar('tb.dut.foo_bready'),
        makeVar('tb.dut.foo_araddr', bitWidth: 32),
        makeVar('tb.dut.foo_arvalid'),
        makeVar('tb.dut.foo_arready'),
        makeVar('tb.dut.foo_rdata', bitWidth: 32),
        makeVar('tb.dut.foo_rresp', bitWidth: 2),
        makeVar('tb.dut.foo_rvalid'),
        makeVar('tb.dut.foo_rready'),
      ]);

      final result = service.computeBindings(
        definition: axi,
        availableSignals: available,
        currentParameters: const {'addr_width': 32, 'data_width': 32},
        existingBindings: const {'aclk': 'tb.dut.foo_clk'},
      );

      // Manual binding preserved verbatim.
      final aclk = findCandidate(result.candidates, 'aclk');
      expect(aclk.signalRef, 'tb.dut.foo_clk');
      expect(aclk.confidence, AutoBindConfidence.exactSuffix);
      expect(aclk.matchReason, 'manually bound');

      // Other bindings resolved via Tier A using foo_ as prefix.
      final awvalid = findCandidate(result.candidates, 'awvalid');
      expect(awvalid.signalRef, 'tb.dut.foo_awvalid');
      expect(awvalid.confidence, AutoBindConfidence.exactSuffix);
      expect(result.detectedPrefix, 'foo_');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Ambiguous prefixes
  // ──────────────────────────────────────────────────────────────────────────

  group('Ambiguous prefixes', () {
    test('two AXI buses in the same scope → result.hasAmbiguity is true', () {
      final master = makeAxi4LiteSignals(prefix: 'm_axi_', scope: 'tb.dut');
      final slave = makeAxi4LiteSignals(prefix: 's_axi_', scope: 'tb.dut');
      final available = availableFromPaths([...master, ...slave]);

      final result = service.computeBindings(
        definition: axi,
        availableSignals: available,
        currentParameters: const {'addr_width': 32, 'data_width': 32},
      );

      expect(result.hasAmbiguity, isTrue);
      expect(
        result.ambiguousPrefixes.toSet(),
        containsAll(<String>['m_axi_', 's_axi_']),
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Known aliases (Tier C)
  // ──────────────────────────────────────────────────────────────────────────

  group('Known aliases', () {
    test('SPI design with sdo/sdi resolves mosi/miso via Tier C', () {
      final available = availableFromPaths([
        makeVar('tb.spi.sclk'),
        makeVar('tb.spi.sdo'),
        makeVar('tb.spi.sdi'),
        makeVar('tb.spi.cs'),
      ]);

      final result = service.computeBindings(
        definition: spi,
        availableSignals: available,
        currentParameters: const {},
      );

      final sclk = findCandidate(result.candidates, 'sclk');
      expect(sclk.confidence, AutoBindConfidence.exactSuffix);
      expect(sclk.signalRef, 'tb.spi.sclk');

      final mosi = findCandidate(result.candidates, 'mosi');
      expect(mosi.confidence, AutoBindConfidence.knownAlias);
      expect(mosi.signalRef, 'tb.spi.sdo');

      final miso = findCandidate(result.candidates, 'miso');
      expect(miso.confidence, AutoBindConfidence.knownAlias);
      expect(miso.signalRef, 'tb.spi.sdi');

      final cs = findCandidate(result.candidates, 'cs');
      expect(cs.confidence, AutoBindConfidence.exactSuffix);
      expect(cs.signalRef, 'tb.spi.cs');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Fuzzy fallback (Tier D)
  // ──────────────────────────────────────────────────────────────────────────

  group('Fuzzy fallback', () {
    test('awvld resolves to awvalid via Levenshtein distance', () {
      // Design uses 'awvld' instead of 'awvalid' for one signal. Other AXI
      // bindings are absent so Tier A scoring on awvld alone wouldn't kick
      // in (a single-binding group has no shared-prefix evidence).
      final available = availableFromPaths([
        makeVar('tb.spi.awvld'), // 2-edit fuzzy from awvalid
        makeVar('tb.spi.awvalu'), // 2-edit fuzzy from awvalid (alternative)
      ]);

      // Use AXI4-Lite definition but provide only fuzzy-near signals.
      final result = service.computeBindings(
        definition: axi,
        availableSignals: available,
        currentParameters: const {'addr_width': 32, 'data_width': 32},
      );

      final awvalid = findCandidate(result.candidates, 'awvalid');
      expect(awvalid.confidence, AutoBindConfidence.fuzzyMatch);
      expect(awvalid.signalRef, 'tb.spi.awvld');
      expect(awvalid.alternatives.isNotEmpty, isTrue);
      expect(awvalid.alternatives, contains('tb.spi.awvalu'));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // No-match returns noMatch
  // ──────────────────────────────────────────────────────────────────────────

  group('No-match returns noMatch', () {
    test('empty available signals → every binding gets noMatch', () {
      final result = service.computeBindings(
        definition: axi,
        availableSignals: const {},
        currentParameters: const {'addr_width': 32, 'data_width': 32},
      );

      // Every required + optional binding present.
      final allBindings = [
        ...axi.requiredSignals.map((b) => b.name),
        ...axi.optionalSignals.map((b) => b.name),
      ];
      for (final name in allBindings) {
        final c = findCandidate(result.candidates, name);
        expect(c.confidence, AutoBindConfidence.noMatch);
        expect(c.signalRef, isNull);
      }

      expect(result.detectedPrefix, isNull);
      expect(result.detectedScopePath, isNull);
      expect(result.hasAmbiguity, isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Optional signals do not block result
  // ──────────────────────────────────────────────────────────────────────────

  group('Optional signals do not block result', () {
    test('APB: pstrb/pprot absent → required bindings resolve, optional '
        'noMatch', () {
      // Build a complete APB required set; omit pstrb/pprot.
      final available = availableFromPaths([
        makeVar('tb.apb.pclk'),
        makeVar('tb.apb.presetn'),
        makeVar('tb.apb.psel'),
        makeVar('tb.apb.penable'),
        makeVar('tb.apb.pwrite'),
        makeVar('tb.apb.paddr', bitWidth: 32),
        makeVar('tb.apb.pwdata', bitWidth: 32),
        makeVar('tb.apb.prdata', bitWidth: 32),
      ]);

      final result = service.computeBindings(
        definition: apb,
        availableSignals: available,
        currentParameters: const {'addr_width': 32, 'data_width': 32},
      );

      for (final binding in apb.requiredSignals) {
        final c = findCandidate(result.candidates, binding.name);
        expect(
          c.confidence,
          AutoBindConfidence.exactSuffix,
          reason:
              'required binding ${binding.name} should resolve, got '
              '${c.confidence} (${c.matchReason})',
        );
        expect(c.signalRef, 'tb.apb.${binding.name}');
      }

      // Optional bindings should be noMatch since the signals don't exist.
      for (final binding in apb.optionalSignals) {
        final c = findCandidate(result.candidates, binding.name);
        expect(
          c.confidence,
          AutoBindConfidence.noMatch,
          reason:
              'optional binding ${binding.name} should be noMatch '
              'when not present in design',
        );
      }

      // Detected prefix is empty string (no shared prefix in the leaf names
      // — they all just *are* the binding name) but scope should be tb.apb.
      expect(result.detectedScopePath, 'tb.apb');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Smoke / sanity
  // ──────────────────────────────────────────────────────────────────────────

  group('definition with no bindings', () {
    test('returns an empty result', () {
      const empty = DecoderDefinition(
        id: 'noop',
        displayName: 'Noop',
        description: 'no bindings',
        requiredSignals: [],
      );
      final result = service.computeBindings(
        definition: empty,
        availableSignals: const {},
        currentParameters: const {},
      );
      expect(result.isEmpty, isTrue);
    });
  });
}
