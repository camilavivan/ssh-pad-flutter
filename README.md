# SSH Pad Flutter

Pad 优先的 Flutter SSH / Telnet / SFTP / FTP 终端客户端。  
对齐 [ServerBox](https://github.com/lollipopkit/flutter_server_box) 架构思路（`dartssh2` + `xterm` + 会话生命周期 + Android 前台服务），重写现有 Kotlin 版 [ssh-pad](https://github.com/camilavivan/ssh-pad)。

> **许可**：本仓库建议 Apache-2.0 / MIT。不复制 ServerBox 源码（AGPLv3）；仅使用 pub.dev 公开包与自研代码。

## 产品目标

- **Pad 优先 UI**：宽屏分栏（节点/文件 + 终端）、外接/蓝牙键盘一等公民。
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
4. **M2** — SFTP / TELNET / FTP ← 当前
5. **M3** — Pad 布局 / 键盘打磨
6. **M5** — 发版打磨

## 如何运行

```bash
# 依赖：Flutter stable、JDK 17、Android SDK（minSdk 26）
flutter pub get
flutter analyze
flutter run   # 需连接设备 / 模拟器
```

保活相关设置入口：主页右上角盾牌图标。

## 仓库说明

- Kotlin 对照仓：`camilavivan/ssh-pad`（勿与本仓混淆）。
- 应用 id：`com.sshtab.ssh_pad_flutter`
- org：`com.sshtab`
