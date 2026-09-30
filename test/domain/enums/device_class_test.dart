// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/device_class.dart';

void main() {
  group('DeviceClass', () {
    test('has exactly 4 values', () {
      expect(DeviceClass.values.length, 4);
    });

    test('all expected values are present', () {
      expect(
        DeviceClass.values,
        containsAll([
          DeviceClass.phone,
          DeviceClass.phoneLandscape,
          DeviceClass.tablet,
          DeviceClass.desktop,
        ]),
      );
    });

    test('breakpoint constants are stable', () {
      expect(DeviceClass.phoneTabletBreakpoint, 600);
      expect(DeviceClass.tabletDesktopBreakpoint, 1200);
      expect(DeviceClass.phoneLandscapeHeightThreshold, 500);
    });
  });

  group('DeviceClass.fromSize — phone (width < 600)', () {
    test('narrow phone portrait → phone', () {
      expect(DeviceClass.fromSize(400, 800), DeviceClass.phone);
    });

    test('width just below 600 → phone', () {
      expect(DeviceClass.fromSize(599, 800), DeviceClass.phone);
    });

    test('phone with very short height → still phone (width gate first)', () {
      // Width-first rule: if width < 600 we never check the height threshold.
      expect(DeviceClass.fromSize(400, 200), DeviceClass.phone);
    });

    test('zero width → phone', () {
      expect(DeviceClass.fromSize(0, 800), DeviceClass.phone);
    });
  });

  group(
    'DeviceClass.fromSize — phoneLandscape (width ≥ 600, height < 500)',
    () {
      test('typical phone in landscape (700×380) → phoneLandscape', () {
        expect(DeviceClass.fromSize(700, 380), DeviceClass.phoneLandscape);
      });

      test('exactly 600 wide and 380 tall → phoneLandscape', () {
        expect(DeviceClass.fromSize(600, 380), DeviceClass.phoneLandscape);
      });

      test('tablet-class width but height = 499 → phoneLandscape', () {
        expect(DeviceClass.fromSize(900, 499), DeviceClass.phoneLandscape);
      });

      test('desktop-class width but very short → still phoneLandscape', () {
        // A very wide but very short window (e.g. ultrawide cropped) follows
        // the same compound rule — short height takes priority.
        expect(DeviceClass.fromSize(1500, 400), DeviceClass.phoneLandscape);
      });

      test('height = 500 (boundary) → tablet, not phoneLandscape', () {
        expect(DeviceClass.fromSize(900, 500), DeviceClass.tablet);
      });
    },
  );

  group('DeviceClass.fromSize — tablet (600 ≤ width < 1200, height ≥ 500)', () {
    test('typical tablet portrait (800×1100) → tablet', () {
      expect(DeviceClass.fromSize(800, 1100), DeviceClass.tablet);
    });

    test('typical tablet landscape (1100×800) → tablet', () {
      expect(DeviceClass.fromSize(1100, 800), DeviceClass.tablet);
    });

    test('exactly at lower width boundary (600×600) → tablet', () {
      expect(DeviceClass.fromSize(600, 600), DeviceClass.tablet);
    });

    test('width just below desktop boundary (1199×800) → tablet', () {
      expect(DeviceClass.fromSize(1199, 800), DeviceClass.tablet);
    });

    test('exactly at height boundary (700×500) → tablet', () {
      expect(DeviceClass.fromSize(700, 500), DeviceClass.tablet);
    });
  });

  group('DeviceClass.fromSize — desktop (width ≥ 1200, height ≥ 500)', () {
    test('typical desktop (1400×900) → desktop', () {
      expect(DeviceClass.fromSize(1400, 900), DeviceClass.desktop);
    });

    test('exactly at desktop boundary (1200×800) → desktop', () {
      expect(DeviceClass.fromSize(1200, 800), DeviceClass.desktop);
    });

    test('large 4k display (3840×2160) → desktop', () {
      expect(DeviceClass.fromSize(3840, 2160), DeviceClass.desktop);
    });

    test('desktop width but height = 500 (boundary) → desktop', () {
      expect(DeviceClass.fromSize(1400, 500), DeviceClass.desktop);
    });
  });

  group('DeviceClass.fromSize — defensive inputs', () {
    test('negative width → treated as 0 → phone', () {
      expect(DeviceClass.fromSize(-100, 800), DeviceClass.phone);
    });

    test('negative height → treated as 0 → phoneLandscape (width-class)', () {
      expect(DeviceClass.fromSize(900, -100), DeviceClass.phoneLandscape);
    });

    test('NaN width → treated as 0 → phone', () {
      expect(DeviceClass.fromSize(double.nan, 800), DeviceClass.phone);
    });

    test('infinite width → treated as 0 → phone', () {
      expect(DeviceClass.fromSize(double.infinity, 800), DeviceClass.phone);
    });

    test('zero width and zero height → phone', () {
      expect(DeviceClass.fromSize(0, 0), DeviceClass.phone);
    });
  });

  group('DeviceClass — convenience getters', () {
    test('isPhoneClass — phone is phone-class', () {
      expect(DeviceClass.phone.isPhoneClass, isTrue);
    });

    test('isPhoneClass — phoneLandscape is phone-class', () {
      expect(DeviceClass.phoneLandscape.isPhoneClass, isTrue);
    });

    test('isPhoneClass — tablet is not phone-class', () {
      expect(DeviceClass.tablet.isPhoneClass, isFalse);
    });

    test('isPhoneClass — desktop is not phone-class', () {
      expect(DeviceClass.desktop.isPhoneClass, isFalse);
    });

    test('isMultiPane — tablet is multi-pane', () {
      expect(DeviceClass.tablet.isMultiPane, isTrue);
    });

    test('isMultiPane — desktop is multi-pane', () {
      expect(DeviceClass.desktop.isMultiPane, isTrue);
    });

    test('isMultiPane — phone is not multi-pane', () {
      expect(DeviceClass.phone.isMultiPane, isFalse);
    });

    test('isMultiPane — phoneLandscape is not multi-pane', () {
      expect(DeviceClass.phoneLandscape.isMultiPane, isFalse);
    });
  });

  // The iPhone Duo is the first foldable WaveCrux ships to, and the first
  // device whose class changes while the user holds it. All four poses are
  // pinned here so a future breakpoint edit has to look at them.
  //
  // Logical sizes: the cover display is its 1398×2034 panel at exactly 3x; the
  // inner display's 1878×2670 panel is downsampled, so 669×951 is the reported
  // logical size rather than a division. Verified against Apple's published
  // panel specs on 2026-09-12; re-check on hardware.
  group('DeviceClass.fromSize — iPhone Duo poses', () {
    test('cover display, portrait (466×678) → phone', () {
      expect(DeviceClass.fromSize(466, 678), DeviceClass.phone);
    });

    test('cover display, landscape (678×466) → phoneLandscape', () {
      // Crosses the 600 dp width threshold but is 466 dp tall: exactly the
      // case the secondary height rule exists for.
      expect(DeviceClass.fromSize(678, 466), DeviceClass.phoneLandscape);
    });

    test('inner display, portrait (669×951) → tablet', () {
      expect(DeviceClass.fromSize(669, 951), DeviceClass.tablet);
    });

    test('inner display, landscape (951×669) → tablet', () {
      expect(DeviceClass.fromSize(951, 669), DeviceClass.tablet);
    });

    test('opening the device crosses the phone → tablet boundary', () {
      // The fold transition is a live device-class change, not just a resize:
      // side panes are force-hidden on phone class and restored on tablet.
      final folded = DeviceClass.fromSize(466, 678);
      final open = DeviceClass.fromSize(669, 951);
      expect(folded.isPhoneClass, isTrue);
      expect(open.isPhoneClass, isFalse);
      expect(open.isMultiPane, isTrue);
    });

    test('no Duo pose reaches desktop class', () {
      // 951 dp is the widest the device gets, well under the 1200 dp desktop
      // breakpoint — so the touch metric set always applies.
      for (final (w, h) in const [
        (466.0, 678.0),
        (678.0, 466.0),
        (669.0, 951.0),
        (951.0, 669.0),
      ]) {
        expect(
          DeviceClass.fromSize(w, h),
          isNot(DeviceClass.desktop),
          reason: '$w×$h must not classify as desktop',
        );
      }
    });
  });
}
