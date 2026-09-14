# KeyRing 工作区 / 分组 / 选择性同步 + 保密项 设计方案

> 状态：设计稿（未实现）· 2026-08-20
> 范围：① 工作区与分组概念，同步可按工作区选择，避免高隐私条目出现在电脑上；② 密码条目支持自定义保密项（安全码、客户号等）。

---

## 1. 现状摘要（设计依据）

| 维度 | 现状 | 关键代码 |
|---|---|---|
| 数据模型 | 单表 `password_items` 9 个固定列，无任何分组/分类概念 | `lib/models/password_item.dart` |
| 存储 | SQLite，`version: 1`，**没有 `onUpgrade`**（迁移框架不存在） | `lib/services/password_repository.dart:22-43` |
| 同步 | 仅 LAN P2P，手动触发，**整库发送**（`items: repository.itemsNotifier.value`），条目级 last-write-wins | `lib/services/lan_sync_service.dart:266,642`；`lib/services/lan/sync_conflict_resolver.dart` |
| 删除 | **不同步删除、无 tombstone**，被删条目会被对端下次同步复活 | 同上 |
| 协议 | JSON 消息 + `protocolVersion`/`vaultVersion` 字段，旧端识别已存在（缺失则告警降级） | `lib/services/lan/sync_protocol_codec.dart:82-109` |
| 加密 | 库文件**明文存储**；secure storage 仅存 deviceId；`SecureKeyService`（主密码 hash）是休眠代码 | `lib/services/secure_key_service.dart` |
| UI | 首页 = 搜索 + 单个"收藏"chip；编辑页固定字段；设置页仅热键 | `lib/screens/home_screen.dart:1021-1065` |
| 快速填充 | 桌面热键弹窗直接读 `itemsNotifier.value` | `lib/quick_fill/quick_fill_host.dart:107` |
| 导入导出 | JSON `exportVersion: 1`，`items:[toMap]`；`fromMap` **静默忽略未知键**（天然向后兼容） | `lib/services/data_export_service.dart:23-81` |

---

## 2. 目标 / 非目标

**目标**

- G1 工作区（Workspace）成为一级隔离边界，每个工作区有独立同步策略
- G2 分组（Group）用于工作区内组织条目，不承载安全语义
- G3 高隐私条目在**传输层面**保证永远不出现在桌面端（包括工作区名称都不发送）
- G4 条目可挂任意数量的自定义保密项（label + value + 类型 + 是否掩码）
- G5 与 v1 旧版本互通：旧端不崩溃、新端自动降级并明示用户
- G6 导入/导出/QR/OCR/快速填充全链路兼容新概念
- G7 删除与"移出高隐私工作区"能正确传播（引入 tombstone）

**非目标（本期不做）**

- 云端同步
- 字段级冲突合并（维持条目级 last-write-wins）
- 工作区级独立加密密钥（列为二期路线，见 §9）
- 工作区独立解锁/二级锁

---

## 3. 概念模型

```
工作区 Workspace ──┬── 分组 Group ──┬── 条目 Item ── 保密项 SecretField[]
                  │                └── 条目 Item
                  └── (未分组条目)
```

### 3.1 工作区 Workspace

| 字段 | 说明 |
|---|---|
| `id` | UUID |
| `name` | 名称，如"个人 / 工作 / 高隐私" |
| `icon` | emoji 或颜色标识 |
| `syncPolicy` | `full` \| `mobileOnly` \| `localOnly` |
| `sortWeight` / 时间戳 | 排序与同步用 |

三种同步策略：

| 策略 | 行为 | 用户语义 |
|---|---|---|
| `full` 全设备同步 | 与所有已配对设备同步 | 默认，普通条目 |
| `mobileOnly` 仅移动端 | 手机↔手机可同步；**绝不发送给桌面端**（deviceClass=desktop） | 高隐私：银行、服务器密钥等 |
| `localOnly` 仅本机 | 不参与任何同步 | 极敏感或临时条目 |

**为什么同步策略挂在工作区而不是条目/分组上**：用户建工作区时心智上就带着目的（个人/工作/高隐私），边界稳定；分组是随手调整的组织维度，不应携带安全语义；逐条目开关管理成本高且易误配。三层结构里只有工作区是"心智上的保险箱"。

### 3.2 分组 Group

`{id, workspaceId, name, sortWeight}`，纯组织用途，删除分组时条目回落"未分组"。跨工作区移动分组不支持（分组隶属工作区）。

