# 开发路线图

本文档是 Codex Aurora Skin 在 Windows、macOS 和共用模块上的统一开发清单。
后续工作应先登记、确认优先级和验收标准，再进入实现。

## 分类与编号

所有功能点必须归入以下一种类型：

- `BUG`：现有行为不符合设计、出现错误或导致功能不可用；
- `OPT`：功能可用，但需要改善体验、性能、稳定性或可维护性；
- `DEV`：新增产品能力、平台支持或开发基础设施。

平台使用 `ALL`、`WIN`、`MAC` 标记。编号格式为
`类型-平台-序号`，例如 `BUG-MAC-001`、`OPT-ALL-001`。

## 维护规则

- 状态统一使用：`待确认`、`已确认`、`进行中`、`已完成`、`暂缓`。
- 优先级统一使用：`P0` 阻断、`P1` 高、`P2` 中、`P3` 低。
- 每个项目必须写明问题或目标、影响范围、目标版本和可验证的验收标准。
- `BUG` 项应附复现条件或日志证据；`OPT` 项应描述预期改善；
  `DEV` 项应说明范围边界以及对现有接口和数据的影响。
- 开始工作前将状态更新为 `进行中`；完成后记录提交或 PR、验证结果，再移入
  “已完成归档”。
- `ALL` 项必须同时完成 Windows 与 macOS 验证。仅影响单个平台时，不要求为
  另一个平台制造无关改动。
- 紧急安全修复可以先处置，但必须在同一提交或 PR 中补录。
- macOS 启动、恢复和验收命令不得再由 `launchctl submit` 包装；该机制会把
  一次性脚本注册为受管任务，脚本退出后可能再次执行并造成 Codex 重启循环。
- 分支职责、跨设备接续和单问题 PR 规则统一遵循
  [`DEVELOPMENT_WORKFLOW.md`](./DEVELOPMENT_WORKFLOW.md)。

## 版本里程碑

| 版本 | 状态 | 范围 |
| --- | --- | --- |
| `v1.0.0` | Draft Release | Windows 安装包、macOS 通用 DMG、双平台校验文件 |
| `v1.0.1` | 候选 | 处理已确认的兼容性缺陷，完成双平台回归并重新构建构件 |

## BUG：缺陷修复

| 编号 | 平台 | 优先级 | 状态 | 目标版本 | 摘要 |
| --- | --- | --- | --- | --- | --- |
| `BUG-ALL-001` | 共用 | P1 | 已完成 | `v1.0.1` 候选 | 旧主页结构规则将新建对话输入框推到视口外 |
| `BUG-WIN-001` | Windows | P1 | 已完成 | `v1.0.1` 候选 | 安装版实时验证脚本未加载主题路径 helper |
| `BUG-ALL-002` | 共用 | P1 | 已完成 | `v1.0.1` 候选 | Codex 26.810 更换 shell/header/composer 结构后主题失效且验证器误报成功 |
| `BUG-MAC-001` | macOS | P1 | 已完成 | `v1.0.1` 候选 | 休眠超过心跳超时后，管理器在唤醒时退出 |
| `BUG-MAC-002` | macOS | P1 | 已完成 | `v1.0.1` 候选 | CDP 重连期间过早报告“未通过显示校验” |

### BUG-ALL-001：新建对话页输入框被裁切

- 证据：Codex `26.721.41059` 的新建对话页仍能正确识别为
  `data-dream-route="home"`。旧版皮肤按直接子节点定位首页 Hero；新版 DOM 中
  该规则实际命中输入框外层，并叠加固定高度。在 `1512×883` 的窗口中，最终
  输入框顶部为 `1131px`、底部为 `1229px`，超出视口 `342px`。
- 影响：用户每次新建普通对话或项目对话后都可能需要手动把输入区域拖回可见
  位置。问题来自 Windows 与 macOS 共用的渲染注入器，当前已在 macOS 复现，
  Windows 需要同步验证。
- 解决方向：移除共享主页 CSS 中依赖直接子节点层级的 Hero 重排规则，保留 Codex
  原生纵向布局；实时验证同时检查主页输入框必须完整位于视口内。
- 验收标准：
  - 新建普通对话和项目内新建对话均识别为首页，输入框完整可见且无需拖动；
  - 已有普通对话仍识别为对话页，不影响消息列表和固定输入区；
  - 关键选择器缺失时页面保持可操作，不隐藏或裁切原生控件；
  - 增加两种新建对话页及普通对话页的 DOM 回归样例；
  - 同步共用运行时资源，并分别完成 Windows、macOS 回归验证。

### BUG-ALL-002：Codex 26.810 renderer 兼容

