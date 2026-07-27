# Codex Aurora Skin for Windows

Windows 版本提供 Inno Setup 安装包、固定 Node.js 运行时、Microsoft Store 包身份
校验、回环 CDP 注入和完整恢复。

普通用户请从
[GitHub Releases](https://github.com/Entropy-R/Codex-Aurora-Skin/releases)
下载 Setup.exe。安装后从开始菜单打开“Codex Aurora Skin”，浏览器管理器会初始化
共享离线资源库。安装器不会创建登录启动项，也不会联网检查更新。

源码验证：

```powershell
node --test manager/*.test.mjs
pwsh -NoProfile -File windows/tests/run-tests.ps1
pwsh -NoProfile -File windows/tests/installer-static.tests.ps1
```

运行时状态位于 `%LOCALAPPDATA%\CodexAuroraSkin`。卸载前会恢复官方外观，用户主题、
图片和覆盖值默认保留。