### 3.3 保密项 SecretField

条目上的自定义键值对列表：

```json
[{"id":"f-…","label":"安全码","value":"582914","type":"password","protected":true}]
```

| 字段 | 说明 |
|---|---|
| `label` | 显示名 |
| `value` | 值 |
| `type` | `text` \| `password` \| `tel` \| `date` \| `number` |
| `protected` | 是否默认掩码（`password` 类型默认 true，可改） |

内置快捷模板（编辑页一键填 label）：**安全码、客户号、会员号、PIN、备用邮箱、恢复代码、客服电话**。

---

## 4. 数据模型与迁移

### 4.1 Schema（DB version 1 → 2，项目首个 `onUpgrade`）

```sql
CREATE TABLE workspaces (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  icon TEXT,
  syncPolicy TEXT NOT NULL DEFAULT 'full',   -- full | mobile_only | local_only
  sortWeight INTEGER NOT NULL DEFAULT 0,
  createdAt TEXT NOT NULL,
  updatedAt TEXT NOT NULL
);

CREATE TABLE item_groups (
  id TEXT PRIMARY KEY,
  workspaceId TEXT NOT NULL,
  name TEXT NOT NULL,
  sortWeight INTEGER NOT NULL DEFAULT 0,
  createdAt TEXT NOT NULL,
  updatedAt TEXT NOT NULL
);

ALTER TABLE password_items ADD COLUMN workspaceId TEXT NOT NULL DEFAULT '';
ALTER TABLE password_items ADD COLUMN groupId TEXT;
ALTER TABLE password_items ADD COLUMN customFields TEXT;   -- SecretField[] 的 JSON

CREATE TABLE tombstones (
  id TEXT PRIMARY KEY,       -- 被删条目/工作区的 id
  kind TEXT NOT NULL,        -- 'item' | 'workspace'
  scope TEXT NOT NULL DEFAULT 'all',  -- 'all' | 'desktop_only'：墓碑的传播范围
  deletedAt TEXT NOT NULL
);
CREATE INDEX idx_password_items_workspace ON password_items(workspaceId);
```

默认工作区"个人"（`syncPolicy=full`）随迁移创建，存量条目全部归入。`vault_metadata`：`vault_version 1→2`、`protocolVersion 1→2`。

**customFields 用 JSON 列而非独立表**：与条目级 LWW 冲突模型天然一致（整行原子替换，不存在"半条目"）；toMap/fromMap、导出、同步全链路零 join；无按字段查询需求。代价与备选见 §11。

### 4.2 迁移安全

1. 升级前自动整库备份：复用 `DatabaseBackupService.createLegacyBackup`（现有 `MigrationService.prepareCompatibility` 机制，`vault_version` 标志位 1→2）
2. `onUpgrade` 事务内：建表 → 建默认工作区 → `UPDATE password_items SET workspaceId=<默认>`
3. 首次启动校验：workspaceId 为空的条目（异常路径残留）自动归入默认工作区

---

## 5. 选择性同步设计（协议 v2）

### 5.1 能力协商

`hello` 增加字段：

```json
{"type":"hello","deviceId":"…","deviceName":"…",
 "deviceClass":"mobile|desktop","protocolVersion":2,"capabilities":["workspaces"]}
```

`deviceClass` 由平台决定（Android/iOS=mobile；macOS/Windows/Linux=desktop）。对端 `protocolVersion<2` 或无 `capabilities` → 走 legacy 降级（§5.4）。

### 5.2 发送侧过滤（核心隐私保证）

`sync_data` 组包前：

```dart
bool canSend(Workspace w, String peerClass) => switch (w.syncPolicy) {
  SyncPolicy.full        => true,
  SyncPolicy.mobileOnly  => peerClass != 'desktop',
  SyncPolicy.localOnly   => false,
};
```

- **items 过滤**：只发送策略允许发给该对端的工作区中的条目
- **metadata 过滤**：`workspaces`/`groups` 定义同样过滤——桌面端连 `mobileOnly` 工作区的**名称都收不到**
- `localOnly` 不留任何痕迹

### 5.3 接收侧防御（双保险）

- 只接受 `workspaceId ∈ 收到的 workspaces 定义` 的条目；未知 workspaceId 的条目丢弃并计入告警
- 桌面端收到 `syncPolicy=mobile_only` 的 workspace 定义时**拒收该工作区**（策略以接收方执行为准，防旧端/篡改）

