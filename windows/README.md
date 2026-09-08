# Codex Aurora Skin for Windows

Windows 版本提供 Inno Setup 安装包、固定 Node.js 运行时、Microsoft Store 包身份
校验、回环 CDP 注入和完整恢复。

普通用户请从
[GitHub Releases](https://github.com/Entropy-R/Codex-Aurora-Skin/releases)
下载 Setup.exe。安装后从开始菜单打开“Codex Aurora Skin”，浏览器管理器会初始化
共享离线资源库。安装器不会创建登录启动项，也不会联网检查更新。

源码验证：

```powershell
node tools/check-project-consistency.mjs
node --test manager/*.test.mjs
pwsh -NoProfile -File windows/tests/run-tests.ps1
pwsh -NoProfile -File windows/tests/installer-static.tests.ps1
```

安装器首次安装和升级时均允许选择程序文件目录。运行时状态位于
`%LOCALAPPDATA%\CodexAuroraSkin`。卸载前会恢复官方外观，用户主题、图片和覆盖值
默认保留。

跨电脑继续开发时，请检出已有版本集成分支，不要另建 Windows 副本。当前
`v1.0.1` Windows 验收使用 `codex/v1.0.1-fixes`；完整规则见
[`docs/DEVELOPMENT_WORKFLOW.md`](../docs/DEVELOPMENT_WORKFLOW.md)。
