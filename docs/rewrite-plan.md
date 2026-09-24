# SSH Pad Flutter 重写计划（草案）

> 日期：2026-09-24（HKT）  
> 范围：研究结论 + 可执行里程碑；**不改写现有应用代码、不 push**  
> 源仓库：`/workspace/ssh-pad`（camilavivan/ssh-pad）、`/workspace/flutter_server_box`（lollipopkit）  
> 产品约束：Pad 优先；SSH 终端 + 文件传输为主；前台保活；外接/蓝牙键盘一等公民；协议选择器对齐经典 Android 客户端

---

## 1. 目标与非目标

### 1.1 目标（v1 / 首个可用发行）

- 用 **Flutter** 全量重写当前 Kotlin/Compose `ssh-pad`，长期架构与 **ServerBox** 对齐（`dartssh2` + `xterm` + 会话生命周期 + Android FGS）。
- **Pad 优先 UI**：宽屏左栏节点/文件 + 可拖分割条 + 右栏终端；窄屏 NavigationRail。
- **首发必须协议**：`SSH`、`SFTP`、`TELNET`、`FTP`（UI 协议选择器可见；主机档案存 `protocol`）。
- **多会话**、密码/密钥认证、日夜间主题（GitHub Primer 风格可延续）。
- **会话保活**：切屏/切应用不断开；仅用户主动断开或杀进程时结束；**默认关闭「静默自动重连到死」**，避免卡死感（可开关，默认谨慎）。
- **外接 / 蓝牙键盘**：Enter、Backspace、Ctrl 组合、方向键、切回清 IME 组字——与现网 ssh-pad 体验对齐或更好。

### 1.2 非目标（v1 不移植 / 不深做）

来自 ServerBox，**明确不进 v1**：

| 模块 | 原因 |
|---
---

## 0. 优先级声明（2026-09-24 更新）

> **保活（Keepalive / Android FGS）是重中之重，不是收尾打磨项。**
>
> - M0 脚手架即包含：同进程 `SessionForegroundService`（`dataSync`）+ MethodChannel + Manifest 权限 + `AppLifecycleListener`/`WidgetsBindingObserver` 钩子 + 电池优化 / OEM 自启动设置占位。
> - 里程碑顺序调整为：`M0 脚手架` → `M1 最小 SSH 终端` → **`M1b 保活 FGS（关键路径）`** → `M2 SFTP/TELNET/FTP` → `M3 Pad 布局/键盘` → `M5 打磨发版`。
> - **不要把保活留到最后。** 同进程 FGS 优先 + WiFi/Wake 锁 + OEM 引导；国行可选 mediaPlayback/弱音（对照 ssh-pad KeepAlive*）；**默认不无限静默自动重连**。
> - 产品语义：切应用/熄屏不断开；仅用户断开或杀进程结束；避免「狂重连到卡死」。

---|------|
| Docker / 容器 / systemd / 进程管理 | 超出 PadSSH 最小焦点 |
| 状态图表、传感器、S.M.A.R.T.、Globe | 非终端产品核心 |
| Monitor Agent / 推送 / 桌面 Widget / watchOS | 依赖独立 agent 与生态 |
| RDP/VNC 远程桌面、BMC/Redfish | 体积与复杂度高 |
| AI Ask / Snippet 深度 / tmux 完整集成 | 可 P2 再议 |
| iOS Live Activity、桌面 tray | 首发 Android Pad |
| Telnet 之外的冷门协议深度优化 | 见协议矩阵：SERIAL/LOCAL/RLOGIN **延后** |
| 直接拷贝 ServerBox 整仓代码 | **AGPLv3**；应用其模式与公开包，不整仓 fork 进产品除非接受 AGPL |

### 1.3 许可注意

- ServerBox：`LICENSE` = **AGPLv3**。计划是「对齐架构 + 用同源库」，不是「复制粘贴 ServerBox 源码」。
- 推荐依赖 **pub.dev** 上的 `dartssh2`、`xterm`（或 TerminalStudio 上游）；若必须参考 ServerBox 私有改动，单独评估 AGPL 合规或只吸收思路自行实现。
- 新产品建议 **Apache-2.0 / MIT**（与 PadSSH 自用定位一致），避免无意感染 AGPL。

---

## 2. 现状摘要（两边代码库）

### 2.1 ssh-pad（Kotlin，1.9.3）

