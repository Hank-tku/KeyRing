import Carbon
import Cocoa
import desktop_multi_window
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // 常驻菜单栏模式（借鉴 1Password）：关窗只是隐藏窗口（Flutter 侧
    // window_manager preventClose 会拦截），退出走托盘菜单。
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    QuickFillWindowStyler.install()
  }
}

/// 把 desktop_multi_window 创建的子窗口样式化成 1Password 式浮动小面板：
/// 无边框视觉、置顶、固定尺寸、打开时中心对齐鼠标光标。
enum QuickFillWindowStyler {
  /// 快速填充面板窗口（弱引用，供每次呼起时重新定位）。
  static weak var panelWindow: NSWindow?

  static func install() {
    // desktop_multi_window 创建子窗口后回调（公开 setter）。
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      guard let window = controller.view.window else { return }
      panelWindow = window

      // 保留 titled 以便可成为 key window，但视觉上完全无边框。
      window.styleMask.insert(.fullSizeContentView)
      window.titlebarAppearsTransparent = true
      window.titleVisibility = .hidden
      window.standardWindowButton(.closeButton)?.isHidden = true
      window.standardWindowButton(.miniaturizeButton)?.isHidden = true
      window.standardWindowButton(.zoomButton)?.isHidden = true
      window.isMovable = false
      window.styleMask.remove(.resizable)
      window.level = .floating
      window.isOpaque = false
      window.backgroundColor = .clear
      window.hasShadow = true
      window.hidesOnDeactivate = false

      // 尺寸固定；位置在每次呼起时由 centerPanelAtMouse 定位。
      let size = NSSize(width: 460, height: 520)
      window.setContentSize(size)
      positionAtMouse(window)
    }
  }

  /// 面板中心对齐鼠标光标，并夹在鼠标所在屏幕的可视区内。
  @discardableResult
  static func positionAtMouse(_ window: NSWindow?) -> Bool {
    guard let window = window else { return false }
    let mouse = NSEvent.mouseLocation
    let screen =
      NSScreen.screens.first { NSPointInRect(mouse, $0.frame) } ?? NSScreen.main
    guard let visible = screen?.visibleFrame else { return false }
    let size = window.frame.size
    var x = mouse.x - size.width / 2
    var y = mouse.y - size.height / 2
    x = min(max(x, visible.minX), visible.maxX - size.width)
    y = min(max(y, visible.minY), visible.maxY - size.height)
    window.setFrame(
      NSRect(x: x, y: y, width: size.width, height: size.height),
      display: false)
    return true
  }
}

/// `keyring/foreground` 平台通道：记录/恢复热键按下时的前台应用。
enum ForegroundAppChannel {
  private static var rememberedApp: NSRunningApplication?

