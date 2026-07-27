# Codex Aurora Skin for macOS

macOS 版本保留通用 Swift App、测试和本地 DMG 构建能力，但 v1.0.0 不生成或
发布 macOS 构件。App 是一次性启动器：原子安装或升级引擎、打开本地浏览器
管理器，然后退出。它不会常驻菜单栏、创建登录项或联网检查更新。

源码验证与构建：

```bash
./macos/tests/run-tests.sh
swift test --package-path macos/menubar-app
./macos/scripts/build-dmg.sh --skip-tests
```

用户主题与覆盖值位于
`~/Library/Application Support/CodexAuroraSkin`，引擎升级和默认卸载不会
删除这些数据。管理器的恢复操作会停止注入器、关闭 CDP 会话并正常重启 Codex。
