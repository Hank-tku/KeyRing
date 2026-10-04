import Flutter
import UIKit
import SQLite3

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var autofillChannel: FlutterMethodChannel?
  override func application(_ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    // Drop the old complete-vault copy on upgrade. Only a filtered projection is shared.
    AppGroupDbSync.removeLegacyCopy()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "KeyRingAutofillBridge") else { return }
    autofillChannel = FlutterMethodChannel(name: "keyring/autofill", binaryMessenger: registrar.messenger())
    autofillChannel?.setMethodCallHandler { call, result in
      guard call.method == "refresh", let path = call.arguments as? String else {
        result(FlutterMethodNotImplemented); return
      }
      if AppGroupDbSync.refresh(sourcePath: path) { result(nil) }
      else { result(FlutterError(code: "autofill_refresh_failed", message: "Autofill snapshot unavailable", details: nil)) }
    }
  }
}

/// Publish only unprotected credential columns. Readers never open the main DB
/// or the old full-vault copy. Failed refresh removes the previous projection.
enum AppGroupDbSync {
  static let appGroupId = "group.com.example.keyRing.shared"
  static func removeLegacyCopy() {
    guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else { return }
    for suffix in ["", "-wal", "-shm"] {
      try? FileManager.default.removeItem(at: container.appendingPathComponent("KeyRing.db" + suffix))
    }
  }
  static func refresh(sourcePath: String) -> Bool {
    guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
      // No provisioned App Group means there is no autofill extension to expose data to.
      return true
    }
    let preferences = UserDefaults(suiteName: appGroupId)
    preferences?.set(false, forKey: "autofillProjectionReady")
    let fm = FileManager.default
    let output = container.appendingPathComponent("KeyRing-autofill-v1.db")
    let temporary = container.appendingPathComponent("KeyRing-autofill-pending.db")
    try? fm.removeItem(at: output)
    try? fm.removeItem(at: temporary)
    var source: OpaquePointer?
    var destination: OpaquePointer?
    guard sqlite3_open_v2(sourcePath, &source, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
      sqlite3_close(source); return false
    }
    defer { sqlite3_close(source) }
    guard sqlite3_open(temporary.path, &destination) == SQLITE_OK else {
      sqlite3_close(destination); return false
    }
    defer { sqlite3_close(destination); try? fm.removeItem(at: temporary) }
    guard sqlite3_exec(destination, "CREATE TABLE password_items (id TEXT, title TEXT, username TEXT, password TEXT, isFavorite INTEGER, updatedAt TEXT)", nil, nil, nil) == SQLITE_OK else { return false }
    let sql = """
      SELECT id, title, username, password, isFavorite, updatedAt FROM password_items
      WHERE workspaceId NOT IN (SELECT workspaceId FROM local_workspace_locks)
      """
    var read: OpaquePointer?
    var write: OpaquePointer?
    guard sqlite3_prepare_v2(source, sql, -1, &read, nil) == SQLITE_OK else { return false }
    defer { sqlite3_finalize(read) }
    guard sqlite3_prepare_v2(destination, "INSERT INTO password_items VALUES (?, ?, ?, ?, ?, ?)", -1, &write, nil) == SQLITE_OK else { return false }
    defer { sqlite3_finalize(write) }
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    guard sqlite3_exec(destination, "BEGIN", nil, nil, nil) == SQLITE_OK else { return false }
    var step = sqlite3_step(read)
    while step == SQLITE_ROW {
      for index: Int32 in 0..<6 {
        sqlite3_bind_text(write, index + 1, sqlite3_column_text(read, index), -1, transient)
      }
      guard sqlite3_step(write) == SQLITE_DONE else { return false }
      sqlite3_reset(write)
      step = sqlite3_step(read)
    }
    guard step == SQLITE_DONE, sqlite3_exec(destination, "COMMIT", nil, nil, nil) == SQLITE_OK else { return false }
    do {
      try fm.moveItem(at: temporary, to: output)
      preferences?.set(true, forKey: "autofillProjectionReady")
      return true
    } catch { return false }
  }
}
