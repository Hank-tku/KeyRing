import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 启动和进入后台时把数据库同步到 App Group，
    // 供 CredentialProvider 扩展只读访问（系统自动填充）。
    AppGroupDbSync.copyDatabaseToSharedContainer()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationWillResignActive(_ application: UIApplication) {
    AppGroupDbSync.copyDatabaseToSharedContainer()
    super.applicationWillResignActive(application)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

/// 把 app_flutter/KeyRing.db 拷贝到 App Group 共享容器。
enum AppGroupDbSync {
  static let appGroupId = "group.com.example.keyRing.shared"

  static func copyDatabaseToSharedContainer() {
    guard
      let container = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupId)
    else { return }

    // sqflite 在 iOS 的数据库位置随版本可能是 Documents 或 Library，
    // 依次探测。
    let fm = FileManager.default
    var candidates: [URL] = []
    if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
      candidates.append(docs.appendingPathComponent("KeyRing.db"))
    }
    if let library = fm.urls(for: .libraryDirectory, in: .userDomainMask).first {
      candidates.append(library.appendingPathComponent("KeyRing.db"))
      candidates.append(
        library.appendingPathComponent("Databases/KeyRing.db"))
    }

    guard let src = candidates.first(where: { fm.fileExists(atPath: $0.path) })
    else { return }
    let dst = container.appendingPathComponent("KeyRing.db")

    do {
      if fm.fileExists(atPath: dst.path) {
        try fm.removeItem(at: dst)
      }
      try fm.copyItem(at: src, to: dst)
    } catch {
      // 同步失败不影响主流程；扩展下次打开时会再尝试。
    }
  }
}
