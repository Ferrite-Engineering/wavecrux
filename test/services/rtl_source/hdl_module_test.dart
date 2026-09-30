// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/rtl_source/hdl_module.dart';

void main() {
  group('HdlModule.mergedWith', () {
    test('unions signals and instances, de-duplicating by name', () {
      const entity = HdlModule(
        name: 'counter',
        sourceFile: 'counter.vhd',
        declarationLine: 2,
        signals: [
          HdlSignal(name: 'clk', lineNumber: 4),
          HdlSignal(name: 'q', lineNumber: 5),
        ],
      );
      const arch = HdlModule(
        name: 'counter',
        sourceFile: 'counter.vhd',
        declarationLine: 9,
        signals: [
          HdlSignal(name: 'q', lineNumber: 99), // duplicate name — entity wins
          HdlSignal(name: 'cnt', lineNumber: 10),
        ],
        instances: [
          HdlInstance(
            moduleType: 'subblock',
            instanceName: 'u_sub',
            lineNumber: 12,
          ),
        ],
      );

      final merged = entity.mergedWith(arch);

      // Declaration site of the receiver (the entity) wins.
      expect(merged.declarationLine, 2);
      // Signals unioned; the entity's `q` (line 5) is kept over the arch's.
      final byName = {for (final s in merged.signals) s.name: s.lineNumber};
      expect(byName, {'clk': 4, 'q': 5, 'cnt': 10});
      expect(merged.instances.map((i) => i.instanceName), ['u_sub']);
    });
  });

  test('HdlSignal / HdlInstance value equality', () {
    expect(
      const HdlSignal(name: 'a', lineNumber: 1),
      const HdlSignal(name: 'a', lineNumber: 1),
    );
    expect(
      const HdlInstance(moduleType: 't', instanceName: 'i', lineNumber: 1),
      const HdlInstance(moduleType: 't', instanceName: 'i', lineNumber: 1),
    );
  });
}
