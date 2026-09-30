// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The `.wavecruxpack` share bundle, end to end at the service layer: write a
// pack, read it back, and load the session inside it exactly as the app does.
//
// The load-bearing assertion is the RELATIVE-PATH REWRITE. A pack whose
// session still names `/Users/someone/sim/dump.vcd` opens to nothing on the
// recipient's machine, and it opens *perfectly* on the sender's — so the
// failure is invisible to whoever wrote the feature and total for everybody
// else. The test therefore extracts into a directory the session has never
// seen and asserts the source resolved to the bundled dump.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/domain/models/cursor_state.dart';
import 'package:wavecrux/domain/models/session_state.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/services/pack/wavecrux_pack_failure.dart';
import 'package:wavecrux/services/pack/wavecrux_pack_reader.dart';
import 'package:wavecrux/services/pack/wavecrux_pack_spec.dart';
import 'package:wavecrux/services/pack/wavecrux_pack_writer.dart';
import 'package:wavecrux/services/session/session_service.dart';

const _vcd = r'''
$timescale 1ns $end
$scope module top $end
$var wire 1 ! clk $end
$upscope $end
$enddefinitions $end
#0
$dumpvars
0!
$end
#5
1!
''';

Annotation _annotation({String id = 'a1', String author = 'Dana'}) =>
    Annotation(
      id: id,
      shape: AnnotationShape.callout,
      anchor: const PointAnchor(time: 400, rowId: 'top.bus'),
      text: 'This is the ack that never arrives',
      authorName: author,
      createdAt: DateTime.utc(2026, 8, 13, 9, 30),
      witness: const AnnotationWitness(bits: '10100011'),
      labelDx: 24,
      labelDy: -48,
    );

SessionState _session({List<Annotation>? annotations}) => SessionState(
  // What the sender's machine calls it — the pack must NOT carry this.
  sourceFilePath: '/Users/sender/sim/run7/dump.vcd',
  signalGroup: SignalGroup(
    entries: [
      SignalEntry.signal(
        signalRef: 'ref0',
        signalPath: 'top.bus',
        displayName: 'bus',
      ),
    ],
  ),
  cursorState: const CursorState(primaryCursorTime: 400),
  ticksPerPixel: 2.5,
  annotations: annotations ?? [_annotation()],
);

WaveCruxPackContents _contents({
  required String sessionJson,
  Uint8List? preview,
}) => WaveCruxPackContents(
  sessionJson: sessionJson,
  waveformVcd: _vcd,
  readme: buildReadmeStub(),
  previewPng: preview,
);

String buildReadmeStub() => 'WaveCrux pack\n';

/// A minimal ZIP local-file-header signature. The reader checks it before
/// handing bytes to the decoder, so the injected-decoder tests below still
/// have to look like an archive on the way in.
final _zipHeader = <int>[0x50, 0x4B, 0x03, 0x04];

