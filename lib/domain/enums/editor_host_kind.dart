// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Which editor, if any, is hosting this build.
///
/// The question this answers is *not* "which platform am I" — `kIsWeb` and
/// `defaultTargetPlatform` already answer that, and both give the same reply
/// inside a VSCode webview as they do in a browser tab. It answers "is there an
/// extension host on the other end of the bridge", which nothing about the
/// platform can tell us.
///
/// The signal must come from the **host bridge** — the thing that only exists
/// when an editor is hosting us — and never from sniffing the user agent or the
/// URL scheme. A user agent is a string a browser is free to change and a
/// webview is free to imitate; deriving a telemetry bucket from it would make
/// the bucket a guess, and a wrong `form_factor` is accepted by the ingestion
/// Worker and reads as measurement forever after.
///
/// **The answer is available synchronously at startup**, which is why there is
/// no `unknown` case and why nothing here ever has to defer. The editor-host
/// bridge's web implementation reads a marker the extension's `index.html` shim
/// sets before `main.dart.js` runs; a browser build finds no marker and is
/// [none] from the first frame. A tri-state would be the honest shape only if
/// the answer arrived asynchronously — and it would then defer forever in a
/// plain browser, where nobody is ever going to answer.
///
/// Pure Dart — no Flutter imports.
enum EditorHostKind {
  /// No editor host: a native window, a mobile app, or a plain browser tab.
  none,

  /// A VSCode extension host — the app is running inside a webview owned by the
  /// EDACrux extension pack rather than in a browser tab.
  ///
  /// Reports `form_factor: 'vscode'`. `os` stays `'web'`, which remains honest:
  /// it is still the web build, and the host OS is not worth a second mechanism
  /// to recover.
  vscode,
}
