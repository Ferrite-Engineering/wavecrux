// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The capability boundaries an editor host introduces.
///
/// Each one is a real limitation of running WaveCrux inside an editor panel
/// rather than as a desktop application, and each is stated in the app in the
/// voice `fsdbWebUnsupportedMessage` established: **what the limitation is,
/// why it exists, and what to do about it** — no wheedling, no countdown, no
/// "upgrade now".
///
/// ### Why an enum and not four ad-hoc widgets
///
/// The four boundaries surface in four different places (a banner over the
/// waveform, two panel empty states, the empty canvas), and the temptation
/// with four surfaces is four voices. Naming them once, and resolving their
/// words through one function
/// (`features/editor_host/editor_host_capability_copy.dart`), is what keeps a
/// later edit to one of them from quietly making it the odd one out.
///
/// ### Nothing here is hidden
///
/// The suite rule that gated features stay **visible and badged, never
/// hidden** applies to capability boundaries just as it does to tier gates.
/// [stage] in particular is deliberately *present and empty with an
/// explanation* rather than omitted: an engineer who cannot find the Stage
/// panel learns nothing, and one who finds it empty with a sentence in it
/// learns exactly what the desktop app is for.
enum EditorHostCapability {
  /// A parse that took long enough to be worth explaining.
  ///
  /// Raised on **measured duration**, never on file size — see
  /// `kEditorHostSlowParseThreshold` and
  /// `WaveformSourceNotifier.lastParseTime`. A size threshold would be a
  /// guess about the machine, the format and the signal count all at once,
  /// and would fire on a 200 MB file that parsed in a second while staying
  /// silent on the 30 MB gate-level FST that took twelve.
  slowParse,

  /// The Stage panel: present in the editor panel, empty, and explained.
  stage,

  /// Interactive / streaming VCD — stdin and named pipes, which a webview
  /// has neither of.
  interactiveVcd,

  /// The RTL Source panel, which needs to read HDL files off disk.
  rtlAnnotation,
}
