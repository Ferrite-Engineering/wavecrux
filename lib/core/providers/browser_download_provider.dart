// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Hands a finished document to the browser as a download named [fileName].
typedef BrowserDownload =
    Future<void> Function({
      required String fileName,
      required Uint8List bytes,
    });

/// How a saved document leaves the web build: as a browser download.
///
/// `null` off the web, where saving picks a path in the OS save dialog and
/// writes to it. A browser has no dialog that returns a path —
/// `FilePicker.saveFile` refuses the empty placeholder bytes that flow passes
/// and returns no path — so the web build builds the document in memory
/// first and downloads it instead. Tests override this to run that branch.
final browserDownloadProvider = Provider<BrowserDownload?>(
  (ref) => kIsWeb ? downloadInBrowser : null,
  name: 'browserDownloadProvider',
);

/// Starts a browser download of [bytes] as [fileName].
///
/// On the web `FilePicker.saveFile` performs the download itself and returns
/// `null`; there is no dialog to cancel.
Future<void> downloadInBrowser({
  required String fileName,
  required Uint8List bytes,
}) async {
  await FilePicker.saveFile(fileName: fileName, bytes: bytes);
}
