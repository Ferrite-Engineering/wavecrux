import Cocoa
import FlutterMacOS

/// Platform channel plugin that manages macOS security-scoped bookmarks.
///
/// Security-scoped bookmarks allow a sandboxed app to regain access to
/// user-selected files across app launches without showing another file picker.
/// The lifecycle is:
///   1. User picks a file → file picker grants access for this session.
///   2. Call `createBookmark` to persist access rights as opaque bookmark data.
///   3. On next launch, call `resolveBookmark` to restore access before reading.
///   4. Call `stopAccessing` when the file is no longer needed.
///
/// Channel name: `com.wavecrux/security_bookmarks`
/// Methods:
///   - `createBookmark({path: String})` → String (base64 bookmark)
///   - `resolveBookmark({bookmark: String})` → {path: String, isStale: Bool}
///   - `stopAccessing({path: String})` → null
class SecurityBookmarkPlugin {
  private let channel: FlutterMethodChannel
  // Tracks URLs we are currently accessing so stopAccessing can find them.
  private var accessedURLs: [String: URL] = [:]

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.wavecrux/security_bookmarks",
      binaryMessenger: messenger)
    channel.setMethodCallHandler(handle)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "createBookmark":
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "path is required", details: nil))
        return
      }
      createBookmark(path: path, result: result)

    case "resolveBookmark":
      guard let args = call.arguments as? [String: Any],
            let base64 = args["bookmark"] as? String,
            let data = Data(base64Encoded: base64) else {
        result(FlutterError(code: "INVALID_ARGS", message: "bookmark is required", details: nil))
        return
      }
      resolveBookmark(data: data, result: result)

    case "stopAccessing":
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "path is required", details: nil))
        return
      }
      stopAccessing(path: path, result: result)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func createBookmark(path: String, result: @escaping FlutterResult) {
    let url = URL(fileURLWithPath: path)
    do {
      let data = try url.bookmarkData(
        options: .withSecurityScope,
        includingResourceValuesForKeys: nil,
        relativeTo: nil)
      result(data.base64EncodedString())
    } catch {
      result(FlutterError(
        code: "BOOKMARK_CREATE_FAILED",
        message: error.localizedDescription,
        details: nil))
    }
  }

  private func resolveBookmark(data: Data, result: @escaping FlutterResult) {
    var isStale = false
    do {
      let url = try URL(
        resolvingBookmarkData: data,
        options: .withSecurityScope,
        relativeTo: nil,
        bookmarkDataIsStale: &isStale)

      guard url.startAccessingSecurityScopedResource() else {
        result(FlutterError(
          code: "ACCESS_DENIED",
          message: "startAccessingSecurityScopedResource returned false",
          details: nil))
        return
      }

      let resolvedPath = url.path
      // If a prior access for the same path is open, stop it first.
      if let prior = accessedURLs[resolvedPath] {
        prior.stopAccessingSecurityScopedResource()
      }
      accessedURLs[resolvedPath] = url
      result(["path": resolvedPath, "isStale": isStale])
    } catch {
      result(FlutterError(
        code: "BOOKMARK_RESOLVE_FAILED",
        message: error.localizedDescription,
        details: nil))
    }
  }

  private func stopAccessing(path: String, result: @escaping FlutterResult) {
    if let url = accessedURLs.removeValue(forKey: path) {
      url.stopAccessingSecurityScopedResource()
    }
    result(nil)
  }
}
