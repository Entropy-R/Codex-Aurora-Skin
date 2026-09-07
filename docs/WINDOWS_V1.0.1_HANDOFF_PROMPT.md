# Windows v1.0.1 Codex 接续提示词

将下面内容完整复制到 Windows 电脑上的 Codex 新任务中。

```text
你正在 Windows 电脑上继续维护 Codex Aurora Skin。

仓库：
https://github.com/Entropy-R/Codex-Aurora-Skin

目标：
接续已有 v1.0.1 工作，完成 Windows 测试、安装包构建和实机验收。不要重复实现
macOS 已完成的功能，不要发布 Release。

开始前：

1. 获取远程更新并检出 codex/v1.0.1-fixes。
2. 确认该分支跟踪 origin/codex/v1.0.1-fixes。
3. 检查 git status；不得覆盖或删除未提交改动。
4. 阅读 AGENTS.md、README.md、docs/ROADMAP.md、
   docs/DEVELOPMENT_WORKFLOW.md、windows/SKILL.md、windows/README.md 和
   .github/CONTRIBUTING.md。
5. 运行 node tools/check-project-consistency.mjs。

当前背景：

- v1.0.0 标签和已有 Release 构件不得修改。
- Windows、macOS 和皮肤引擎版本已经统一为 1.0.1。
- macOS 验收已经完成。
- Draft PR #2：
  https://github.com/Entropy-R/Codex-Aurora-Skin/pull/2
- Windows 尚需完成：
  - BUG-ALL-001：普通新建任务和项目内新建任务的输入框完整位于窗口内。
  - OPT-ALL-001：管理器断开连接时显示中文提示，HTTP 和业务错误保留原信息。
  - Windows PowerShell 回归、安装器构建和实机恢复门禁。

执行要求：

1. 先检查现有代码、工具版本和工作区，给出简短方案，等我确认后再改代码。
2. 优先运行现有测试；测试失败时先提交原因和证据，不要直接猜测修改。
3. 完成以下自动检查：
   - node tools/check-project-consistency.mjs
   - node --test manager/*.test.mjs
   - node --test windows/tests/*.test.mjs
   - Windows PowerShell 5.1 执行 windows/tests/run-tests.ps1
   - PowerShell 7 执行 windows/tests/run-tests.ps1
   - 两种 PowerShell 执行 windows/tests/installer-static.tests.ps1
4. 使用 windows/installer/build-release.ps1 构建
   CodexAuroraSkin-Setup-v1.0.1.exe，并校验文件名、版本、大小和 SHA-256。
5. 安装并启动 Codex Aurora Skin，实测：
   - 普通新建任务输入框完整可见，无需拖动或额外滚动；
   - 项目内新建任务输入框完整可见；
   - 已有任务页面布局正常；
   - 背景、侧栏、输入区、页面宽度和注入器状态正常；
   - 管理器连接断开时显示
     “管理器连接已断开，请重新打开 Codex Aurora Skin。”；
   - HTTP 状态错误和服务端业务错误不被误报为连接断开。
6. 恢复官方外观，确认注入器停止、CDP 状态清理，Codex 正常启动。
7. 将 Windows 版本、Codex 版本、命令结果、Setup.exe 大小和 SHA-256、
   无私人内容的截图路径及恢复结果回填到 docs/ROADMAP.md。
8. 如果验收不需要改代码，只提交验收证据和文档。
9. 如果发现新的 Windows 专属问题：
   - 先在 ROADMAP 登记 BUG-WIN、OPT-WIN 或 DEV-WIN 编号；
   - 从 codex/v1.0.1-fixes 创建
     codex/fix/<编号>-<英文摘要>、codex/opt/... 或 codex/dev/...；
   - 单问题 PR 合回 codex/v1.0.1-fixes，不直接提交 main。
10. 可以提交并推送验收结果，但不得合并 PR、创建标签或发布 v1.0.1。

安全边界：

- 不修改或替换 v1.0.0 标签和构件。
- 不删除用户主题或配置。
- 不修改 WindowsApps、app.asar、API Key、Base URL 或 Codex 官方文件。
- 不绕过 PowerShell 执行策略。
- 不提交日志、用户名路径、私人截图、Token、密钥或本机配置。
- 构建失败时不得安装不完整构件。

最终使用中文汇报：

- 当前分支和最终提交；
- 修改内容；
- 测试命令与结果；
- Windows 与 Codex 版本；
- Setup.exe 路径、大小和 SHA-256；
- 实机截图路径；
- 恢复官方外观的检查结果；
- 遗留风险或门禁；
- 建议的中文 commit message。
```
