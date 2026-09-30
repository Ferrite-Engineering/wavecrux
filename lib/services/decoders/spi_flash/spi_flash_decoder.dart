// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/enums/decoder_category.dart';
import 'package:wavecrux/domain/enums/decoder_parameter_type.dart';
import 'package:wavecrux/domain/interfaces/protocol_decoder.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/domain/models/decoder_parameter.dart';
import 'package:wavecrux/domain/models/timescale.dart';

/// Decodes JEDEC SPI NOR flash commands by stacking on the SPI decoder.
///
/// Consumes [DecodedTransaction] output from the parent `spi` decoder.
/// Each parent SPI transaction is treated as one flash bus transfer: the
/// first MOSI byte is the opcode; subsequent bytes are interpreted per the
/// JEDEC JESD47 command table.
///
/// Single-wire (standard SPI) framing only. Dual/Quad data-plane decoding
/// (4-wire io0–io3 capture) is out of scope for this phase.
class SpiFlashDecoder extends StackedDecoder {
  const SpiFlashDecoder(this._config);

  final DecoderConfig _config;

  // ── static definition ──────────────────────────────────────────────────────

  static const decoderDefinition = DecoderDefinition(
    id: 'spi_flash',
    displayName: 'SPI Flash',
    description:
        'Decodes JEDEC SPI NOR flash commands stacked on the SPI decoder.',
    category: DecoderCategory.serial,
    parentDecoderId: 'spi',
    requiredSignals: [],
    parameters: [
      DecoderParameter(
        name: 'vendor_preset',
        displayName: 'Vendor Preset',
        labelKey: 'spiFlashParamVendorPreset',
        descriptionKey: 'spiFlashParamVendorPresetDescription',
        type: DecoderParameterType.enumeration,
        defaultValue: 'generic',
        description:
            'Vendor preset that activates vendor-specific command recognition.',
        enumValues: [
          'generic',
          'winbond_w25q',
          'macronix_mx25l',
          'micron_n25q',
          'spansion_s25fl',
          'issi_is25lp',
        ],
        enumLabels: {
          'generic': 'Generic JEDEC',
          'winbond_w25q': 'Winbond W25Q',
          'macronix_mx25l': 'Macronix MX25L',
          'micron_n25q': 'Micron N25Q',
          'spansion_s25fl': 'Spansion S25FL',
          'issi_is25lp': 'ISSI IS25LP',
        },
        // Reuses the already-existing (previously orphaned) ARB keys.
        enumLabelKeys: {
          'generic': 'spiFlashChoiceVendorGeneric',
          'winbond_w25q': 'spiFlashChoiceVendorWinbond',
          'macronix_mx25l': 'spiFlashChoiceVendorMacronix',
          'micron_n25q': 'spiFlashChoiceVendorMicron',
          'spansion_s25fl': 'spiFlashChoiceVendorSpansion',
          'issi_is25lp': 'spiFlashChoiceVendorIssi',
        },
      ),
      DecoderParameter(
        name: 'address_width',
        displayName: 'Address Width',
        labelKey: 'spiFlashParamAddressWidth',
        descriptionKey: 'spiFlashParamAddressWidthDescription',
        type: DecoderParameterType.enumeration,
        defaultValue: '24',
        description:
            'Address field width: 24-bit (3-byte) or 32-bit (4-byte '
            'extended addressing mode).',
        enumValues: ['24', '32'],
        enumLabels: {'24': '24-bit (3B)', '32': '32-bit (4B)'},
        // Reuses the already-existing (previously orphaned) ARB keys.
        enumLabelKeys: {
          '24': 'spiFlashChoiceAddr24',
          '32': 'spiFlashChoiceAddr32',
        },
      ),
      DecoderParameter(
        name: 'dummy_cycles',
        displayName: 'Dummy Cycles',
        labelKey: 'spiFlashParamDummyCycles',
        descriptionKey: 'spiFlashParamDummyCyclesDescription',
        type: DecoderParameterType.integer,
        defaultValue: -1,
        description:
            'Dummy clock cycles before data phase (-1 = auto from command).',
      ),
    ],
  );

  @override
  DecoderDefinition get definition => SpiFlashDecoder.decoderDefinition;

  // ── StackedDecoder ─────────────────────────────────────────────────────────

