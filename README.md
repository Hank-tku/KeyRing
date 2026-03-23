# KeyRing - 技术栈与功能实现

## 项目概述

KeyRing 是一款基于 Flutter 开发的跨平台密码管理应用，支持多端数据同步，提供安全的本地存储和局域网同步功能。

---

## 核心技术栈

### 1. 开发框架

#### Flutter
- **版本**: 3.8.1+ (SDK)
- **用途**: 跨平台应用开发
- **支持平台**:
  - Android
  - iOS
  - macOS
  - Windows
  - Linux
  - Web

#### Dart
- **版本**: 3.8.1+
- **用途**: 应用逻辑开发语言

---

### 2. 核心依赖库

#### 数据存储
- **sqflite**: ^2.4.1
  - SQLite 数据库支持（移动平台）
  - 本地密码数据持久化存储
- **sqflite_common_ffi**: ^2.3.4
  - 桌面平台 SQLite FFI 实现
  - 支持 Windows、Linux、macOS

#### 安全存储
- **flutter_secure_storage**: ^9.2.2
  - 加密密钥存储
  - 主密码哈希存储
  - 设备 ID 安全保存
  - 跨平台安全存储：
    - Android: EncryptedSharedPreferences
    - iOS/macOS: Keychain
- **shared_preferences**: ^2.3.3
  - 轻量级键值对存储
  - Debug 模式下作为安全存储的降级方案

#### 身份认证
- **local_auth**: ^2.3.0
  - 生物识别认证（指纹、面容ID）
  - 系统密码验证
- **local_auth_android**: ^1.0.46
  - Android 平台生物识别支持
- **local_auth_darwin**: ^1.4.1
  - iOS/macOS 平台生物识别支持

#### 网络与同步
- **bonsoir**: ^6.0.1
  - 局域网设备发现（mDNS/Bonjour）
  - 自动发现同局域网设备
- **web_socket_channel**: ^3.0.1
  - WebSocket 实时通信
  - 设备间数据传输

#### 工具库
- **uuid**: ^4.5.1
  - 生成唯一标识符
  - 密码条目 ID
  - 设备 ID 生成
- **intl**: ^0.19.0
  - 国际化与日期格式化
- **path**: ^1.9.0
  - 文件路径处理
- **path_provider**: ^2.1.5
  - 获取应用目录路径
  - 数据库文件存储位置
- **crypto**: 间接依赖
  - SHA-256 哈希算法
  - 主密码加密存储

#### UI 资源
- **flutter_launcher_icons**: ^0.13.1
  - 应用图标自动生成
  - 支持所有平台自适应图标
- **flutter_native_splash**: ^2.4.1
  - 启动画面配置
  - 支持深色/浅色模式
  - Android 12+ 兼容

---

## 架构设计

### 1. 分层架构

```
┌─────────────────────────────────────┐
│         UI Layer (Screens)          │  │
│  - HomeScreen                      │  用户界面
│  - LockScreen                      │
│  - PasscodeScreen                  │
│  - EditItemScreen                  │
│  - DetailScreen                    │
└─────────────────────────────────────┘
                ↓
┌─────────────────────────────────────┐
│      Service Layer (Services)       │
│  - PasswordRepository              │  业务逻辑
│  - AuthService                     │
│  - LanSyncService                 │
│  - SecureKeyService                │
│  - DeviceService                   │
└─────────────────────────────────────┘
                ↓
┌─────────────────────────────────────┐
│     Data Layer (Models & Storage)   │
│  - PasswordItem Model              │  数据模型
│  - SQLite Database                 │
│  - Secure Storage                  │
└─────────────────────────────────────┘
```

### 2. 核心模块

#### PasswordRepository（密码仓库）
- **职责**: 管理密码数据的 CRUD 操作
- **功能**:
  - 数据库初始化
  - 密码条目增删改查
  - 标题唯一性校验
  - 数据变更通知（ValueNotifier）
  - 时间戳保留的 upsert（用于同步）

#### SecureKeyService（密钥服务）
- **职责**: 主密码安全存储与验证
- **功能**:
  - 主密码加密存储（SHA-256 + Salt）
  - 密码验证
  - 安全密钥管理

