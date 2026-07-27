# Windows 安装

## 安装

1. 从 [GitHub Releases](https://github.com/Entropy-R/Codex-Aurora-Skin/releases)
   下载 `CodexAuroraSkin-Setup-v*.exe` 与 `SHA256SUMS.txt`。
2. 校验 SHA-256 后运行安装器。
3. 安装完成页可选择“立即启动”；安装器不会创建登录启动项。
4. 后续从开始菜单打开“Codex Aurora Skin”。

管理器首次打开时会初始化离线主题库。如果 Codex 已运行但没有启用主题 CDP，
管理器会说明原因，并只在你明确确认后重启 Codex。

## 数据与恢复

运行时与用户数据位于 `%LOCALAPPDATA%\CodexAuroraSkin`。内置资源随升级替换，
`themes`、`overrides.json` 与当前主题会保留。

开始菜单的“恢复官方外观”会停止注入器、关闭主题 CDP 会话并正常重启 Codex。
卸载也会先执行恢复；用户主题和图片默认保留。

## 安全提示

公开安装包目前未签名。项目只支持 Microsoft Store 安装且身份校验通过的官方
Codex 应用。不要绕过包身份、CDP 目标页或回环监听校验。
