import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {

  // MARK: - URL handling

  /// Handles files opened while the app is already running (warm start).
  ///
  /// Called by UIKit when the user taps "Open With WaveCrux" or shares a file
  /// to WaveCrux while the app is in the foreground or background.
  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    // Copy the shared file into the sandbox BEFORE calling super. The parent
    // FlutterSceneDelegate's deep-link handling consumes/invalidates the URL's
    // security scope, so if we run after super, startAccessingSecurityScopedResource
    // fails and the copy of Mail attachments / iCloud / Files-provider URLs fails.
    for context in URLContexts {
      IncomingFilePlugin.shared.handleURL(context.url)
    }
    super.scene(scene, openURLContexts: URLContexts)
  }

  /// Handles files that cold-started the app.
  ///
  /// `super.scene(_:willConnectTo:options:)` is called first so that the
  /// Flutter engine initialises and registers `IncomingFilePlugin` before we
  /// store the pending file path.  By the time Dart's `main()` runs the
  /// pending path is already set and `getInitialFile()` will return it.
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    // Copy the launch file into the sandbox first, while its security scope is
    // still valid (importIntoSandbox is pure Swift and does not need the Flutter
    // engine). The copied path is stored in pendingFilePath and read later by
    // getInitialFile once Dart's main() runs. Then init the engine via super.
    for context in connectionOptions.urlContexts {
      IncomingFilePlugin.shared.handleURL(context.url)
    }
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }
}
