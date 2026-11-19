// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// file_picker's dialogs on Windows, owned by the app window.
///
/// file_picker's Windows code shows its dialog from a background isolate
/// and gives it the app window as owner only when a call passes
/// `lockParentWindow: true`. Without an owner the dialog is a free-standing
/// top-level window, and Windows may place it behind the window that
/// asked for it, so File > Open appears to do nothing until the dialog is
/// found underneath. An owned dialog stays above its owner until it closes.
///
/// No call in the app passes the flag, and dialogs are opened from some two
/// dozen places. This wraps the platform implementation so that every pick,
/// save and folder dialog is owned, whichever screen opens it.
class OwnedFilePicker extends FilePickerPlatform {
  /// Wraps [inner], file_picker's own implementation for the platform.
  OwnedFilePicker(this.inner);

  /// The implementation each call is handed on to.
  final FilePickerPlatform inner;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    void Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
    bool cancelUploadOnWindowBlur = true,
    AndroidSAFOptions? androidSafOptions,
  }) => inner.pickFiles(
    dialogTitle: dialogTitle,
    initialDirectory: initialDirectory,
    type: type,
    allowedExtensions: allowedExtensions,
    onFileLoading: onFileLoading,
    compressionQuality: compressionQuality,
    allowMultiple: allowMultiple,
    withData: withData,
    withReadStream: withReadStream,
    lockParentWindow: true,
    readSequential: readSequential,
    cancelUploadOnWindowBlur: cancelUploadOnWindowBlur,
    androidSafOptions: androidSafOptions,
  );

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
    AndroidSAFOptions? androidSafOptions,
  }) => inner.getDirectoryPath(
    dialogTitle: dialogTitle,
    lockParentWindow: true,
    initialDirectory: initialDirectory,
    androidSafOptions: androidSafOptions,
  );

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    // The platform interface's own parameter order.
    // ignore: always_put_required_named_parameters_first
    required String fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    // The platform interface's own parameter order.
    // ignore: always_put_required_named_parameters_first
    required Uint8List bytes,
    void Function(FilePickerStatus)? onFileLoading,
    bool lockParentWindow = false,
  }) => inner.saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    initialDirectory: initialDirectory,
    type: type,
    allowedExtensions: allowedExtensions,
    bytes: bytes,
    onFileLoading: onFileLoading,
    lockParentWindow: true,
  );

  @override
  Future<List<String>?> pickFileAndDirectoryPaths({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
  }) => inner.pickFileAndDirectoryPaths(
    dialogTitle: dialogTitle,
    initialDirectory: initialDirectory,
    type: type,
    allowedExtensions: allowedExtensions,
  );

  @override
  Future<void> releaseSAFGrant(String uri) => inner.releaseSAFGrant(uri);

  @override
  Future<bool?> clearTemporaryFiles() => inner.clearTemporaryFiles();

  @override
  Future<void> skipEntitlementsChecks() => inner.skipEntitlementsChecks();
}

/// Makes every file dialog on Windows owned by the app window.
///
/// Called once from `bootstrap()`, after the binding is initialized. Other
/// platforms are left as they are, and a second call changes nothing.
void useOwnedFileDialogsOnWindows() {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
  final current = FilePickerPlatform.instance;
  if (current is OwnedFilePicker) return;
  FilePickerPlatform.instance = OwnedFilePicker(current);
}