void main() {
  const writer = WaveCruxPackWriter();
  const sessions = SessionService();

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('wavecruxpack_test');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  group('round trip', () {
    test(
      'a pack opens on a machine that has never seen the original dump',
      () async {
        final sender = _session();
        // The share flow rewrites the source to the bundled dump's relative
        // name before encoding; this is that same rewrite.
        final json = sessions.encodeDocument(
          sender.copyWith(sourceFilePath: WaveCruxPackSpec.waveformEntryName),
        );
        final packPath = p.join(
          tmp.path,
          'sender',
          'run7-annotated.wavecruxpack',
        );
        await writer.writeToFile(
          path: packPath,
          contents: _contents(
            sessionJson: json,
            preview: Uint8List.fromList([137, 80, 78, 71]),
          ),
        );

        // Extract somewhere with no relationship to where it was written —
        // the recipient's machine, as far as the code can tell.
        final cacheRoot = p.join(tmp.path, 'recipient', 'cache');
        final extracted = await WaveCruxPackReader().extract(
          packPath: packPath,
          cacheRoot: cacheRoot,
        );

        expect(
          p.basename(extracted.sessionPath),
          WaveCruxPackSpec.sessionEntryName,
        );
        expect(extracted.previewPath, isNotNull);
        expect(File(extracted.previewPath!).existsSync(), isTrue);

        final restored = await sessions.loadSession(extracted.sessionPath);

        // THE assertion: the source resolved to the bundled dump, not to the
        // sender's absolute path.
        expect(
          restored.sourceFilePath,
          p.join(extracted.directory, WaveCruxPackSpec.waveformEntryName),
        );
        expect(File(restored.sourceFilePath!).existsSync(), isTrue);
        expect(File(restored.sourceFilePath!).readAsStringSync(), _vcd);

        // …and the annotated view came with it.
        expect(restored.annotations, hasLength(1));
        final note = restored.annotations.single;
        expect(note.text, 'This is the ack that never arrives');
        expect(note.authorName, 'Dana');
        expect(note.witness?.bits, '10100011');
        expect((note.anchor as PointAnchor).time, 400);
        expect(note.labelDx, 24);
        expect(restored.cursorState.primaryCursorTime, 400);
        expect(restored.ticksPerPixel, 2.5);
      },
    );

    test(
      'author names can be stripped without losing the annotations',
      () async {
        final stripped = [
          for (final a in _session().annotations) a.copyWith(authorName: ''),
        ];
        final json = sessions.encodeDocument(
          _session(annotations: stripped).copyWith(
            sourceFilePath: WaveCruxPackSpec.waveformEntryName,
          ),
        );
        final packPath = p.join(tmp.path, 'anon.wavecruxpack');
        await writer.writeToFile(
          path: packPath,
          contents: _contents(sessionJson: json),
        );

        final extracted = await WaveCruxPackReader().extract(
          packPath: packPath,
          cacheRoot: p.join(tmp.path, 'cache'),
        );
        final restored = await sessions.loadSession(extracted.sessionPath);

        expect(restored.annotations, hasLength(1));
        expect(restored.annotations.single.authorName, '');
        expect(
          restored.annotations.single.text,
          'This is the ack that never arrives',
        );
      },
    );

    test('a pack opens from bytes alone, with no filesystem', () async {
      // The web path. The recipient worth reaching is the one who does NOT
      // have WaveCrux, and they open it in a browser — where there is no
      // directory to extract into and no path for the session's relative
      // `sourceFilePath` to resolve against.
      final sender = _session();
      final json = sessions.encodeDocument(
        sender.copyWith(sourceFilePath: WaveCruxPackSpec.waveformEntryName),
      );
      final packPath = p.join(tmp.path, 'emailed.wavecruxpack');
      await writer.writeToFile(
        path: packPath,
        contents: _contents(sessionJson: json),
      );

      // Everything past this point is bytes — exactly what a browser has.
      final bytes = File(packPath).readAsBytesSync();
      final entries = WaveCruxPackReader().readEntries(
        bytes: bytes,
        diagnosticName: 'emailed.wavecruxpack',
      );

      expect(entries[WaveCruxPackSpec.waveformEntryName], isNotNull);
      final restored = sessions.decodeDocument(
        utf8.decode(entries[WaveCruxPackSpec.sessionEntryName]!),
        diagnosticName: 'emailed.wavecruxpack/session',
      );
      // The annotations are the payload: a pack that arrives without the notes
      // is just a waveform, and the notes are the reason it was sent.
      expect(restored.annotations, hasLength(sender.annotations.length));
      expect(restored.signalGroup.entries, isNotEmpty);
      // Unresolved on purpose — `decodeDocument` does no path resolution, so
      // the caller decides what a relative source means. On web it means the
      // sibling ZIP entry, which is why the bytes above are enough.
      expect(restored.sourceFilePath, WaveCruxPackSpec.waveformEntryName);
    });

    test('the byte path enforces the same guards as extraction', () async {
      // Two readers with two ideas of "safe" would be two attack surfaces, on
      // the one format designed to arrive by email.
      final unsafe = Archive()
        ..addFile(
          ArchiveFile(
            '../escape.wavecrux',
            4,
            Uint8List.fromList([1, 2, 3, 4]),
          ),
        );
      final bytes = Uint8List.fromList(ZipEncoder().encode(unsafe));

      expect(
        () => WaveCruxPackReader().readEntries(
          bytes: bytes,
          diagnosticName: 'hostile.wavecruxpack',
        ),
        throwsA(
          isA<WaveCruxPackException>().having(
            (e) => e.kind,
            'kind',
            WaveCruxPackFailureKind.unsafeEntryName,
          ),
        ),
      );
    });

    test('the preview is written beside the pack, not only inside it', () async {
      // The image is the point of the share: it goes in the email body next to
      // the attachment. Sealed inside the zip, the sender has to unzip their
      // own bundle to reach it, so they screenshot instead.
      final json = sessions.encodeDocument(
        _session().copyWith(
          sourceFilePath: WaveCruxPackSpec.waveformEntryName,
        ),
      );
      final packPath = p.join(tmp.path, 'run7-annotated.wavecruxpack');
      final contents = _contents(
        sessionJson: json,
        preview: Uint8List.fromList([137, 80, 78, 71]),
      );
      await writer.writeToFile(path: packPath, contents: contents);

      final beside = await writer.writePreviewBeside(
        packPath: packPath,
        contents: contents,
      );

      expect(beside, isNotNull);
      expect(p.basename(beside!.path), 'run7-annotated.png');
      expect(beside.readAsBytesSync(), [137, 80, 78, 71]);
      // And still inside, because that is what makes the pack self-describing
      // for a recipient who only got the one file.
      final extracted = await WaveCruxPackReader().extract(
        packPath: packPath,
        cacheRoot: p.join(tmp.path, 'cache'),
      );
      expect(extracted.previewPath, isNotNull);
    });

    test('no preview means no file beside the pack', () async {
      // Rather than an empty or placeholder .png, which would be worse than
      // nothing: it would attach cleanly and show a broken image.
      final packPath = p.join(tmp.path, 'bare.wavecruxpack');
      final contents = _contents(
        sessionJson: sessions.encodeDocument(_session()),
      );
      await writer.writeToFile(path: packPath, contents: contents);

      expect(
        await writer.writePreviewBeside(
          packPath: packPath,
          contents: contents,
        ),
        isNull,
      );
      expect(File(p.join(tmp.path, 'bare.png')).existsSync(), isFalse);
    });

    test('a pack with no preview still opens', () async {
      final json = sessions.encodeDocument(
        _session().copyWith(
          sourceFilePath: WaveCruxPackSpec.waveformEntryName,
        ),
      );
      final packPath = p.join(tmp.path, 'nopreview.wavecruxpack');
      await writer.writeToFile(
        path: packPath,
        contents: _contents(sessionJson: json),
      );

      final extracted = await WaveCruxPackReader().extract(
        packPath: packPath,
        cacheRoot: p.join(tmp.path, 'cache'),
      );
      expect(extracted.previewPath, isNull);
      final restored = await sessions.loadSession(extracted.sessionPath);
      expect(restored.annotations, hasLength(1));
    });

    test(
      'reopening a pack replaces the previous extraction rather than merging',
      () async {
        final packPath = p.join(tmp.path, 'twice.wavecruxpack');
        final cacheRoot = p.join(tmp.path, 'cache');
        await writer.writeToFile(
          path: packPath,
          contents: _contents(
            sessionJson: sessions.encodeDocument(
              _session().copyWith(
                sourceFilePath: WaveCruxPackSpec.waveformEntryName,
              ),
            ),
          ),
        );
        final first = await WaveCruxPackReader().extract(
          packPath: packPath,
          cacheRoot: cacheRoot,
        );
        // A stale file from a previous version of the same pack. If the
        // extraction merged rather than replaced, this would survive — and a
        // stale `waveform.vcd` is a session silently one run out of date.
        final stale = File(p.join(first.directory, 'waveform.vcd.old'))
          ..writeAsStringSync('stale');

        final second = await WaveCruxPackReader().extract(
          packPath: packPath,
          cacheRoot: cacheRoot,
        );
        expect(second.directory, first.directory);
        expect(stale.existsSync(), isFalse);
      },
    );

    test(
      'a pack from a newer schema version degrades per the lenient policy',
      () async {
        // Hand-built: a future build's document, carrying a version this build
        // has never heard of, an unknown top-level key, and an extensions
        // namespace with no codec here.
        final future = <String, Object?>{
          'version': SessionService.currentSchemaVersion + 7,
          'sourceFilePath': WaveCruxPackSpec.waveformEntryName,
          'signals': <Object?>[],
          'somethingFromTheFuture': {'nested': true},
          'annotations': [_annotation().toJson()],
          'extensions': {
            'pro.unknown': {'payload': 42},
          },
        };
        final packPath = p.join(tmp.path, 'future.wavecruxpack');
        await writer.writeToFile(
          path: packPath,
          contents: _contents(
            sessionJson: const JsonEncoder.withIndent('  ').convert(future),
          ),
        );

        final extracted = await WaveCruxPackReader().extract(
          packPath: packPath,
          cacheRoot: p.join(tmp.path, 'cache'),
        );
        final restored = await sessions.loadSession(extracted.sessionPath);

        expect(restored.annotations, hasLength(1));
        expect(restored.extensions['pro.unknown'], {'payload': 42});
      },
    );
  });

  group('reader guards', () {
    Future<String> writeArchive(Archive archive, String name) async {
      final path = p.join(tmp.path, name);
      await File(path).writeAsBytes(ZipEncoder().encode(archive), flush: true);
      return path;
    }

    ArchiveFile textEntry(String name, String content) {
      final bytes = utf8.encode(content);
      return ArchiveFile(name, bytes.length, bytes);
    }

    test('a file that is not an archive is refused as such', () async {
      final path = p.join(tmp.path, 'notazip.wavecruxpack');
      await File(path).writeAsString('this is plain text');
      expect(
        () => WaveCruxPackReader().extract(
          packPath: path,
          cacheRoot: p.join(tmp.path, 'cache'),
        ),
        throwsA(
          isA<WaveCruxPackException>().having(
            (e) => e.kind,
            'kind',
            WaveCruxPackFailureKind.notAnArchive,
          ),
        ),
      );
    });

    test('a missing file is refused as missing, not as corrupt', () async {
      expect(
        () => WaveCruxPackReader().extract(
          packPath: p.join(tmp.path, 'absent.wavecruxpack'),
          cacheRoot: p.join(tmp.path, 'cache'),
        ),
        throwsA(
          isA<WaveCruxPackException>().having(
            (e) => e.kind,
            'kind',
            WaveCruxPackFailureKind.fileMissing,
          ),
        ),
      );
    });

    test('a zip with no session is refused', () async {
      final archive = Archive()
        ..addFile(textEntry(WaveCruxPackSpec.waveformEntryName, _vcd));
      final path = await writeArchive(archive, 'nosession.wavecruxpack');
      expect(
        () => WaveCruxPackReader().extract(
          packPath: path,
          cacheRoot: p.join(tmp.path, 'cache'),
        ),
        throwsA(
          isA<WaveCruxPackException>().having(
            (e) => e.kind,
            'kind',
            WaveCruxPackFailureKind.missingSession,
          ),
        ),
      );
    });

    test(
      'a traversing entry name is refused before anything is written',
      () async {
        // Injected rather than written: a real ZipEncoder normalises some of
        // these away, and the guard has to hold against an archive built by
        // something other than this app.
        final hostile = Archive()
          ..addFile(textEntry('../../etc/wavecrux-owned', 'x'))
          ..addFile(textEntry(WaveCruxPackSpec.sessionEntryName, '{}'));
        final reader = WaveCruxPackReader(archiveDecoder: (_) => hostile);
        final cacheRoot = p.join(tmp.path, 'cache');
        final path = p.join(tmp.path, 'hostile.wavecruxpack');
        await File(path).writeAsBytes(_zipHeader);

        expect(
          () => reader.extract(packPath: path, cacheRoot: cacheRoot),
          throwsA(
            isA<WaveCruxPackException>().having(
              (e) => e.kind,
              'kind',
              WaveCruxPackFailureKind.unsafeEntryName,
            ),
          ),
        );
        expect(Directory(cacheRoot).existsSync(), isFalse);
      },
    );

    test('an absolute entry name is refused', () async {
      final hostile = Archive()
        ..addFile(textEntry('/etc/passwd', 'x'))
        ..addFile(textEntry(WaveCruxPackSpec.sessionEntryName, '{}'));
      final reader = WaveCruxPackReader(archiveDecoder: (_) => hostile);
      final path = p.join(tmp.path, 'absolute.wavecruxpack');
      await File(path).writeAsBytes(_zipHeader);
      expect(
        () => reader.extract(
          packPath: path,
          cacheRoot: p.join(tmp.path, 'cache'),
        ),
        throwsA(
          isA<WaveCruxPackException>().having(
            (e) => e.kind,
            'kind',
            WaveCruxPackFailureKind.unsafeEntryName,
          ),
        ),
      );
    });

    test('an oversized expansion is refused', () async {
      final bomb = Archive()
        ..addFile(
          ArchiveFile(
            WaveCruxPackSpec.sessionEntryName,
            WaveCruxPackSpec.maxUncompressedBytes + 1,
            <int>[0],
          ),
        );
      final reader = WaveCruxPackReader(archiveDecoder: (_) => bomb);
      final path = p.join(tmp.path, 'bomb.wavecruxpack');
      await File(path).writeAsBytes(_zipHeader);
      expect(
        () => reader.extract(
          packPath: path,
          cacheRoot: p.join(tmp.path, 'cache'),
        ),
        throwsA(
          isA<WaveCruxPackException>().having(
            (e) => e.kind,
            'kind',
            WaveCruxPackFailureKind.tooLarge,
          ),
        ),
      );
    });
  });

  group('entry-name safety', () {
    test('accepts the four entries the format defines', () {
      for (final name in [
        WaveCruxPackSpec.sessionEntryName,
        WaveCruxPackSpec.waveformEntryName,
        WaveCruxPackSpec.previewEntryName,
        WaveCruxPackSpec.readmeEntryName,
      ]) {
        expect(WaveCruxPackSpec.isSafeEntryName(name), isTrue, reason: name);
      }
    });

    test('rejects traversal, absolutes, drive letters and backslashes', () {
      for (final name in [
        '',
        '..',
        '../session.wavecrux',
        'a/../../b',
        '/session.wavecrux',
        r'C:\session.wavecrux',
        r'dir\session.wavecrux',
        'a/b/c/d/e/session.wavecrux',
      ]) {
        expect(
          WaveCruxPackSpec.isSafeEntryName(name),
          isFalse,
          reason: 'should reject "$name"',
        );
      }
    });
  });

  group('size accounting', () {
    test('uncompressed size counts every entry', () {
      final contents = _contents(
        sessionJson: '{"a":1}',
        preview: Uint8List(64),
      );
      expect(
        contents.uncompressedBytes,
        utf8.encode(contents.sessionJson).length +
            utf8.encode(contents.waveformVcd).length +
            utf8.encode(contents.readme).length +
            64,
      );
    });
  });
}