| 维度 | 事实 |
|------|------|
| 结构 | 单模块 `:app`，Compose UI |
| SSH | **JSch**（`com.github.mwiede:jsch:0.2.26`），**不是**用户记忆中的 SSHJ；Telnet = `commons-net` |
| 终端 | **WebView + xterm.js**（`assets/xterm/`），非原生 VT |
| 会话进程 | `SshSessionService` 跑在 **`:session` 独立进程**，Messenger IPC |
| 保活 | FGS `specialUse\|mediaPlayback` + PARTIAL_WAKE_LOCK + WifiLock + 弱音 AudioTrack + 悬浮球 + OEM 引导 |
| SFTP | 同会话 `ChannelSftp`：list/mkdir/rm/upload/download（UI 称 XFTP 双栏） |
| 主机 | `NodeStore` SharedPreferences JSON；`TransportKind` 仅 **SSH / TELNET** |
| 键盘 | `TerminalWebView.onCreateInputConnection` 关联想；JS `__wake`/`__sleep` 清 IME；`configChanges` 含 keyboard |

**关键路径：**

- 保活：`app/src/main/java/com/sshtab/pad/service/SshSessionService.kt`  
  `KeepAlivePlayer.kt` / `KeepAliveFloat.kt` / `KeepAliveOem.kt`
- 键盘/IME：`ui/XtermView.kt`、`assets/xterm/index.html`、`MainActivity.kt`
- 会话/SFTP：`ssh/SshSession.kt`、`ssh/SessionHub.kt`、`service/SessionClient.kt`
- 布局：`ui/SshPadAppUi.kt`（≥600dp 分栏 + 拖拽条）
- Manifest：`app/src/main/AndroidManifest.xml`

### 2.2 flutter_server_box（参考）

| 维度 | 事实 |
|------|------|
| 栈 | Flutter ≥3.44.9 / SDK ≥3.11；Riverpod；vendored `packages/dartssh2`、`packages/xterm`（submodule，浅克隆未拉子模块） |
| SSH | `lib/core/utils/server.dart` → `SSHClient`；终端 `lib/data/ssh/terminal_session.dart` |
| 终端 UI | `lib/view/page/ssh/page/page.dart` + `xterm` `TerminalView` |
| 键盘 | `lib/view/page/ssh/page/keyboard.dart`（`HardwareKeyboard`）；`lib/data/ssh/terminal_platform.dart`（Android keytab） |
| 虚拟键 | `lib/view/page/ssh/page/virt_key.dart`、`lib/data/model/ssh/virtual_key.dart` |
| SFTP | `lib/view/page/storage/sftp.dart` + `core/utils/sftp_*.dart`（含 sudo/escalation，v1 可砍） |
| 保活 | Dart：`lib/data/ssh/session_manager.dart` + `android_service_policy.dart`；Kotlin：`android/.../ForegroundService.kt`（**dataSync**，同进程）；通道 `lib/core/chan.dart` |
| LOCAL | 有 `LocalSource` + `flutter_pty` / rootfs——**不是**经典「本机 shell」产品焦点，Pad 可延后 |
| 无 | TELNET / FTP / RLOGIN / USB SERIAL 客户端 |

**关键路径：**

- `lib/view/page/ssh/page/keyboard.dart`、`page.dart`、`virt_key.dart`
- `lib/data/ssh/session_manager.dart`、`android_service_policy.dart`、`terminal_platform.dart`、`terminal_session.dart`
- `android/app/src/main/kotlin/tech/lolli/toolbox/ForegroundService.kt`
- `android/app/src/main/kotlin/tech/lolli/toolbox/MainActivity.kt`（MethodChannel）
- `lib/view/page/storage/sftp.dart`

---

## 3. 技术栈建议

