---
name: codex-aurora-skin-windows
description: Build, verify, and maintain the Windows Codex Aurora Skin installer and runtime.
---

# Windows 维护说明

保持 Microsoft Store 包身份校验、回环 CDP、目标页验证、注入器热更新和完整恢复。
共享管理器与资源库位于仓库根目录 `manager/`、`library/`；Windows 脚本只处理
应用发现、进程、CDP、安装路径和恢复。

修改共享 CSS 或渲染器后运行：

```powershell
node tools/sync-runtime-assets.mjs
node --test manager/*.test.mjs
pwsh -NoProfile -File windows/tests/run-tests.ps1
pwsh -NoProfile -File windows/tests/installer-static.tests.ps1
```

不得写入 Codex `config.toml`，不得创建托盘、登录启动项或联网更新检查。
