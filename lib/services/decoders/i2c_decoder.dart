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

/// Decodes I²C (Inter-Integrated Circuit) bus transactions.
///
/// Detects START/STOP/repeated-START conditions from SDA and SCL, samples
/// data bits on SCL rising edges, and interprets the first byte as an address
/// frame (7-bit or 10-bit) followed by zero or more data bytes.
///
/// Each decoded transaction covers one START–STOP (or START–repeated-START)
/// boundary. [DecodedTransaction.isError] is set when an unexpected NACK is
/// detected:
///   - Address-phase NACK always signals an error (no device responded).
///   - Write data-byte NACK is an error (slave rejected the byte).
///   - Read final-byte NACK is **not** an error — it is the normal master
///     handshake for "I have received all the data I need, stop sending."
///   - Read non-final-byte NACK is an error (unexpected mid-stream abort).
class I2cDecoder implements ProtocolDecoder {
  /// Creates an [I2cDecoder] bound to [config].
  const I2cDecoder(this._config);

  final DecoderConfig _config;

  // ── static definition ──────────────────────────────────────────────────────

  /// Static metadata registered with [DecoderRegistry] at app startup.
  static const decoderDefinition = DecoderDefinition(
    id: 'i2c',
    displayName: 'I²C',
    description: 'Decodes I²C (Inter-Integrated Circuit) bus transactions.',
    category: DecoderCategory.serial,
    requiredSignals: [
      SignalBinding(
        name: 'sda',
        description: 'Serial Data line',
        bitWidth: 1,
      ),
      SignalBinding(
        name: 'scl',
        description: 'Serial Clock line',
        bitWidth: 1,
      ),
    ],
    parameters: [
      DecoderParameter(
        name: 'address_bits',
        displayName: 'Address Bits',
        labelKey: 'i2cParamAddressBits',
        descriptionKey: 'i2cParamAddressBitsDescription',
        type: DecoderParameterType.enumeration,
        defaultValue: '7',
        description: 'Address width in bits (7 = standard, 10 = extended)',
        enumValues: ['7', '10'],
        enumLabels: {'7': '7-bit (Standard)', '10': '10-bit (Extended)'},
        enumLabelKeys: {
          '7': 'i2cChoiceAddressBits7',
          '10': 'i2cChoiceAddressBits10',
        },
      ),
    ],
  );

  @override
  DecoderDefinition get definition => I2cDecoder.decoderDefinition;

  // ── decode ─────────────────────────────────────────────────────────────────

  @override
  List<DecodedTransaction> decode(
    int startTime,
    int endTime,
    SignalValueQuery query,
    SignalChangesQuery changesQuery, {
    Timescale? timescale,
  }) {
    final tenBit = (_config.parameters['address_bits'] ?? '7') == '10';

    // Merge SDA and SCL changes into a single sorted timeline.
    final sdaChanges = changesQuery('sda', startTime, endTime);
    final sclChanges = changesQuery('scl', startTime, endTime);

    if (sdaChanges.isEmpty && sclChanges.isEmpty) return [];

    // ── find START/STOP conditions ──────────────────────────────────────────
    // START: SDA falls while SCL is high.
    // STOP:  SDA rises while SCL is high.
    final events = _buildEvents(sdaChanges, sclChanges, query);
    if (events.isEmpty) return [];

    return _decodeEvents(
      events,
      query,
      changesQuery,
      tenBit,
      startTime,
      endTime,
    );
  }

  // ── private ────────────────────────────────────────────────────────────────

  /// Represents a decoded I²C bus condition.
  static const _start = 'START';
  static const _stop = 'STOP';
  static const _rstart = 'RSTART';

  List<_I2cEvent> _buildEvents(
    List<(int, String)> sdaChanges,
    List<(int, String)> sclChanges,
    SignalValueQuery query,
  ) {
    final events = <_I2cEvent>[];

    for (final (time, sdaVal) in sdaChanges) {
      final sclHigh = isVcdHigh(query('scl', time));
      if (!sclHigh) continue;

      if (isVcdLow(sdaVal)) {
        // SDA falling while SCL high → START (or repeated START)
        events.add(
          _I2cEvent(time: time, kind: events.isEmpty ? _start : _rstart),
        );
      } else if (isVcdHigh(sdaVal)) {
        // SDA rising while SCL high → STOP
        events.add(_I2cEvent(time: time, kind: _stop));
      }
    }
    return events;
  }

  List<DecodedTransaction> _decodeEvents(
    List<_I2cEvent> events,
    SignalValueQuery query,
    SignalChangesQuery changesQuery,
    bool tenBit,
    int rangeStart,
    int rangeEnd,
  ) {
    final transactions = <DecodedTransaction>[];

    for (var i = 0; i < events.length; i++) {
      final ev = events[i];
      if (ev.kind != _start && ev.kind != _rstart) continue;

      final txStart = ev.time;
      final txEnd = i + 1 < events.length ? events[i + 1].time : rangeEnd;
      final nextKind = i + 1 < events.length ? events[i + 1].kind : null;

      final tx = _decodeTransaction(
        txStart,
        txEnd,
        query,
        changesQuery,
        tenBit,
        missingStop: nextKind != _stop && nextKind != _rstart,
      );
      if (tx != null) transactions.add(tx);
    }
    return transactions;
  }