  @override
  List<DecodedTransaction> decodeStacked(
    List<DecodedTransaction> parentTransactions,
    int startTime,
    int endTime,
    SignalValueQuery query,
    SignalChangesQuery changesQuery, {
    Timescale? timescale,
  }) {
    final addrBytes = _strParam('address_width', '24') == '32' ? 4 : 3;
    final vendor = _strParam('vendor_preset', 'generic');
    final dummyOverride = _intParam('dummy_cycles', -1);

    final result = <DecodedTransaction>[];
    var welSet = false; // WEL bit tracking across transactions

    for (final tx in parentTransactions) {
      if (tx.startTime < startTime || tx.startTime >= endTime) continue;

      final mosiStr = tx.fields['mosi'];
      if (mosiStr == null || mosiStr.isEmpty) continue;

      final mosiBytes = _parseHexBytes(mosiStr);
      if (mosiBytes.isEmpty) continue;

      final misoBytes = _parseHexBytes(tx.fields['miso'] ?? '');

      final opcode = mosiBytes.first;
      final cmd = _lookupCommand(opcode, vendor);
      final body = mosiBytes.sublist(1);

      final (fields, isError, errorMsg) = _decodeCommand(
        cmd,
        opcode,
        body,
        misoBytes.isNotEmpty ? misoBytes.sublist(1) : [],
        addrBytes,
        dummyOverride,
        welSet,
      );

      // Update WEL state from this transaction.
      welSet = _nextWelState(cmd, welSet);

      result.add(
        DecodedTransaction(
          startTime: tx.startTime,
          endTime: tx.endTime,
          label: cmd.mnemonic,
          fields: fields,
          isError: isError,
          errorMessage: isError ? errorMsg : null,
        ),
      );
    }

    return result;
  }

  // ── command lookup ─────────────────────────────────────────────────────────

  static final _baseCommands = <int, _FlashCmd>{
    0x00: const _FlashCmd('NOP', _CmdKind.noOp),
    0x01: const _FlashCmd('WRSR', _CmdKind.writeReg),
    0x02: const _FlashCmd('PP', _CmdKind.write),
    0x03: const _FlashCmd('READ', _CmdKind.read),
    0x04: const _FlashCmd('WRDI', _CmdKind.control),
    0x05: const _FlashCmd('RDSR', _CmdKind.readReg),
    0x06: const _FlashCmd('WREN', _CmdKind.control),
    0x0B: const _FlashCmd('FAST_READ', _CmdKind.read, defaultDummy: 1),
    0x20: const _FlashCmd('SE', _CmdKind.erase),
    0x3B: const _FlashCmd('DUAL_READ', _CmdKind.read, defaultDummy: 1),
    0x5A: const _FlashCmd('rsfdp', _CmdKind.read, defaultDummy: 1),
    0x60: const _FlashCmd('CE', _CmdKind.erase),
    0x6B: const _FlashCmd('QUAD_READ', _CmdKind.read, defaultDummy: 1),
    0x9F: const _FlashCmd('RDID', _CmdKind.readId),
    0xAB: const _FlashCmd('RES', _CmdKind.readId),
    0xB9: const _FlashCmd('DP', _CmdKind.control),
    0xBB: const _FlashCmd('DUAL_IO_READ', _CmdKind.read, defaultDummy: 1),
    0xC7: const _FlashCmd('CE', _CmdKind.erase),
    0xD8: const _FlashCmd('BE64K', _CmdKind.erase),
    0xEB: const _FlashCmd('QUAD_IO_READ', _CmdKind.read, defaultDummy: 3),
  };