### 5.4 Legacy 互通（v1 ↔ v2）

- 对端 v1：发送时剥离 `workspaceId/groupId/customFields`（旧端 `fromMap` 本就忽略未知键，显式剥离只为语义清晰），条目照常同步；UI 提示"对端为旧版本，工作区/分组/保密项不会同步"
- 收到旧格式条目（无 `workspaceId`）：归入默认工作区
- **接收侧字段保留合并（防数据丢失，必须）**：现有 `upsertPreserveTimestamps` 是整行 `ConflictAlgorithm.replace`（`password_repository.dart:122-129`）。若远端 map 缺失 `customFields/workspaceId/groupId`（v1 对端必然缺失），整行替换会把本地保密项抹掉、工作区归属重置。v2 接收路径必须改为：**远端缺失的键保留本地值**，仅远端显式携带的键参与覆盖。该规则同时防御任何旧端/异常端灌入残缺数据
- ⚠️ 必须向用户说明：**与 v1 桌面端同步 = 没有选择性同步保护**，提示其升级

### 5.5 Tombstone（删除传播）

现状删除会被复活（无 tombstone）；选择性同步会放大该问题。规则：

| 事件 | 行为 |
|---|---|
| 删除条目 | 写 `tombstones(kind=item)`，随 `sync_data` 发送 |
| 删除工作区（需先清空条目） | 写 `tombstones(kind=workspace)`，发给**所有**对端（仅 id，不含名称/内容），对端删除同 id 工作区及其条目 |
| 工作区策略 full → mobileOnly | 等价于"对桌面端删除"：向 desktop 对端发送该工作区的 tombstone |
| 条目移入 mobileOnly/localOnly 工作区 | 对看不见目标工作区的对端：表现为删除（发送该条目 tombstone，仅 id） |
| 条目移出（mobileOnly → full） | 下次同步作为新条目 upsert 到对端 |
| 应用顺序 | **先应用 tombstone 再 upsert items** |
| TTL | tombstone 保留 90 天后本地清理 |

> 注：工作区 tombstone 只泄露 UUID，不泄露名称——可接受的最小信息暴露。

### 5.6 sync_data v2 消息形状

```json
{
  "type": "sync_data", "protocolVersion": 2, "vaultVersion": 2,
  "deviceClass": "mobile",
  "workspaces": [{"id":"ws-…","name":"个人","icon":"🏠","syncPolicy":"full","sortWeight":0,"createdAt":"…","updatedAt":"…"}],
  "groups": [{"id":"g-…","workspaceId":"ws-…","name":"开发","sortWeight":0,"createdAt":"…","updatedAt":"…"}],
  "items": [{"id":"…","title":"…","username":"…","password":"…","url":null,"notes":null,
             "workspaceId":"ws-…","groupId":"g-…","customFields":[{"id":"f-…","label":"安全码","value":"…","type":"password","protected":true}],
             "createdAt":"…","updatedAt":"…","isFavorite":0}],
  "tombstones": [{"id":"…","kind":"item","deletedAt":"…"}],
  "timestamp": 1234567890
}
```

工作区/分组定义同步采用与条目一致的 **id + updatedAt LWW**；本地手动创建的同名工作区不合并（id 不同即两个工作区，导入场景重命名规避）。

### 5.7 版本兼容矩阵与降级策略

| 场景 | 结果 |
|---|---|
| v2 应用打开 v1 库（正常升级） | ✅ `onUpgrade` 迁移 + 升级前自动整库备份 |
| v2 ↔ v2 同步 | ✅ 完整功能 |
| v2 ↔ v1 同步 | ⚠️ 降级可用：条目本体同步，结构/保密项/tombstone 失效，UI 明示 |
| v1 应用导入 v2 导出文件 | ✅ 旧 `parseJsonItems` 读 `items` 键，未知键被忽略，结构丢弃 |
| v2 应用导入 v1 导出文件 | ✅ 归入默认工作区 |
| QR/OCR 载荷 | ✅ 同理 |
| **v1 应用打开 v2 库（降级安装）** | ❌ 打不开——sqflite（Android SQLiteOpenHelper 系）默认拒绝降级打开。**数据结构单向升级**，迁移前备份文件是降级兜底 |

已知限制（与现状一致，未更糟）：混版本下删除仍会复活（v1 不理解 tombstone）；v1 桌面端不受 `mobileOnly` 保护——均依赖"对端为旧版本"提示引导升级。

---

## 6. UI 设计