#### AuthService（认证服务）
- **职责**: 生物识别与系统认证
- **功能**:
  - 生物识别能力检测
  - 指纹/面容ID认证
  - 系统密码认证
  - 可用生物识别类型查询

#### LanSyncService（局域网同步服务）
- **职责**: 跨设备数据同步
- **架构**: 采用多管理器设计模式
  - `ConnectionStateManager`: 连接状态管理
  - `WebSocketConnectionManager`: WebSocket 连接管理
  - `VerificationManager`: 验证码管理
  - `DataSyncEngine`: 数据同步引擎
  - `ServiceDiscoveryManager`: 服务发现管理
- **功能**:
  - mDNS 设备发现
  - WebSocket P2P 通信
  - 设备配对与验证码验证
  - 基于时间戳的数据冲突解决
  - 自动角色分配（设备 ID 大者为服务端）

#### DeviceService（设备服务）
- **职责**: 设备标识管理
- **功能**:
  - 设备 ID 生成与持久化
  - 设备名称管理（如 "Android-Pixel", "macOS-MacBook"）
  - 跨平台类型识别
  - 安全存储降级策略

---

## 实现功能

### 1. 密码管理核心功能

#### 密码条目管理
- ✅ 创建密码条目
- ✅ 编辑密码条目
- ✅ 删除密码条目
- ✅ 收藏功能（isFavorite）
- ✅ 标题唯一性校验
- ✅ 时间戳管理（createdAt, updatedAt）

#### 数据模型字段
```dart
- id: String (UUID)
- title: String (标题)
- username: String (用户名)
- password: String (密码)
- url: String? (网址，可选)
- notes: String? (备注，可选)
- createdAt: DateTime (创建时间)
- updatedAt: DateTime (更新时间)
- isFavorite: bool (是否收藏)
```

### 2. 安全功能

#### 主密码保护
- ✅ 主密码设置（SHA-256 加密）
- ✅ 主密码验证
- ✅ Salt 值管理（UUID 生成）
- ✅ 安全存储（Keychain/EncryptedSharedPreferences）

#### 生物识别
- ✅ 指纹识别（Android）
- ✅ 面容ID（iOS/macOS）
- ✅ 系统密码认证
- ✅ 可用生物识别类型查询

#### 加密存储
- ✅ 敏感数据使用 FlutterSecureStorage
- ✅ 数据库文件存储在安全目录
- ✅ Debug 模式下降级到 SharedPreferences

### 3. 局域网同步

#### 设备发现
- ✅ mDNS/Bonjour 广播
- ✅ 自动发现同网设备
- ✅ 设备信息展示（设备名称、平台类型）
- ✅ 12 秒超时机制

#### 设备配对
- ✅ 6 位数字验证码
- ✅ 双向验证（服务端/客户端）
- ✅ 手动确认机制
- ✅ 验证超时处理（120 秒）

#### 数据同步
- ✅ WebSocket 实时通信
- ✅ 全量数据传输
- ✅ 基于时间戳的冲突解决（最新更新优先）
- ✅ 双向同步
- ✅ 同步超时处理（30 秒）
- ✅ 同步完成通知

#### 连接管理
- ✅ 服务端/客户端自动角色分配
- ✅ 连接状态管理
- ✅ 连接复用
- ✅ 错误处理与重连

### 4. UI/UX 功能

#### 启动体验
- ✅ 自定义启动画面
- ✅ 深色/浅色模式适配
- ✅ Android 12+ 启动画面适配
- ✅ 自适应应用图标

#### 主题系统
- ✅ Material Design 3
- ✅ 暗色主题（#121A2E 主色调）
- ✅ 自定义主题配置

#### 交互功能
- ✅ 锁屏界面
- ✅ 密码输入界面
- ✅ 密码条目详情
- ✅ 编辑界面
- ✅ 验证码输入对话框

### 5. 跨平台支持

#### 移动平台
- ✅ Android（指纹、加密存储、权限管理）
- ✅ iOS（面容ID、TouchID、Keychain）

#### 桌面平台
- ✅ macOS（Keychain、生物识别）
- ✅ Windows（FFI SQLite、安全存储）
- ✅ Linux（FFI SQLite、安全存储降级）

#### Web 平台
- ✅ 基础支持（部分功能受限）