  // Vendor-specific additions / overrides keyed by vendor preset name.
  static final _vendorCommands = <String, Map<int, _FlashCmd>>{
    'winbond_w25q': {
      0x28: const _FlashCmd('BE32K', _CmdKind.erase),
      0x35: const _FlashCmd('RDSR2', _CmdKind.readReg),
      0x42: const _FlashCmd('PRSP', _CmdKind.write),
      0x44: const _FlashCmd('ERSP', _CmdKind.erase),
      0x48: const _FlashCmd('RDSP', _CmdKind.read, defaultDummy: 1),
      0x4B: const _FlashCmd('RUID', _CmdKind.readId, defaultDummy: 4),
      0x15: const _FlashCmd('RDSR3', _CmdKind.readReg),
      0x11: const _FlashCmd('WRSR3', _CmdKind.writeReg),
      0x31: const _FlashCmd('WRSR2', _CmdKind.writeReg),
    },
    'macronix_mx25l': {
      0x52: const _FlashCmd('BE32K', _CmdKind.erase),
      0x07: const _FlashCmd('RDSR2', _CmdKind.readReg),
      0x15: const _FlashCmd('RDCR', _CmdKind.readReg),
    },
    'micron_n25q': {
      0x52: const _FlashCmd('BE32K', _CmdKind.erase),
      0x70: const _FlashCmd('RFSR', _CmdKind.readReg),
      0x50: const _FlashCmd('CLRFSR', _CmdKind.control),
    },
    'spansion_s25fl': {
      0x32: const _FlashCmd('QPP', _CmdKind.write),
      0x58: const _FlashCmd('SE', _CmdKind.erase),
      0x65: const _FlashCmd('RDAR', _CmdKind.readReg, defaultDummy: 1),
      0x71: const _FlashCmd('WRAR', _CmdKind.writeReg),
    },
    'issi_is25lp': {
      0x52: const _FlashCmd('BE32K', _CmdKind.erase),
      0x3E: const _FlashCmd('AAIP', _CmdKind.write),
    },
  };

  _FlashCmd _lookupCommand(int opcode, String vendor) {
    final vendorTable = _vendorCommands[vendor];
    if (vendorTable != null) {
      final vendorCmd = vendorTable[opcode];
      if (vendorCmd != null) return vendorCmd;
    }
    return _baseCommands[opcode] ??
        _FlashCmd(
          '0x${opcode.toRadixString(16).toUpperCase().padLeft(2, '0')}',
          _CmdKind.unknown,
        );
  }

  // ── per-command decoding ───────────────────────────────────────────────────

  (Map<String, String>, bool, String?) _decodeCommand(
    _FlashCmd cmd,
    int opcode,
    List<int> body,
    List<int> miso,
    int addrBytes,
    int dummyOverride,
    bool welSet,
  ) {
    final fields = <String, String>{
      'opcode': '0x${opcode.toRadixString(16).toUpperCase().padLeft(2, '0')}',
    };
    final errors = <String>[];

    switch (cmd.kind) {
      case _CmdKind.noOp:
        break;

      case _CmdKind.control:
        // WREN, WRDI, DP: no address or data.
        if (body.isNotEmpty) {
          fields['extra'] = _hexBytes(body);
        }
        if (cmd.mnemonic == 'WREN' && welSet) {
          errors.add('double_wren');
        }

      case _CmdKind.read:
        _decodeAddrData(
          cmd,
          body,
          miso,
          addrBytes,
          dummyOverride,
          fields,
          errors,
        );

      case _CmdKind.write:
        if (!welSet) errors.add('write_without_wel');
        _decodeAddrData(
          cmd,
          body,
          miso,
          addrBytes,
          dummyOverride,
          fields,
          errors,
          writeData: true,
        );

      case _CmdKind.erase:
        if (!welSet && cmd.mnemonic != 'CE') errors.add('write_without_wel');
        if (cmd.mnemonic == 'CE' && !welSet) errors.add('write_without_wel');
        if (cmd.mnemonic != 'CE' && cmd.mnemonic != 'ERSP') {
          // Sector/block erases carry an address.
          if (body.length >= addrBytes) {
            fields['address'] = _hexAddr(body.take(addrBytes).toList());
          } else if (body.isNotEmpty) {
            fields['address'] = _hexAddr(body);
            errors.add('incomplete_frame');
          } else {
            errors.add('incomplete_frame');
          }
        }

      case _CmdKind.readReg:
        if (miso.isNotEmpty) {
          fields['status'] = _hexBytes(miso);
        }

      case _CmdKind.writeReg:
        if (!welSet) errors.add('write_without_wel');
        if (body.isNotEmpty) {
          fields['status'] = _hexBytes(body);
        } else {
          errors.add('incomplete_frame');
        }

      case _CmdKind.readId:
        if (cmd.mnemonic == 'RDID') {
          if (miso.length >= 3) {
            fields['jedec_id'] =
                '${_hexByte(miso[0])}-${_hexByte(miso[1])}-${_hexByte(miso[2])}';
          } else {
            fields['jedec_id'] = _hexBytes(miso);
            if (miso.isEmpty) errors.add('incomplete_frame');
          }
        } else if (cmd.mnemonic == 'RES') {
          // RES: 3 dummy bytes then 1 byte device ID on MISO.
          final effectiveDummy = dummyOverride >= 0 ? dummyOverride : 3;
          final dataStart = effectiveDummy;
          if (miso.length > dataStart) {
            fields['device_id'] = _hexByte(miso[dataStart]);
          }
          if (miso.length <= dataStart) errors.add('incomplete_frame');
        } else if (cmd.mnemonic == 'RUID') {
          final effectiveDummy = dummyOverride >= 0 ? dummyOverride : 4;
          final dataStart = effectiveDummy;
          if (miso.length > dataStart) {
            fields['unique_id'] = _hexBytes(miso.sublist(dataStart));
          }
        }

      case _CmdKind.unknown:
        fields['raw'] = _hexBytes(body);
        if (miso.isNotEmpty) fields['miso'] = _hexBytes(miso);
    }

    final isError = errors.isNotEmpty;
    return (fields, isError, isError ? errors.join(';') : null);
  }

