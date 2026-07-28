# macOS 安装

## 下载与安装

macOS 版本要求 macOS 13 或更高版本，并需要已安装官方 Codex App。

1. 从 [GitHub Releases](https://github.com/Entropy-R/Codex-Aurora-Skin/releases)
   下载 `CodexAuroraSkin-v1.0.0.dmg` 和 `SHA256SUMS.txt`。
2. 核对 DMG 的 SHA-256 与校验文件一致。
3. 打开 DMG，将 “Codex Aurora Skin” 拖入“应用程序”。
4. 尝试启动一次。如果 macOS 提示无法验证开发者，请打开
   “系统设置 → 隐私与安全性”，确认文件来源和 SHA-256 后点击“仍要打开”。
5. 再次启动 App；它会安装本地主题引擎、打开浏览器管理器，然后自动退出。

“仍要打开”是 Apple 为未公证 App 提供的单次例外流程，具体界面以
[Apple 官方说明](https://support.apple.com/zh-cn/102445)为准。本项目不要求关闭
Gatekeeper，也不提供删除 quarantine 属性的终端命令。

## 使用主题管理器

1. 从“应用程序”启动 “Codex Aurora Skin”。
2. 在浏览器管理器中选择内置主题，或导入 PNG、JPEG、WebP 图片。
3. 分别调整浅色、暗色模式的背景亮度、背景压暗和界面底色强度。
4. 点击应用；如果 Codex 正在以普通模式运行，按提示允许它重启一次。
5. 需要暂停主题时选择“恢复官方外观”，管理器会停止注入器、关闭 CDP 会话并
   正常重启 Codex。

App 不会常驻菜单栏、创建登录项或联网检查更新。后续再次打开 App 即可重新启动
管理器。

## 数据与恢复

引擎安装在 `~/.codex/codex-aurora-skin`，用户主题与覆盖值保存在
`~/Library/Application Support/CodexAuroraSkin`。升级不会覆盖用户数据。

管理器中的“恢复官方外观”会停止注入器、关闭主题 CDP 会话并正常重启 Codex。
默认卸载保留用户主题与图片。

## 安全提示

公开 DMG 使用 ad-hoc 签名且未经过 Apple 公证，因此 macOS 默认会阻止首次启动。
运行时只接受签名身份符合预期的官方 Codex 应用及其 Node 运行时，并只连接回环
CDP 端点；它不会修改 Codex 的 `app.asar` 或官方签名。

## 开发验证

开发者从源码构建需要完整 Xcode 和 Node.js 20 或更高版本：

```bash
./macos/tests/run-tests.sh
swift test --package-path macos/menubar-app
./macos/scripts/build-dmg.sh --skip-tests
```