- 证据：Windows Codex `26.810.7004.0` 将主表面和 Header 改为公开 app-shell
  属性与 CSS Modules，并将输入框稳定表面移到 Composer Layout Root。旧契约只
  命中侧栏，运行时将任务页误判为设置页；verifier 又把任意 L0 当作结构通过。
  同版还将输入框后的整宽渐变改为 `from-surface via-surface`，旧透明化规则未
  命中，形成 146px 高的黑色底部遮罩。
- 修复：保留旧选择器并增加新版别名；以 `data-aurora-part` 提供有限语义回退；
  Composer 样式改施加到 Root，首页 Body/Footer 保持透明；未知页面进入
  `unknown`，不得再伪装成设置页或报告成功。底部渐变同时兼容旧 token 和新版
  `from-surface.via-surface`，且不清除较小的原生操作提示渐变。
- 验收：Windows 26.810 的已有任务和新建任务均达到 L1、`missingL1=[]`，背景、
  Composer 与 Footer 可见且无横向溢出，整宽底部渐变计算样式为透明；PowerShell
  7、Windows PowerShell 5.1 及双端 Node 回归均通过。设置页和未知页面由显式
  锚点回归测试覆盖。

### BUG-WIN-001：安装版实时验证缺少主题 helper

- 证据：Windows v1.0.1 安装器成功安装并启动主题会话后，
  `verify-aurora-skin.ps1` 稳定报错
  `Get-AuroraSkinThemePaths` 未识别。该函数定义在 `theme-windows.ps1`，
  验证入口只加载了 `common-windows.ps1`。
- 影响：主题注入器和已验证 CDP 会话能够启动，但安装版无法完成实时显示校验
  和验收截图，阻断 Windows v1.0.1 门禁。
- 解决方向：验证入口显式加载 `theme-windows.ps1`，并增加静态回归断言，
  防止打包后的独立入口再次遗漏依赖。
- 验收标准：
  - PowerShell 5.1 与 PowerShell 7 回归测试通过；
  - 安装器静态测试通过；
  - 安装版实时验证能够读取活动主题目录并返回成功；
  - 普通新建、项目内新建和已有任务页面可分别完成实时验证与截图。

### BUG-MAC-001：休眠后管理器退出

- 证据：管理器连续 120 秒未收到认证心跳时退出；Mac 休眠也会造成相同的时间
  间隔，唤醒后旧页面请求显示 `Failed to fetch`。
- 影响：用户必须关闭旧页面并重新启动 Codex Aurora Skin。
- 解决方向：区分系统休眠造成的事件循环长间隔和真正的客户端离线，同时保留
  无客户端时自动退出的安全边界。
- 验收标准：
  - Mac 休眠超过 3 分钟再唤醒，原管理器页面可以继续读取和应用主题；
  - 正常关闭所有管理器页面后，服务仍在约 120 秒内退出；
  - 管理器鉴权、Host/Origin 校验和随机令牌机制保持不变。

### BUG-MAC-002：唤醒后 CDP 校验误报

- 证据：唤醒后日志先出现 `CDP session is closed` 和多次
  `Initial theme verification failed`，随后注入器自动重连并验证成功；界面已经
  显示主题，但管理器仍提示“应用失败，未通过显示校验”。
- 影响：真实结果与界面提示不一致，用户可能重复应用或误以为主题损坏。
- 解决方向：为休眠后的 CDP 重连增加有界宽限和最终状态复查，只在确认无法恢复
  时报告失败。
- 验收标准：
  - 主题会话中休眠超过 3 分钟，唤醒后注入器能够自动恢复；
  - 在限定宽限期内恢复成功时，管理器返回成功而不是失败；
  - 真正的注入失败仍会停止注入器、清理状态并保留错误日志；
  - 恢复后实时验证通过，Codex 官方签名保持有效。

## OPT：优化

| 编号 | 平台 | 优先级 | 状态 | 目标版本 | 摘要 |
| --- | --- | --- | --- | --- | --- |
| `OPT-ALL-001` | 共用 | P2 | 已完成 | `v1.0.1` 候选 | 将网络断开错误改为可操作的本地化提示 |

### OPT-ALL-001：管理器断线提示

- 现状：浏览器无法连接本地管理器时直接显示 `Failed to fetch`。
- 目标：识别连接失败，并提示“管理器连接已断开，请重新打开 Codex Aurora Skin。”；
  服务端返回的具体业务错误仍按原内容显示。
- 验收标准：
  - Windows 与 macOS 共享管理器均显示简体中文可操作提示；
  - HTTP 业务错误不被错误归类为连接中断；
  - 前端自动化测试覆盖两种错误路径。

## DEV：开发

暂无已确认的新增开发项。新功能在范围和验收标准确认后登记在此处。

## 已完成归档

### v1.0.1 macOS 稳定性

