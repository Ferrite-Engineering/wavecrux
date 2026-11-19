// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// On Windows file_picker gives its dialog the app window as owner only when a
// call passes `lockParentWindow: true`; an unowned dialog can open behind the
// window, so File > Open seemed to do nothing. The app opens dialogs from many
// screens and none passes the flag, so one wrapper owns them all.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/platform/owned_file_dialogs.dart';

/// Records the `lockParentWindow` each dialog was asked for.
class _Recorder extends FilePickerPlatform {
  final Map<String, bool> locked = <String, bool>{};

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
  }) async {
    locked['pickFiles'] = lockParentWindow;
    return null;
  }

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
    AndroidSAFOptions? androidSafOptions,
  }) async {
    locked['getDirectoryPath'] = lockParentWindow;
    return null;
  }

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
  }) async {
    locked['saveFile'] = lockParentWindow;
    return null;
  }
}

void main() {
  test('every dialog is asked to be owned by the app window', () async {
    final inner = _Recorder();
    final picker = OwnedFilePicker(inner);

    await picker.pickFiles();
    await picker.getDirectoryPath();
    await picker.saveFile(fileName: 'a.csv', bytes: Uint8List(0));

    expect(inner.locked, {
      'pickFiles': true,
      'getDirectoryPath': true,
      'saveFile': true,
    });
  });

  test('the other arguments reach the platform unchanged', () async {
    String? title;
    String? folder;
    List<String>? extensions;
    final picker = OwnedFilePicker(
      _Capturing((t, f, e) {
        title = t;
        folder = f;
        extensions = e;
      }),
    );

    await picker.pickFiles(
      dialogTitle: 'Open waveform',
      initialDirectory: r'C:\sims',
      type: FileType.custom,
      allowedExtensions: const ['vcd', 'fst'],
    );

    expect(title, 'Open waveform');
    expect(folder, r'C:\sims');
    expect(extensions, ['vcd', 'fst']);
  });

  test('useOwnedFileDialogsOnWindows installs it on Windows only, once', () {
    final original = FilePickerPlatform.instance;
    addTearDown(() {
      FilePickerPlatform.instance = original;
      debugDefaultTargetPlatformOverride = null;
    });

    for (final other in [
      TargetPlatform.macOS,
      TargetPlatform.linux,
      TargetPlatform.android,
      TargetPlatform.iOS,
    ]) {
      debugDefaultTargetPlatformOverride = other;
      useOwnedFileDialogsOnWindows();
      expect(FilePickerPlatform.instance, same(original), reason: '$other');
    }

    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    useOwnedFileDialogsOnWindows();
    final installed = FilePickerPlatform.instance;
    expect(installed, isA<OwnedFilePicker>());
    expect((installed as OwnedFilePicker).inner, same(original));

    useOwnedFileDialogsOnWindows();
    expect(FilePickerPlatform.instance, same(installed));
  });
}

class _Capturing extends FilePickerPlatform {
  _Capturing(this.onCall);

  final void Function(String?, String?, List<String>?) onCall;

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
  }) async {
    onCall(dialogTitle, initialDirectory, allowedExtensions);
    return null;
  }
}
