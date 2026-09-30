// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/last_session_manifest.dart';

void main() {
  // ── LastSessionTab ──────────────────────────────────────────────────────────

  group('LastSessionTab', () {
    const tab = LastSessionTab(filePath: '/tmp/dump.vcd');
    const tabWithSession = LastSessionTab(
      filePath: '/tmp/dump.vcd',
      sessionFilePath: '/tmp/dump.wavecrux',
    );

    group('construction', () {
      test('stores filePath', () {
        expect(tab.filePath, equals('/tmp/dump.vcd'));
      });

      test('sessionFilePath defaults to null', () {
        expect(tab.sessionFilePath, isNull);
      });

      test('stores sessionFilePath when provided', () {
        expect(tabWithSession.sessionFilePath, equals('/tmp/dump.wavecrux'));
      });
    });

    group('equality', () {
      test('equal when both fields match', () {
        const a = LastSessionTab(filePath: '/x', sessionFilePath: '/y');
        const b = LastSessionTab(filePath: '/x', sessionFilePath: '/y');
        expect(a, equals(b));
      });

      test('equal when sessionFilePath is null on both', () {
        const a = LastSessionTab(filePath: '/x');
        const b = LastSessionTab(filePath: '/x');
        expect(a, equals(b));
      });

      test('not equal when filePath differs', () {
        const a = LastSessionTab(filePath: '/a');
        const b = LastSessionTab(filePath: '/b');
        expect(a, isNot(equals(b)));
      });

      test('not equal when sessionFilePath differs', () {
        const a = LastSessionTab(filePath: '/x', sessionFilePath: '/s1');
        const b = LastSessionTab(filePath: '/x', sessionFilePath: '/s2');
        expect(a, isNot(equals(b)));
      });

      test('not equal when one has sessionFilePath and other does not', () {
        const a = LastSessionTab(filePath: '/x');
        const b = LastSessionTab(filePath: '/x', sessionFilePath: '/y');
        expect(a, isNot(equals(b)));
      });

      test('hashCode matches for equal objects', () {
        const a = LastSessionTab(filePath: '/x', sessionFilePath: '/y');
        const b = LastSessionTab(filePath: '/x', sessionFilePath: '/y');
        expect(a.hashCode, equals(b.hashCode));
      });
    });

    group('toJson', () {
      test('includes filePath', () {
        final json = tab.toJson();
        expect(json['filePath'], equals('/tmp/dump.vcd'));
      });

      test('omits sessionFilePath when null', () {
        final json = tab.toJson();
        expect(json.containsKey('sessionFilePath'), isFalse);
      });

      test('includes sessionFilePath when set', () {
        final json = tabWithSession.toJson();
        expect(json['sessionFilePath'], equals('/tmp/dump.wavecrux'));
      });
    });

    group('fromJson', () {
      test('round-trip without sessionFilePath', () {
        final json = tab.toJson();
        expect(LastSessionTab.fromJson(json), equals(tab));
      });

      test('round-trip with sessionFilePath', () {
        final json = tabWithSession.toJson();
        expect(LastSessionTab.fromJson(json), equals(tabWithSession));
      });

      test('missing filePath key falls back to empty string', () {
        final result = LastSessionTab.fromJson(const {});
        expect(result.filePath, isEmpty);
        expect(result.sessionFilePath, isNull);
      });

      test('null filePath value falls back to empty string', () {
        final result = LastSessionTab.fromJson(const {'filePath': null});
        expect(result.filePath, isEmpty);
      });

      test('null sessionFilePath value produces null field', () {
        final result = LastSessionTab.fromJson(
          const {'filePath': '/x', 'sessionFilePath': null},
        );
        expect(result.sessionFilePath, isNull);
      });

      test('extra unknown keys are silently ignored', () {
        final result = LastSessionTab.fromJson(
          const {'filePath': '/x', 'unknownKey': 'ignored'},
        );
        expect(result.filePath, equals('/x'));
      });
    });

    test('toString contains filePath', () {
      expect(tab.toString(), contains('/tmp/dump.vcd'));
    });
  });

  // ── LastSessionManifest ─────────────────────────────────────────────────────

  group('LastSessionManifest', () {
    const tab1 = LastSessionTab(filePath: '/a.vcd');
    const tab2 = LastSessionTab(
      filePath: '/b.fst',
      sessionFilePath: '/b.wavecrux',
    );

    group('empty constant', () {
      test('has zero tabs', () {
        expect(LastSessionManifest.empty.tabs, isEmpty);
      });

      test('tabs list is unmodifiable', () {
        expect(
          () => LastSessionManifest.empty.tabs.add(tab1),
          throwsUnsupportedError,
        );
      });
    });

    group('construction', () {
      test('stores tabs', () {
        const m = LastSessionManifest(tabs: [tab1, tab2]);
        expect(m.tabs, equals([tab1, tab2]));
      });
    });

    group('equality', () {
      test('equal manifests with same tabs', () {
        const a = LastSessionManifest(tabs: [tab1, tab2]);
        const b = LastSessionManifest(tabs: [tab1, tab2]);
        expect(a, equals(b));
      });

      test('empty equals empty', () {
        expect(LastSessionManifest.empty, equals(LastSessionManifest.empty));
      });

      test('not equal when tab order differs', () {
        const a = LastSessionManifest(tabs: [tab1, tab2]);
        const b = LastSessionManifest(tabs: [tab2, tab1]);
        expect(a, isNot(equals(b)));
      });

      test('not equal when tab count differs', () {
        const a = LastSessionManifest(tabs: [tab1]);
        const b = LastSessionManifest(tabs: [tab1, tab2]);
        expect(a, isNot(equals(b)));
      });

      test('hashCode matches for equal manifests', () {
        const a = LastSessionManifest(tabs: [tab1, tab2]);
        const b = LastSessionManifest(tabs: [tab1, tab2]);
        expect(a.hashCode, equals(b.hashCode));
      });
    });

    group('toJson / fromJson round-trip', () {
      test('empty manifest round-trips', () {
        final json = LastSessionManifest.empty.toJson();
        expect(
          LastSessionManifest.fromJson(json),
          equals(LastSessionManifest.empty),
        );
      });

      test('single-tab manifest round-trips', () {
        const m = LastSessionManifest(tabs: [tab1]);
        expect(LastSessionManifest.fromJson(m.toJson()), equals(m));
      });

      test('multi-tab manifest with mixed session paths round-trips', () {
        const m = LastSessionManifest(tabs: [tab1, tab2]);
        expect(LastSessionManifest.fromJson(m.toJson()), equals(m));
      });
    });

    group('fromJson edge cases', () {
      test('missing tabs key returns empty manifest', () {
        final result = LastSessionManifest.fromJson(const {});
        expect(result.tabs, isEmpty);
      });

      test('null tabs value returns empty manifest', () {
        final result = LastSessionManifest.fromJson(const {'tabs': null});
        expect(result.tabs, isEmpty);
      });

      test('tabs with non-Map entries are skipped', () {
        final result = LastSessionManifest.fromJson(
          const {
            'tabs': ['not-a-map', 42, null],
          },
        );
        expect(result.tabs, isEmpty);
      });

      test('tabs list is unmodifiable after fromJson', () {
        final result = LastSessionManifest.fromJson(
          const {
            'tabs': [
              {'filePath': '/x'},
            ],
          },
        );
        expect(
          () => result.tabs.add(tab1),
          throwsUnsupportedError,
        );
      });

      test('extra unknown keys in manifest are ignored', () {
        final result = LastSessionManifest.fromJson(
          const {
            'tabs': [
              {'filePath': '/x'},
            ],
            'future_field': 'ignored',
          },
        );
        expect(result.tabs, hasLength(1));
        expect(result.tabs.first.filePath, equals('/x'));
      });

      test('empty tabs array returns manifest with no tabs', () {
        final result = LastSessionManifest.fromJson(const {
          'tabs': <Object?>[],
        });
        expect(result.tabs, isEmpty);
      });
    });

    test('toString contains class name', () {
      expect(
        LastSessionManifest.empty.toString(),
        contains('LastSessionManifest'),
      );
    });
  });
}