| 项 | 建议 | 说明 |
|----|------|------|
| Flutter | **稳定通道最新 3.x**（以发布时 `flutter stable` 为准；不必强跟 ServerBox 3.44 私有底线） | 首发 Android；minSdk **26**（与现 ssh-pad / PadSSH 一致） |
| 语言 / 状态 | Dart 3 + **Riverpod**（或简化的 `ChangeNotifier`；推荐 Riverpod 以便对齐 ServerBox 习惯） | |
| SSH | **`dartssh2`**（pub.dev） | 对齐 ServerBox；PTY shell + SFTP |
| 终端 | **`xterm`**（pub.dev / TerminalStudio） | 原生 Flutter，告别 WebView |
| Telnet | **`ctelnet`** 或自研薄封装（`Socket` + IAC）；备选 `telnet` 包 | ssh-pad 已有 commons-net 行为可作对照 |
| FTP | **`ftpconnect`**（FTP/FTPS） | 明文 FTP 需安全警告；优先引导 FTPS |
| SFTP | dartssh2 `SftpClient` | 与 SSH 会话可共用 client 或独立连接 |
| 文件选择 | `file_picker` | 上传 |
| 持久化 | `shared_preferences` / `hive_ce` / 轻量 `sqflite` | 主机列表 + 协议类型；密钥建议后续 `flutter_secure_storage` |
| 唤醒锁 | `wakelock_plus` | 终端页可选常亮 |
| 保活 | **自写 Android FGS + MethodChannel**（借鉴 ServerBox `ForegroundService` + ssh-pad OEM/音频策略） | 见 §6；不依赖未维护插件硬扛国行 |
| 主题 | Material 3 + Primer 日/夜色板 | 对照 `ssh-pad/.../theme/Theme.kt` |
| 测试 | `integration_test` + 真机平板 + 蓝牙键盘 | |

不建议首发引入：Rust bridge、整仓 fl_lib、Monitor、根文件系统 LOCAL。

---

## 4. 模块映射（ServerBox → Pad）

| ServerBox 模块 | 策略 | Pad 侧落点 |
|----------------|------|------------|
| `dartssh2` 连接 / 认证（`server.dart` 思路） | **改编**（自写精简 `SshConnector`） | `lib/core/ssh/` |
| `terminal_session.dart` 字节泵 | **改编** | `lib/core/session/terminal_session.dart` |
| `xterm` TerminalView | **直接用** | `lib/ui/terminal/` |
| `keyboard.dart` / `terminal_platform.dart` | **改编**（Android 平板 + 蓝牙） | `lib/ui/terminal/hardware_keyboard.dart` |
| `virt_key.dart` | **精简改编**（Esc/Tab/Ctrl/方向，对齐 ssh-pad ExtraKeys） | `lib/ui/terminal/extra_keys.dart` |
| `session_manager.dart` + `ForegroundService` | **改编**（合并 ssh-pad 国行保活手段） | `lib/core/keepalive/` + `android/.../SessionForegroundService.kt` |
| `sftp.dart` 全功能浏览器 | **大幅精简重写**（双栏 up/down，无 sudo） | `lib/ui/files/` |
| Telnet / FTP | ServerBox **无** → **自研** | `lib/core/telnet/`、`lib/core/ftp/` |
| Docker/图表/AI/RDP/Monitor | **不移植** | — |
| `LocalSource` / PTY | **P2 延后** | — |
| 主机模型 `Spi` | **重写为 Pad `HostProfile`**（含 `protocol`） | `lib/data/host_profile.dart` |

抽象建议：统一 `SessionBackend` 接口（`connect` / `stdin` / `stdout` / `resize?` / `disconnect`），SSH shell / Telnet /（P2 Serial）都实现它；SFTP/FTP 走 `FileBackend`。

---

## 5. 协议矩阵（UI 选择器）

主机编辑页提供协议下拉（经典客户端风格），**档案字段 `protocol` 必存**。默认端口随协议切换。

| 协议 | 默认端口 | 实现路径 | ServerBox | 优先级 | 首发 |
|------|----------|----------|-----------|--------|------|
| **SSH** | 22 | `dartssh2` shell PTY | 有 | **必做** | ✅ |
| **SFTP** | 22 | `dartssh2` SftpClient；可与 SSH 同主机复用或独立会话 | 有（偏重） | **必做** | ✅ |
| **TELNET** | 23 | `ctelnet` 或 Socket+IAC；对照 ssh-pad `SshSession.connectTelnet` | 无 | **必做** | ✅ |
| **FTP** | 21 | `ftpconnect`；UI 与 SFTP 共用文件双栏，换 backend | 无 | **必做** | ✅ |
| SERIAL | — | `usb_serial`（Android OTG） | 无 | **P2 延后** | ❌ |
| LOCAL | — | `Process`/`flutter_pty`；ServerBox LocalSource 过重 | 有（重） | **P2 延后** | ❌ |
| RLOGIN | 513 | 几乎无成熟 Dart 包；自研或远期 | 无 | **P2 延后** | ❌ |

### 5.1 安全与产品 caveat

