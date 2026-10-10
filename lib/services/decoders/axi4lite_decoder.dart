// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/enums/decoder_category.dart';
import 'package:wavecrux/domain/enums/decoder_parameter_type.dart';
import 'package:wavecrux/domain/interfaces/protocol_decoder.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/domain/models/decoder_parameter.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/services/decoders/decoder_value_helpers.dart';

/// Decodes AXI4-Lite bus transactions.
///
/// Tracks the five AXI4-Lite channels (AW, W, B, AR, R) and groups
/// channel handshakes into complete write and read transactions.
///
/// A handshake occurs on the rising edge of ACLK when both VALID and READY
/// are high. Write transactions require AW + W + B channel handshakes (AW and
/// W may occur in any order relative to each other). Read transactions require
/// AR + R channel handshakes.
///
/// AXI4-Lite allows several outstanding transactions per direction, answered
/// in order. AW addresses, W beats and AR addresses are therefore queued, and
/// each B completes the oldest AW with the oldest W, each R the oldest AR.
/// Writes and reads still waiting for a response at the end of the trace are
/// listed as unanswered rows ending at the last clock edge.
///
/// Protocol violations detected:
/// - Write response (B) without a prior AW + W handshake (orphan response).
/// - Read data (R) without a prior AR handshake (orphan response).
/// - EXOKAY response code, which is not valid in AXI4-Lite.
class Axi4LiteDecoder implements ProtocolDecoder {
  /// Creates an [Axi4LiteDecoder] bound to [config].
  const Axi4LiteDecoder(this._config);

  final DecoderConfig _config;

  // ── static definition ──────────────────────────────────────────────────────

  /// Static metadata registered with [DecoderRegistry] at app startup.
  static const decoderDefinition = DecoderDefinition(
    id: 'axi4_lite',
    displayName: 'AXI4-Lite',
    description:
        'Decodes AXI4-Lite bus transactions (write and read channels).',
    category: DecoderCategory.amba,
    requiredSignals: [
      SignalBinding(name: 'aclk', description: 'AXI clock', bitWidth: 1),
      SignalBinding(
        name: 'aresetn',
        description: 'AXI active-low synchronous reset',
        bitWidth: 1,
      ),
      SignalBinding(
        name: 'awaddr',
        description: 'Write address channel: address',
        bitWidth: 32,
      ),
      SignalBinding(
        name: 'awvalid',
        description: 'Write address channel: valid',
        bitWidth: 1,
      ),
      SignalBinding(
        name: 'awready',
        description: 'Write address channel: ready',
        bitWidth: 1,
      ),
      SignalBinding(
        name: 'wdata',
        description: 'Write data channel: data',
        bitWidth: 32,
      ),
      SignalBinding(
        name: 'wvalid',
        description: 'Write data channel: valid',
        bitWidth: 1,
      ),
      SignalBinding(
        name: 'wready',
        description: 'Write data channel: ready',
        bitWidth: 1,
      ),
      SignalBinding(
        name: 'bresp',
        description: 'Write response channel: response code',
        bitWidth: 2,
      ),
      SignalBinding(
        name: 'bvalid',
        description: 'Write response channel: valid',
        bitWidth: 1,
      ),
      SignalBinding(
        name: 'bready',
        description: 'Write response channel: ready',
        bitWidth: 1,
      ),
      SignalBinding(
        name: 'araddr',
        description: 'Read address channel: address',
        bitWidth: 32,
      ),
      SignalBinding(
        name: 'arvalid',
        description: 'Read address channel: valid',
        bitWidth: 1,
      ),
      SignalBinding(
        name: 'arready',
        description: 'Read address channel: ready',
        bitWidth: 1,
      ),
      SignalBinding(
        name: 'rdata',
        description: 'Read data channel: data',
        bitWidth: 32,
      ),
      SignalBinding(
        name: 'rresp',
        description: 'Read data channel: response code',
        bitWidth: 2,
      ),
      SignalBinding(
        name: 'rvalid',
        description: 'Read data channel: valid',
        bitWidth: 1,
      ),
      SignalBinding(
        name: 'rready',
        description: 'Read data channel: ready',
        bitWidth: 1,
      ),
    ],
    optionalSignals: [
      SignalBinding(
        name: 'awprot',
        description: 'Write address channel: protection type',
        bitWidth: 3,
      ),
      SignalBinding(
        name: 'arprot',
        description: 'Read address channel: protection type',
        bitWidth: 3,
      ),
      SignalBinding(
        name: 'wstrb',
        description: 'Write data channel: byte strobe (write enable per byte)',
        bitWidth: 4,
      ),
    ],
    parameters: [
      DecoderParameter(
        name: 'addr_width',
        displayName: 'Address Width',
        type: DecoderParameterType.integer,
        defaultValue: 32,
        description: 'Address bus width in bits',
      ),
      DecoderParameter(
        name: 'data_width',
        displayName: 'Data Width',
        type: DecoderParameterType.integer,
        defaultValue: 32,
        description: 'Data bus width in bits',
      ),
    ],
  );

