import Flutter
import UIKit

/// Platform channel plugin that delivers share-sheet / "Open With" files to Dart.
///
/// Channel: `com.wavecrux/incoming_file` (MethodChannel)
///   • `getInitialFile() → String?` — path of the file that cold-started the app.
///
/// Channel: `com.wavecrux/incoming_file_stream` (EventChannel)
///   • emits `String` — absolute path of each file opened while the app is running.
///
/// ### iOS file delivery
/// When iOS delivers a file via "Open With" or the share sheet it copies the
/// document into the app's `Documents/Inbox/` directory and passes a `file://`
/// URL.  The path is already a local filesystem path — no security-scope
/// management is needed for these temporary inbox copies.
///
/// ### Usage
/// Call `IncomingFilePlugin.shared.register(with:)` from
/// `AppDelegate.didInitializeImplicitFlutterEngine(_:)`.
/// Call `IncomingFilePlugin.shared.handleURL(_:)` from `SceneDelegate` when
/// URL contexts arrive.
class IncomingFilePlugin: NSObject {
    /// Shared singleton — accessed by both AppDelegate and SceneDelegate.
    static let shared = IncomingFilePlugin()

    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?

    /// Path stored before Flutter is ready (cold start).
    private(set) var pendingFilePath: String?
    /// Set to `true` once Flutter calls `getInitialFile()`.
    private var isFlutterReady = false

    private override init() {}

    // MARK: - Registration

    /// Registers method and event channels with the Flutter binary messenger.
    ///
    /// Call this from `AppDelegate.didInitializeImplicitFlutterEngine(_:)` so
    /// channels are ready before Dart's `main()` runs.
    func register(with messenger: FlutterBinaryMessenger) {
        let mc = FlutterMethodChannel(
            name: "com.wavecrux/incoming_file",
            binaryMessenger: messenger)
        mc.setMethodCallHandler(handleMethodCall)
        methodChannel = mc

        let ec = FlutterEventChannel(
            name: "com.wavecrux/incoming_file_stream",
            binaryMessenger: messenger)
        ec.setStreamHandler(self)
        eventChannel = ec
    }

    // MARK: - URL handling

    /// Delivers a file URL received from the system (share sheet or "Open With").
    ///
    /// If Flutter is already running the path is sent via the event stream;
    /// otherwise it is stored as the cold-start pending file.
    ///
    /// ### Why we copy the file
    ///
    /// With `LSSupportsOpeningDocumentsInPlace = true`, iOS may deliver the
    /// original file URL inside a security-scoped resource boundary (Mail
    /// share sheet, Files app, AirDrop).  Reading `url.path` from Dart later
    /// then fails because:
    ///
    ///  1. The security scope is bound to this Swift call, not the Dart
    ///     isolate that runs minutes later.
    ///  2. The original location may be a temporary URL that iOS deletes
    ///     after the share sheet closes.
    ///
    /// We side-step both problems by copying the file into a stable
    /// subdirectory of the app's Documents folder while we still have access
    /// to the security-scoped URL, then handing the local copy's path to
    /// Dart.  The wellen Rust parser opens the local copy with no extra
    /// permissions required.
    func handleURL(_ url: URL) {
        // If the import fails we must NOT fall back to url.path: for security-
        // scoped locations (Mail attachments in Library/Mail/AttachmentsData,
        // Files-provider URLs, AirDrop) that raw path is unreadable from the
        // Dart isolate and surfaces as a PathAccessException ("Operation not
        // permitted"). Drop with a log instead of delivering a broken path.
        // If the import fails, drop rather than deliver the raw url.path: for
        // security-scoped locations that path is unreadable from Dart and would
        // surface as a PathAccessException.
        guard let path = importIntoSandbox(url) else {
            NSLog("IncomingFilePlugin: could not access shared file \(url)")
            return
        }
        if isFlutterReady, let sink = eventSink {
            sink(path)
        } else {
            pendingFilePath = path
        }
    }

    /// Copies [url] into `Documents/SharedImports/` and returns the local path,
    /// or `nil` if the copy fails.
    ///
    /// NOT `Documents/Inbox`: iOS marks that directory read-only, so writing a
    /// copy into it fails with NSFileWriteNoPermissionError.
    private func importIntoSandbox(_ url: URL) -> String? {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer {
            if needsScope { url.stopAccessingSecurityScopedResource() }
        }

        let fm = FileManager.default
        do {
            let docs = try fm.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true)

            // If iOS already copied the file into our Documents directory
            // (the standard "Open With" path when LSSupportsOpeningDocumentsInPlace
            // is *not* in effect), just use that path directly — re-copying
            // it would be wasted work, and on some iOS releases trying to
            // copy a file onto itself returns EEXIST.
            if url.isFileURL && url.path.hasPrefix(docs.path + "/") {
                return url.path
            }

            // Copy into a normal Documents subdirectory — NOT `Documents/Inbox`,
            // which iOS reserves for documents it delivers to us and marks
            // READ-ONLY: writing into Inbox fails with NSFileWriteNoPermissionError
            // (513 / EPERM). This subdirectory is app-writable.
            let importsDir = docs.appendingPathComponent(
                "SharedImports", isDirectory: true)
            if !fm.fileExists(atPath: importsDir.path) {
                try fm.createDirectory(
                    at: importsDir, withIntermediateDirectories: true)
            }

            // Use the original filename so the user can recognize it in
            // Recent Files. If a same-named file already exists from a
            // previous import, replace it with the new contents.
            let dest = importsDir.appendingPathComponent(url.lastPathComponent)
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            // Copy through NSFileCoordinator so files owned by another app
            // (Mail attachments, Files-provider URLs, AirDrop) are read via the
            // provider's coordinator. A raw `copyItem(at:to:)` on these
            // security-scoped locations fails with "Operation not permitted"
            // (errno 1) even inside startAccessingSecurityScopedResource.
            var coordError: NSError?
            var innerError: Error?
            NSFileCoordinator().coordinate(
                readingItemAt: url,
                options: [.withoutChanges],
                error: &coordError
            ) { readURL in
                do {
                    try fm.copyItem(at: readURL, to: dest)
                } catch {
                    innerError = error
                }
            }
            if let err = coordError ?? innerError { throw err }
            return dest.path
        } catch {
            NSLog("IncomingFilePlugin: failed to import \(url): \(error)")
            return nil
        }
    }

    // MARK: - Private

    private func handleMethodCall(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        switch call.method {
        case "getInitialFile":
            isFlutterReady = true
            result(pendingFilePath)
            pendingFilePath = nil
        default:
            result(FlutterMethodNotImplemented)
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
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}
