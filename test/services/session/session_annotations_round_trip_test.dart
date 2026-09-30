// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/domain/models/session_state.dart';
import 'package:wavecrux/services/session/session_service.dart';

/// `.wavecrux` schema v4 annotation persistence.
///
/// The invariants under test are the ones that break quietly: a pre-annotation
/// document must stay byte-stable through a save on this build, a single
/// malformed annotation must not cost the user the rest of the session, and
/// the Pro-payload preserve-unknown contract must be untouched by the new
/// top-level key.
const _service = SessionService();

Future<T> _withTempFile<T>(Future<T> Function(String path) fn) async {
  final dir = await Directory.systemTemp.createTemp('wavecrux_ann_');
  final path = '${dir.path}/session.wavecrux';
  try {
    return await fn(path);
  } finally {
    try {
      await dir.delete(recursive: true);
    } on FileSystemException catch (_) {}
  }
}

Annotation _callout({
  String id = 'ann-1',
  int time = 1250,
  String row = 'top.cpu.alu_result',
}) => Annotation(
  id: id,
  shape: AnnotationShape.callout,
  anchor: PointAnchor(time: time, rowId: row),
  text: 'stale by one cycle',
  authorName: 'Martin',
  createdAt: DateTime.utc(2026, 8, 12, 9, 30),
  witness: const AnnotationWitness(bits: "8'hA3", edgeOrdinal: 17),
);

