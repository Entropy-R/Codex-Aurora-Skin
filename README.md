<div align="center">

# Codex Aurora Skin

为 Codex 桌面端添加可管理、可恢复的沉浸式背景主题。

[English](./README.en.md) ·
[下载](https://github.com/Entropy-R/Codex-Aurora-Skin/releases) ·
[Windows 安装说明](./docs/install-windows.md) ·
[项目文档](./docs/PROJECT.md)

</div>

![Codex Aurora Skin 雪景主题效果](./docs/images/screenshot-windows-snow-public.png)

> [!IMPORTANT]
> 本项目是非官方社区项目，与 OpenAI 无隶属、赞助或背书关系。
> 它不会修改 Codex 官方安装包、账号、模型配置、插件或任务数据。

## 项目简介

Codex Aurora Skin 是面向 Codex 桌面端的本地主题管理器。它通过仅监听
回环地址的 CDP 会话注入背景样式，让 Codex 的主界面、任务页和输入区域
融入用户选择的图片，同时保留官方界面的交互与浅色/暗色模式。

- 本地导入 PNG、JPEG、WebP 图片；
- 分别调节浅色、暗色模式下的亮度、背景压暗和界面底色强度；
- 浏览、应用、重命名和删除用户主题；
- 内置主题保持只读，用户主题在升级或默认卸载后继续保留；
- 随时恢复官方外观，并关闭主题使用的 CDP 会话；
- 不创建登录启动项，不联网检查更新。

## 效果展示

### Codex 桌面端

README 顶部展示了主题在 Codex 主界面的实际效果。主题只作用于背景层和
界面面板，不会对文字、按钮、图标或原生控件套用图片滤镜。

### 本地主题管理器

管理器集中展示内置主题与用户导入主题，并为浅色、暗色外观分别保存参数。

![Codex Aurora Skin 主题管理器](./docs/images/screenshot-theme-manager.png)

> 截图中的用户导入图片仅用于演示，不包含在仓库或安装包中。

## 平台与发布状态

| 平台 | 状态 | 获取方式 |
| --- | --- | --- |
| Windows 10/11 | 已发布 | 从 Releases 下载 `CodexAuroraSkin-Setup-v*.exe` |
| macOS | 已发布 | 从 Releases 下载 `CodexAuroraSkin-v*.dmg` |

公开构件目前未使用商业代码签名。macOS App 使用 ad-hoc 签名且未经 Apple
公证，首次打开时需要在“系统设置 → 隐私与安全性”中确认“仍要打开”。
下载安装包后，请先核对 Release 中提供的 `SHA256SUMS.txt`。

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

## 快速开始

1. 从 [GitHub Releases](https://github.com/Entropy-R/Codex-Aurora-Skin/releases)
   下载 Windows 安装包和校验文件。
2. 核对安装包 SHA-256 后运行安装程序。
3. 启动 **Codex Aurora Skin**，浏览器会打开仅限本机访问的主题管理器。
4. 选择内置主题或导入自己的图片，调整参数后点击“应用主题”。
5. 需要退出主题会话时，点击“恢复官方外观”。

完整步骤、数据目录和卸载行为见
[Windows 安装说明](./docs/install-windows.md)。

## 主题参数

| 参数 | 暗色模式 | 浅色模式 | 作用 |
| --- | --- | --- | --- |
| 图片亮度 | `0.35～1.20` | `0.35～1.20` | 仅调整背景图片 |
| 背景压暗 | `0～0.70` | `0.32～0.70` | 保证前景文字对比度 |
| 界面底色强度 | `0.20～1.00` | `0.60～1.00` | 调整面板透明度 |

主题始终使用 `appearance: auto`，跟随 Codex 官方浅色或暗色外观。

## 安全边界

- 管理服务只绑定 `127.0.0.1` 的系统临时端口；
- 每次启动生成 256 位随机令牌，并校验 Host、Origin 与 Bearer 认证；
- 页面启用严格 CSP 与 `Referrer-Policy: no-referrer`；
- 导入图片限制为 16 MB、单边 16384 px、总像素 50 MP；
- 主题与覆盖值通过临时目录和原子替换提交；
- 连续 120 秒无认证客户端后管理服务退出；系统休眠唤醒会重新给予完整心跳
  窗口，注入器继续维持并自动恢复当前主题；
- 恢复操作会停止注入器、关闭 CDP 会话并按官方方式重启 Codex。

## 开发与验证

仓库主要目录：

```text
manager/   本地主题管理服务与 Web 界面
runtime/   跨平台样式与渲染器注入脚本
windows/   Windows 安装、启动、恢复和测试脚本
macos/     macOS 源码、脚本与测试
library/   离线内置主题资源库
docs/      安装说明与项目文档
tools/     一致性检查与开发工具
```

Windows 与共用模块：

```powershell
node --test manager/*.test.mjs
pwsh -NoProfile -File windows/tests/run-tests.ps1
pwsh -NoProfile -File windows/tests/installer-static.tests.ps1
node tools/sync-runtime-assets.mjs --check
```

macOS 构建与回归需要在 macOS 上运行：

```bash
./macos/tests/run-tests.sh
swift test --package-path macos/menubar-app
./macos/scripts/build-dmg.sh --skip-tests
```

更多信息：

- [项目设计说明](./docs/PROJECT.md)
- [Windows 安装说明](./docs/install-windows.md)
- [macOS 安装说明](./docs/install-macos.md)
- [平台差异](./docs/platforms.md)
- [开发路线图](./docs/ROADMAP.md)
- [开发与分支流程](./docs/DEVELOPMENT_WORKFLOW.md)
- [Windows Codex 接续提示词](./docs/WINDOWS_V1.0.1_HANDOFF_PROMPT.md)

## 许可证

代码按 [MIT License](./LICENSE) 发布。第三方声明见 [NOTICE](./NOTICE.md)。
