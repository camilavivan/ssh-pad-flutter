# SSH Pad Flutter

Pad 优先的 Flutter SSH / Telnet / SFTP / FTP 终端客户端。  
对齐 [ServerBox](https://github.com/lollipopkit/flutter_server_box) 架构思路（`dartssh2` + `xterm` + 会话生命周期 + Android 前台服务），重写现有 Kotlin 版 [ssh-pad](https://github.com/camilavivan/ssh-pad)。

> **许可**：本仓库建议 Apache-2.0 / MIT。不复制 ServerBox 源码（AGPLv3）；仅使用 pub.dev 公开包与自研代码。

## 产品目标

- **Pad 优先 UI**：宽屏（≥600dp）左栏节点/会话 + 可拖分割条 + 右栏终端/文件；窄屏 NavigationRail。
- **外接 / 蓝牙键盘**：`configChanges` 含 keyboard；Ctrl-C = SIGINT；resume 清 IME 组字；插拔/旋转 refit PTY。
- **首发协议**：SSH、SFTP、TELNET、FTP；主机档案含 `protocol` 字段。
- **保活是重中之重**：切应用/熄屏不断开；同进程 ForegroundService（`dataSync`）+ Wake/Wifi 锁 + OEM 引导；默认**不**无限静默自动重连。
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
| 保活 | 自写 Android FGS + MethodChannel |

## 里程碑（保活提前）

1. **M0** — 脚手架 + HostProfile + 保活骨架（FGS stub）
2. **M1** — 最小 SSH 终端
3. **M1b** — **保活 FGS 完整接通（关键路径）**
4. **M2** — SFTP / TELNET / FTP
5. **M3** — Pad 布局 / 键盘打磨 ← 当前
6. **M5** — 发版打磨

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
