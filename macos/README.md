# Codex Aurora Skin for macOS

macOS 版本通过 GitHub Releases 发布通用 DMG。App 是一次性启动器：原子安装或
升级引擎、打开本地浏览器管理器，然后退出。它不会常驻菜单栏、创建登录项或
联网检查更新。

当前公开 DMG 使用 ad-hoc 签名且未经 Apple 公证。普通用户应先核对 Release 中的
SHA-256，再按 [安装说明](../docs/install-macos.md) 使用 macOS
“隐私与安全性 → 仍要打开”的官方流程完成首次启动。

源码验证与构建：

```bash
./macos/tests/run-tests.sh
swift test --package-path macos/menubar-app
./macos/scripts/build-dmg.sh --skip-tests
```

用户主题与覆盖值位于
`~/Library/Application Support/CodexAuroraSkin`，引擎升级和默认卸载不会
删除这些数据。管理器的恢复操作会停止注入器、关闭 CDP 会话并正常重启 Codex。
