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
| SERIAL | — | ❌ 稍后 | USB OTG |
| LOCAL | — | ❌ 稍后 | 本机 shell |
| RLOGIN | 513 | ❌ 稍后 | 明文冷门 |

## 技术栈

| 项 | 选型 |
|----|------|
| Flutter | stable（本机以 `flutter --version` 为准） |
| 状态 | Riverpod |
| SSH/SFTP | dartssh2 |
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
6. **M5** — 发版打磨 ← 当前

## Pad 布局与键盘（M3）

- **≥600dp**：左栏主机卡片 / 会话列表，中间 14dp 拖拽分割条（宽度持久化），右栏终端或文件。
- **&lt;600dp**：`NavigationRail`（主机 / 终端 / 文件 / 设置），避免破坏手机布局。
- **安全区**：顶栏控件最小点击热区 **48dp**；OEM 状态栏 inset 为 0 时保底 40dp。
- **键盘**：
  - Manifest `configChanges` 已含 `keyboard|keyboardHidden|navigation`（插拔不重建 Activity）。
  - `HardwareKeyboard`：Esc 转发；**Ctrl-C → SIGINT**（非复制；复制为 Ctrl+Shift+C）。
  - Resume / 可见性：unfocus→`InputMethodManager.restartInput`→focus，清 IME 组字。
  - Metrics 变化：重建 fit 行列并触发 PTY `resize`。
  - 软键盘：`TextInputType.visiblePassword`（少联想 / 智能标点）。
  - 检测到硬件键盘时可隐藏 ExtraKeys。

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