- **TELNET / FTP / RLOGIN**：明文凭据与会话。UI 必须显示醒目警告；设置中可「仅授信局域网」提示；生产环境引导 **SSH/SFTP/FTPS**。
- **FTP**：优先暴露 FTPS（TLS）选项；明文 FTP 默认二次确认。
- **SFTP vs FTP**：协议选择器里二者并列；SFTP 走 SSH 认证（密码/密钥），FTP 走用户/密码（及可选匿名）。
- **SERIAL**：需 USB Host / 权限与波特率 UI；平板场景有价值但非 MVP。
- **LOCAL**：Android 上「本机 shell」能力因 SELinux/toybox 碎片化，ServerBox 靠 rootfs——Pad 不做。
- **RLOGIN**：老旧、明文、生态差——仅占位枚举 +「即将推出」即可。

### 5.2 `HostProfile` 字段（建议）

```text
id, name, protocol (ssh|sftp|telnet|ftp|serial|local|rlogin),
host, port, username, auth (password|key),
password?, privateKey?, passphrase?,
ftpSecure? (none|ftps|ftpes),   // FTP only
serialDeviceId?, baudRate?,     // P2
saveSecret: bool
```

现网 ssh-pad 仅 `SSH|TELNET`；迁移时 `kind` → `protocol`，SFTP/FTP 为新增枚举值。

---

## 6. 功能矩阵（ssh-pad → Flutter）

| 功能 | Flutter 做法 | 优先级 |
|------|--------------|--------|
| SSH 连接 + PTY 终端 | dartssh2 + xterm | **P0 首发** |
| 密码 / 私钥认证 | dartssh2 identities | **P0** |
| 多会话切换/关闭 | SessionHub 风格状态管理 | **P0** |
| 日夜间主题 | ThemeData / 动态切换 | **P0** |
| 主机列表 CRUD | HostStore + protocol | **P0** |
| Pad 分栏 + 拖拽分割条 | `LayoutBuilder` + GestureDetector（对照 `SshPadAppUi.kt`） | **P0** |
| 外接键盘 + IME 清理 | 见 §7 | **P0** |
| ExtraKeys（Esc/Tab/Ctrl-C…） | 精简 virt keys | **P0** |
| SFTP 列表/上传/下载 | dartssh2 SFTP + file_picker | **P0 首发** |
| TELNET 终端 | ctelnet / 自研 → 同一 TerminalView | **P0 首发** |
| FTP 列表/上传/下载 | ftpconnect → 同一文件 UI | **P0 首发** |
| 前台保活 FGS | 见 §8 | **P0**（可紧随终端后） |
| 电池优化 / OEM 自启动引导 | 移植 `KeepAliveOem` 思路 | **P0/P1** |
| SSH keepalive 探测（server alive） | dartssh2 空闲发包 / 定时 ping；对照 JSch 8s | **P0** |
| 断线提示（默认不强行狂重连） | 可选开关；默认有限次数或关闭 | **P1**（产品：避免冻结） |
| 节点卡片 CPU/内存预览 | SSH exec 轻量采样（ssh-pad stats） | **P1** |
| 悬浮球 overlay | 可选；国行加分 | **P1** |
| 弱音 mediaPlayback 保活 | 平台代码移植 `KeepAlivePlayer` | **P1**（国行） |
| 会话日志面板 | 简易 | **P1** |
| FTPS | ftpconnect securityType | **P1** |
| Telnet 选项协商完善 | ECHO/SGA/TTYPE/NAWS | **P1** |
| TOFU 主机密钥 | 对照 PadSSH / ServerBox fingerprint | **P1** |
| 安全存储密钥 | flutter_secure_storage | **P1** |
| SERIAL | usb_serial | **P2 延后** |
| LOCAL shell | — | **P2 延后** |
| RLOGIN | — | **P2 延后** |
| 独立进程 `:session` | **不默认照搬**；先同进程 FGS + 验证；不足再评估 | 风险项 |

---

## 7. 外接键盘计划（一等公民）

### 7.1 现网做法（必须对齐的行为）

1. `MainActivity`：`configChanges` 含 `keyboard|keyboardHidden|navigation`，避免插拔键盘重建 Activity。  
2. `TerminalWebView.onCreateInputConnection`：`TYPE_TEXT_VARIATION_VISIBLE_PASSWORD | NO_SUGGESTIONS`，`IME_FLAG_NO_EXTRACT_UI` 等——关掉联想/智能标点。  
3. `index.html`：`hardenTextarea` + `clearIme`；`__sleep`/`__wake` 在 pause/resume、visibilitychange 时 **blur + 清空组字**，避免 `cd ..` → `cd cd...`。  
4. 硬件键经 xterm.js `onData` 下发；Compose 层无单独 KeyEvent 路径。