  static func register(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "keyring/foreground",
      binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "remember":
        // 主窗口即将弹出小面板，此刻的前台应用就是填充目标。
        // 前台是 KeyRing 自己（或拿不到）：不记录，避免把密码填给自己。
        let front = NSWorkspace.shared.frontmostApplication
        if let ownId = Bundle.main.bundleIdentifier,
           front?.bundleIdentifier == ownId {
          rememberedApp = nil
          result(false)
          return
        }
        rememberedApp = front
        result(front != nil)
      case "activate":
        guard let app = rememberedApp else {
          result(false)
          return
        }
        let ok: Bool
        if #available(macOS 14.0, *) {
          ok = app.activate()
        } else {
          // 仅 activateAllWindows 从后台激活经常失败，必须叠加 ignoring。
          ok = app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }
        result(ok)
      case "activateSelf":
        // 呼出快速填充面板前把 KeyRing 带回前台：后台 app 的窗口
        // 无法直接成为 key window，搜索框会拿不到键盘焦点。
        NSApp.activate(ignoringOtherApps: true)
        result(true)
      case "centerPanelAtMouse":
        // 每次呼起都把面板中心定位到鼠标光标处（夹在可视区内）。
        result(QuickFillWindowStyler.positionAtMouse(QuickFillWindowStyler.panelWindow))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

/// `keyring/hotkeycheck` 平台通道：全局热键占用预检。
///
/// hotkey_manager 的 register 无条件返回成功（底层 Carbon 注册失败被吞），
/// 冲突检测必须自己做：RegisterEventHotKey 试注册后立即注销——系统级
/// 热键全局排他，注册失败即被其它应用占用。
enum HotkeyCheckChannel {
  static func register(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "keyring/hotkeycheck",
      binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isAvailable":
        guard let args = call.arguments as? [String: Any],
              let keyCode = args["keyCode"] as? Int,
              let modifierNames = args["modifiers"] as? [String]
        else {
          result(FlutterError(code: "bad_args", message: "need keyCode & modifiers", details: nil))
          return
        }
        var carbonModifiers: UInt32 = 0
        for name in modifierNames {
          switch name {
          case "meta": carbonModifiers |= UInt32(cmdKey)
          case "shift": carbonModifiers |= UInt32(shiftKey)
          case "alt": carbonModifiers |= UInt32(optionKey)
          case "control": carbonModifiers |= UInt32(controlKey)
          default: break // capsLock/fn 不参与探测
          }
        }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
          UInt32(keyCode),
          carbonModifiers,
          EventHotKeyID(signature: OSType(0x4B525247), id: 0),
          GetApplicationEventTarget(),
          0,
          &ref)
        if status != noErr {
          result(false)
          return
        }
        if let ref = ref {
          UnregisterEventHotKey(ref)
        }
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

/// `keyring/keyboard` 平台通道：模拟键盘输入（桌面快速填充）。
///
/// 用 CGEvent 逐字符注入：用户名 → Tab → 密码。
/// 需要「系统设置 > 隐私与安全性 > 辅助功能」授权，否则 post 静默失败。
enum KeyboardInjectChannel {
  static func register(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "keyring/keyboard",
      binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "typeCredentials":
        guard let args = call.arguments as? [String: Any],
              let username = args["username"] as? String,
              let password = args["password"] as? String
        else {
          result(FlutterError(code: "bad_args", message: "missing username/password", details: nil))
          return
        }
        result(Self.typeCredentials(username: username, password: password))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// 逐段注入文本；CGEventKeyboardSetUnicodeString 每个事件最多 20 个 UTF-16 单元。
  private static func typeText(_ text: String) -> Bool {
    guard let source = CGEventSource(stateID: .combinedSessionState) else {
      return false
    }
    let units = Array(text.utf16)
    var index = 0
    while index < units.count {
      let end = min(index + 20, units.count)
      var chunk = Array(units[index..<end])
      chunk.append(0) // CGEvent 要求 null 结尾缓冲。
      guard
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
      else { return false }
      chunk.withUnsafeBufferPointer { buf in
        down.keyboardSetUnicodeString(
          stringLength: chunk.count - 1, unicodeString: buf.baseAddress)
        up.keyboardSetUnicodeString(
          stringLength: chunk.count - 1, unicodeString: buf.baseAddress)
      }
      down.post(tap: .cghidEventTap)
      up.post(tap: .cghidEventTap)
      index = end
    }
    return true
  }

  private static func pressTab() {
    guard let source = CGEventSource(stateID: .combinedSessionState),
          let down = CGEvent(keyboardEventSource: source, virtualKey: 0x30, keyDown: true),
          let up = CGEvent(keyboardEventSource: source, virtualKey: 0x30, keyDown: false)
    else { return }
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
  }

  static func typeCredentials(username: String, password: String) -> Bool {
    var ok = true
    if !username.isEmpty {
      ok = typeText(username) && ok
      usleep(80_000)
      pressTab()
      usleep(80_000)
    }
    ok = typeText(password) && ok
    return ok
  }
}
