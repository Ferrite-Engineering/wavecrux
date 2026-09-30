// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Annotations outlive the tab that made them.
//
// The reported loss: annotate a waveform, close the tab, reopen the same file,
// and the notes are gone. Per-tab state autosaves to `sessions/{tabId}` and
// `closeTab` deletes it — correct for cursors and zoom, catastrophic for prose
// the user wrote. These pin the separation: the sidecar keeps the view, the
// trace store keeps the words.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/services/session/trace_annotation_store.dart';

Annotation _note({String id = 'a1', String text = 'req asserts here'}) =>
    Annotation(
      id: id,
      shape: AnnotationShape.callout,
      anchor: const PointAnchor(time: 200, rowId: 'top.req'),
      authorName: 'Martin',
      createdAt: DateTime.utc(2026, 8, 16),
      text: text,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late TraceAnnotationStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('trace-annotations');
    store = TraceAnnotationStore(tmp);
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('notes written for a trace are read back for that trace', () async {
    const trace = '/sim/run/out.vcd';
    await store.save(
      trace,
      TraceAnnotations(
        annotations: [_note()],
        layers: const [],
        visible: true,
      ),
    );

    final read = await store.load(trace);
    expect(read.annotations.single.text, 'req asserts here');
    expect(read.visible, isTrue);
  });

  test('the same trace spelled differently is the same trace', () async {
    // The whole point of keying by canonical path. A file opened from the
    // recent list, from a CLI argument, and by drag-and-drop arrives as three
    // different strings; if they keyed differently the user would lose their
    // notes depending on how they happened to open the file.
    final dir = await Directory.systemTemp.createTemp('trace-id');
    addTearDown(() async => dir.delete(recursive: true));
    final file = File('${dir.path}${Platform.pathSeparator}out.vcd')
      ..writeAsStringSync('');

    await store.save(
      file.path,
      TraceAnnotations(
        annotations: [_note()],
        layers: const [],
        visible: true,
      ),
    );

    final viaDots =
        '${dir.path}${Platform.pathSeparator}.'
        '${Platform.pathSeparator}out.vcd';
    expect((await store.load(viaDots)).annotations, hasLength(1));
  });

  test('a different trace does not see them', () async {
    await store.save(
      '/sim/a.vcd',
      TraceAnnotations(
        annotations: [_note()],
        layers: const [],
        visible: true,
      ),
    );
    expect((await store.load('/sim/b.vcd')).annotations, isEmpty);
  });

  test(
    'emptying a trace removes its file rather than leaving a husk',
    () async {
      const trace = '/sim/run/out.vcd';
      await store.save(
        trace,
        TraceAnnotations(
          annotations: [_note()],
          layers: const [],
          visible: true,
        ),
      );
      expect(store.fileFor(trace).existsSync(), isTrue);

      await store.save(trace, const TraceAnnotations.empty());
      expect(
        store.fileFor(trace).existsSync(),
        isFalse,
        reason: 'a user who deleted every note has said this trace has none',
      );
    },
  );

  test('a record written for another trace is ignored', () async {
    // Guards a filename-hash collision. The record names the trace it belongs
    // to, so the worst a collision can do is read as "no notes" — never as
    // somebody else's notes appearing on your waveform.
    const mine = '/sim/mine.vcd';
    final file = store.fileFor(mine)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        '{"version":1,"tracePath":"/sim/theirs.vcd",'
        '"annotations":[{"id":"x","shape":"callout",'
        '"anchor":{"kind":"point","time":1,"rowId":"top.x"},'
        '"author":"Someone","createdAt":"2026-08-16T00:00:00.000Z",'
        '"text":"not yours"}],"annotationsVisible":true}',
      );
    expect(file.existsSync(), isTrue);

    expect((await store.load(mine)).annotations, isEmpty);
  });

  test('a corrupt record does not stop the waveform opening', () async {
    const trace = '/sim/run/out.vcd';
    store.fileFor(trace)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{ this is not json');

    // No throw: the notes enhance the file, they are not a precondition for it.
    expect((await store.load(trace)).annotations, isEmpty);
  });

  test('one unreadable note does not cost the others', () async {
    const trace = '/sim/run/out.vcd';
    store.fileFor(trace)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        '{"version":1,"tracePath":"$trace","annotations":['
        '{"nonsense":true},'
        '{"id":"a2","shape":"callout",'
        '"anchor":{"kind":"point","time":5,"rowId":"top.req"},'
        '"author":"Martin","createdAt":"2026-08-16T00:00:00.000Z",'
        '"text":"survivor"}],"annotationsVisible":true}',
      );

    final read = await store.load(trace);
    expect(read.annotations.single.text, 'survivor');
  });
}
