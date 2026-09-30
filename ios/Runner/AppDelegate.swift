import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Register the incoming-file plugin so the method/event channels are ready
    // before Dart's main() runs and calls getInitialFile().
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "IncomingFilePlugin") {
      IncomingFilePlugin.shared.register(with: registrar.messenger())
    }
  }
}
