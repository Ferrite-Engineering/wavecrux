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
/// Protocol violations detected:
/// - Second write address (AW) while a write is already outstanding.
/// - Second read address (AR) while a read is already outstanding.
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

    // Write-side state.
    _AwPhase? pendingAw; // AW handshake captured, waiting for W and B.
    _WPhase? pendingW; // W handshake captured (may precede AW).
    var writeOutstanding = false; // true from AW handshake until B handshake.

    // Read-side state.
    _ArPhase? pendingAr; // AR handshake captured, waiting for R.
    var readOutstanding = false;

    for (final (edgeTime, edgeVal) in clkChanges) {
      if (!isVcdHigh(edgeVal)) continue; // only rising edges

      // During reset: clear any in-flight state and skip channel processing.
      if (!isVcdHigh(query('aresetn', edgeTime))) {
        pendingAw = null;
        pendingW = null;
        writeOutstanding = false;
        pendingAr = null;
        readOutstanding = false;
        continue;
      }

      // ── AW channel ────────────────────────────────────────────────────────
      if (isVcdHigh(query('awvalid', edgeTime)) &&
          isVcdHigh(query('awready', edgeTime))) {
        if (writeOutstanding) {
          transactions.add(
            _makeViolation(
              edgeTime,
              edgeTime,
              'AXI4-Lite violation: new write address while write outstanding',
            ),
          );
        } else {
          pendingAw = _AwPhase(
            startTime: edgeTime,
            addr: parseVcdVectorInt(query('awaddr', edgeTime)),
            prot: parseVcdVectorInt(query('awprot', edgeTime)),
          );
          writeOutstanding = true;
        }
      }

      // ── W channel ─────────────────────────────────────────────────────────
      if (isVcdHigh(query('wvalid', edgeTime)) &&
          isVcdHigh(query('wready', edgeTime))) {
        pendingW = _WPhase(
          captureTime: edgeTime,
          data: parseVcdVectorInt(query('wdata', edgeTime)),
          strb: parseVcdVectorInt(query('wstrb', edgeTime)),
        );
      }

      // ── B channel ─────────────────────────────────────────────────────────
      if (isVcdHigh(query('bvalid', edgeTime)) &&
          isVcdHigh(query('bready', edgeTime))) {
        if (pendingAw == null || pendingW == null) {
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

          final aw = pendingAw;
          final w = pendingW;
          final hasWstrb =
              w.strb != null && _config.signalBindings.containsKey('wstrb');

          transactions.add(
            DecodedTransaction(
              startTime: aw.startTime,
              endTime: edgeTime,
              label: 'W ${_fmtAddr(aw.addr)} = ${_fmtData(w.data)} [$respCode]',
              fields: {
                'type': 'Write',
                'address': _fmtAddr(aw.addr),
                'data': _fmtData(w.data),
                'response': respCode,
                if (hasWstrb) 'wstrb': _fmtStrobe(w.strb),
              },
              isError: errors.isNotEmpty,
              errorMessage: errors.isNotEmpty ? errors.join('; ') : null,
            ),
          );

          pendingAw = null;
          pendingW = null;
          writeOutstanding = false;
        }
      }

      // ── AR channel ────────────────────────────────────────────────────────
      if (isVcdHigh(query('arvalid', edgeTime)) &&
          isVcdHigh(query('arready', edgeTime))) {
        if (readOutstanding) {
          transactions.add(
            _makeViolation(
              edgeTime,
              edgeTime,
              'AXI4-Lite violation: new read address while read outstanding',
            ),
          );
        } else {
          pendingAr = _ArPhase(
            startTime: edgeTime,
            addr: parseVcdVectorInt(query('araddr', edgeTime)),
            prot: parseVcdVectorInt(query('arprot', edgeTime)),
          );
          readOutstanding = true;
        }
      }

      // ── R channel ─────────────────────────────────────────────────────────
      if (isVcdHigh(query('rvalid', edgeTime)) &&
          isVcdHigh(query('rready', edgeTime))) {
        if (pendingAr == null) {
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

          final ar = pendingAr;
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

          pendingAr = null;
          readOutstanding = false;
        }
      }
    }

    return transactions;
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
