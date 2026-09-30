// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/cocotb_log_severity.dart';

void main() {
  group('CocotbLogSeverity', () {
    test('has six values', () {
      expect(CocotbLogSeverity.values, hasLength(6));
    });

    test('values include all six severities', () {
      expect(
        CocotbLogSeverity.values,
        containsAll([
          CocotbLogSeverity.trace,
          CocotbLogSeverity.debug,
          CocotbLogSeverity.info,
          CocotbLogSeverity.warning,
          CocotbLogSeverity.error,
          CocotbLogSeverity.critical,
        ]),
      );
    });

    test('trace sorts below debug', () {
      // The enum is declared least- to most-severe and callers rely on the
      // ordinal, so TRACE has to lead rather than be appended at the end.
      expect(
        CocotbLogSeverity.trace.index,
        lessThan(CocotbLogSeverity.debug.index),
      );
    });

    test('each value has a distinct name', () {
      final names = CocotbLogSeverity.values.map((v) => v.name).toSet();
      expect(names, hasLength(CocotbLogSeverity.values.length));
    });

    group('fromString', () {
      // cocotb registers TRACE itself (logging.addLevelName(5, "TRACE")); it
      // is not a stock Python level. Cocotb 2.1's GPI_DEBUG / PYGPI_DEBUG turn
      // it on, and before this the parser returned null and dropped the line.
      test('parses TRACE, which cocotb 2.1 debug flags emit', () {
        expect(
          CocotbLogSeverity.fromString('TRACE'),
          CocotbLogSeverity.trace,
        );
        expect(
          CocotbLogSeverity.fromString('trace'),
          CocotbLogSeverity.trace,
        );
        expect(
          CocotbLogSeverity.fromString('  Trace  '),
          CocotbLogSeverity.trace,
        );
      });

      test('TRACE renders its cocotb spelling', () {
        expect(CocotbLogSeverity.trace.displayLabel, 'TRACE');
      });

      test('parses uppercase canonical names', () {
        expect(
          CocotbLogSeverity.fromString('DEBUG'),
          CocotbLogSeverity.debug,
        );
        expect(CocotbLogSeverity.fromString('INFO'), CocotbLogSeverity.info);
        expect(
          CocotbLogSeverity.fromString('WARNING'),
          CocotbLogSeverity.warning,
        );
        expect(
          CocotbLogSeverity.fromString('ERROR'),
          CocotbLogSeverity.error,
        );
        expect(
          CocotbLogSeverity.fromString('CRITICAL'),
          CocotbLogSeverity.critical,
        );
      });

      test('parses lowercase names', () {
        expect(
          CocotbLogSeverity.fromString('debug'),
          CocotbLogSeverity.debug,
        );
        expect(
          CocotbLogSeverity.fromString('warning'),
          CocotbLogSeverity.warning,
        );
        expect(
          CocotbLogSeverity.fromString('critical'),
          CocotbLogSeverity.critical,
        );
      });

      test('parses mixed case', () {
        expect(
          CocotbLogSeverity.fromString('Warning'),
          CocotbLogSeverity.warning,
        );
        expect(CocotbLogSeverity.fromString('iNfO'), CocotbLogSeverity.info);
      });

      test('accepts WARN alias for warning', () {
        expect(
          CocotbLogSeverity.fromString('WARN'),
          CocotbLogSeverity.warning,
        );
        expect(
          CocotbLogSeverity.fromString('warn'),
          CocotbLogSeverity.warning,
        );
      });

      test('accepts FATAL alias for critical', () {
        expect(
          CocotbLogSeverity.fromString('FATAL'),
          CocotbLogSeverity.critical,
        );
        expect(
          CocotbLogSeverity.fromString('fatal'),
          CocotbLogSeverity.critical,
        );
      });

      test('trims surrounding whitespace', () {
        expect(
          CocotbLogSeverity.fromString('  INFO  '),
          CocotbLogSeverity.info,
        );
      });

      test('returns null for unknown values', () {
        // 'TRACE' used to be asserted here as unknown. It is a real cocotb
        // level — cocotb registers it at 5, below DEBUG — and the parser
        // discards any line whose severity does not resolve, so asserting it
        // was unknown pinned the dropping of TRACE output as correct. Cocotb
        // 2.1's GPI_DEBUG / PYGPI_DEBUG make that output routine.
        expect(CocotbLogSeverity.fromString(''), isNull);
        expect(CocotbLogSeverity.fromString('NOTICE'), isNull);
        expect(CocotbLogSeverity.fromString('???'), isNull);
      });
    });

    group('displayLabel', () {
      test('debug → "DEBUG"', () {
        expect(CocotbLogSeverity.debug.displayLabel, 'DEBUG');
      });
      test('info → "INFO"', () {
        expect(CocotbLogSeverity.info.displayLabel, 'INFO');
      });
      test('warning → "WARNING"', () {
        expect(CocotbLogSeverity.warning.displayLabel, 'WARNING');
      });
      test('error → "ERROR"', () {
        expect(CocotbLogSeverity.error.displayLabel, 'ERROR');
      });
      test('critical → "CRITICAL"', () {
        expect(CocotbLogSeverity.critical.displayLabel, 'CRITICAL');
      });

      test('all displayLabels round-trip via fromString', () {
        for (final s in CocotbLogSeverity.values) {
          expect(CocotbLogSeverity.fromString(s.displayLabel), s);
        }
      });
    });
  });
}
