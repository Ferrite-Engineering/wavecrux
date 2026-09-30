// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Web-specific file loading via the browser File API.
//
// Uses `file_picker` with `withData: true` to obtain raw bytes from the
// browser file dialog. On Flutter Web `FilePicker` returns null for
// `PlatformFile.path` but populates `PlatformFile.bytes`.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:wavecrux/services/pack/wavecrux_pack_spec.dart';

/// Signature for the underlying browser file-pick call used by
/// [WebFileLoader]. Injected so tests can supply synthetic bytes —
/// `file_picker` 12 made `FilePicker.pickFiles` a static method, so it can no
/// longer be replaced via `FilePicker.platform = mock`.
typedef WebPickFiles = Future<FilePickerResult?> Function();

/// Default [WebPickFiles] backed by the static `FilePicker.pickFiles`.
///
/// `withData: true` is passed explicitly: web byte consumption depends on
/// `PlatformFile.bytes` being populated, and we do not want to silently rely
/// on the implicit `kIsWeb` default for that contract.
Future<FilePickerResult?> defaultWebPickFiles() => FilePicker.pickFiles(
  // file_picker 12 deprecates withData but it remains the supported way to
  // force eager byte loading on web.
  // ignore: deprecated_member_use
  withData: true,
  type: FileType.custom,
  // `wavecruxpack` is here because the browser is where a recipient who does
  // not have WaveCrux ends up — which is most recipients, and the entire
  // reason the format exists. A share bundle you can only open by installing
  // something first is a worse email attachment than a screenshot.
  allowedExtensions: [
    'vcd',
    'fst',
    'ghw',
    'lxt',
    'lxt2',
    WaveCruxPackSpec.fileExtension.substring(1),
  ],
);

/// The result of a successful web file pick.
@immutable
class WebPickResult {
  const WebPickResult({required this.bytes, required this.name});

  /// Raw file bytes from the browser.
  final Uint8List bytes;

  /// The file's basename (e.g. `"dump.vcd"`).
  final String name;
}

/// Utility for picking waveform files on Flutter Web.
///
/// On web, [FilePicker] does not provide a filesystem path — it provides
/// raw bytes via the browser File API. This class handles that path and
/// exposes a simple [pickFile] method.
///
/// Use [isLargeFile] to decide whether to show a size-warning dialog before
/// loading — large files on the main thread can cause visible jank in the
/// browser, and WASM linear memory grows in 64 KB pages with the same
/// real-RAM cost as the desktop build.
class WebFileLoader {
  /// Creates a loader. [pickFiles] defaults to [defaultWebPickFiles]; tests
  /// inject a stub that returns synthetic [FilePickerResult] bytes.
  const WebFileLoader({WebPickFiles pickFiles = defaultWebPickFiles})
    : _pickFiles = pickFiles;

  final WebPickFiles _pickFiles;

  /// Files larger than this threshold trigger a size warning. It is
  /// 100 MB (matching the mobile-phone budget) because the
  /// WASM provider is significantly faster than the Dart fallback for both
  /// VCD and the newly supported FST/GHW formats.
  static const int fileSizeWarningThresholdBytes = 100 * 1024 * 1024; // 100 MB

  /// Returns `true` when [sizeBytes] exceeds [fileSizeWarningThresholdBytes].
  static bool isLargeFile(int sizeBytes) =>
      sizeBytes > fileSizeWarningThresholdBytes;

  /// Opens the browser file picker and returns the selected file's bytes.
  ///
  /// Returns `null` if the user cancelled the dialog or no bytes were returned
  /// (which should not happen for a successful pick on web). Asserts that this
  /// is only called on [kIsWeb].
  ///
  /// Web WASM parsing extends the accepted extensions from
  /// VCD-only to `vcd`, `fst`, and `ghw` because the `WellenWasmProvider` can
  /// decode all three. `lxt` / `lxt2` are accepted too — those route through
  /// the WASM `lxt2fst` converter in `WaveformSourceNotifier.openFromBytes`
  /// before the wellen WASM module touches the buffer.
  Future<WebPickResult?> pickFile() async {
    assert(kIsWeb, 'WebFileLoader.pickFile is only for Flutter Web');
    final result = await _pickFiles();
    if (result == null || result.files.isEmpty) return null;
    // `.first`, not `.single`: the picker permits a multiple selection and
    // `.single` throws on one, which on web meant the Open button did nothing
    // at all. This method returns one waveform by contract, so the rest are
    // ignored rather than opened.
    final file = result.files.first;
    // `readAsBytes()` returns the eagerly-loaded bytes (withData: true) on web;
    // it replaces the deprecated `PlatformFile.bytes` getter.
    final bytes = await file.readAsBytes();
    return WebPickResult(bytes: bytes, name: file.name);
  }
}