  DecodedTransaction? _decodeTransaction(
    int txStart,
    int txEnd,
    SignalValueQuery query,
    SignalChangesQuery changesQuery,
    bool tenBit, {
    required bool missingStop,
  }) {
    // Collect SCL rising edges in [txStart, txEnd) — each is a data sample.
    final sclChanges = changesQuery('scl', txStart, txEnd);
    final risingEdges = [
      for (final (t, v) in sclChanges)
        if (isVcdHigh(v)) t,
    ];
    if (risingEdges.isEmpty) return null;

    // Sample SDA at every rising SCL edge.
    final bits = risingEdges
        .map((t) => isVcdHigh(query('sda', t)) ? 1 : 0)
        .toList();
    if (bits.length < 9) {
      // Not enough bits for even a single byte + ACK.
      return _errorTransaction(
        txStart,
        txEnd,
        'Not enough bits: ${bits.length} (need ≥9)',
      );
    }

    // ── parse address byte ──────────────────────────────────────────────────
    final String address;
    final String rw;
    int bitIndex;

    if (tenBit) {
      if (bits.length < 18) {
        return _errorTransaction(
          txStart,
          txEnd,
          '10-bit address needs ≥18 bits, got ${bits.length}',
        );
      }
      // First byte: 11110xx0 (upper 2 bits of address + W), then ACK, then lower 8 bits, then ACK.
      final addrHigh =
          ((bits[5] & 1) << 1) | (bits[6] & 1); // bits 5..6 of first byte
      final rwBit = bits[7]; // bit 7 of first byte (0=write for address phase)
      final ackByte1 = bits[8]; // 9th bit
      final addrLow = _collectByte(bits, 9);
      final ackByte2 = bits[17];
      final addr10 = (addrHigh << 8) | addrLow;
      address = '0x${addr10.toRadixString(16).toUpperCase().padLeft(3, '0')}';
      rw = rwBit == 0 ? 'W' : 'R';
      final ack1 = ackByte1 == 0;
      final ack2 = ackByte2 == 0;
      bitIndex = 18;
      if (!ack1 || !ack2) {
        return DecodedTransaction(
          startTime: txStart,
          endTime: txEnd,
          label: 'I²C $address NACK',
          fields: {
            'address': address,
            'rw': rw,
            'ack': ack1 && ack2 ? 'ACK' : 'NACK',
          },
          isError: true,
          errorMessage: 'Address phase NACK',
        );
      }
    } else {
      // 7-bit: first 7 bits = address, bit 7 = R/W, bit 8 = ACK.
      final addr7 = _collectByte(bits, 0) >> 1; // upper 7 bits
      final rwBit = bits[7];
      rw = rwBit == 0 ? 'W' : 'R';
      address = '0x${addr7.toRadixString(16).toUpperCase().padLeft(2, '0')}';
      final ackAddr = bits[8] == 0;
      if (!ackAddr) {
        return DecodedTransaction(
          startTime: txStart,
          endTime: txEnd,
          label: 'I²C $address $rw NACK',
          fields: {'address': address, 'rw': rw, 'ack': 'NACK'},
          isError: true,
          errorMessage: 'Address phase NACK',
        );
      }
      bitIndex = 9; // skip address byte + ACK
    }

    // ── parse data bytes ────────────────────────────────────────────────────
    final dataBytes = <int>[];
    final ackList = <bool>[];

    while (bitIndex + 8 <= bits.length) {
      final byte = _collectByte(bits, bitIndex);
      dataBytes.add(byte);
      bitIndex += 8;
      final ack = bitIndex >= bits.length || bits[bitIndex] == 0;
      ackList.add(ack);
      bitIndex++; // consume ACK bit
    }

    // For writes: any data-byte NACK is an error (slave rejecting the byte).
    // For reads: a NACK on the *final* data byte is the normal master-terminates
    // handshake — only NACKs before the final byte are protocol errors.
    final isRead = rw == 'R';
    final hasNack = isRead && ackList.isNotEmpty
        ? ackList.sublist(0, ackList.length - 1).any((a) => !a)
        : ackList.any((a) => !a);

    final dataHex = dataBytes
        .map((b) => '0x${b.toRadixString(16).toUpperCase().padLeft(2, '0')}')
        .join(' ');
    final ackStr = ackList.map((a) => a ? 'ACK' : 'NACK').join(' ');

    final errors = <String>[
      if (hasNack) 'NACK received',
      if (missingStop) 'Missing STOP condition',
    ];

    final label = dataBytes.isEmpty
        ? 'I²C $address $rw'
        : 'I²C $address $rw ${dataBytes.length == 1 ? dataHex : '${dataBytes.length} bytes'}';

    return DecodedTransaction(
      startTime: txStart,
      endTime: txEnd,
      label: label,
      fields: {
        'address': address,
        'rw': rw,
        if (dataBytes.isNotEmpty) 'data': dataHex,
        if (ackList.isNotEmpty) 'ack': ackStr,
      },
      isError: errors.isNotEmpty,
      errorMessage: errors.isNotEmpty ? errors.join('; ') : null,
    );
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  /// Collects 8 bits starting at [offset] from [bits] into a byte (MSB first).
  int _collectByte(List<int> bits, int offset) {
    var byte = 0;
    for (var i = 0; i < 8; i++) {
      byte = (byte << 1) | (bits[offset + i] & 1);
    }
    return byte;
  }

  DecodedTransaction _errorTransaction(int start, int end, String message) =>
      DecodedTransaction(
        startTime: start,
        endTime: end,
        label: 'I²C error',
        isError: true,
        errorMessage: message,
      );
}

/// Internal event representing a bus condition detected on the I²C bus.
class _I2cEvent {
  const _I2cEvent({required this.time, required this.kind});
  final int time;
  final String kind;
}