- 实现提交：`4a8c0cc`；评审入口：Draft PR
  [#2](https://github.com/Entropy-R/Codex-Aurora-Skin/pull/2)。
- `BUG-MAC-001`：新增可测试的心跳租约。管理器进程暂停 17 秒再恢复后，原 PID、
  令牌和 `/api/ping` 均保持有效；正常无心跳超时的单元测试通过。
- `BUG-MAC-002`：自动 CDP 恢复增加 45 秒宽限和单次最终提示，显式应用操作仍
  保持严格校验。Codex 更新到 `26.721.81911` 后，v1.0.1 注入器重新连接并通过
  实时验证。
- macOS Node/管理器测试 21 项和 Swift/XCTest 3 项通过。通用 DMG 内含
  `arm64 + x86_64`，App 与引擎版本均为 `1.0.1`，ad-hoc 深度签名有效。
  最终 DMG SHA-256 为
  `ddfc2bf4c70686c07567304aa78e38852348173ac51f7d1138961547f92b4164`。
- 普通新建任务和项目内新建任务均通过实时校验；输入框坐标为
  `y=835–933`，完整位于 `949px` 视口内。
- 恢复后确认 `state.json`、注入器和 9341 CDP 均不存在，官方 Codex 以普通模式
  运行。验收过程曾因错误地用 `launchctl submit` 包装恢复脚本造成重启循环；
  该包装不属于产品代码，并已加入上方执行禁令。

### v1.0.1 Windows 验收

- 环境：Windows 10 Pro 22H2（build `19045.6466`），Codex
  `26.721.11231.0`（Microsoft Store 签名），Windows PowerShell
  `5.1.19041.6456`，PowerShell `7.6.4`，Node.js `24.15.0`。
- 自动化门禁全部通过：
  - `node tools/check-project-consistency.mjs`；
  - `node tools/sync-runtime-assets.mjs --check`；
  - `node --test manager/*.test.mjs`（14/14）；
  - `node --test manager/web/*.test.mjs`（3/3）；
  - `powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File
    .\windows\tests\run-tests.ps1`；
  - `pwsh.exe -NoProfile -ExecutionPolicy RemoteSigned -File
    .\windows\tests\run-tests.ps1`；
  - Windows PowerShell 5.1 与 PowerShell 7 分别运行
    `.\windows\tests\installer-static.tests.ps1`。
- 安装包：
  `release/CodexAuroraSkin-Setup-v1.0.1.exe`，大小 `25,300,317` 字节，
  文件版本 `1.0.1.0`，产品版本 `1.0.1`，SHA-256
  `72FC34BC0397CFC5E04EA6BF98402F25003420B7523EA6EBC0C41EA265C357B3`；
  `.sha256` 边车文件一致，安装内容完整且不含测试文件。
- 安装升级前后用户配置哈希和 7 个用户主题均保持不变；安装后应用程序、引擎
  版本均为 `1.0.1`，捆绑 Node.js 为 `22.23.1`。
- `BUG-WIN-001` 修复后，安装版实时验证脚本成功读取活动主题并返回
  `pass=true`。普通新建任务输入框为 `y=1113–1211`、宽 `1148px`；项目内
  新建任务和已有任务输入框均为 `y=1113–1211`、宽 `736px`，完整位于
  `2000×1227` 视口内，页面无横向或纵向溢出。背景、侧栏、输入区和页面宽度
  目视正常，隐私安全裁剪证据：
  - [`normal-new-task-composer.png`](./qa/windows-v1.0.1/normal-new-task-composer.png)；
  - [`project-new-task-composer.png`](./qa/windows-v1.0.1/project-new-task-composer.png)；
  - [`existing-task-composer.png`](./qa/windows-v1.0.1/existing-task-composer.png)。
- 管理器刷新后报告主题会话活动，真实主题应用返回
  `ok=true, applied=true, pending=false`。停止管理器后，已打开页面准确显示
  “管理器连接已断开，请重新打开 Codex Aurora Skin。”，证据：
  [`manager-disconnected-message.png`](./qa/windows-v1.0.1/manager-disconnected-message.png)。
  不存在接口保留 404“接口不存在”，不存在主题保留 400 原始业务错误，均未
  误报为连接断开。
- 使用安装版 `restore-aurora-skin.ps1 -ForceRestart` 恢复后，
  `state.json` 不存在、注入器数量为 0、9336 端口未监听、Codex 进程不含
  `remote-debugging-port=9336`，官方 Store 版本正常启动。恢复未启用
  `RestoreBaseTheme` 或 `RecoverConfigBackup`，未进入配置写入分支；当前配置
  与安装前备份均不存在 API Key/Base URL 字段。WindowsApps、`app.asar` 和
  Codex 官方文件未被修改。

`BUG-ALL-001`、`OPT-ALL-001` 已完成 Windows 与 macOS 双平台验收；
`BUG-WIN-001` 已完成修复和 Windows 回归。v1.0.1 仍为候选版本，本次不创建
标签、不发布 Release。
