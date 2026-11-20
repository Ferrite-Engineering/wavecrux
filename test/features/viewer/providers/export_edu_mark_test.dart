// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The export dialog under an educational licence: the images (PNG, SVG) say
// they were made with WaveCrux Educational, and the data (VCD, SAIF) is
// written exactly as under any other licence, because a tool reads it back.
//
// Driven through the browser-download path so every export lands in memory:
// no save dialog, no disk.

import 'dart:convert';
import 'dart:typed_data';

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/providers/browser_download_provider.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/export_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/export/image_export_service.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

import '../../../helpers/fake_waveform_data_source.dart';
import '../../../helpers/product_telemetry_config.dart';

const _mark = 'Made with WaveCrux Educational · Non-commercial use only';

CruxLicenseStatus _status(LicenseTier tier) => CruxLicenseStatus(
  activation: CruxLicenseActivation.active,
  grant: LicenseGrant(
    issuerId: kEduLicenseIssuerId,
    tier: tier,
    products: CruxProduct.values.toSet(),
    licenseId: 'lic-1',
    email: 'student@example.edu',
    expiry: DateTime.utc(2027, 8, 2, 12),
  ),
);

final _licences = <String, CruxLicenseStatus>{
  'EDU': _status(LicenseTier.edu),
  'Pro': _status(LicenseTier.pro),
  'open core': CruxLicenseStatus.openCore,
};

final _source = FakeWaveformDataSource(
  signals: {
    'clk': const [
      SignalChange(time: 0, value: '0'),
      SignalChange(time: 100, value: '1'),
      SignalChange(time: 200, value: '0'),
      SignalChange(time: 300, value: '1'),
    ],
    'data': const [
      SignalChange(time: 0, value: '00'),
      SignalChange(time: 150, value: '10'),
    ],
  },
);

Variable _v(String name, {int bitWidth = 1}) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: name,
  scopePath: 'top',
  bitWidth: bitWidth,
);

final Map<String, Variable> _signalMap = {
  'clk': _v('clk'),
  'data': _v('data', bitWidth: 2),
};

final _group = SignalGroup(
  entries: [
    SignalEntry.signal(signalRef: 'clk', displayName: 'clk'),
    SignalEntry.signal(signalRef: 'data', displayName: 'data'),
  ],
);

class _FakeSourceNotifier extends WaveformSourceNotifier {
  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

class _FakeSignalGroupsNotifier extends SignalGroupsNotifier {
  @override
  SignalGroup build() => _group;
}

class _FakeTimeMapperNotifier extends TimeMapperNotifier {
  @override
  TimeMapper build() =>
      TimeMapper.fitAll(startTime: 0, endTime: 1000, viewportWidth: 800);
}

/// Records the mark a PNG capture was asked to paint; returns a stand-in PNG.
class _CapturingImageExportService extends ImageExportService {
  _CapturingImageExportService();

  final marks = <String?>[];

  @override
  Future<Uint8List> capturePng(
    GlobalKey boundaryKey, {
    double pixelRatio = 2.0,
    Color? background,
    String? eduMark,
  }) async {
    marks.add(eduMark);
    return Uint8List.fromList(const [0x89, 0x50, 0x4E, 0x47]);
  }
}

/// Runs one export through the dialog and returns the downloaded bytes.
Future<Map<String, List<int>>> _export(
  WidgetTester tester, {
  required CruxLicenseStatus licence,
  required String formatLabel,
  ImageExportService? images,
}) async {
  final downloads = <String, List<int>>{};
  final repaintKey = GlobalKey();
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        productTelemetryConfig,
        licenseStatusProvider.overrideWithValue(licence),
        browserDownloadProvider.overrideWithValue(({
          required fileName,
          required bytes,
        }) async {
          downloads[fileName] = bytes;
        }),
        waveformSourceProvider.overrideWith(_FakeSourceNotifier.new),
        signalGroupsProvider.overrideWith(_FakeSignalGroupsNotifier.new),
        signalVariablesMapProvider.overrideWithValue(_signalMap),
        timeMapperProvider.overrideWith(_FakeTimeMapperNotifier.new),
        if (images != null)
          imageExportServiceProvider.overrideWithValue(images),
      ],
      child: MaterialApp(
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => RepaintBoundary(
              key: repaintKey,
              child: TextButton(
                onPressed: () => ref
                    .read(exportProvider.notifier)
                    .showExportDialog(context, waveformRepaintKey: repaintKey),
                child: const Text('Export'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Export'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text(formatLabel));
  await tester.pump();
  await tester.tap(find.text('Export…'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
  expect(tester.takeException(), isNull);
  return downloads;
}

/// A VCD minus its `$date` line, which carries the wall clock.
String _withoutDate(String vcd) =>
    vcd.split('\n').where((l) => !l.startsWith(r'$date')).join('\n');

void main() {
  group('SVG export', () {
    testWidgets('carries the mark under EDU', (tester) async {
      final out = await _export(
        tester,
        licence: _licences['EDU']!,
        formatLabel: 'SVG Vector',
      );

      final svg = utf8.decode(out['waveform.svg']!);
      expect(svg, contains('class="crux-edu-mark"'));
      expect(svg, contains(_mark));
    });

    for (final name in ['Pro', 'open core']) {
      testWidgets('carries no mark at $name', (tester) async {
        final out = await _export(
          tester,
          licence: _licences[name]!,
          formatLabel: 'SVG Vector',
        );

        final svg = utf8.decode(out['waveform.svg']!);
        expect(svg, isNot(contains('crux-edu-mark')));
        expect(svg, isNot(contains('Educational')));
      });
    }
  });

  group('PNG export', () {
    for (final MapEntry(key: name, value: licence) in _licences.entries) {
      testWidgets('asks the capture for ${name == 'EDU' ? 'the' : 'no'} '
          'mark at $name', (tester) async {
        final images = _CapturingImageExportService();
        await _export(
          tester,
          licence: licence,
          formatLabel: 'PNG Image',
          images: images,
        );

        expect(images.marks, [if (name == 'EDU') _mark else null]);
      });
    }
  });

  group('data exports are never marked', () {
    testWidgets('a VCD is identical under EDU and open core', (tester) async {
      final edu = await _export(
        tester,
        licence: _licences['EDU']!,
        formatLabel: 'VCD (Value Change Dump)',
      );
      final open = await _export(
        tester,
        licence: CruxLicenseStatus.openCore,
        formatLabel: 'VCD (Value Change Dump)',
      );

      final eduVcd = utf8.decode(edu['export.vcd']!);
      expect(eduVcd, isNot(contains('Educational')));
      expect(eduVcd, isNot(contains('Non-commercial')));
      expect(
        _withoutDate(eduVcd),
        _withoutDate(utf8.decode(open['export.vcd']!)),
      );
    });

    testWidgets('a SAIF is identical under EDU and open core', (tester) async {
      final edu = await _export(
        tester,
        licence: _licences['EDU']!,
        formatLabel: 'SAIF (switching activity)',
      );
      final open = await _export(
        tester,
        licence: CruxLicenseStatus.openCore,
        formatLabel: 'SAIF (switching activity)',
      );

      expect(
        utf8.decode(edu['activity.saif']!),
        isNot(contains('Educational')),
      );
      expect(edu['activity.saif'], open['activity.saif']);
    });
  });
}