### 7.2 Flutter / xterm 做法

| 议题 | 方案 |
|------|------|
| 键事件 | `HardwareKeyboard.instance.addHandler`（对照 ServerBox `keyboard.dart`）；**仅当前可见会话**处理，防多 tab 重复 |
| 平台 keytab | `Terminal(platform: TerminalTargetPlatform.android)`（`terminal_platform.dart` 思路） |
| Enter / Backspace | 交 `TerminalView` 默认路径；回归测蓝牙键盘与软键盘 |
| Ctrl-A/C/D/Z、方向、Esc | xterm 默认 shortcuts + ExtraKeys 补齐；**保留 Ctrl-C = SIGINT**（勿被复制快捷键吃掉） |
| 剪贴板 | 用 TerminalView 自带绑定，**不要**再在 HardwareKeyboard 里重复处理（ServerBox 注释：会粘贴两次） |
| Focus | 页 `FocusNode`；resume / 切回会话 `requestFocus`；连接成功后 focus |
| IME 组字 | AppLifecycle **resumed** 时：unfocus→再 focus；若 xterm 暴露 composition API 则 clear；必要时 Android `InputMethodManager.restartInput` MethodChannel |
| 软键盘 | ExtraKeys 含「切换 IME」；外接键盘连接时可隐藏 virt keys（可选检测） |
| Android 坑 | 部分 ROM 蓝牙键盘仍走 IME；必须 NO_SUGGESTIONS 同类设置（检查 xterm `TextField`/`inputFormatters`）；插拔键盘触发 `didChangeMetrics` 时 **重新 fit 行列并 SSH resize**；勿在 `paused` 才启 FGS（见保活） |

验证设备：至少 1 台 Android 平板 + 蓝牙键盘（含国产 ROM）。

---

## 8. 保活计划（Keepalive）

### 8.1 目标语义（产品）

- **保持**：已建立的 SSH/Telnet（及活动中的文件传输）在切应用、熄屏、多任务后仍存活。  
- **断开**：用户点断开、关会话、或用户从通知 Stop；**杀进程**无法保证。  
- **不默认**：无限静默 auto-reconnect 导致 UI 假死（ssh-pad 有 5 次重连；Pad 产品要求更克制）。

### 8.2 分层

| 层 | 内容 | 参考 |
|----|------|------|
| A. SSH 协议保活 | 定时 keepalive / 读超时处理 | JSch `ServerAliveInterval=8000`；dartssh2 等价实现 |
| B. 进程保活 FGS | 有会话时 `startForegroundService`；通知展示会话数 | ServerBox `ForegroundService` + `TermSessionManager` |
| C. 锁 | `PARTIAL_WAKE_LOCK` + `WifiLock`（注意局域网无 INTERNET capability） | `SshSessionService.acquireLocks/holdNetwork` |
| D. 国行增强 | 可选 mediaPlayback 弱音、悬浮窗、忽略电池优化、厂商自启动页 | `KeepAlivePlayer` / `Float` / `Oem` |
| E. 生命周期 | 在 **inactive** 就 sync FGS（Android 12+ 后台无法新启 FGS） | ServerBox `setBackgrounded` 注释 |

### 8.3 与两边差异的决策

| 点 | ssh-pad | ServerBox | Pad Flutter 建议 |
|----|---------|-----------|------------------|
| 进程 | 独立 `:session` | 同进程 | **先同进程**（实现简单、与 Dart 会话一体）；若 OEM 仍杀再评估隔离 |
| FGS type | specialUse + mediaPlayback | dataSync | **dataSync 打底**（与 ServerBox 一致、审核清晰）；国行不够再 **可选** mediaPlayback + 弱音（需 Play 政策评估） |
| 会话位置 | 服务进程 | Dart isolate/主 isolate | 会话在 **Dart**；FGS 只负责「别被冻」+ 通知 |
| Sticky | START_STICKY + onDestroy 再拉 | START_STICKY + keepAlive 占位 | 对齐 ServerBox：`keepAlive` 空会话占位避免无法再 start |

### 8.4 实现草图

