import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var bookmarkPlugin: SecurityBookmarkPlugin?
  private var windowAttentionPlugin: WindowAttentionPlugin?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 800, height: 500)

    // Hide the redundant window title bar text. The native macOS menu bar
    // (PlatformMenuBar) lives at the top of the screen and the in-app toolbar
    // sits below the title-bar area, so showing "wavecrux" between them is
    // chrome the user does not need.
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true

    RegisterGeneratedPlugins(registry: flutterViewController)
    bookmarkPlugin = SecurityBookmarkPlugin(messenger: flutterViewController.engine.binaryMessenger)
    windowAttentionPlugin = WindowAttentionPlugin(messenger: flutterViewController.engine.binaryMessenger)
    // Registers the channels a Finder double-click delivers on. The singleton
    // buffers anything that arrived before now, which on a cold launch is the
    // document that caused the launch in the first place.
    IncomingFilePlugin.shared.register(with: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}