  @override
  DecoderDefinition get definition => Axi4LiteDecoder.decoderDefinition;

  // ── decode ─────────────────────────────────────────────────────────────────

  @override
  List<DecodedTransaction> decode(
    int startTime,
    int endTime,
    SignalValueQuery query,
    SignalChangesQuery changesQuery, {
    Timescale? timescale,
  }) {
    final clkChanges = changesQuery('aclk', startTime, endTime);
    if (clkChanges.isEmpty) return [];

    final transactions = <DecodedTransaction>[];

    // Write-side state: AW addresses and W beats queue independently (W may
    // precede its AW); each B completes the oldest of each.
    final pendingAw = <_AwPhase>[];
    final pendingW = <_WPhase>[];

    // Read-side state: AR addresses waiting for R, oldest first.
    final pendingAr = <_ArPhase>[];

    var lastEdge = clkChanges.first.$1;

    for (final (edgeTime, edgeVal) in clkChanges) {
      if (!isVcdHigh(edgeVal)) continue; // only rising edges
      lastEdge = edgeTime;

      // During reset: clear any in-flight state and skip channel processing.
      if (!isVcdHigh(query('aresetn', edgeTime))) {
        pendingAw.clear();
        pendingW.clear();
        pendingAr.clear();
        continue;
      }

      // ── AW channel ────────────────────────────────────────────────────────
      if (isVcdHigh(query('awvalid', edgeTime)) &&
          isVcdHigh(query('awready', edgeTime))) {
        pendingAw.add(
          _AwPhase(
            startTime: edgeTime,
            addr: parseVcdVectorInt(query('awaddr', edgeTime)),
            prot: parseVcdVectorInt(query('awprot', edgeTime)),
          ),
        );
      }

      // ── W channel ─────────────────────────────────────────────────────────
      if (isVcdHigh(query('wvalid', edgeTime)) &&
          isVcdHigh(query('wready', edgeTime))) {
        pendingW.add(
          _WPhase(
            captureTime: edgeTime,
            data: parseVcdVectorInt(query('wdata', edgeTime)),
            strb: parseVcdVectorInt(query('wstrb', edgeTime)),
          ),
        );
      }

      // ── B channel ─────────────────────────────────────────────────────────
      if (isVcdHigh(query('bvalid', edgeTime)) &&
          isVcdHigh(query('bready', edgeTime))) {
        if (pendingAw.isEmpty || pendingW.isEmpty) {
          // A response before both halves of the write arrived. Whatever half
          // did arrive is consumed with it, so it is not also listed as
          // unanswered at the end of the trace.
          if (pendingAw.isNotEmpty) pendingAw.removeAt(0);
          if (pendingW.isNotEmpty) pendingW.removeAt(0);
          transactions.add(
            _makeViolation(
              edgeTime,
              edgeTime,
              'AXI4-Lite violation: write response without pending write '
              'transaction',
            ),
          );
        } else {
          final respCode = _respCode(
            parseVcdVectorInt(query('bresp', edgeTime)),
          );
          final isSlvErr = respCode == 'SLVERR' || respCode == 'DECERR';
          final isExokay = respCode == 'EXOKAY';

          final errors = <String>[
            if (isSlvErr) 'Response: $respCode',
            if (isExokay) 'AXI4-Lite violation: EXOKAY not valid in AXI4-Lite',
          ];

          final aw = pendingAw.removeAt(0);
          final w = pendingW.removeAt(0);

          transactions.add(
            _makeWrite(
              aw.startTime,
              edgeTime,
              aw.addr,
              w,
              respCode,
              errors,
            ),
          );
        }
      }

      // ── AR channel ────────────────────────────────────────────────────────
      if (isVcdHigh(query('arvalid', edgeTime)) &&
          isVcdHigh(query('arready', edgeTime))) {
        pendingAr.add(
          _ArPhase(
            startTime: edgeTime,
            addr: parseVcdVectorInt(query('araddr', edgeTime)),
            prot: parseVcdVectorInt(query('arprot', edgeTime)),
          ),
        );
      }

      // ── R channel ─────────────────────────────────────────────────────────
      if (isVcdHigh(query('rvalid', edgeTime)) &&
          isVcdHigh(query('rready', edgeTime))) {
        if (pendingAr.isEmpty) {
          transactions.add(
            _makeViolation(
              edgeTime,
              edgeTime,
              'AXI4-Lite violation: read data without pending read transaction',
            ),
          );
        } else {
          final respCode = _respCode(
            parseVcdVectorInt(query('rresp', edgeTime)),
          );
          final isSlvErr = respCode == 'SLVERR' || respCode == 'DECERR';
          final isExokay = respCode == 'EXOKAY';

          final errors = <String>[
            if (isSlvErr) 'Response: $respCode',
            if (isExokay) 'AXI4-Lite violation: EXOKAY not valid in AXI4-Lite',
          ];

          final ar = pendingAr.removeAt(0);
          final rdata = parseVcdVectorInt(query('rdata', edgeTime));

          transactions.add(
            DecodedTransaction(
              startTime: ar.startTime,
              endTime: edgeTime,
              label: 'R ${_fmtAddr(ar.addr)} = ${_fmtData(rdata)} [$respCode]',
              fields: {
                'type': 'Read',
                'address': _fmtAddr(ar.addr),
                'data': _fmtData(rdata),
                'response': respCode,
              },
              isError: errors.isNotEmpty,
              errorMessage: errors.isNotEmpty ? errors.join('; ') : null,
            ),
          );
        }
      }
    }

    // ── unanswered at end of trace ─────────────────────────────────────────
    // A write is listed from whichever of its AW or W arrived first; a W beat
    // with no AW yet has no address, and an AW with no W has no data.
    final unansweredWrites = pendingAw.length > pendingW.length
        ? pendingAw.length
        : pendingW.length;
    for (var i = 0; i < unansweredWrites; i++) {
      final aw = i < pendingAw.length ? pendingAw[i] : null;
      final w = i < pendingW.length ? pendingW[i] : null;
      final start = switch ((aw, w)) {
        (final a?, final b?) =>
          a.startTime < b.captureTime ? a.startTime : b.captureTime,
        (final a?, null) => a.startTime,
        (null, final b?) => b.captureTime,
        (null, null) => lastEdge,
      };
      transactions.add(
        _makeWrite(start, lastEdge, aw?.addr, w, _kNoResponse, const []),
      );
    }
    for (final ar in pendingAr) {
      transactions.add(
        DecodedTransaction(
          startTime: ar.startTime,
          endTime: lastEdge,
          label: 'R ${_fmtAddr(ar.addr)} [$_kNoResponse]',
          fields: {
            'type': 'Read',
            'address': _fmtAddr(ar.addr),
            'response': _kNoResponse,
          },
        ),
      );
    }

    return transactions;
  }