### 6.1 首页（`home_screen.dart`）

```
┌──────────────────────────────────────────┐
│ 🔍 搜索（作用于当前工作区）                  │
│ [🏠 个人] [💼 工作] [🔐 高隐私] … [管理]     │ ← 工作区 pill 行（水平滚动）
│ (全部) (★收藏) (开发) (运维) (Ø)           │ ← 分组 chip 行（Ø=新增分组）
│ ┌──────────────────────────────────────┐ │
│ │ 条目卡片（不变，长按菜单加"移动到…"）      │ │
└──────────────────────────────────────────┘
```

- 收藏 chip 保留并并入分组行；搜索/收藏作用域 = 当前工作区
- 长按条目 → 移动到分组/工作区（bottom sheet，双级选择）
- 长按分组 chip → 重命名/删除（删除仅解除分组归属）
- 桌面端**不显示**任何"存在已隐藏工作区"的提示（不泄露元信息）

### 6.2 工作区管理页（新 screen）

- 列表：图标、名称、策略徽章（全设备/仅移动端/仅本机）、条目数
- 新建/编辑：名称、emoji、同步策略三选一，说明文案：
  - 仅移动端：**"条目只会在手机/平板之间同步，永远不会发送到电脑——包括工作区名称。"**
  - 仅本机："不参与任何同步。"
- 策略从 full 收窄（→mobileOnly/localOnly）时弹确认：**"电脑端将删除该工作区的全部条目"**（对应 §5.5 tombstone）
- 删除工作区：要求先移走或删除条目；拖拽排序

### 6.3 编辑页（`edit_item_screen.dart`）

- 顶部新增工作区/分组选择器（默认当前工作区）
- "可选信息"下方新增**保密项区块**：

```
保密项                                    [+ 添加]
┌───────────────────────────────────────────┐
│ [安全码▾] [•••••••• ] [👁] [🗑]           │
│ [客户号▾] [C88231      ]      [🗑]         │
│ 快捷: (安全码)(客户号)(会员号)(PIN)(备用邮箱) │
└───────────────────────────────────────────┘
```

- 行内：label 输入（带模板下拉）、value 输入、类型选择、protected 开关、删除
- 保存校验：label 非空且**同条目内不重名**；value 允许为空（占位记录）

### 6.4 详情页（`detail_screen.dart`）

保密项逐行展示：`protected` 默认 `••••••••`，可切换显示/一键复制，样式与现有密码行一致。

### 6.5 设置页（`settings_screen.dart`）

新增"同步"分区：本设备类型展示（"此设备：手机 / 桌面"）、协议版本、工作区策略只读总览。

### 6.6 快速填充（桌面）

桌面端天然只拥有 `full` 工作区（发送侧过滤保证），无需特判；`quick_fill_host` 列表按工作区分组展示即可。

### 6.7 全局搜索

作用于当前工作区（含 customFields 的 label+value）；跨工作区找条目靠切换工作区，成本可接受。

---

## 7. 导入 / 导出 / QR / OCR

- **导出 v2**：`exportVersion: 2`，顶层携带 `workspaces`/`groups` 定义，items 带新字段；支持"仅导出当前工作区"。`mobileOnly` 工作区导出时**明文包含**——导出即用户主动带出，弹一次强提醒
- **导入**：v2 文件完整恢复结构；v1 文件（无 workspaceId）全部入默认工作区；`ImportMerger` 条目级 newer-wins 规则不变；导入的工作区与本地同名即视为不同工作区，名称后缀"(导入)"
- **QR/OCR**（`qr_payload_parser.dart` / `ocr_field_extractor.dart`）：关键词识别（安全码/客户号/PIN/会员号…）尽力预填 customFields
- **`titleExists` 唯一性检查**：从全局唯一改为**工作区内唯一**（更符合分组心智；同步 upsert 路径不走该检查，维持现状）

---

## 8. 边界情况汇总

| 场景 | 行为 |
|---|---|
| 桌面端已有数据后，手机把工作区改为 mobileOnly | 手机向桌面发 workspace tombstone，桌面删除该工作区及条目（§5.5） |
| 手机把条目从 full 工作区移入 mobileOnly 工作区 | 桌面端表现为该条目被删除（item tombstone） |
| 手机删除条目，桌面还留着 | tombstone 先于 items 应用，桌面删除；90 天 TTL |
| 与 v1 旧端同步 | 降级为无结构同步 + 提示（§5.4） |
| 旧端发来无 workspaceId 条目 | 归入默认工作区 |
| 两台手机都有同名 mobileOnly 工作区 | 按 id LWW，不按名称合并 |
| 接收到的条目 workspaceId 未知 | 丢弃 + 告警计数（§5.3） |
| 删除分组 | 条目回落"未分组"，不产生 tombstone（条目未删除） |

