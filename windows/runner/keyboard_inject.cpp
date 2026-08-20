#include "keyboard_inject.h"

#include <windows.h>

#include <string>
#include <vector>

namespace keyboard_inject {
namespace {

// 逐字符注入 Unicode 文本（KEYEVENTF_UNICODE，每个字符一次 down/up）。
bool TypeText(const std::wstring& text) {
  std::vector<INPUT> inputs;
  inputs.reserve(text.size() * 2);
  for (wchar_t ch : text) {
    INPUT down = {};
    down.type = INPUT_KEYBOARD;
    down.ki.wScan = static_cast<WORD>(ch);
    down.ki.dwFlags = KEYEVENTF_UNICODE;
    INPUT up = down;
    up.ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP;
    inputs.push_back(down);
    inputs.push_back(up);
  }
  if (inputs.empty()) return true;
  return ::SendInput(static_cast<UINT>(inputs.size()), inputs.data(),
                     static_cast<int>(sizeof(INPUT))) == inputs.size();
}

// 热键唤起小面板前的前台窗口（填充目标）。
HWND g_remembered_hwnd = nullptr;

// keyring/hotkeycheck：全局热键占用预检。
// hotkey_manager 的 RegisterHotKey 返回值被忽略，冲突检测需自己做：
// 试注册（线程消息队列即可，无需窗口）后立即注销，能注册说明未被占用。
void HandleHotkeyCheckCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    flutter::MethodResult<flutter::EncodableValue>& result) {
  if (call.method_name() != "isAvailable") {
    result.NotImplemented();
    return;
  }
  const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
  if (!args) {
    result.Error("bad_args", "arguments must be a map");
    return;
  }
  int key_code = 0;
  auto kc = args->find(flutter::EncodableValue("keyCode"));
  if (kc != args->end()) {
    if (const auto* v = std::get_if<int>(&kc->second)) key_code = *v;
  }
  UINT fs_modifiers = 0;
  auto mods = args->find(flutter::EncodableValue("modifiers"));
  if (mods != args->end()) {
    if (const auto* list = std::get_if<flutter::EncodableList>(&mods->second)) {
      for (const auto& m : *list) {
        if (const auto* s = std::get_if<std::string>(&m)) {
          if (*s == "alt") {
            fs_modifiers |= MOD_ALT;
          } else if (*s == "control") {
            fs_modifiers |= MOD_CONTROL;
          } else if (*s == "shift") {
            fs_modifiers |= MOD_SHIFT;
          } else if (*s == "meta") {
            fs_modifiers |= MOD_WIN;
          }
        }
      }
    }
  }
  constexpr int kProbeHotkeyId = 0x4B52;  // 'KR'
  BOOL ok = ::RegisterHotKey(nullptr, kProbeHotkeyId, fs_modifiers,
                             static_cast<UINT>(key_code));
  if (ok) {
    ::UnregisterHotKey(nullptr, kProbeHotkeyId);
  }
  result.Success(flutter::EncodableValue(ok != FALSE));
}

void HandleForegroundCall(const std::string& method,
                          flutter::MethodResult<flutter::EncodableValue>& result) {
  if (method == "remember") {
    g_remembered_hwnd = ::GetForegroundWindow();
    result.Success(flutter::EncodableValue(g_remembered_hwnd != nullptr));
    return;
  }
  if (method == "activate") {
    if (g_remembered_hwnd == nullptr || !::IsWindow(g_remembered_hwnd)) {
      result.Success(flutter::EncodableValue(false));
      return;
    }
    // 最小化则还原，再切前台。
    if (::IsIconic(g_remembered_hwnd)) {
      ::ShowWindow(g_remembered_hwnd, SW_RESTORE);
    }
    BOOL ok = ::SetForegroundWindow(g_remembered_hwnd);
    result.Success(flutter::EncodableValue(ok != FALSE));
    return;
  }
  result.NotImplemented();
}

bool PressTab() {
  INPUT inputs[2] = {};
  inputs[0].type = INPUT_KEYBOARD;
  inputs[0].ki.wVk = VK_TAB;
  inputs[1].type = INPUT_KEYBOARD;
  inputs[1].ki.wVk = VK_TAB;
  inputs[1].ki.dwFlags = KEYEVENTF_KEYUP;
  return ::SendInput(2, inputs, sizeof(INPUT)) == 2;
}

bool TypeCredentials(const std::wstring& username,
                     const std::wstring& password) {
  bool ok = true;
  if (!username.empty()) {
    ok = TypeText(username) && ok;
    ::Sleep(80);
    PressTab();
    ::Sleep(80);
  }
  ok = TypeText(password) && ok;
  return ok;
}

}  // namespace

void Register(flutter::BinaryMessenger* messenger) {
  // keyring/foreground：记录/恢复热键按下时的前台窗口。
  auto fg_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "keyring/foreground",
          &flutter::StandardMethodCodec<flutter::EncodableValue>::GetInstance());
  fg_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        HandleForegroundCall(call.method_name(), *result);
      });
  static std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      fg_holder;
  fg_holder = std::move(fg_channel);

  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "keyring/keyboard",
          &flutter::StandardMethodCodec<flutter::EncodableValue>::GetInstance());

  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() != "typeCredentials") {
          result->NotImplemented();
          return;
        }
        const auto* args =
            std::get_if<flutter::EncodableMap>(call.arguments());
        if (!args) {
          result->Error("bad_args", "arguments must be a map");
          return;
        }
        std::string username, password;
        auto u = args->find(flutter::EncodableValue("username"));
        auto p = args->find(flutter::EncodableValue("password"));
        if (u != args->end() && !u->second.IsNull()) {
          username = std::get<std::string>(u->second);
        }
        if (p != args->end() && !p->second.IsNull()) {
          password = std::get<std::string>(p->second);
        }
        // UTF-8 → UTF-16。
        int ulen = ::MultiByteToWideChar(CP_UTF8, 0, username.c_str(), -1,
                                         nullptr, 0);
        int plen = ::MultiByteToWideChar(CP_UTF8, 0, password.c_str(), -1,
                                         nullptr, 0);
        std::wstring wusername(ulen > 0 ? ulen - 1 : 0, L'\0');
        std::wstring wpassword(plen > 0 ? plen - 1 : 0, L'\0');
        if (ulen > 0) {
          ::MultiByteToWideChar(CP_UTF8, 0, username.c_str(), -1,
                                wusername.data(), ulen);
        }
        if (plen > 0) {
          ::MultiByteToWideChar(CP_UTF8, 0, password.c_str(), -1,
                                wpassword.data(), plen);
        }
        bool ok = TypeCredentials(wusername, wpassword);
        result->Success(flutter::EncodableValue(ok));
      });

  // channel 生命周期交给静态持有，避免被回收。
  static std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      channel_holder;
  channel_holder = std::move(channel);

  // keyring/hotkeycheck：全局热键占用预检（注册前确认组合可用）。
  auto check_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "keyring/hotkeycheck",
          &flutter::StandardMethodCodec<flutter::EncodableValue>::GetInstance());
  check_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        HandleHotkeyCheckCall(call, *result);
      });
  static std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      check_holder;
  check_holder = std::move(check_channel);
}

}  // namespace keyboard_inject
