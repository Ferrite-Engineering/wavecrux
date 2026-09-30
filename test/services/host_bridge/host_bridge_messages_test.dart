// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:typed_data';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_telemetry/crux_telemetry.dart' show TelemetryEvent;
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/host_bridge/host_bridge_messages.dart';

/// The wire contract between the extension host and this build.
///
/// Two things are being pinned here, and only one of them is decoding. The
/// other is refusal: every frame on this channel is untrusted input, so the
/// tests that matter most are the ones asserting that a malformed, oversized,
/// or unrecognised frame produces `null` rather than a partial action or a
/// throw.
void main() {
  Map<String, Object?> frameOf(
    String kind,
    Map<String, Object?> payload, {
    String messageId = 'm1',
    String cxpVersion = cxpProtocolVersion,
  }) => <String, Object?>{
    'type': kHostBridgeCxpFrameType,
    'envelope': <String, Object?>{
      'cxp_version': cxpVersion,
      'message_id': messageId,
      'from': 'vscode.host',
      'kind': kind,
      'payload': payload,
    },
  };

  group('the marker constants', () {
    test("name the globals crux-vscode's html.ts sets", () {
      // These four are one contract with two implementations. Renaming either
      // side alone fails silently — the build reports form_factor 'web'
      // forever after — so the values are pinned literally here and by
      // `EDITOR_HOST_MARKER_GLOBAL` / `EDITOR_HOST_KIND` /
      // `EDITOR_HOST_PROTOCOL_VERSION` in the extension's own test.
      expect(kEditorHostMarkerGlobal, 'cruxEditorHost');
      expect(kEditorHostMarkerKindVscode, 'vscode');
      expect(kEditorHostMarkerProtocol, 1);
      // `TELEMETRY_MESSAGE_TYPE` in packages/wavecrux/src/webview/panel.ts.
      expect(kHostBridgeTelemetryFrameType, 'crux.telemetry');
    });
  });

  group('hostBridgeStringMap', () {
    test('accepts the Map<Object?, Object?> dartify() produces', () {
      final raw = <Object?, Object?>{'type': 'crux.cxp', 'protocol': 1};
      expect(hostBridgeStringMap(raw), <String, Object?>{
        'type': 'crux.cxp',
        'protocol': 1,
      });
    });

    test('rejects a map with a non-String key rather than casting lazily', () {
      // A lazy `cast` would defer the failure to the first read — inside
      // message handling, where a throw is precisely what must not happen.
      expect(hostBridgeStringMap(<Object?, Object?>{1: 'x'}), isNull);
    });

    test('rejects non-maps', () {
      expect(hostBridgeStringMap(null), isNull);
      expect(hostBridgeStringMap('crux.cxp'), isNull);
      expect(hostBridgeStringMap(<Object?>['crux.cxp']), isNull);
    });
  });

  group('decodeHostBridgeFrame', () {
    test('decodes a request_highlight into its CXP message type', () {
      final inbound = decodeHostBridgeFrame(
        frameOf(CxpMessageKind.requestHighlight, <String, Object?>{
          'element': <String, Object?>{'kind': 'signal', 'path': 'top.data'},
          'metadata': <String, Object?>{'wavecrux.cursor_time_fs': 42},
        }),
      );
      expect(inbound, isNotNull);
      expect(inbound!.envelope.messageId, 'm1');
      final message = inbound.message as RequestHighlight;
      expect(message.element.kind, ElementKind.signal);
      expect(message.element.path, 'top.data');
      expect(message.metadata['wavecrux.cursor_time_fs'], 42);
    });

    test('decodes the product-defined open-waveform kind', () {
      final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final inbound = decodeHostBridgeFrame(
        frameOf(kHostBridgeOpenWaveformKind, <String, Object?>{
          'display_name': 'dump.vcd',
          'bytes_base64': base64Encode(bytes),
        }),
      );
      final message = inbound!.message as HostBridgeOpenWaveform;
      expect(message.displayName, 'dump.vcd');
      expect(message.bytes, bytes);
      expect(message.kind, kHostBridgeOpenWaveformKind);
    });

    test('decodes a structured-clone Uint8List as readily as base64', () {
      // Which of the two arrives depends on the transport the host picked, not
      // on anything semantic. Refusing one would couple the Dart side to that
      // choice.
      final bytes = Uint8List.fromList(<int>[9, 8, 7]);
      final inbound = decodeHostBridgeFrame(
        frameOf(kHostBridgeOpenWaveformKind, <String, Object?>{
          'display_name': 'dump.fst',
          'bytes': bytes,
        }),
      );
      expect((inbound!.message as HostBridgeOpenWaveform).bytes, bytes);
    });

    test('returns null for a frame that is not ours', () {
      expect(
        decodeHostBridgeFrame(<String, Object?>{
          'type': 'crux.webview.diagnostic',
          'kind': 'boot',
        }),
        isNull,
      );
    });

    test('returns null for a malformed envelope, and does not throw', () {
      // Missing `message_id` — CxpEnvelope.fromJson throws FormatException,
      // which the decoder swallows into a refusal.
      expect(
        decodeHostBridgeFrame(<String, Object?>{
          'type': kHostBridgeCxpFrameType,
          'envelope': <String, Object?>{
            'cxp_version': cxpProtocolVersion,
            'from': 'vscode.host',
            'kind': CxpMessageKind.requestHighlight,
            'payload': <String, Object?>{},
          },
        }),
        isNull,
      );
    });

    test('returns null for a malformed payload of a known kind', () {
      expect(
        decodeHostBridgeFrame(
          frameOf(CxpMessageKind.requestHighlight, <String, Object?>{}),
        ),
        isNull,
      );
    });

    test('refuses an incompatible major protocol version', () {
      // CXP's own policy, applied at the bridge rather than re-invented: a
      // major mismatch is refused, a minor one is accepted.
      expect(
        decodeHostBridgeFrame(
          frameOf(
            CxpMessageKind.requestHighlight,
            <String, Object?>{
              'element': <String, Object?>{'kind': 'signal', 'path': 'top.a'},
            },
            cxpVersion: '2.0',
          ),
        ),
        isNull,
      );
      expect(
        decodeHostBridgeFrame(
          frameOf(
            CxpMessageKind.requestHighlight,
            <String, Object?>{
              'element': <String, Object?>{'kind': 'signal', 'path': 'top.a'},
            },
            cxpVersion: '1.99',
          ),
        ),
        isNotNull,
      );
    });

    test('returns null for a kind neither CXP nor this bridge defines', () {
      expect(
        decodeHostBridgeFrame(
          frameOf('crux.teleport', <String, Object?>{'x': 1}),
        ),
        isNull,
      );
    });
  });

  group('hostBridgeBytesFrom bounds the buffer', () {
    test('accepts a payload at the cap', () {
      final bytes = Uint8List(16);
      expect(hostBridgeBytesFrom(bytes), hasLength(16));
    });

    test('the shipped cap is 256 MiB', () {
      expect(kHostBridgeMaxOpenBytes, 256 * 1024 * 1024);
    });

    test('refuses a raw buffer over the cap', () {
      expect(hostBridgeBytesFrom(Uint8List(9), maxBytes: 8), isNull);
      expect(hostBridgeBytesFrom(Uint8List(8), maxBytes: 8), hasLength(8));
    });

    test('refuses a list over the cap before copying it', () {
      expect(hostBridgeBytesFrom(<int>[1, 2, 3], maxBytes: 2), isNull);
    });

    test('refuses an oversize base64 string on its encoded length', () {
      // 4/3 expansion means a string this long cannot decode under the cap, so
      // it is refused without ever allocating the buffer.
      final encoded = base64Encode(Uint8List(64));
      expect(hostBridgeBytesFrom(encoded, maxBytes: 8), isNull);
      expect(hostBridgeBytesFrom(encoded, maxBytes: 64), hasLength(64));
    });

    test('an oversize open-waveform payload does not decode at all', () {
      // The refusal is total: the message is `null`, so the app never sees a
      // truncated waveform or a partially-applied open.
      expect(
        HostBridgeOpenWaveform.tryFromJson(<String, Object?>{
          'display_name': 'huge.vcd',
          'bytes': Uint8List(100),
        }, maxBytes: 10),
        isNull,
      );
    });

    test('refuses a base64 string that is not base64', () {
      expect(hostBridgeBytesFrom('not!valid!base64!'), isNull);
    });

    test('refuses anything that is not bytes at all', () {
      expect(hostBridgeBytesFrom(null), isNull);
      expect(hostBridgeBytesFrom(42), isNull);
      expect(hostBridgeBytesFrom(<String, Object?>{}), isNull);
    });
  });

  group('outbound framing', () {
    test('wraps a CXP envelope in the frame the host routes on', () {
      const envelope = CxpEnvelope(
        messageId: 'wc-0',
        from: kHostBridgePeerId,
        kind: CxpMessageKind.notifySelection,
        payload: <String, Object?>{'elements': <Object?>[]},
      );
      final frame = hostBridgeCxpFrame(envelope);
      expect(frame['type'], kHostBridgeCxpFrameType);
      expect(frame['protocol'], kHostBridgeProtocolVersion);
      expect(
        (frame['envelope']! as Map<String, Object?>)['from'],
        kHostBridgePeerId,
      );
      // Encodable — the frame is structured-cloned or JSON-serialized on its
      // way to the host, and a value that will not encode is dropped silently.
      expect(() => jsonEncode(frame), returnsNormally);
    });

    test('a telemetry frame carries the descriptor and nothing else', () {
      final frame = hostBridgeTelemetryFrame(
        TelemetryEvent(
          'file.opened',
          properties: const <String, Object?>{'format': 'vcd'},
          timestamp: DateTime.utc(2026, 8, 9),
        ),
      );
      expect(frame['type'], kHostBridgeTelemetryFrameType);
      final event = frame['event']! as Map<String, Object?>;
      expect(event['name'], 'file.opened');
      expect(event['properties'], <String, Object?>{'format': 'vcd'});
      // The envelope — installation_id, os, form_factor, license tier — is
      // host-core's to assemble. A webview never constructs one, which is what
      // makes those fields unspoofable from here.
      expect(event.keys, unorderedEquals(<String>['name', 'properties']));
      // The timestamp ages `crux_telemetry`'s queue and is never transmitted;
      // per-event client timestamps amount to an interaction sequence.
      expect(event.containsKey('timestamp'), isFalse);
    });

    test('an event with no properties omits the key entirely', () {
      final frame = hostBridgeTelemetryFrame(TelemetryEvent('app.launched'));
      expect(
        (frame['event']! as Map<String, Object?>).keys,
        <String>['name'],
      );
    });
  });

  group('HostBridgeOpenWaveform round-trips', () {
    test('toJson emits base64 that tryFromJson reads back', () {
      final bytes = Uint8List.fromList(<int>[0, 255, 128, 7]);
      final message = HostBridgeOpenWaveform(
        displayName: 'a.vcd',
        bytes: bytes,
      );
      final decoded = HostBridgeOpenWaveform.tryFromJson(message.toJson());
      expect(decoded!.displayName, 'a.vcd');
      expect(decoded.bytes, bytes);
    });

    test('refuses an empty display name', () {
      expect(
        HostBridgeOpenWaveform.tryFromJson(<String, Object?>{
          'display_name': '',
          'bytes_base64': base64Encode(<int>[1]),
        }),
        isNull,
      );
    });
  });

  group('HostBridgeThemeTokens decoding', () {
    test("names the kind and appearance set crux-vscode's shim posts", () {
      expect(kHostBridgeThemeKind, 'crux.theme_tokens');
      expect(kHostBridgeThemeAppearances, <String>{
        'light',
        'dark',
        'highContrast',
        'highContrastLight',
      });
    });

    test('decodes through the frame decoder like any other kind', () {
      final inbound = decodeHostBridgeFrame(
        frameOf(kHostBridgeThemeKind, <String, Object?>{
          'appearance': 'dark',
          'tokens': <String, Object?>{
            'editor.background': '#1E1E1E',
            'editor.foreground': '#D4D4D4',
          },
        }),
      );
      final message = inbound!.message as HostBridgeThemeTokens;
      expect(message.appearance, 'dark');
      expect(message.tokens, <String, String>{
        'editor.background': '#1E1E1E',
        'editor.foreground': '#D4D4D4',
      });
    });

    test('toJson round-trips through tryFromJson', () {
      const message = HostBridgeThemeTokens(
        appearance: 'light',
        tokens: <String, String>{'editor.background': '#FFFFFF'},
      );
      final decoded = HostBridgeThemeTokens.tryFromJson(message.toJson());
      expect(decoded, message);
    });

    test('refuses an appearance outside vscode.ColorThemeKind', () {
      expect(
        HostBridgeThemeTokens.tryFromJson(<String, Object?>{
          'appearance': 'solarized', // not a real ColorThemeKind
          'tokens': <String, Object?>{},
        }),
        isNull,
      );
    });

    test('refuses a missing or non-map tokens field', () {
      expect(
        HostBridgeThemeTokens.tryFromJson(<String, Object?>{
          'appearance': 'dark',
        }),
        isNull,
      );
      expect(
        HostBridgeThemeTokens.tryFromJson(<String, Object?>{
          'appearance': 'dark',
          'tokens': 'not a map',
        }),
        isNull,
      );
    });

    test('refuses a token map over the receiver cap whole', () {
      final tooMany = <String, Object?>{
        for (var i = 0; i < kHostBridgeMaxThemeTokens + 1; i++)
          'token.$i': '#000000',
      };
      expect(
        HostBridgeThemeTokens.tryFromJson(<String, Object?>{
          'appearance': 'dark',
          'tokens': tooMany,
        }),
        isNull,
      );
    });

    test(
      'drops one unparseable token value rather than refusing the frame',
      () {
        // A future VSCode color id this build doesn't expect the shape of
        // must not blank out every token that did parse.
        final message = HostBridgeThemeTokens.tryFromJson(<String, Object?>{
          'appearance': 'dark',
          'tokens': <String, Object?>{
            'editor.background': '#1E1E1E',
            'some.futureToken': 12345, // not a string at all
            'another.token': '', // empty string
          },
        });
        expect(message!.tokens, <String, String>{
          'editor.background': '#1E1E1E',
        });
      },
    );
  });

  group('HostBridgeHostSession decoding', () {
    test("names the kind crux-vscode's host-session.ts posts", () {
      // Renaming one side only is silent — the receiver answers
      // `unknown_kind`, the session provider keeps its conservative default,
      // and the capability nudge simply never fires. Both sides pin the literal.
      expect(kHostBridgeHostSessionKind, 'crux.host_session');
    });

    test('decodes through the frame decoder like any other kind', () {
      final inbound = decodeHostBridgeFrame(
        frameOf(kHostBridgeHostSessionKind, <String, Object?>{
          'opened_file_before': true,
        }),
      );
      final message = inbound!.message as HostBridgeHostSession;
      expect(message.openedFileBefore, isTrue);
    });

    test('toJson round-trips through tryFromJson', () {
      const message = HostBridgeHostSession(openedFileBefore: true);
      expect(HostBridgeHostSession.tryFromJson(message.toJson()), message);
    });

    test('refuses a missing flag', () {
      expect(
        HostBridgeHostSession.tryFromJson(const <String, Object?>{}),
        isNull,
      );
    });

    test('refuses a non-boolean flag rather than coercing it', () {
      // Coercion here would invent `true` — the one value that *enables* a
      // nudge — out of a malformed frame.
      for (final value in <Object?>['true', 1, <String>[], null]) {
        expect(
          HostBridgeHostSession.tryFromJson(<String, Object?>{
            'opened_file_before': value,
          }),
          isNull,
          reason: 'coerced $value',
        );
      }
    });
  });

  group('HostBridgeValueQuery decoding', () {
    test("names the kinds crux-vscode's value-query.ts uses", () {
      // The host correlates responses by `query_id`; a rename on one side
      // only leaves the extension silently un-annotated, so both sides pin
      // the literals.
      expect(kHostBridgeValueQueryKind, 'crux.value_query');
      expect(kHostBridgeValueResponseKind, 'crux.value_response');
    });

    test('decodes through the frame decoder like any other kind', () {
      final inbound = decodeHostBridgeFrame(
        frameOf(kHostBridgeValueQueryKind, <String, Object?>{
          'query_id': 'q7',
          'paths': <Object?>['top.cpu.alu.result', 'top.clk'],
        }),
      );
      final message = inbound!.message as HostBridgeValueQuery;
      expect(message.queryId, 'q7');
      expect(message.paths, <String>['top.cpu.alu.result', 'top.clk']);
    });

    test('toJson round-trips through tryFromJson', () {
      const message = HostBridgeValueQuery(
        queryId: 'q7',
        paths: <String>['top.a', 'top.b'],
      );
      expect(HostBridgeValueQuery.tryFromJson(message.toJson()), message);
    });

    test('accepts an empty path list — that is how the host cancels', () {
      final message = HostBridgeValueQuery.tryFromJson(<String, Object?>{
        'query_id': 'q7',
        'paths': <Object?>[],
      });
      expect(message, isNotNull);
      expect(message!.paths, isEmpty);
    });

    test('drops a bad entry rather than failing the whole viewport', () {
      final message = HostBridgeValueQuery.tryFromJson(<String, Object?>{
        'query_id': 'q7',
        'paths': <Object?>['top.a', 42, '', '  ', 'top.a', 'top.b'],
      });
      // One unresolvable line must not cost the other thirty-nine their
      // annotations; duplicates are collapsed so the app samples each path
      // once.
      expect(message!.paths, <String>['top.a', 'top.b']);
    });

    test('refuses a missing or empty query id', () {
      for (final value in <Object?>[null, '', 7, <String>[]]) {
        expect(
          HostBridgeValueQuery.tryFromJson(<String, Object?>{
            'query_id': value,
            'paths': <Object?>['top.a'],
          }),
          isNull,
          reason: 'accepted $value',
        );
      }
    });

    test('refuses more paths than the cap, before any work starts', () {
      final paths = <Object?>[
        for (var i = 0; i <= kHostBridgeMaxValueQueryPaths; i++) 'top.s$i',
      ];
      expect(
        HostBridgeValueQuery.tryFromJson(<String, Object?>{
          'query_id': 'q7',
          'paths': paths,
        }),
        isNull,
      );
    });

    test('refuses a non-list paths field', () {
      expect(
        HostBridgeValueQuery.tryFromJson(<String, Object?>{
          'query_id': 'q7',
          'paths': 'top.a',
        }),
        isNull,
      );
    });

    test('the response carries values, the query id and the cursor label', () {
      const response = HostBridgeValueResponse(
        queryId: 'q7',
        values: <String, String>{'top.a': "8'hff"},
        cursorLabel: '15 ns',
      );
      expect(response.kind, kHostBridgeValueResponseKind);
      expect(response.toJson(), <String, Object?>{
        'query_id': 'q7',
        'values': <String, Object?>{'top.a': "8'hff"},
        'cursor_label': '15 ns',
      });
    });

    test('the response omits an absent cursor label', () {
      const response = HostBridgeValueResponse(
        queryId: 'q7',
        values: <String, String>{},
      );
      expect(response.toJson().containsKey('cursor_label'), isFalse);
    });
  });

  group('HostBridgeOpenWaveformChunk decoding', () {
    Map<String, Object?> chunkJson({
      String transferId = 't1',
      int index = 0,
      int count = 2,
      String displayName = 'big.fst',
      int totalBytes = 8,
      List<int> bytes = const <int>[1, 2, 3, 4],
    }) => <String, Object?>{
      'transfer_id': transferId,
      'index': index,
      'count': count,
      'display_name': displayName,
      'total_bytes': totalBytes,
      'bytes': Uint8List.fromList(bytes),
    };

    test('names the kind crux-vscode posts', () {
      // `OPEN_WAVEFORM_CHUNK_KIND` in
      // packages/wavecrux/src/webview/open-waveform.ts.
      expect(kHostBridgeOpenWaveformChunkKind, 'crux.open_waveform_chunk');
    });

    test('decodes through the frame decoder like any other kind', () {
      final inbound = decodeHostBridgeFrame(
        frameOf(kHostBridgeOpenWaveformChunkKind, chunkJson()),
      );
      final message = inbound!.message as HostBridgeOpenWaveformChunk;
      expect(message.transferId, 't1');
      expect(message.index, 0);
      expect(message.count, 2);
      expect(message.totalBytes, 8);
      expect(message.isLast, isFalse);
    });

    test('accepts base64 as readily as a structured-clone buffer', () {
      final json = chunkJson()..remove('bytes');
      json['bytes_base64'] = base64Encode(<int>[1, 2, 3, 4]);
      final message = HostBridgeOpenWaveformChunk.tryFromJson(json);
      expect(message!.bytes, Uint8List.fromList(<int>[1, 2, 3, 4]));
    });

    test('refuses an index outside its own count', () {
      expect(
        HostBridgeOpenWaveformChunk.tryFromJson(chunkJson(index: 2)),
        isNull,
      );
      expect(
        HostBridgeOpenWaveformChunk.tryFromJson(chunkJson(index: -1)),
        isNull,
      );
    });

    test('refuses a count outside the receiver-side limit', () {
      expect(
        HostBridgeOpenWaveformChunk.tryFromJson(chunkJson(count: 0)),
        isNull,
      );
      expect(
        HostBridgeOpenWaveformChunk.tryFromJson(
          chunkJson(count: kHostBridgeMaxChunksPerTransfer + 1),
        ),
        isNull,
      );
    });

    test(
      'refuses a declared total over the cap, before buffering anything',
      () {
        expect(
          HostBridgeOpenWaveformChunk.tryFromJson(
            chunkJson(totalBytes: 9),
            maxBytes: 8,
          ),
          isNull,
        );
        expect(
          HostBridgeOpenWaveformChunk.tryFromJson(chunkJson(totalBytes: 0)),
          isNull,
        );
      },
    );

    test('refuses a chunk claiming more bytes than the whole transfer', () {
      expect(
        HostBridgeOpenWaveformChunk.tryFromJson(
          chunkJson(totalBytes: 2, bytes: <int>[1, 2, 3, 4]),
        ),
        isNull,
      );
    });

    test('refuses a transfer id that is empty or unbounded', () {
      expect(
        HostBridgeOpenWaveformChunk.tryFromJson(chunkJson(transferId: '')),
        isNull,
      );
      expect(
        HostBridgeOpenWaveformChunk.tryFromJson(
          chunkJson(
            transferId:
                'x' * (HostBridgeOpenWaveformChunk.maxTransferIdLength + 1),
          ),
        ),
        isNull,
      );
    });

    test('refuses an empty display name and a missing field', () {
      expect(
        HostBridgeOpenWaveformChunk.tryFromJson(chunkJson(displayName: '')),
        isNull,
      );
      expect(
        HostBridgeOpenWaveformChunk.tryFromJson(
          chunkJson()..remove('total_bytes'),
        ),
        isNull,
      );
    });

    test('round-trips through toJson', () {
      final message = HostBridgeOpenWaveformChunk.tryFromJson(chunkJson())!;
      final decoded = HostBridgeOpenWaveformChunk.tryFromJson(
        message.toJson(),
      )!;
      expect(decoded.transferId, message.transferId);
      expect(decoded.bytes, message.bytes);
      expect(decoded.totalBytes, message.totalBytes);
    });
  });

  group('HostBridgeTransferAssembler', () {
    HostBridgeOpenWaveformChunk chunk({
      required int index,
      required int count,
      required int totalBytes,
      required List<int> bytes,
      String transferId = 't1',
      String displayName = 'big.fst',
    }) => HostBridgeOpenWaveformChunk(
      transferId: transferId,
      index: index,
      count: count,
      displayName: displayName,
      totalBytes: totalBytes,
      bytes: Uint8List.fromList(bytes),
    );

    test('reassembles a transfer into one open-waveform message', () {
      final assembler = HostBridgeTransferAssembler();
      final first = assembler.accept(
        chunk(index: 0, count: 2, totalBytes: 6, bytes: <int>[1, 2, 3]),
      );
      expect(first.state, HostBridgeTransferState.accepted);
      expect(assembler.openTransferCount, 1);
      expect(assembler.bufferedBytes, 3);

      final second = assembler.accept(
        chunk(index: 1, count: 2, totalBytes: 6, bytes: <int>[4, 5, 6]),
      );
      expect(second.state, HostBridgeTransferState.completed);
      expect(second.waveform!.displayName, 'big.fst');
      expect(
        second.waveform!.bytes,
        Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6]),
      );
      // Nothing is retained once the waveform is handed over.
      expect(assembler.openTransferCount, 0);
      expect(assembler.bufferedBytes, 0);
    });

    test('completes a one-chunk transfer without ceremony', () {
      final assembler = HostBridgeTransferAssembler();
      final result = assembler.accept(
        chunk(index: 0, count: 1, totalBytes: 2, bytes: <int>[7, 8]),
      );
      expect(result.state, HostBridgeTransferState.completed);
      expect(result.waveform!.bytes, Uint8List.fromList(<int>[7, 8]));
    });

    test(
      'rejects a chunk that arrives out of order, and drops the transfer',
      () {
        // postMessage preserves order, so a gap means this is not the stream
        // being reassembled. Holding it open would be a leak with no timer to
        // collect it.
        final assembler = HostBridgeTransferAssembler()
          ..accept(
            chunk(index: 0, count: 3, totalBytes: 9, bytes: <int>[1, 2, 3]),
          );
        final result = assembler.accept(
          chunk(index: 2, count: 3, totalBytes: 9, bytes: <int>[7, 8, 9]),
        );
        expect(result.state, HostBridgeTransferState.rejected);
        expect(result.reason, contains('out of order'));
        expect(assembler.openTransferCount, 0);
      },
    );

    test('rejects a chunk for a transfer it never saw start', () {
      final assembler = HostBridgeTransferAssembler();
      final result = assembler.accept(
        chunk(index: 1, count: 2, totalBytes: 4, bytes: <int>[3, 4]),
      );
      expect(result.state, HostBridgeTransferState.rejected);
      expect(result.reason, contains('before its transfer'));
    });

    test('rejects a chunk that disagrees with its own transfer', () {
      final assembler = HostBridgeTransferAssembler()
        ..accept(
          chunk(index: 0, count: 2, totalBytes: 6, bytes: <int>[1, 2, 3]),
        );
      final result = assembler.accept(
        chunk(
          index: 1,
          count: 2,
          totalBytes: 6,
          displayName: 'other.fst',
          bytes: <int>[4, 5, 6],
        ),
      );
      expect(result.state, HostBridgeTransferState.rejected);
      expect(result.reason, contains('disagrees'));
    });

    test('rejects a transfer that overruns its declared length', () {
      final assembler = HostBridgeTransferAssembler()
        ..accept(
          chunk(index: 0, count: 2, totalBytes: 4, bytes: <int>[1, 2, 3]),
        );
      final result = assembler.accept(
        chunk(index: 1, count: 2, totalBytes: 4, bytes: <int>[4, 5]),
      );
      expect(result.state, HostBridgeTransferState.rejected);
      expect(result.reason, contains('overran'));
      expect(assembler.openTransferCount, 0);
    });

    test('rejects a transfer that ends short of its declared length', () {
      // Half a waveform is not a smaller waveform; it is a corrupt one.
      final assembler = HostBridgeTransferAssembler()
        ..accept(
          chunk(index: 0, count: 2, totalBytes: 6, bytes: <int>[1, 2, 3]),
        );
      final result = assembler.accept(
        chunk(index: 1, count: 2, totalBytes: 6, bytes: <int>[4, 5]),
      );
      expect(result.state, HostBridgeTransferState.rejected);
      expect(result.reason, contains('short'));
    });

    test('refuses a transfer whose declared total is over the cap', () {
      final assembler = HostBridgeTransferAssembler(maxBytes: 8);
      final result = assembler.accept(
        chunk(index: 0, count: 1, totalBytes: 9, bytes: <int>[1]),
      );
      expect(result.state, HostBridgeTransferState.rejected);
      expect(result.reason, contains('byte cap'));
      expect(assembler.bufferedBytes, 0);
    });

    test('bounds the total buffered across concurrent transfers', () {
      // A host must not be able to open two transfers and hold twice the cap.
      final assembler = HostBridgeTransferAssembler(maxBytes: 10)
        ..accept(
          chunk(
            transferId: 'a',
            index: 0,
            count: 2,
            totalBytes: 8,
            bytes: <int>[1, 2, 3, 4],
          ),
        );
      final second = assembler.accept(
        chunk(
          transferId: 'b',
          index: 0,
          count: 2,
          totalBytes: 8,
          bytes: <int>[1, 2, 3, 4],
        ),
      );
      expect(second.state, HostBridgeTransferState.rejected);
      expect(second.reason, contains('total buffered cap'));
      expect(assembler.bufferedBytes, 4);
    });

    test(
      'evicts the least-recently-touched transfer past the concurrency cap',
      () {
        // An abandoned transfer — a webview reloaded mid-stream — has no other
        // way to be collected.
        final assembler = HostBridgeTransferAssembler();
        for (final id in <String>['a', 'b', 'c']) {
          assembler.accept(
            chunk(
              transferId: id,
              index: 0,
              count: 2,
              totalBytes: 4,
              bytes: <int>[1, 2],
            ),
          );
        }
        expect(assembler.openTransferCount, kHostBridgeMaxConcurrentTransfers);
        // 'a' is gone: its continuation is now a chunk for an unknown transfer.
        final continued = assembler.accept(
          chunk(
            transferId: 'a',
            index: 1,
            count: 2,
            totalBytes: 4,
            bytes: <int>[3, 4],
          ),
        );
        expect(continued.state, HostBridgeTransferState.rejected);
        // 'c' is not.
        expect(
          assembler
              .accept(
                chunk(
                  transferId: 'c',
                  index: 1,
                  count: 2,
                  totalBytes: 4,
                  bytes: <int>[3, 4],
                ),
              )
              .state,
          HostBridgeTransferState.completed,
        );
      },
    );

    test('interleaves two transfers without blending them', () {
      final assembler = HostBridgeTransferAssembler()
        ..accept(
          chunk(
            transferId: 'a',
            index: 0,
            count: 2,
            totalBytes: 4,
            bytes: <int>[1, 2],
          ),
        )
        ..accept(
          chunk(
            transferId: 'b',
            index: 0,
            count: 2,
            totalBytes: 4,
            bytes: <int>[9, 9],
          ),
        );
      final a = assembler.accept(
        chunk(
          transferId: 'a',
          index: 1,
          count: 2,
          totalBytes: 4,
          bytes: <int>[3, 4],
        ),
      );
      expect(a.waveform!.bytes, Uint8List.fromList(<int>[1, 2, 3, 4]));
      final b = assembler.accept(
        chunk(
          transferId: 'b',
          index: 1,
          count: 2,
          totalBytes: 4,
          bytes: <int>[8, 8],
        ),
      );
      expect(b.waveform!.bytes, Uint8List.fromList(<int>[9, 9, 8, 8]));
    });

    test('clear() releases every open transfer', () {
      final assembler = HostBridgeTransferAssembler()
        ..accept(chunk(index: 0, count: 2, totalBytes: 4, bytes: <int>[1, 2]));
      expect(assembler.bufferedBytes, 2);
      assembler.clear();
      expect(assembler.openTransferCount, 0);
      expect(assembler.bufferedBytes, 0);
    });
  });
}
