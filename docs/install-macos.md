# macOS 安装

## v1.0.0 状态

v1.0.0 只发布 Windows EXE，不生成或发布 macOS DMG。macOS 源码和测试继续保留，
供开发者审查与本机构建；当前没有面向普通用户的 macOS 安装包。

源码验证与本机构建：

```bash
./macos/tests/run-tests.sh
swift test --package-path macos/menubar-app
./macos/scripts/build-dmg.sh --skip-tests
```

本机构建的 App 会原子安装或升级本地引擎，打开浏览器管理器，然后自动退出。

产品不会常驻菜单栏、创建登录项或联网检查更新。后续再次打开 App 即可重新
启动管理器。

## 数据与恢复

引擎安装在 `~/.codex/codex-aurora-skin`，用户主题与覆盖值保存在
`~/Library/Application Support/CodexAuroraSkin`。升级不会覆盖用户数据。

管理器中的“恢复官方外观”会停止注入器、关闭主题 CDP 会话并正常重启 Codex。
默认卸载保留用户主题与图片。

## 安全提示

本机构建的 DMG 使用临时签名且未公证，不属于 v1.0.0 公开构件。运行时只接受
签名身份符合预期的官方 Codex 应用及其 Node 运行时，并只连接回环 CDP 端点。