1. Dart `KeepAliveController`：会话增删、`AppLifecycleListener` → `MethodChannel.updateSessions(payload)`。  
2. Kotlin `SessionForegroundService`：解析 sessions、update notification、stop 广播回 Dart。  
3. 设置页：电池无限制、自启动（OEM intents）、悬浮窗、通知权限——文案移植 `KeepAliveOem`。  
4. 验收：后台 30–120 min 会话仍可输入；杀 FGS 后行为符合预期且不卡死。

---

## 9. 分阶段里程碑

> **「可用 MVP」定义**：SSH 终端 + **基础 FGS 保活（先于协议扩展）** + SFTP + TELNET + FTP + 主机列表/协议选择器 + Pad 基本布局 + 外接键盘不翻车。SERIAL / LOCAL / RLOGIN **不阻塞 MVP**。保活是重中之重。

### M0 — 脚手架（含保活骨架）

- 新建仓库（见 §11），Flutter Android 工程，minSdk 26。  
- 依赖：dartssh2、xterm、riverpod、file_picker、ftpconnect、ctelnet（或 Telnet 占位）。  
- `HostProfile.protocol` 枚举含全部 7 项；UI 选择器展示，P2 项标注「稍后」。  
- **保活骨架（必须）**：`SessionForegroundService`（`foregroundServiceType=dataSync`）+ MethodChannel + Manifest 权限 + lifecycle 钩子 + 电池/OEM 设置占位；Wake/Wifi 锁。  
- CI：分析 + debug APK。

### M1 — 连接 + 终端（SSH，最小可用）

- SSH 密码/密钥连接、xterm 绑定、多会话 tab、主题、ExtraKeys。  
- 硬件键盘 handler + resume 清 IME。  
- 断线 UI 状态（**默认不狂重连**）。

### M1b — 保活 FGS（**关键路径 / 重中之重**）

> 紧随首次 SSH 连通之后，先于 SFTP/TELNET/FTP 与布局打磨。

- 有会话即 start FGS；`inactive` 即 sync（Android 12+）。  
- 通知展示会话数；Stop 回传 Dart 断开。  
- PARTIAL_WAKE_LOCK + WifiLock；设置页：电池无限制、OEM 自启动。  
- 可选国行：mediaPlayback + 弱音 / 悬浮球（对照 ssh-pad KeepAlive*；Play 政策评估）。  
- SSH 协议层 server-alive；**默认关闭无限静默 auto-reconnect**。

### M2 — SFTP + TELNET + FTP（**进入可用 MVP 的协议门禁**）

- SFTP：双栏/列表 + 上传下载（对齐 XFTP 最小集）。  
- TELNET：同一 TerminalView；基本协商；档案 protocol=telnet。  
- FTP：文件 UI 复用；明文警告；可选 FTPS。  
- 协议选择器与默认端口、表单字段显隐（SSH 密钥区 / FTP 安全选项等）。

### M3 — Pad 布局 + 键盘打磨 ✅（2026-09-24）

- ≥600dp 左栏可拖拽；节点卡片；窄屏 rail。  
- 蓝牙键盘专项：Enter/BS/Ctrl/方向、插拔 resize、IME 残留回归。  
- 状态栏 inset / 点击热区（对照 ssh-pad README）。  
- 实现落点：`lib/ui/pad/pad_shell.dart`、`hardware_keyboard_handler.dart`、`MainActivity` IME channel。

### M4 — （已并入 M1b）保活深化 / 回归

- 原「M4 保活」提升为 **M1b**；本阶段仅作国行增强与长时后台回归，不阻塞协议 MVP。

### M5 — 打磨与 APK

- 日志页、设置项、崩溃收敛、TOFU（可选）、签名 APK。  
- 验收清单（§10）全绿。  
- P2 协议仅占位，不实现。

---

## 10. 风险与验证清单

### 10.1 风险

| 风险 | 缓解 |
|------|------|
| 国行杀后台强于 ServerBox dataSync | 吸收 ssh-pad OEM + 可选 mediaPlayback；文档教用户加白名单 |
| 独立进程 vs Dart 会话 | MVP 同进程；不足再隔离 |
| xterm IME 与 WebView 行为差 | 专项测试；必要时 platform view / restartInput |
| dartssh2 算法/旧服务器兼容 | 对照 ssh-pad JSch 算法列表做兼容配置 |
| AGPL 污染 | 不复制 ServerBox 源码；只用 pub 包与自研 |
| 明文协议被滥用 | UI 警告；默认推荐 SSH |
| FTP 主动/被动模式 NAT | 测局域网；暴露 passive 选项 |
| 自动重连卡死 | 默认关或限次；UI 明确「连接中」可取消 |
| Flutter 升级与插件 | 锁版本；M0 选定 stable |

