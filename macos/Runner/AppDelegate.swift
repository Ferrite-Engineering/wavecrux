import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// Finder double-click, `open -a`, and drag-onto-the-Dock-icon.
  ///
  /// File URLs are ours; everything else (custom schemes a plugin registered
  /// for) goes to `super`. Splitting rather than always calling `super` keeps
  /// this the single path for a document — the base class may also push the
  /// URL at the framework as a deep link, and two routes opening the same file
  /// is how you get a duplicate tab.
  override func application(_ application: NSApplication, open urls: [URL]) {
    IncomingFilePlugin.shared.handle(urls: urls)
    let others = urls.filter { !$0.isFileURL }
    if !others.isEmpty {
      super.application(application, open: others)
    }
  }
}

/// Delivers documents macOS opens on our behalf to Dart.
///
/// **The gap this closes.** `Info.plist` declares nine `CFBundleDocumentTypes`,
/// so macOS registers WaveCrux as the handler for `.vcd`, `.fst`, `.wavecrux`
/// and `.wavecruxpack`, shows their icons, and offers the app in "Open With" —
/// and then nothing implemented `application(_:open:)`, so every double-click,
/// `open -a` and drag-to-Dock was accepted and silently discarded. Files
/// reached the app only through `argv`, which Finder never uses.
///
/// Registering as a handler and then doing nothing is worse than not
/// registering at all: the file carries our icon, so it looks openable, and the
/// failure is indistinguishable from the app hanging.
///
/// The routing on the Dart side was already written for this — `ViewerScreen`'s
/// runtime-open path names "Finder double-click / `open -a`" and branches to
/// the pack, session and waveform loaders. Only the native half was missing.
///
/// **Reuses the `com.wavecrux/incoming_file` channels** that iOS and Android
/// already implement, rather than inventing a macOS-only contract, so the Dart
/// side needed no new code — only permission to listen on macOS.
///
/// Simpler than the iOS plugin because macOS hands over a real, readable path:
/// the app is not sandboxed (see `Release.entitlements`), so there is no
/// security scope to hold open and no inbox copy to make.
final class IncomingFilePlugin: NSObject {
  static let shared = IncomingFilePlugin()

  private var methodChannel: FlutterMethodChannel?
  private var eventChannel: FlutterEventChannel?
  private var eventSink: FlutterEventSink?

  /// Paths that arrived before Dart was listening.
  ///
  /// A cold launch fires `application(_:open:)` long before `main()` runs, so
  /// without this buffer the case the feature exists for — double-clicking a
  /// pack when the app is *not* already running — would be the one case that
  /// dropped it.
  private var pending: [String] = []

  /// Set once Dart has asked for the cold-start file, so later arrivals go to
  /// the event stream instead of the buffer.
  private var isFlutterReady = false

  private override init() {}

  /// Call from `MainFlutterWindow.awakeFromNib()`, once the engine exists.
  func register(with messenger: FlutterBinaryMessenger) {
    let mc = FlutterMethodChannel(
      name: "com.wavecrux/incoming_file",
      binaryMessenger: messenger)
    mc.setMethodCallHandler { [weak self] call, result in
      guard let self = self, call.method == "getInitialFile" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.isFlutterReady = true
      // Hand back only the first: Dart opens it as the initial file and takes
      // the rest off the event stream, which is the same shape as several
      // files on the command line.
      result(self.pending.isEmpty ? nil : self.pending.removeFirst())
    }
    methodChannel = mc

    let ec = FlutterEventChannel(
      name: "com.wavecrux/incoming_file_stream",
      binaryMessenger: messenger)
    ec.setStreamHandler(self)
    eventChannel = ec
  }

  /// Forwards each file URL; non-file URLs are not ours to open.
  func handle(urls: [URL]) {
    for url in urls where url.isFileURL {
      if isFlutterReady, let sink = eventSink {
        sink(url.path)
      } else {
        pending.append(url.path)
      }
    }
  }
}

// MARK: - FlutterStreamHandler

extension IncomingFilePlugin: FlutterStreamHandler {
  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    // Drain anything that landed between `getInitialFile` and this subscription
    // — a second file in the same Finder selection, or a fast second
    // double-click during startup.
    let queued = pending
    pending.removeAll()
    for path in queued {
      events(path)
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}
