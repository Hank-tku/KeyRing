// keyring/keyboard 平台通道：模拟键盘输入（Windows 快速填充）。
// 用 SendInput 按「用户名 → Tab → 密码」顺序注入 Unicode 字符。
#ifndef RUNNER_KEYBOARD_INJECT_H_
#define RUNNER_KEYBOARD_INJECT_H_

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

namespace keyboard_inject {

void Register(flutter::BinaryMessenger* messenger);

}  // namespace keyboard_inject

#endif  // RUNNER_KEYBOARD_INJECT_H_
