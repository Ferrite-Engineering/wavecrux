// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/services/policy/org_object_policy_key.dart';
import 'package:wavecrux/services/policy/org_signal_groups.dart';

OrgSignalGroups groups(Object? raw, {bool locked = false}) =>
    OrgSignalGroups.fromPolicyEntry(
      raw == null ? null : OrgPolicyEntry(value: raw, locked: locked),
    );

Map<String, Object?> orgGroup(
  String name,
  List<String> patterns, {
  bool collapsed = false,
}) => <String, Object?>{
  'name': name,
  'patterns': patterns,
  'collapsed': collapsed,
};

void main() {
  group('glob matching', () {
    test('* stays inside one segment', () {
      expect(globMatches('top.*.clk', 'top.cpu.clk'), isTrue);
      expect(
        globMatches('top.*.clk', 'top.cpu.core.clk'),
        isFalse,
        reason:
            'a single star that crossed segments would make `top.*.clk` match '
            'the whole design, which is not what anybody writing it means',
      );
    });

    test('** crosses segments', () {
      expect(globMatches('top.**.clk', 'top.cpu.core.clk'), isTrue);
      expect(globMatches('top.**', 'top.cpu.core.clk'), isTrue);
    });

    test('regex metacharacters are literal', () {
      expect(
        globMatches('top.mem[0].we', 'top.mem[0].we'),
        isTrue,
        reason:
            'a pattern in a signed file must mean what it looks like it '
            'means — `[0]` is an index, not a character class',
      );
      expect(globMatches('top.mem[0].we', 'top.mem0.we'), isFalse);
    });

    test('a pattern anchors at both ends', () {
      expect(globMatches('axi_aw*', 'axi_awvalid'), isTrue);
      expect(globMatches('axi_aw*', 'top.axi_awvalid'), isFalse);
    });
  });

  group('parsing', () {
    test('an absent key configures nothing', () {
      expect(groups(null).isEmpty, isTrue);
    });

    test('groups parse in declaration order', () {
      final org = groups(<Object?>[
        orgGroup('AXI write', <String>['top.**.axi_aw*']),
        orgGroup('Reset tree', <String>['top.**.rst*'], collapsed: true),
      ]);
      expect(org.groups.map((g) => g.name), ['AXI write', 'Reset tree']);
      expect(
        org.groups.last.collapsed,
        isTrue,
        reason:
            'the reset tree is a group you want to exist and rarely want to '
            'look at',
      );
    });

    test('one malformed group does not cost the others', () {
      final org = groups(<Object?>[
        <String, Object?>{
          'patterns': <String>['a*'],
        }, // no name
        <String, Object?>{'name': 'Empty', 'patterns': <String>[]},
        'not an object',
        orgGroup('Good', <String>['top.**']),
      ]);
      expect(org.groups.map((g) => g.name), ['Good']);
    });
  });

  group('assignment', () {
    final org = groups(<Object?>[
      orgGroup('AXI write', <String>['top.**.axi_aw*']),
      orgGroup('Everything else', <String>['top.**']),
    ]);

    test('a signal lands in its group', () {
      expect(org.groupFor('top.cpu.axi_awvalid')?.name, 'AXI write');
    });

    test('declaration order breaks a tie — first wins, not every', () {
      expect(
        org.groupFor('top.cpu.axi_awready')?.name,
        'AXI write',
        reason:
            'duplicating a trace is how a reader ends up comparing a signal '
            'against itself; order makes overlap something an administrator '
            'controls rather than something that surprises them',
      );
      expect(org.groupFor('top.cpu.data')?.name, 'Everything else');
    });

    test('an unmatched signal belongs to no group', () {
      expect(org.groupFor('other.thing'), isNull);
    });
  });

  group('applying groups to a batch', () {
    final org = groups(<Object?>[
      orgGroup('AXI write', <String>['top.**.axi_aw*'], collapsed: true),
      orgGroup('Reset tree', <String>['top.**.rst*']),
    ]);

    SignalEntry signal(String path) => SignalEntry.signal(
      signalRef: path,
      signalPath: path,
      displayName: path.split('.').last,
    );

    test('with no organization groups the entries are untouched', () {
      final entries = <SignalEntry>[signal('top.a'), signal('top.b')];
      expect(
        identical(applyOrgSignalGroups(entries, OrgSignalGroups.none), entries),
        isTrue,
        reason:
            'one early return on the hot "Add All in Scope" path rather than '
            'a cost every user pays',
      );
    });

    test('signals land under their group headers, in declaration order', () {
      final arranged = applyOrgSignalGroups(<SignalEntry>[
        signal('top.cpu.data'),
        signal('top.cpu.axi_awvalid'),
        signal('top.cpu.rst_n'),
      ], org);

      expect(arranged.map((e) => e.groupName ?? e.signalPath), [
        'AXI write',
        'Reset tree',
        'top.cpu.data',
      ]);
      expect(arranged.first.collapsed, isTrue);
      expect(arranged.first.children.single.signalPath, 'top.cpu.axi_awvalid');
    });

    test('a group the capture has no signals for is omitted, not empty', () {
      final arranged = applyOrgSignalGroups(<SignalEntry>[
        signal('top.cpu.rst_n'),
      ], org);
      expect(
        arranged.map((e) => e.groupName),
        ['Reset tree'],
        reason:
            'twelve empty headers above a capture of one block reads as a '
            'feature that does not work',
      );
    });

    test('unmatched signals keep their order and come last', () {
      final arranged = applyOrgSignalGroups(<SignalEntry>[
        signal('top.z'),
        signal('top.cpu.axi_awvalid'),
        signal('top.a'),
      ], org);
      expect(
        arranged.skip(1).map((e) => e.signalPath),
        ['top.z', 'top.a'],
        reason:
            'a signal the organization did not anticipate must not vanish '
            'into a catch-all or be silently reordered away from its '
            'neighbours',
      );
    });

    test('a header the user already placed is left alone', () {
      final arranged = applyOrgSignalGroups(<SignalEntry>[
        const SignalEntry.group(groupName: 'Mine'),
        signal('top.cpu.rst_n'),
      ], org);
      expect(
        arranged.last.groupName,
        'Mine',
        reason:
            'rearranging it would be the feature fighting the layout rather '
            'than seeding it',
      );
    });
  });

  test('the lock flag rides through', () {
    final org = groups(
      <Object?>[
        orgGroup('AXI', <String>['axi*']),
      ],
      locked: true,
    );
    expect(org.locked, isTrue);
  });
}
