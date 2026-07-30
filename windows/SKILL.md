---
name: codex-aurora-skin-windows
description: Build, verify, and maintain the Windows Codex Aurora Skin installer and runtime.
---

# Windows 维护说明

保持 Microsoft Store 包身份校验、回环 CDP、目标页验证、注入器热更新和完整恢复。
共享管理器与资源库位于仓库根目录 `manager/`、`library/`；Windows 脚本只处理
应用发现、进程、CDP、安装路径和恢复。

跨设备继续工作前阅读 `docs/DEVELOPMENT_WORKFLOW.md` 和 `docs/ROADMAP.md`。
同一版本在 Windows 与 macOS 上共用版本集成分支；只有新发现且需要修改代码的
独立问题才创建 `codex/fix`、`codex/opt` 或 `codex/dev` 单问题分支。

修改共享 CSS 或渲染器后运行：

```powershell
node tools/check-project-consistency.mjs
node tools/sync-runtime-assets.mjs
node --test manager/*.test.mjs
pwsh -NoProfile -File windows/tests/run-tests.ps1
pwsh -NoProfile -File windows/tests/installer-static.tests.ps1
```

不得写入 Codex `config.toml`，不得创建托盘、登录启动项或联网更新检查。
