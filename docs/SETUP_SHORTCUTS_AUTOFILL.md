# 快捷键与自动填充配置说明

本文件说明 KeyRing 的快捷键（应用内 + 桌面全局）与系统自动填充（Android/iOS）的使用与配置。

## 一、应用内快捷键（所有平台）

| 快捷键 | macOS | Windows/Linux | 动作 |
|---|---|---|---|
| 导入 | `Cmd+I` | `Ctrl+I` | 打开导入面板（文件 / 扫码 / 截图） |
| 导出 | `Cmd+E` | `Ctrl+E` | 导出 JSON |
| 搜索 | `Cmd+F` | `Ctrl+F` | 聚焦搜索框 |
| 锁定 | `Cmd+L` | `Ctrl+L` | 立即锁定 |

实现：`lib/utils/app_shortcuts.dart`（`ShortcutBus` 消息总线）+ `lib/main.dart` 根节点 `Shortcuts/Actions`。

## 二、桌面全局快速填充（1Password 式）

- **默认热键**：macOS `Cmd+Shift+Space`，Windows/Linux `Ctrl+Shift+Space`
- **流程**：任意应用中按热键 → KeyRing 记住当前前台应用并弹出置顶候选面板（中心对齐鼠标光标，自动夹在屏幕可视区内）→ `↑↓` 选择、`↵` 填充、`Esc` 关闭 → 自动切回原应用并输入「用户名 → Tab → 密码」
- 面板每次呼起都会刷新条目；10 秒无操作或失焦自动隐藏
- 填充失败（如未授权辅助功能）会在面板内显示原因
- **锁定保护**：KeyRing 处于锁定状态时按热键不会弹出条目列表，只会唤起主窗口的解锁界面
- **热键冲突检测**：录制新热键时先向系统预检组合是否被其它应用占用（macOS Carbon / Windows RegisterHotKey 试注册探测），被占用时保留原热键并提示；`⌘Space`、`⌘Tab`（Windows 为 `Win+L`）等系统保留组合会被拦截
- 媒体键等无法注册的按键会被拒绝（避免原生层崩溃）；只按住修饰键未按主键时不会误报错误

### macOS 首次使用需授权

系统键盘模拟（CGEvent）需要辅助功能权限：

1. 系统设置 → 隐私与安全性 → 辅助功能
2. 添加并勾选 KeyRing

### Windows

无需额外权限；若被安全软件拦截模拟输入，需将 KeyRing 加入白名单。

### Linux

前台应用记忆与模拟输入暂不可用：按热键可以呼起面板，但选中条目后会提示无法确定填充目标（不会盲打密码）。

实现：
- `lib/services/global_hotkey_service.dart`（hotkey_manager + 注册前占用预检）
- `lib/services/hotkey_probe_service.dart`（平台通道 `keyring/hotkeycheck`）
- `lib/services/foreground_app_service.dart`（平台通道 `keyring/foreground`：记忆/恢复前台应用、呼出面板前激活自身抢键盘焦点）
- `lib/quick_fill/`（宿主 `quick_fill_host.dart` + 子窗口 `window_entry.dart`）
- `lib/services/app_lock_state.dart`（锁定状态门禁）
- `lib/services/keyboard_inject_service.dart`（平台通道 `keyring/keyboard`）
- `macos/Runner/AppDelegate.swift`（CGEvent、Carbon 热键探测、面板样式）
- `windows/runner/keyboard_inject.cpp`（SendInput、RegisterHotKey 探测）

## 三、Android 系统自动填充

1. 系统设置 → 密码和自动填充（或「密码、通行码和自动填充」）
2. 自动填充服务选择 **KeyRing**
3. 在任意应用登录框点击即可看到 KeyRing 候选

实现：`android/app/src/main/kotlin/com/example/key_ring/KeyRingAutofillService.kt`
（直接只读查询 `app_flutter/KeyRing.db`；需 Android 8.0+）

## 四、iOS 密码自动填充（Credential Provider Extension）

### 用户开启方式

系统设置 → 密码 → 密码选项 → 自动填充来源勾选 **KeyRing**。之后在网页/App 登录框点键盘上的「密码」即可选择条目。

### 开发者/发布须知

- 扩展 target `CredentialProvider` 已通过 `ios/add_credential_provider_target.rb`（幂等脚本，可重复运行）加入工程，并随主 app 一起构建。
- 主 app 会在启动和退后台时把 `KeyRing.db` 拷贝到 App Group `group.com.example.keyRing.shared`，扩展只读该副本。
- **发布前必须在 Apple Developer 后台为两个 App ID（主 app 与扩展）启用 App Groups capability**（组 ID：`group.com.example.keyRing.shared`），扩展还需 `AutoFill Credential Provider` capability，否则真机签名安装会失败。
- 注意：当前扩展为「手动选择」模式，不支持静默填充（那需要实现凭据标识同步 ASCredentialIdentityStore，可作为后续增强）。

### 安全提示

KeyRing 数据库当前未加密，App Group 副本对扩展与主 app 可见。若未来对数据库加密，需要同步改造本扩展的读取逻辑。

## 五、已知限制

- **Web**：全局填充与 OCR 不可用（浏览器沙箱 / ML Kit 无 Web 支持）；应用内快捷键与文件导入可用。
- **桌面热键占用**：macOS/Windows 注册前会做占用预检并在设置页显示注册状态；Linux 无法探测，注册结果以设置页状态为准。
- **OCR**：识别结果仅供参考，导入前务必在确认表单中复核。
