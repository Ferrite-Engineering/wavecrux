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

/// Decodes AMBA APB (APB3 / APB4) bus transactions.
///
/// APB transfers progress through three phases driven by the rising edge of
/// PCLK:
///
/// - **IDLE** — `PSEL=0`, `PENABLE=0`. No transfer in progress.
/// - **SETUP** — `PSEL=1`, `PENABLE=0`. First cycle: `PADDR`, `PWRITE`,
///   `PWDATA` (and optional `PSTRB`/`PPROT`) become valid.
/// - **ACCESS** — `PSEL=1`, `PENABLE=1`. Second cycle and any wait states.
///   The transfer completes on the cycle where `PREADY=1` (or immediately if
///   `PREADY` is unbound, i.e. an always-ready slave).
///
/// A transaction begins at the SETUP rising edge and ends at the ACCESS edge
/// where `PREADY` samples high. For reads, `PRDATA` is sampled at the
/// completion edge; for writes, `PWDATA` and `PSTRB` are captured at SETUP.
///
/// Protocol violations detected:
/// - `PENABLE` asserted while `PSEL` is low.
/// - `PSEL` deasserted during the ACCESS phase before `PREADY` (transfer
///   aborted).
/// - `PENABLE` deasserted during the ACCESS phase before `PREADY`.
/// - `PADDR` or `PWRITE` changing during the ACCESS phase (bus instability).
/// - `PSLVERR` asserted at completion (decoded transaction is flagged as an
///   error but still emitted with all captured fields).
class ApbDecoder implements ProtocolDecoder {
  /// Creates an [ApbDecoder] bound to [config].
  const ApbDecoder(this._config);

  final DecoderConfig _config;

  // ── static definition ──────────────────────────────────────────────────────

