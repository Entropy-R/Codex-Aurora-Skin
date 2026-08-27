# Codex Aurora Skin

[English](./README.en.md) | 简体中文

Codex Aurora Skin 是面向 Windows、macOS 与 Linux 的非官方 Codex 桌面主题管理器。
它通过仅监听回环地址的 CDP 会话注入背景样式，不修改 Codex 应用文件、
账号、模型配置、插件或任务数据。

> 本项目与 OpenAI 无隶属、赞助或背书关系。

## 下载与安装

从 [GitHub Releases](https://github.com/Entropy-R/Codex-Aurora-Skin/releases)
下载对应平台的公开安装包：

- Windows：`CodexAuroraSkin-Setup-v*.exe`
- macOS：`CodexAuroraSkin-v*.dmg`
- Linux 预览版：`CodexAuroraSkin-v*-linux.tar.gz`、`.deb` 或 `.rpm`
- 校验文件：`SHA256SUMS.txt`

不同版本包含的公开构件可能不同，请以对应 Release 的 Assets 列表为准。Linux
首版代码已合入 `main`，安装包发布在
[Linux v1.0.1 预览版](https://github.com/Entropy-R/Codex-Aurora-Skin/releases/tag/linux-v1.0.1)；
也可以按下文从源码安装。Linux 包尚未完成全部受支持发行版和 ARM64 实机验收，
因此当前作为预览版提供。

公开构件目前未使用商业代码签名。macOS App 使用 ad-hoc 签名且未经 Apple
公证，首次打开时需要在“系统设置 → 隐私与安全性”中确认“仍要打开”。
产品只在用户手动启动时运行，不创建登录启动项，也不会联网检查更新。

`v1.0.1` 修复了新建任务输入框在部分窗口尺寸下超出可视区域的问题，兼容
Codex 26.810 的新版主区域、Header 与 Composer 结构，并改善 macOS 休眠唤醒
后的管理器心跳和皮肤连接恢复。浏览器管理器断开时会提示重新打开 App，不再
直接显示 `Failed to fetch`。

### macOS 首次使用

1. 打开下载的 DMG，将 “Codex Aurora Skin” 拖入“应用程序”。
2. 尝试启动一次；如果 macOS 阻止运行，打开“系统设置 → 隐私与安全性”，
   确认下载文件的 SHA-256 与 Release 一致后选择“仍要打开”。
3. 再次启动 App，本地主题管理器会在浏览器中打开。
4. 选择主题并点击应用；首次启用时按提示允许 Codex 重启。
5. 需要退出主题会话时，在管理器中选择“恢复官方外观”。

详细步骤和数据目录见 [macOS 安装说明](./docs/install-macos.md)。安全提示参考
[Apple 官方说明](https://support.apple.com/zh-cn/102445)。

### Linux 首次使用

Linux 版用于官方 ChatGPT Linux 桌面端中的 Codex 工作区。请先通过系统包管理器
安装官方 `chatgpt` 软件包，再执行：

```bash
git clone https://github.com/Entropy-R/Codex-Aurora-Skin.git
cd Codex-Aurora-Skin
./linux/scripts/install-aurora-skin-linux.sh
```

安装器只写入当前用户的 XDG 数据目录，不修改 ChatGPT 的安装文件，也不创建
登录启动项或 systemd 服务。安装完成后会自动打开管理器；以后可以从应用菜单
启动 “Codex Aurora Skin”，或运行：

```bash
~/.local/bin/codex-aurora-skin
```

在管理器中点击“导入主题”可导入 PNG、JPEG 或 WebP 图片，选择主题并点击应用后，
按提示允许重启 ChatGPT。用户主题默认保存在
`~/.local/share/codex-aurora-skin/state/themes`。该目录中的每个子目录都是包含
`theme.json`、背景图和缩略图的完整主题包，不应只把原始图片复制进去。

需要结束主题会话时，在管理器中选择“恢复官方外观”，或运行：

```bash
~/.local/bin/codex-aurora-skin-restore --restart-chatgpt
```

支持的发行版、源码安装选项、DEB/RPM/TAR 构建和诊断命令见
[Linux 安装说明](./docs/install-linux.md)与
[Linux 版 README](./linux/README.md)。

## 主题管理器

启动 “Codex Aurora Skin” 后会打开简体中文浏览器管理器：

- 浏览内置主题与用户主题；
- 分别设置浅色、暗色模式的背景亮度、背景压暗和界面底色强度；
- 导入 PNG、JPEG、WebP 图片，并在本机生成缩略图；
- 应用、重命名或删除用户主题；
- 明确确认后启动或重启 Codex 主题会话；
- 恢复官方外观并关闭 CDP 会话。

首版离线资源库包含原创“红白抽象”主题。内置主题只读，
用户主题保存在平台状态目录，升级和默认卸载都会保留。

亮度范围为 `0.35～1.20`。暗色模式的背景压暗范围为 `0～0.70`、界面底色强度
范围为 `0.20～1.00`；浅色模式为保证文字对比度，安全下限分别是 `0.32` 和
`0.60`。图片参数只作用于独立背景层，界面底色强度只改变面板透明度，
不会连带改变文字、按钮、代码和原生控件。主题始终使用 `appearance: auto`，
跟随 Codex 官方浅色/暗色外观。

## 安全边界

- 管理服务仅绑定 `127.0.0.1` 的系统临时端口；
- 每次启动生成 256 位随机令牌，并校验 Host、Origin 与 Bearer 认证；
- 页面使用严格 CSP，不发送 Referrer；
- 导入图片限制为 16 MB、单边 16384px、总像素 50MP；
- 主题与覆盖值通过临时目录和原子替换提交；
- 连续 120 秒无认证客户端后管理服务退出；系统休眠唤醒会重新给予完整心跳
  窗口，注入器继续维持并自动恢复当前主题；
- 恢复操作会停止注入器、关闭 CDP 会话并按官方方式重启 Codex。

## 开发验证

```powershell
node --test manager/*.test.mjs
pwsh -NoProfile -File windows/tests/run-tests.ps1
pwsh -NoProfile -File windows/tests/installer-static.tests.ps1
node tools/sync-runtime-assets.mjs --check
```

macOS 构建与回归需在 macOS 上运行：

```bash
./macos/tests/run-tests.sh
swift test --package-path macos/menubar-app
./macos/scripts/build-dmg.sh --skip-tests
```

Linux 回归与构建：

```bash
./linux/tests/run-tests.sh
./linux/scripts/doctor-linux.sh
./linux/installer/build-release.sh
```

详细安装说明见
[Windows](./docs/install-windows.md)、[macOS](./docs/install-macos.md) 与
[Linux](./docs/install-linux.md)。

## 开发路线图

Windows、macOS、Linux 和共用模块的 BUG 修复、优化与新增开发项统一维护在
[开发路线图](./docs/ROADMAP.md)。后续工作以其中的优先级、目标版本和验收标准
为依据。跨设备接续、版本集成分支和单问题修复分支的使用方式见
[开发与分支流程](./docs/DEVELOPMENT_WORKFLOW.md)。切换到 Windows 电脑继续
`v1.0.1` 时，可复制
[Windows Codex 接续提示词](./docs/WINDOWS_V1.0.1_HANDOFF_PROMPT.md)。
