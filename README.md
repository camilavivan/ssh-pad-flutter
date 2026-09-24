# SSH Pad Flutter

Pad 优先的 Flutter SSH / Telnet / SFTP / FTP 终端客户端。  
对齐 [ServerBox](https://github.com/lollipopkit/flutter_server_box) 架构思路（`dartssh2` + `xterm` + 会话生命周期 + Android 前台服务），重写现有 Kotlin 版 [ssh-pad](https://github.com/camilavivan/ssh-pad)。

> **许可**：本仓库建议 Apache-2.0 / MIT。不复制 ServerBox 源码（AGPLv3）；仅使用 pub.dev 公开包与自研代码。

## 产品目标

- **Pad 优先 UI**：宽屏（≥600dp）左栏节点/会话 + 可拖分割条 + 右栏终端/文件；窄屏 NavigationRail。
- **外接 / 蓝牙键盘**：`configChanges` 含 keyboard；Ctrl-C = SIGINT；resume 清 IME 组字；插拔/旋转 refit PTY。
- **首发协议**：SSH、SFTP、TELNET、FTP；主机档案含 `protocol` 字段。
- **保活是重中之重**：切应用/熄屏不断开；同进程 ForegroundService（`mediaPlayback|dataSync`）+ 默认弱音 AudioTrack + Wake/Wifi 锁 + 首次连接电池白名单 + OEM 引导；默认**不**无限静默自动重连。
- 延后：SERIAL / LOCAL / RLOGIN（选择器可见，标注「稍后」）。

完整计划见 [`docs/rewrite-plan.md`](docs/rewrite-plan.md)。

## 协议矩阵（MVP vs 延后）

| 协议 | 默认端口 | 首发 | 说明 |
|------|----------|------|------|
| SSH | 22 | ✅ MVP | `dartssh2` PTY |
| SFTP | 22 | ✅ MVP | `dartssh2` SftpClient |
| TELNET | 23 | ✅ MVP | `ctelnet` |
| FTP | 21 | ✅ MVP | `ftpconnect`（FTPS/FTPES + PASV） |
| SERIAL / LOCAL / RLOGIN | — | 隐藏 | 枚举保留；协议选择器不展示 |

## 技术栈

| 项 | 选型 |
|----|------|
| Flutter | stable（本机以 `flutter --version` 为准） |
| 状态 | Riverpod |
| SSH/SFTP | dartssh2（每主机共享一个 `SSHClient`；多终端=多 shell；Files=`client.sftp()`） |
| 终端 | xterm |
| Telnet | ctelnet |
| FTP | ftpconnect |
| 持久化 | shared_preferences |
| 唤醒 | wakelock_plus |
| 保活 | 自写 Android FGS（mediaPlayback\|dataSync）+ 弱音 + MethodChannel |

## 里程碑（保活提前）

1. **M0** — 脚手架 + HostProfile + 保活骨架（FGS stub）
2. **M1** — 最小 SSH 终端
3. **M1b** — **保活 FGS 完整接通（关键路径）**
4. **M2** — SFTP / TELNET / FTP
5. **M3** — Pad 布局 / 键盘打磨
6. **M5** — 发版打磨
7. **v0.5.3** — 连接共享（多 shell + SFTP 同会话）
8. **v0.5.4** — 主机卡片资源状态（CPU / MEM / NET / DISK，共享 SSH exec）
9. **v0.5.5** — 硬件 Esc 全局策略（永不作 Back；终端发 0x1b）
10. **v0.5.6** — Esc / 硬件键盘打磨版（overlay 优先、Ctrl+[、分栏无焦点）← 当前

## Pad 布局与键盘（M3）

- **≥600dp**：左栏主机卡片 / 会话列表，中间 14dp 拖拽分割条（宽度持久化），右栏终端或文件。
- **&lt;600dp**：`NavigationRail`（主机 / 终端 / 文件 / 设置），避免破坏手机布局。
- **安全区**：顶栏控件最小点击热区 **48dp**；OEM 状态栏 inset 为 0 时保底 40dp。
- **键盘**：
  - Manifest `configChanges` 已含 `keyboard|keyboardHidden|navigation`（插拔不重建 Activity）。
  - **Esc 全局策略**：整个 App 内硬件 Esc **绝不**当作 Flutter/Android Back；`DismissIntent` shortcut + action 双保险；仅可关闭 barrierDismissible 浮层（菜单优先于终端）；终端会话活跃且非文本框焦点时发 `0x1b` 到 PTY（含 Pad 分栏终端可见但未聚焦）；**Ctrl+[** → Esc（vi）；系统返回键/手势仍可导航。
  - `HardwareKeyboard`：**Ctrl-C → SIGINT**（非复制；复制为 Ctrl+Shift+C）。Esc / Ctrl+[ 由 `AppEscapePolicy` 单路径发送，避免与 TerminalView 双发。
  - Resume / 可见性：unfocus→`InputMethodManager.restartInput`→focus，清 IME 组字。
  - Metrics 变化：重建 fit 行列并触发 PTY `resize`。
  - 软键盘：`TextInputType.visiblePassword`（少联想 / 智能标点）。
  - 检测到硬件键盘时可隐藏 ExtraKeys。


## 主机资源状态（v0.5.4）

已连接的 **SSH / SFTP** 主机卡片显示 ServerBox 风格紧凑条：

- **CPU %**（`/proc/stat` 两次采样差分）
- **MEM** used/total（`/proc/meminfo` MemTotal − MemAvailable）
- **NET** ↓rx ↑tx B/s（`/proc/net/dev` 差分）
- **DISK** `/` used/total（`df -Pk /`，可选）
- load average

采样：每 ~2.5s 对共享 `SshConnectionHub` 客户端 `exec` 一次（**不**另开 SSH）；应用进后台停表，保活不变；Telnet/FTP 不显示。

## 如何运行

```bash
# 依赖：Flutter stable、JDK 17、Android SDK（minSdk 26）
export PATH="/home/box/flutter/bin:$PATH"
flutter pub get
flutter analyze
flutter test
flutter run   # 需连接设备 / 模拟器
```

保活相关设置：左栏盾牌图标，或窄屏「设置」。

## 仓库说明

- Kotlin 对照仓：`camilavivan/ssh-pad`（勿与本仓混淆）。
- 应用 id：`com.sshtab.ssh_pad_flutter`
- org：`com.sshtab`


## M5 打磨

- **TOFU 主机密钥**：SSH/SFTP 首次连接展示指纹并写入信任库；指纹变更时警告，可拒绝或替换。
- **安全密钥存储**：密码 / 私钥 / 口令经 `flutter_secure_storage` 保存；SharedPreferences 仅存主机元数据；启动时迁移旧明文。
- **双栏文件浏览器**：宽屏（≥600dp）左本地 / 右远程，支持上传、下载、远程 mkdir/删除；窄屏可切换显示本地栏。
- **会话日志**：设置页可查看近期连接 / 密钥 / 文件操作事件。
- **安装**：从 [GitHub Releases](https://github.com/camilavivan/ssh-pad-flutter/releases) 下载 APK（`v0.5.0-m5`）。

### 自行签名发版

```bash
# 生成上传密钥（勿提交）
mkdir -p /workspace/secrets
keytool -genkeypair -v -keystore /workspace/secrets/ssh-pad-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias ssh-pad \
  -storepass CHANGE_ME -keypass CHANGE_ME \
  -dname "CN=SSH Pad, OU=Dev, O=SSHTab, L=HK, ST=HK, C=HK"

# /workspace/secrets/key.properties:
# storePassword=CHANGE_ME
# keyPassword=CHANGE_ME
# keyAlias=ssh-pad
# storeFile=/workspace/secrets/ssh-pad-upload.jks

export PATH="/home/box/flutter/bin:$PATH"
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

若未配置 `key.properties`，release 仍可用 Android debug 签名构建（仅供内测）。用户可用自己的密钥重新签名后再分发。


## 硬件 Esc 自测清单（v0.5.6 打磨版）

1. 外接 / 蓝牙键盘连接 SSH，打开 `vi` / `vim`，`i` 进插入模式 → **Esc** 退回正常模式，**不得**退出 App / 切走终端。
2. 同上，试 **Ctrl+[**：应等同 Esc（退插入模式），且只生效一次（无双 Esc）。
3. 主机列表 / 设置 / 文件页按 Esc：界面保持，不得 `Navigator.pop` / 退桌面。
4. 打开终端溢出菜单（⋯）按 Esc：仅关闭菜单，不离开终端、不杀会话。
5. TOFU 主机密钥对话框（不可点遮罩关闭）：Esc **不得**误关 / 误拒绝；需点按钮。
6. Pad 分栏：终端在右侧可见，焦点在左侧主机列表时按 Esc：应送到 PTY（vi 仍可退模式），不得 Back。
7. 主机编辑页（TextField 焦点）按 Esc：不得注入后台 PTY，也不得 pop 编辑页。
8. 系统返回键或手势返回：仍可按原 UX 离开或切 pane。
9. ExtraKeys 点 Esc：照常发 `0x1b`（软键路径与硬件策略独立）。

## 保活自测（v0.5.1+）

1. 安装 release APK，授予**通知权限**。
2. 连接一台 SSH 主机；应立刻看到「SSH Pad 会话保活」通知。
3. 按 Home / 切到其他应用，等待 **2–5 分钟**，再返回：会话应仍在，终端可继续输入。
4. `adb logcat -s SshPadFGS SshPadAudio SshPadMain` 应能看到 `startForeground mediaPlayback|dataSync ok` 与 `weak audio started`。

### 国行 OEM 建议（若仍被冻）

| 厂商 | 设置 |
|------|------|
| 小米/红米 | 自启动 = 允许；省电策略 = 无限制；锁屏清理白名单 |
| 华为/荣耀 | 启动管理 = 手动管理全开；后台活动 = 允许 |
| OPPO/一加/realme | 耗电管理 = 允许后台；自启动 = 允许 |
| vivo/iQOO | 后台高耗电 = 允许；自启动 = 允许 |
| 通用 | 忽略电池优化；可选开启悬浮窗 |

弱音保活默认开启（设置里可关）。关闭后多数国行会在切应用后很快冻死同进程 Dart SSH。
