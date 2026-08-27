# Codex Aurora Skin Linux 版

Linux 版面向官方 ChatGPT 桌面端中的 Codex 工作区。它通过只监听
`127.0.0.1` 的 CDP 会话注入共享主题，不修改 `/usr/lib/chatgpt`、`app.asar`、
账号、模型配置、插件或任务数据。

## 支持范围

官方 ChatGPT Linux 预览版目前支持：

- Ubuntu 24.04 LTS、Ubuntu 26.04 LTS；
- Debian 13；
- Fedora 43、Fedora 44；
- x64 与 ARM64；
- Ubuntu/Debian 的 `.deb` 和 Fedora 的 `.rpm` 安装方式。

官方说明：<https://learn.chatgpt.com/docs/linux/linux-app>

仓库开发环境是 Ubuntu 22.04 x64，已安装 `chatgpt 26.814.41407`。该系统版本
不在官方支持列表内，只作为实现和初步回归环境，不能替代受支持发行版的发布
验收。

## 从源码安装

```bash
./linux/scripts/install-aurora-skin-linux.sh
```

默认安装到：

- 引擎：`${XDG_DATA_HOME:-~/.local/share}/codex-aurora-skin/engine`；
- 主题和会话状态：
  `${XDG_DATA_HOME:-~/.local/share}/codex-aurora-skin/state`；
- 日志：`${XDG_STATE_HOME:-~/.local/state}/codex-aurora-skin`；
- 桌面入口：`${XDG_DATA_HOME:-~/.local/share}/applications`。

安装器不会创建登录启动项或 systemd 服务。升级时如果存在活动主题会话，会先
要求用户恢复官方外观，避免替换仍由注入器使用的引擎文件。

## 使用

安装后从应用菜单打开 “Codex Aurora Skin”，也可以运行：

```bash
~/.local/bin/codex-aurora-skin
```

启动主题会话会在需要时明确请求重启 ChatGPT。恢复官方外观：

```bash
~/.local/bin/codex-aurora-skin-restore --restart-chatgpt
```

从源码直接运行管理器、验证和诊断：

```bash
./linux/scripts/launch-manager-linux.sh
./linux/scripts/verify-aurora-skin-linux.sh
./linux/scripts/doctor-linux.sh
```

## 软件包身份与安全边界

Linux 版只接受包管理器登记的 `chatgpt`：

- Debian/Ubuntu 校验 `dpkg` 安装状态、架构、文件归属及清单摘要；
- Fedora 校验 RPM 包、架构、文件归属及文件摘要；
- 主程序、启动器和随包 Node.js 必须来自同一软件包；
- 包文件不得由当前普通用户写入；
- CDP 端口必须同时通过 HTTP 探测和 `/proc` 进程身份校验；
- 只对记录了 PID、启动时刻、Node 路径、注入器路径和端口的注入器发送信号。

DEB 本身没有可跨更新长期固定的 OpenAI 代码签名身份，因此这里验证的是已安装
包的归属与本机包数据库完整性，不把它表述为 macOS 代码签名的等价物。安装
ChatGPT 时仍应使用 OpenAI 官方下载页面。

## 构建发行构件

```bash
./linux/installer/build-release.sh
```

构建器生成：

- `CodexAuroraSkin-v*-linux.tar.gz`；
- 检测到 `dpkg-deb` 时生成 `codex-aurora-skin_*_all.deb`；
- 检测到 `rpmbuild` 时生成 noarch RPM。

系统软件包卸载不会跨用户强制终止 ChatGPT。卸载前应先从管理器恢复官方外观。

## 验证

```bash
./linux/tests/run-tests.sh
./linux/scripts/doctor-linux.sh
./linux/scripts/doctor-linux.sh --require-live
```

发布前还需要在 Ubuntu 24.04/26.04、Debian 13、Fedora 43/44，以及 x64、ARM64
的代表性环境中完成真实启动、注入、热更新、恢复和软件包卸载验收。