  void _decodeAddrData(
    _FlashCmd cmd,
    List<int> body,
    List<int> miso,
    int addrBytes,
    int dummyOverride,
    Map<String, String> fields,
    List<String> errors, {
    bool writeData = false,
  }) {
    final effectiveDummy = dummyOverride >= 0
        ? dummyOverride
        : cmd.defaultDummy;

    if (body.length < addrBytes) {
      if (body.isNotEmpty) fields['address'] = _hexAddr(body);
      errors.add('incomplete_frame');
      return;
    }

    fields['address'] = _hexAddr(body.take(addrBytes).toList());

    final afterAddr = body.sublist(addrBytes);
    final dataOffset = effectiveDummy;

    if (writeData) {
      // Write commands: data comes from MOSI after address.
      if (afterAddr.isNotEmpty) {
        fields['data'] = _hexBytes(afterAddr);
      }
    } else {
      // Read commands: data comes from MISO after dummy cycles.
      if (miso.length > addrBytes + dataOffset) {
        final data = miso.sublist(addrBytes + dataOffset);
        if (data.isNotEmpty) fields['data'] = _hexBytes(data);
      }
    }
  }

  // ── WEL state machine ──────────────────────────────────────────────────────

  bool _nextWelState(_FlashCmd cmd, bool current) {
    switch (cmd.mnemonic) {
      case 'WREN':
        return true;
      case 'WRDI':
      case 'PP':
      case 'SE':
      case 'BE32K':
      case 'BE64K':
      case 'CE':
      case 'WRSR':
      case 'WRSR2':
      case 'WRSR3':
      case 'ERSP':
      case 'PRSP':
        return false; // write/erase clears WEL
      default:
        return current;
    }
  }

  // ── formatting helpers ─────────────────────────────────────────────────────

  String _hexByte(int b) =>
      '0x${b.toRadixString(16).toUpperCase().padLeft(2, '0')}';

  String _hexBytes(List<int> bytes) => bytes.map(_hexByte).join(' ');

  String _hexAddr(List<int> bytes) {
    final value = bytes.fold(0, (acc, b) => (acc << 8) | b);
    final nibbles = bytes.length * 2;
    return '0x${value.toRadixString(16).toUpperCase().padLeft(nibbles, '0')}';
  }

  // Parses SPI decoder's space-separated hex output, e.g. "0xAB 0xCD".
  List<int> _parseHexBytes(String s) {
    if (s.isEmpty) return [];
    final result = <int>[];
    for (final token in s.split(' ')) {
      final t = token.trim();
      if (t.isEmpty) continue;
      final v = int.tryParse(
        t.startsWith('0x') ? t.substring(2) : t,
        radix: 16,
      );
      if (v != null) result.add(v & 0xFF);
    }
    return result;
  }

  // ── parameter helpers ──────────────────────────────────────────────────────

  String _strParam(String name, String fallback) {
    final v = _config.parameters[name];
    return v is String ? v : fallback;
  }

  int _intParam(String name, int fallback) {
    final v = _config.parameters[name];
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }
}

// ── internal types ─────────────────────────────────────────────────────────

enum _CmdKind {
  noOp,
  control,
  read,
  write,
  erase,
  readReg,
  writeReg,
  readId,
  unknown,
}

class _FlashCmd {
  const _FlashCmd(this.mnemonic, this.kind, {this.defaultDummy = 0});

  final String mnemonic;
  final _CmdKind kind;

  /// Default dummy bytes/cycles between address and data for read commands.
  final int defaultDummy;
}
