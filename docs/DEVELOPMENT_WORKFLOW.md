# 开发与分支流程

本文档规定 Windows、macOS 和共用模块的接续开发方式。所有平台共同维护
`docs/ROADMAP.md`，不要为同一版本建立彼此独立、最终再手工拼接的平台分支。

## 分支职责

- `main`：只接收已经完成目标平台验收的稳定改动；发布标签从 `main` 创建。
- `codex/vX.Y.Z-<scope>`：版本集成分支，汇总目标版本的已确认项目。例如
  `v1.0.1` 当前使用 `codex/v1.0.1-fixes`。
- `codex/fix/<编号>-<摘要>`：单个 BUG 分支。
- `codex/opt/<编号>-<摘要>`：单个优化分支。
- `codex/dev/<编号>-<摘要>`：单个新增开发分支。

单问题分支从当前版本集成分支创建，PR 也合回该版本集成分支。只有版本集成分支
完成路线图要求的双平台门禁后，才向 `main` 提交合并 PR。已经发布的标签和构件
不得移动或替换。

## 开始一项工作

1. 在 `docs/ROADMAP.md` 中登记编号、平台、优先级、目标版本和验收标准。
2. 更新远程引用并切换到当前版本集成分支，确认工作区干净。
3. 将路线图状态改为“进行中”。
4. 如果只是继续同一项跨设备验收，直接使用现有版本集成分支；如果需要修改一个
   新发现的问题，再创建对应的单问题分支。
5. 保持一个 PR 只处理一个已登记问题；不要混入无关重构、日志、构建临时文件或
   私人截图。

示例：

```text
codex/v1.0.1-fixes
└── codex/fix/BUG-WIN-001-example
```

## 跨设备接续

换到另一台电脑时，应先推送原电脑的提交，再在新电脑获取同一个远程分支。不要
复制带有 `.git` 状态的工作目录，也不要为了区分电脑创建 `-windows` 或 `-mac`
分支。

```bash
git fetch origin
git switch codex/v1.0.1-fixes
git status --short --branch
node tools/check-project-consistency.mjs
```

如果远程分支尚未在本地存在：

```bash
git switch --track origin/codex/v1.0.1-fixes
```

开始修改前核对当前分支、上游和工作区。发现未提交文件或与预期不同的提交历史时
先停止，不覆盖其他设备留下的工作。

## 验收与归档

- `ALL` 项必须分别留下 Windows 和 macOS 证据。
- 只做实机验证且不需要改代码时，也应把系统版本、Codex 版本、命令结果、构件
  哈希和恢复结果写入路线图。
- 共用资源改动后运行 `node tools/check-project-consistency.mjs`。
- 用户可见改动同步更新对应平台 CHANGELOG 和使用文档。
- 验收完成后，将路线图项目移入“已完成归档”，记录提交或 PR。
- 合并前检查提交元数据、路径、日志和截图，避免提交姓名、邮箱、Token、密钥、
  私人任务或本机绝对路径。

## 当前 v1.0.1 接续关系

- `codex/macos-v1.0.0-docs` / PR #1：保留 v1.0.0 macOS 文档历史。
- `codex/v1.0.1-fixes` / PR #2：v1.0.1 版本集成分支，Windows 电脑继续使用此
  分支。
- Windows Codex 可直接使用
  [`WINDOWS_V1.0.1_HANDOFF_PROMPT.md`](./WINDOWS_V1.0.1_HANDOFF_PROMPT.md)
  中的接续提示词。
- PR #1 合入 `main` 后，将 PR #2 的目标分支调整为 `main`。
- Windows 门禁完成前，不合并 PR #2、不创建 `v1.0.1` 标签、不发布 Release。