void main() {
  group('schema v4 — annotations round-trip', () {
    test('a session with annotations survives save + load', () async {
      final state = SessionState(
        sourceFilePath: '/tmp/dump.vcd',
        annotations: [
          _callout(),
          Annotation(
            id: 'ann-2',
            shape: AnnotationShape.band,
            anchor: const RangeAnchor(startTime: 100, endTime: 900),
            authorName: 'Martin',
            createdAt: DateTime.utc(2026, 8, 12, 9, 31),
            text: '800 ns of back-pressure',
          ),
          Annotation(
            id: 'ann-3',
            shape: AnnotationShape.arrow,
            anchor: const PointAnchor(time: 42, rowId: 'top.clk'),
            authorName: 'Martin',
            createdAt: DateTime.utc(2026, 8, 12, 9, 32),
            colorRgb: 0xFFEE5522,
            collapsed: true,
          ),
        ],
      );

      await _withTempFile((path) async {
        await _service.saveSession(state, path);
        final loaded = await _service.loadSession(path);
        expect(loaded.annotations, state.annotations);
      });
    });

    test('the document declares version 4', () async {
      await _withTempFile((path) async {
        await _service.saveSession(
          SessionState(annotations: [_callout()]),
          path,
        );
        final json =
            jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
        expect(json['version'], 4);
        expect(json['annotations'], isA<List<dynamic>>());
      });
    });
  });

  group('backward and forward compatibility', () {
    test('a v3 document loads with no annotations', () async {
      await _withTempFile((path) async {
        await File(path).writeAsString(
          jsonEncode({
            'version': 3,
            'sourceFilePath': '/tmp/dump.vcd',
            'signals': <Object?>[],
          }),
        );
        final loaded = await _service.loadSession(path);
        expect(loaded.annotations, isEmpty);
      });
    });

    test('an empty annotation list emits no key at all', () async {
      await _withTempFile((path) async {
        await _service.saveSession(const SessionState(), path);
        final json =
            jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
        expect(
          json.containsKey('annotations'),
          isFalse,
          reason: 'pre-annotation sessions must round-trip byte-stable',
        );
      });
    });

    test('a newer document still yields its readable annotations', () async {
      await _withTempFile((path) async {
        await File(path).writeAsString(
          jsonEncode({
            'version': 99,
            'signals': <Object?>[],
            'annotations': [
              _callout().toJson(),
              // A shape this build does not know — dropped, not fatal.
              {
                'id': 'future-1',
                'shape': 'hexagon',
                'anchor': {'kind': 'point', 'time': 5, 'rowId': 'top.clk'},
              },
            ],
          }),
        );
        final loaded = await _service.loadSession(path);
        expect(loaded.annotations.length, 1);
        expect(loaded.annotations.single.id, 'ann-1');
      });
    });
  });

  group('tolerance', () {
    test('one malformed annotation does not cost the others', () async {
      await _withTempFile((path) async {
        await File(path).writeAsString(
          jsonEncode({
            'version': 4,
            'signals': <Object?>[],
            'annotations': [
              _callout(id: 'good-1').toJson(),
              'not even a map',
              {'id': 'no-anchor', 'shape': 'callout'},
              {
                'shape': 'callout',
                'anchor': {'kind': 'point', 'time': 1, 'rowId': 'r'},
              },
              _callout(id: 'good-2', time: 99).toJson(),
            ],
          }),
        );
        final loaded = await _service.loadSession(path);
        expect(
          loaded.annotations.map((a) => a.id),
          ['good-1', 'good-2'],
        );
      });
    });

    test('a non-list annotations field degrades to empty', () async {
      await _withTempFile((path) async {
        await File(path).writeAsString(
          jsonEncode({
            'version': 4,
            'signals': <Object?>[],
            'annotations': {'not': 'a list'},
          }),
        );
        final loaded = await _service.loadSession(path);
        expect(loaded.annotations, isEmpty);
      });
    });
  });

  group('the extensions seam is unaffected', () {
    test('unknown Pro namespaces still round-trip verbatim', () async {
      await _withTempFile((path) async {
        await File(path).writeAsString(
          jsonEncode({
            'version': 4,
            'signals': <Object?>[],
            'annotations': [_callout().toJson()],
            'extensions': {
              'pro.unknown': {'opaque': 42},
            },
          }),
        );
        final loaded = await _service.loadSession(path);
        expect(loaded.annotations.length, 1);
        expect(loaded.extensions['pro.unknown'], {'opaque': 42});

        await _service.saveSession(loaded, path);
        final resaved =
            jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
        expect(
          (resaved['extensions'] as Map)['pro.unknown'],
          {'opaque': 42},
          reason: 'preserve-unknown must survive the v4 bump',
        );
      });
    });
  });

  group('SessionState value semantics', () {
    test('annotations participate in equality', () {
      final a = SessionState(annotations: [_callout()]);
      final b = SessionState(annotations: [_callout()]);
      final c = SessionState(annotations: [_callout(time: 1251)]);
      expect(a, b);
      expect(a == c, isFalse);
    });

    test('copyWith replaces the list without touching other state', () {
      final base = SessionState(
        sourceFilePath: '/tmp/x.vcd',
        annotations: [_callout()],
      );
      final cleared = base.copyWith(annotations: const []);
      expect(cleared.annotations, isEmpty);
      expect(cleared.sourceFilePath, '/tmp/x.vcd');
    });
  });

  group('adopted layers — additive on top of v4', () {
    test('the registry round-trips and the version does not move', () async {
      await _withTempFile((path) async {
        const layer = AnnotationLayer(
          id: 'L1',
          label: 'Design review · 3 participants',
          sourceSessionId: 'S1',
          visible: false,
        );
        await _service.saveSession(
          SessionState(
            annotations: [_callout().copyWith(layerId: 'L1')],
            annotationLayers: const [layer],
          ),
          path,
        );

        final raw =
            jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
        expect(
          raw['version'],
          4,
          reason: 'the registry rides alongside annotations, additively',
        );

        final loaded = await _service.loadSession(path);
        expect(loaded.annotationLayers, const [layer]);
      });
    });

    test('a document with no layers emits no key', () async {
      await _withTempFile((path) async {
        await _service.saveSession(
          SessionState(annotations: [_callout()]),
          path,
        );
        final raw =
            jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
        expect(raw.containsKey('annotationLayers'), isFalse);
      });
    });

    test('a v4 document with layerIds and no registry still loads', () async {
      // What a layered document looks like to a build that predates the
      // registry, and vice versa: unnamed groups, never lost notes.
      await _withTempFile((path) async {
        await _service.saveSession(
          SessionState(annotations: [_callout().copyWith(layerId: 'L1')]),
          path,
        );
        final loaded = await _service.loadSession(path);
        expect(loaded.annotations.single.layerId, 'L1');
        expect(loaded.annotationLayers, isEmpty);
      });
    });

    test('one malformed layer does not cost the rest', () async {
      await _withTempFile((path) async {
        await File(path).writeAsString(
          jsonEncode({
            'version': 4,
            'annotationLayers': [
              {'label': 'no id'},
              {'id': 'L2', 'label': 'kept'},
            ],
          }),
        );
        final loaded = await _service.loadSession(path);
        expect(
          loaded.annotationLayers.map((l) => l.id),
          ['L2'],
        );
      });
    });

    test('layers participate in SessionState equality', () {
      const layer = AnnotationLayer(id: 'L1', label: 'Design review');
      expect(
        const SessionState(annotationLayers: [layer]),
        const SessionState(annotationLayers: [layer]),
      );
      expect(
        const SessionState(annotationLayers: [layer]) == const SessionState(),
        isFalse,
      );
    });
  });
}