  /// Static metadata registered with [DecoderRegistry] at app startup.
  static const decoderDefinition = DecoderDefinition(
    id: 'apb',
    displayName: 'APB',
    description:
        'Decodes AMBA APB (APB3/APB4) bus transactions (read and write).',
    category: DecoderCategory.amba,
    requiredSignals: [
      SignalBinding(name: 'pclk', description: 'APB clock', bitWidth: 1),
      SignalBinding(
        name: 'presetn',
        description: 'APB active-low reset',
        bitWidth: 1,
      ),
      SignalBinding(
        name: 'psel',
        description: 'Peripheral select',
        bitWidth: 1,
      ),
      SignalBinding(
        name: 'penable',
        description: 'Peripheral enable (high during ACCESS phase)',
        bitWidth: 1,
      ),
      SignalBinding(
        name: 'pwrite',
        description: 'Transfer direction (1 = write, 0 = read)',
        bitWidth: 1,
      ),
      // No bitWidth pin: APB address buses are design-specific (the
      // addr_width PARAMETER, often 12-16 bits) — a hard 32 made narrower
      // address buses unbindable in the config dialog and unmatchable by
      // auto-bind, while the decoder itself handles any width.
      SignalBinding(name: 'paddr', description: 'Address bus'),
      SignalBinding(
        name: 'pwdata',
        description: 'Write data bus',
        bitWidth: 32,
      ),
      SignalBinding(
        name: 'prdata',
        description: 'Read data bus',
        bitWidth: 32,
      ),
    ],
    optionalSignals: [
      SignalBinding(
        name: 'pready',
        description:
            'Slave ready (1 = transfer completes this cycle). '
            'When unbound, the slave is treated as always-ready.',
        bitWidth: 1,
      ),
      SignalBinding(
        name: 'pslverr',
        description: 'Slave error (APB3+). Flagged when high at completion.',
        bitWidth: 1,
      ),
      SignalBinding(
        name: 'pprot',
        description: 'Protection type (APB4)',
        bitWidth: 3,
      ),
      SignalBinding(
        name: 'pstrb',
        description: 'Byte write strobe (APB4)',
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
  DecoderDefinition get definition => ApbDecoder.decoderDefinition;

  // ── decode ─────────────────────────────────────────────────────────────────

  @override
  List<DecodedTransaction> decode(
    int startTime,
    int endTime,
    SignalValueQuery query,
    SignalChangesQuery changesQuery, {
    Timescale? timescale,
  }) {
    final clkChanges = changesQuery('pclk', startTime, endTime);
    if (clkChanges.isEmpty) return [];

    final hasPready = _config.signalBindings.containsKey('pready');
    final hasPslverr = _config.signalBindings.containsKey('pslverr');
    final hasPprot = _config.signalBindings.containsKey('pprot');
    final hasPstrb = _config.signalBindings.containsKey('pstrb');

    final transactions = <DecodedTransaction>[];

    var state = _ApbState.idle;
    _ApbPending? pending;
    var unstable = false;

    for (final (edgeTime, edgeVal) in clkChanges) {
      if (!isVcdHigh(edgeVal)) continue; // rising edges only

      // Synchronous reset: drop any in-flight state and skip this edge.
      if (!isVcdHigh(query('presetn', edgeTime))) {
        state = _ApbState.idle;
        pending = null;
        unstable = false;
        continue;
      }

      final psel = isVcdHigh(query('psel', edgeTime));
      final penable = isVcdHigh(query('penable', edgeTime));

      // Always-ready when `pready` is unbound.
      final pready = !hasPready || isVcdHigh(query('pready', edgeTime));

      // PENABLE without SELECT is a violation regardless of state.
      if (!psel && penable) {
        transactions.add(
          _makeViolation(
            edgeTime,
            edgeTime,
            'APB violation: PENABLE asserted while PSEL is low',
          ),
        );
        state = _ApbState.idle;
        pending = null;
        unstable = false;
        continue;
      }

      switch (state) {
        case _ApbState.idle:
          if (psel && !penable) {
            // SETUP phase: capture transfer details.
            pending = _ApbPending(
              startTime: edgeTime,
              addr: parseVcdVectorInt(query('paddr', edgeTime)),
              isWrite: isVcdHigh(query('pwrite', edgeTime)),
              wdata: parseVcdVectorInt(query('pwdata', edgeTime)),
              pstrb: hasPstrb
                  ? parseVcdVectorInt(query('pstrb', edgeTime))
                  : null,
              pprot: hasPprot
                  ? parseVcdVectorInt(query('pprot', edgeTime))
                  : null,
            );
            unstable = false;
            state = _ApbState.setup;
          }
        // Otherwise stay IDLE.

        case _ApbState.setup:
          if (!psel) {
            // Master aborted the transfer before reaching ACCESS.
            pending = null;
            unstable = false;
            state = _ApbState.idle;
          } else if (penable) {
            // SETUP → ACCESS. Verify bus stability against captured SETUP
            // values.
            final p = pending!;
            final addrNow = parseVcdVectorInt(query('paddr', edgeTime));
            final writeNow = isVcdHigh(query('pwrite', edgeTime));
            if (addrNow != p.addr || writeNow != p.isWrite) {
              unstable = true;
            }

            if (pready) {
              transactions.add(
                _completeTransaction(
                  pending: p,
                  endTime: edgeTime,
                  query: query,
                  hasPslverr: hasPslverr,
                  hasPstrb: hasPstrb,
                  hasPprot: hasPprot,
                  unstable: unstable,
                ),
              );
              pending = null;
              unstable = false;
              state = _ApbState.idle;
            } else {
              state = _ApbState.access;
            }
          }
        // PSEL=1, PENABLE=0 again: stay in SETUP (non-standard but
        // tolerated).

        case _ApbState.access:
          final p = pending!;
          if (!psel) {
            transactions.add(
              _makeViolation(
                p.startTime,
                edgeTime,
                'APB violation: PSEL deasserted during ACCESS phase',
              ),
            );
            pending = null;
            unstable = false;
            state = _ApbState.idle;
          } else if (!penable) {
            transactions.add(
              _makeViolation(
                p.startTime,
                edgeTime,
                'APB violation: PENABLE deasserted during ACCESS phase',
              ),
            );
            pending = null;
            unstable = false;
            state = _ApbState.idle;
          } else {
            final addrNow = parseVcdVectorInt(query('paddr', edgeTime));
            final writeNow = isVcdHigh(query('pwrite', edgeTime));
            if (addrNow != p.addr || writeNow != p.isWrite) {
              unstable = true;
            }

            if (pready) {
              transactions.add(
                _completeTransaction(
                  pending: p,
                  endTime: edgeTime,
                  query: query,
                  hasPslverr: hasPslverr,
                  hasPstrb: hasPstrb,
                  hasPprot: hasPprot,
                  unstable: unstable,
                ),
              );
              pending = null;
              unstable = false;
              state = _ApbState.idle;
            }
            // else: another wait state.
          }
      }
    }

    return transactions;
  }

  // ── transaction emission ───────────────────────────────────────────────────

  DecodedTransaction _completeTransaction({
    required _ApbPending pending,
    required int endTime,
    required SignalValueQuery query,
    required bool hasPslverr,
    required bool hasPstrb,
    required bool hasPprot,
    required bool unstable,
  }) {
    final isSlvErr = hasPslverr && isVcdHigh(query('pslverr', endTime));
    final errors = <String>[
      if (isSlvErr) 'Slave error (PSLVERR)',
      if (unstable) 'PADDR/PWRITE changed during ACCESS phase',
    ];
    final hasError = errors.isNotEmpty;
    final response = isSlvErr ? 'SLVERR' : 'OKAY';

    final addrStr = _fmtAddr(pending.addr);

    if (pending.isWrite) {
      final dataStr = _fmtData(pending.wdata);
      final label = isSlvErr
          ? 'W $addrStr = $dataStr [SLVERR]'
          : 'W $addrStr = $dataStr';
      return DecodedTransaction(
        startTime: pending.startTime,
        endTime: endTime,
        label: label,
        fields: {
          'type': 'Write',
          'address': addrStr,
          'data': dataStr,
          'response': response,
          if (hasPstrb) 'pstrb': _fmtStrobe(pending.pstrb),
          if (hasPprot) 'pprot': _fmtProt(pending.pprot),
        },
        isError: hasError,
        errorMessage: hasError ? errors.join('; ') : null,
      );
    }

    final rdata = parseVcdVectorInt(query('prdata', endTime));
    final dataStr = _fmtData(rdata);
    final label = isSlvErr
        ? 'R $addrStr → $dataStr [SLVERR]'
        : 'R $addrStr → $dataStr';
    return DecodedTransaction(
      startTime: pending.startTime,
      endTime: endTime,
      label: label,
      fields: {
        'type': 'Read',
        'address': addrStr,
        'data': dataStr,
        'response': response,
        if (hasPprot) 'pprot': _fmtProt(pending.pprot),
      },
      isError: hasError,
      errorMessage: hasError ? errors.join('; ') : null,
    );
  }

  DecodedTransaction _makeViolation(
    int startTime,
    int endTime,
    String message,
  ) => DecodedTransaction(
    startTime: startTime,
    endTime: endTime,
    label: 'APB Violation',
    fields: {'error': message},
    isError: true,
    errorMessage: message,
  );

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

  String _fmtProt(int? val) {
    if (val == null) return '0x?';
    return '0x${val.toRadixString(16).toUpperCase()}';
  }
}

// ── internal phase state ─────────────────────────────────────────────────────

enum _ApbState { idle, setup, access }

class _ApbPending {
  const _ApbPending({
    required this.startTime,
    required this.addr,
    required this.isWrite,
    required this.wdata,
    this.pstrb,
    this.pprot,
  });

  final int startTime;
  final int? addr;
  final bool isWrite;
  final int? wdata;
  final int? pstrb;
  final int? pprot;
}