---

## 9. 安全边界（诚实声明）与加密路线

本设计的 `mobileOnly`/`localOnly` 保证的是**传输与存在边界**：高隐私数据不出现在桌面端的数据库与内存中。但当前**所有设备的库文件均为明文**（现状），手机本身被物理获取时无加密保护。二期路线：

1. **静态加密**：启用休眠的 `SecureKeyService`（已有主密码 hash+salt 逻辑），主密码派生密钥，应用层加密敏感列或整体迁移 SQLCipher——与工作区结构解耦，可独立推进
2. **工作区级密钥**（更远期）：高隐私工作区独立密钥，未解锁时密文落盘；换设备需显式导入密钥，实现真正的密码学隔离

排序理由：先结构后加密，避免单次变更过大；选择性同步本身已消除"桌面端明文副本"这一最大暴露面。

---

## 10. 里程碑

| 里程碑 | 内容 | 可独立发版 |
|---|---|---|
| **M1 本地能力** | 模型/Schema/迁移 v2 + 工作区与分组 UI + 保密项（编辑/详情/搜索）+ 导入导出 v2 + quick-fill 兼容 | ✅ **但同步策略锁死为 `full`**（设置项隐藏）——过滤引擎在 M2 才有，提前开放 mobileOnly 会造成虚假安全感 |
| **M2 选择性同步** | 协议 v2：能力协商、双侧过滤、metadata 同步、tombstone、legacy 降级+字段保留合并、设置页同步分区；放开三档策略设置 | ✅（需双端升级） |
| **M3 加密（二期）** | 静态加密 → 工作区级密钥 | ✅ |

**风险清单**

- 项目**首个 `onUpgrade`**：务必保留升级前自动备份 + 迁移单测（v1 库→v2 各路径）
- `home_screen.dart` 1359 行，加两层过滤行改造量不小，注意 `_applyFilters`/`_applySort` 与 quick-fill 的数据源联动
- 双端必须都到 v2 才有选择性同步效果——旧端提示文案必须明确
- `DataSyncEngine` 与 `LanSyncService` 存在重复的死代码（现状），M2 改造时顺手收敛或明确不动

---

## 11. 备选方案与取舍（Decisions Log）

| 日期 | 决策 | 备选 | 理由 |
|---|---|---|---|
| 2026-08-20 | 同步策略挂**工作区级** | 条目级开关 / 分组级开关 | 用户心智边界稳定；管理成本低；不易误配（§3.1） |
| 2026-08-20 | 保密项存 **JSON 列** | 独立 `item_fields` 表 | 与条目级 LWW 原子一致；零 join；导出/同步免改造（§4.1） |
| 2026-08-20 | 过滤**双侧执行**（发送+接收） | 只信发送方 | 防旧端/篡改灌入；接收方是最后一道防线（§5.3） |
| 2026-08-20 | 工作区隐藏采用**完全不发送**（含名称） | 桌面显示"有 N 个隐藏工作区" | 不泄露元信息，移动端 UI 已足够（§6.1） |
| 2026-08-20 | 引入 **tombstone**（item+workspace 两类，90 天 TTL） | 维持现状（删除不同步） | 选择性同步使"复活"从 bug 升级为隐私泄漏（§5.5） |
| 2026-08-20 | 与 v1 互通走**优雅降级**而非拒绝 | 强制双端升级 | 单字段协议版本已存在，`fromMap` 忽略未知键天然兼容；降级即可用 |
| 2026-08-20 | 加密放**二期**（M3） | 与本次一起做 | 单次变更过大；选择性同步已消除桌面端明文副本这一最大暴露面（§9） |

## 12. 待确认的开放问题

1. 工作区是否需要**独立解锁**（打开高隐私工作区需再次生物认证）？—— 建议二期随加密一起评估
2. mobileOnly 工作区是否允许**导出**？当前设计允许（强提醒），还是默认禁止？
3. 分组是否支持嵌套？当前设计不支持（一层足够，复杂度控制）
4. 桌面端 quick-fill 是否需要按工作区过滤的偏好设置？当前设计仅分组展示
