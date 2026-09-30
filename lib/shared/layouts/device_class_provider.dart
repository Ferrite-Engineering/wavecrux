// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui' show Size;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/enums/device_class.dart';

part 'device_class_provider.g.dart';

/// Whether the app is running as a **native desktop** application (macOS,
/// Windows, or Linux), as opposed to web or a mobile/touch OS.
///
/// On these hosts the windowed app always uses the desktop IDE layout: the
/// window shrinks only to its OS-enforced minimum size, but the content never
/// reflows to the tablet/phone layout. Rationale: a small desktop window is
/// still a desktop — it has a mouse, a keyboard, and a user who expects the
/// multi-pane IDE — so window *width* alone must not demote it to touch-sized
/// chrome. Web and mobile keep the size-driven classification (a narrow browser
/// tab, or a phone/tablet in split-screen, genuinely needs the adaptive
/// layout). This is the one deliberate exception to the otherwise size-only
/// rule in [DeviceClass.fromSize].
bool get isDesktopHostPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux);

/// Host-aware device-class classification — the single entry point every layout
/// decision should use.
///
/// Returns [DeviceClass.desktop] unconditionally on [isDesktopHostPlatform];
/// otherwise classifies by [size] via [DeviceClass.fromSize] (compound
/// width+height), defaulting to desktop when the size is not yet known.
///
/// **That default is a layout convenience, not an answer.** A caller that
/// cannot afford to be wrong before the first frame — telemetry is the one such
/// caller — must use [resolvedDeviceClassForSize] and handle the `null`.
DeviceClass deviceClassForSize(Size? size) =>
    resolvedDeviceClassForSize(size) ?? DeviceClass.desktop;

/// [deviceClassForSize] without the pre-layout default: `null` means "not
/// knowable yet", and it is a state that really happens.
///
/// On [isDesktopHostPlatform] the answer is unconditional and never `null` —
/// the window is a desktop window whatever its size, so there is nothing to
/// wait for. Everywhere else the classification needs a display size, and until
/// `DisplaySizeFeed` has pushed one there is no honest answer to give.
///
/// Exists because [deviceClassForSize]'s desktop default is safe for **layout**
/// consumers, which build inside the widget tree and therefore after the first
/// size, and unsafe for anything that reads from outside it. Telemetry's
/// envelope is assembled by a service on the launch flush, ahead of the tree:
/// it observed the default on three of four launches of one build on one
/// tablet, and reported `desktop` from a `w800dp` portrait device. A defaulted
/// layout decision draws the wrong chrome for one frame; a defaulted
/// `form_factor` is accepted by the ingestion Worker and silently books mobile
/// installations as desktop forever.
DeviceClass? resolvedDeviceClassForSize(Size? size) {
  if (isDesktopHostPlatform) return DeviceClass.desktop;
  if (size == null) return null;
  return DeviceClass.fromSize(size.width, size.height);
}

/// Holds the current display size in logical pixels.
///
/// Source of truth for [deviceClassProvider]. Maintained by `DisplaySizeFeed`
/// (mounted once near the app root inside `MaterialApp.builder`), which watches
/// `MediaQuery.sizeOf` and calls [DisplaySizeNotifier.set] whenever the
/// dimensions change.
///
/// Initially `null` — consumers should treat that as "size not yet known"
/// and either default to a sensible class or wait for the first frame.
@Riverpod(keepAlive: true)
class DisplaySizeNotifier extends _$DisplaySizeNotifier {
  @override
  Size? build() => null;

  /// Updates the current display size. Idempotent — no-op when [size]
  /// equals the current state.
  void set(Size size) {
    if (state == size) return;
    state = size;
  }
}

/// Current [DeviceClass] derived from [displaySizeProvider].
///
/// Re-evaluates whenever the host pushes a new size (window resize,
/// orientation change, split-screen entry/exit). Delegates to
/// [deviceClassForSize], so on a native desktop host it is always
/// [DeviceClass.desktop] regardless of window size, and on web/mobile it uses
/// [DeviceClass.fromSize]'s compound width+height classification.
///
/// When the size has not been reported yet (and the host is not desktop), it
/// defaults to [DeviceClass.desktop].
///
/// **That default is never observed by a layout consumer, and is observed by
/// others.** Every consumer inside the widget tree builds after
/// `DisplaySizeFeed` has pushed the first size — on phone and tablet the splash
/// screen runs before the tree does — so for layout the default is unreachable.
/// It is reachable, and was reached, by a reader outside the tree: telemetry
/// resolves its envelope from a service on the launch flush, saw the default on
/// three of four launches of one build on one tablet, and reported `desktop`
/// from a `w800dp` portrait device. Readers in that position take
/// [resolvedDeviceClassForSize] and handle "not yet".
@riverpod
DeviceClass deviceClass(Ref ref) =>
    deviceClassForSize(ref.watch(displaySizeProvider));