### 10.2 验证清单

- [ ] SSH：密码、Ed25519/RSA 密钥、错误密码提示  
- [ ] 终端：颜色、中文、vim/top、滚回  
- [ ] 蓝牙键盘：字母、Enter、BS、Ctrl-C、方向；切应用再回来无重复组字  
- [ ] 软键盘：无智能标点污染  
- [ ] 多会话：切换不丢、关闭释放  
- [ ] SFTP：列目录、上传、下载  
- [ ] TELNET：连 23 端口设备/模拟器，输入回显正常  
- [ ] FTP：列表/上传/下载；明文警告出现；FTPS 若开则可用  
- [ ] 协议选择器：切换协议改端口与表单；P2 项不可连或提示延后  
- [ ] 后台 30min+：SSH/Telnet 仍可输入；通知常驻  
- [ ] 用户断开后 FGS 停止；无幽灵重连  
- [ ] 平板横屏分栏与拖拽  
- [ ] 日夜间主题  

---

## 11. 仓库策略建议

| 方案 | 评价 |
|------|------|
| **A. 新建 `camilavivan/ssh-pad-flutter`（推荐）** | 历史清晰；Kotlin 版 `ssh-pad` fork 可继续对照/发版；Flutter 用 MIT/Apache |
| B. 清空并替换现有 `camilavivan/ssh-pad` 内容 | 丢失 Kotlin 对照史；与 upstream Ghostpanter 关系混乱 |
| C. 单仓 monorepo `android/` + `flutter/` | 可，但首发更重 |

**建议：方案 A**。README 写明「Flutter 重写，协议 SSH/SFTP/TELNET/FTP；Kotlin 版见 ssh-pad」。应用 id 可用 `com.sshtab.pad` 或 `com.sshtab.pad.flutter`（避免与旧包冲突则用新 id）。

---

## 12. 附录：两边关键文件速查

### 键盘 / IME

- `/workspace/ssh-pad/app/src/main/java/com/sshtab/pad/ui/XtermView.kt`
- `/workspace/ssh-pad/app/src/main/assets/xterm/index.html`
- `/workspace/ssh-pad/app/src/main/java/com/sshtab/pad/MainActivity.kt`
- `/workspace/flutter_server_box/lib/view/page/ssh/page/keyboard.dart`
- `/workspace/flutter_server_box/lib/view/page/ssh/page/page.dart`
- `/workspace/flutter_server_box/lib/data/ssh/terminal_platform.dart`
- `/workspace/flutter_server_box/lib/view/page/ssh/page/virt_key.dart`

### 保活

- `/workspace/ssh-pad/app/src/main/java/com/sshtab/pad/service/SshSessionService.kt`
- `/workspace/ssh-pad/app/src/main/java/com/sshtab/pad/service/KeepAlivePlayer.kt`
- `/workspace/ssh-pad/app/src/main/java/com/sshtab/pad/service/KeepAliveFloat.kt`
- `/workspace/ssh-pad/app/src/main/java/com/sshtab/pad/service/KeepAliveOem.kt`
- `/workspace/ssh-pad/app/src/main/AndroidManifest.xml`
- `/workspace/flutter_server_box/android/app/src/main/kotlin/tech/lolli/toolbox/ForegroundService.kt`
- `/workspace/flutter_server_box/lib/data/ssh/session_manager.dart`
- `/workspace/flutter_server_box/lib/data/ssh/android_service_policy.dart`
- `/workspace/flutter_server_box/lib/core/chan.dart`

### 协议 / 会话 / 文件

- `/workspace/ssh-pad/app/src/main/java/com/sshtab/pad/ssh/SshSession.kt`（SSH+Telnet+SFTP）
- `/workspace/ssh-pad/app/src/main/java/com/sshtab/pad/ssh/HostProfile.kt`
- `/workspace/flutter_server_box/lib/data/ssh/terminal_session.dart`
- `/workspace/flutter_server_box/lib/view/page/storage/sftp.dart`
- `/workspace/flutter_server_box/lib/core/utils/server.dart`

---

*本文件随 M0 脚手架入库；2026-09-24 起保活提升为关键路径（M1b）。*
