import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    KeyboardInjectChannel.register(with: flutterViewController)
    ForegroundAppChannel.register(with: flutterViewController)
    HotkeyCheckChannel.register(with: flutterViewController)
    // 双保险：applicationDidFinishLaunching 之外再挂一次样式器注册
    //（幂等，只是给插件静态回调赋值），确保子窗口样式一定生效。
    QuickFillWindowStyler.install()

    super.awakeFromNib()
  }
}
