// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Riverpod providers for the LXT/LXT2 convert-on-open pipeline.
//
// Hand-written (not `@riverpod` generated) so adding the file does not
// require a `build_runner` step on every clone. The Provider shape is the
// same one the generator would emit for a `Lxt2FstConverter`-typed
// keepAlive provider.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/services/waveform/lxt2fst_cache.dart';
import 'package:wavecrux/services/waveform/lxt2fst_converter.dart';

/// The active [Lxt2FstConverter]. Single instance per app lifetime — the
/// native library is loaded lazily on first use and cached internally.
final Provider<Lxt2FstConverter> lxt2FstConverterProvider =
    Provider<Lxt2FstConverter>(
      (ref) => Lxt2FstConverter(),
    );

/// The active [Lxt2FstCache]. Desktop/mobile-only; the web path converts in
/// memory on every open and caches nothing.
final Provider<Lxt2FstCache> lxt2FstCacheProvider = Provider<Lxt2FstCache>(
  (ref) => Lxt2FstCache(),
);