  /// Response label for a write or read still waiting at the end of the trace.
  static const _kNoResponse = 'no response';

  DecodedTransaction _makeWrite(
    int startTime,
    int endTime,
    int? addr,
    _WPhase? w,
    String respCode,
    List<String> errors,
  ) {
    final hasWstrb =
        w?.strb != null && _config.signalBindings.containsKey('wstrb');
    final data = w == null ? '0x????????' : _fmtData(w.data);
    return DecodedTransaction(
      startTime: startTime,
      endTime: endTime,
      label: 'W ${_fmtAddr(addr)} = $data [$respCode]',
      fields: {
        'type': 'Write',
        'address': _fmtAddr(addr),
        'data': data,
        'response': respCode,
        if (hasWstrb) 'wstrb': _fmtStrobe(w?.strb),
      },
      isError: errors.isNotEmpty,
      errorMessage: errors.isNotEmpty ? errors.join('; ') : null,
    );
  }

  // ── private helpers ────────────────────────────────────────────────────────

  int get _addrWidth => intParam(_config.parameters, 'addr_width', 32);
  int get _dataWidth => intParam(_config.parameters, 'data_width', 32);

  String _fmtAddr(int? val) {
    if (val == null) return '0x????????';
    final nibbles = (_addrWidth + 3) >> 2;
    return '0x${val.toRadixString(16).toUpperCase().padLeft(nibbles, '0')}';
  }

  String _fmtData(int? val) {
    if (val == null) return '0x????????';
    final nibbles = (_dataWidth + 3) >> 2;
    return '0x${val.toRadixString(16).toUpperCase().padLeft(nibbles, '0')}';
  }

  String _fmtStrobe(int? val) {
    if (val == null) return '0x?';
    return '0x${val.toRadixString(16).toUpperCase()}';
  }

  /// Maps a 2-bit BRESP/RRESP integer to its AXI response name.
  String _respCode(int? val) {
    switch (val) {
      case 0:
        return 'OKAY';
      case 1:
        return 'EXOKAY';
      case 2:
        return 'SLVERR';
      case 3:
        return 'DECERR';
      default:
        return 'OKAY';
    }
  }

  DecodedTransaction _makeViolation(
    int startTime,
    int endTime,
    String message,
  ) => DecodedTransaction(
    startTime: startTime,
    endTime: endTime,
    label: 'AXI Violation',
    fields: {'error': message},
    isError: true,
    errorMessage: message,
  );
}

// ── internal phase records ─────────────────────────────────────────────────

class _AwPhase {
  const _AwPhase({required this.startTime, required this.addr, this.prot});
  final int startTime;
  final int? addr;
  final int? prot;
}

class _WPhase {
  const _WPhase({required this.captureTime, required this.data, this.strb});
  final int captureTime;
  final int? data;
  final int? strb;
}

class _ArPhase {
  const _ArPhase({required this.startTime, required this.addr, this.prot});
  final int startTime;
  final int? addr;
  final int? prot;
}