---

## 数据存储架构

### 1. SQLite 数据库

#### 数据库结构
```sql
CREATE TABLE password_items (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  username TEXT NOT NULL,
  password TEXT NOT NULL,
  url TEXT,
  notes TEXT,
  createdAt TEXT NOT NULL,
  updatedAt TEXT NOT NULL,
  isFavorite INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX idx_password_items_updatedAt 
ON password_items(updatedAt DESC);
```

#### 查询优化
- 按收藏状态和更新时间排序
- 索引加速更新时间查询

### 2. 安全存储

#### 密钥管理
```
Master Password
    ↓
SHA-256(password + salt)
    ↓
存储到 Keychain/EncryptedSharedPreferences
```

#### 设备信息存储
```
Device ID → 安全存储
Device Name → 安全存储
Debug 模式 → SharedPreferences (降级)
```

---

## 同步流程

### 1. 服务发现流程
```
1. 启动 mDNS 广播
2. 扫描局域网设备
3. 获取设备列表（ID、名称、IP、端口）
```

### 2. 配对流程
```
1. 比较设备 ID 决定角色
   - ID 较大 → 服务端
   - ID 较小 → 客户端

2. 客户端连接服务端
3. 服务端生成验证码
4. 用户在两端输入验证码
5. 验证通过后标记为已验证
```

### 3. 数据同步流程
```
1. 客户端请求服务端数据
2. 服务端返回全部密码条目
3. 客户端发送本地数据到服务端
4. 双方按时间戳合并数据
   - 新增：直接插入
   - 已存在：取 updatedAt 较新的版本
5. 完成后发送 sync_complete 消息
```

---

## 安全特性

### 1. 密码安全
- ✅ 主密码 SHA-256 + Salt 加密
- ✅ UUID 生成随机 Salt
- ✅ 防止彩虹表攻击
- ✅ 常量时间密码比较

### 2. 存储安全
- ✅ Keychain 加密存储（iOS/macOS）
- ✅ EncryptedSharedPreferences（Android）
- ✅ 数据库文件在应用私有目录

### 3. 网络安全
- ✅ 局域网内通信
- ✅ 双向验证码验证
- ✅ 防止未授权访问

---

## 性能优化

### 1. 数据库优化
- ✅ 索引加速查询
- ✅ ValueNotifier 响应式更新
- ✅ 按需加载数据

### 2. 网络优化
- ✅ WebSocket 长连接复用
- ✅ JSON 序列化优化
- ✅ 超时控制

### 3. UI 优化
- ✅ 懒加载
- ✅ 状态管理高效更新
- ✅ 流畅的动画效果

---

## 开发规范

### 1. 代码组织
```
lib/
├── models/              # 数据模型
├── screens/            # 页面组件
├── services/           # 业务服务
│   └── lan/           # 局域网同步相关
└── utils/             # 工具类
```

### 2. 命名规范
- 文件名：小写下划线（snake_case）
- 类名：大驼峰（PascalCase）
- 私有成员：下划线前缀（_prefix）
- 常量：小写下划线（lower_case）

### 3. 错误处理
- Try-catch 包装异步操作
- 用户友好的错误提示
- 降级策略处理

---

## 技术亮点

1. **跨平台统一**: 一套代码支持 6 个平台
2. **安全优先**: 多层加密、生物识别、安全存储
3. **离线优先**: 本地 SQLite，无网络依赖
4. **局域网同步**: 数据同步，无需云服务
5. **模块化设计**: 清晰的分层架构和职责划分
6. **用户体验**: 流畅的动画、深色主题、自适应 UI

---

## 版本信息

- **当前版本**: 1.0.0+1
- **Flutter SDK**: 3.8.1+
- **最后一次更新**: 2026-03-23

---

## 扩展方向

### 短期
- [ ] 密码强度检测
- [ ] 密码生成器
- [ ] 自动填充集成
- [ ] 导出/导入功能（CSV）

### 中期
- [ ] 云端备份同步
- [ ] 密码分类与标签
- [ ] 搜索功能
- [ ] 使用统计

### 长期
- [ ] 二维码配对
- [ ] 多用户支持
- [ ] 团队共享功能
- [ ] 密码泄露检测


