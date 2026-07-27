# Codex Aurora Skin

Codex Aurora Skin 是面向 Windows 与 macOS 的非官方 Codex 桌面主题管理器。
它通过仅监听回环地址的 CDP 会话注入背景样式，不修改 Codex 应用文件、
账号、模型配置、插件或任务数据。

> 本项目与 OpenAI 无隶属、赞助或背书关系。

## 下载

从 [GitHub Releases](https://github.com/Entropy-R/Codex-Aurora-Skin/releases)
下载 Windows 公开安装包：

- Windows：`CodexAuroraSkin-Setup-v*.exe`
- 校验文件：`SHA256SUMS.txt`

公开构件目前未签名。macOS 源码与测试仍保留，但 v1.0.0 不生成或发布 DMG。
产品只在用户手动启动时运行，不创建登录启动项，也不会联网检查更新。

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
- 连续 120 秒无认证客户端后管理服务退出，注入器继续维持当前主题；
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

详细安装说明见
[Windows](./docs/install-windows.md) 与 [macOS](./docs/install-macos.md)。
