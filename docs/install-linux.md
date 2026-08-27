# Linux 安装与恢复

Linux 版适配官方 ChatGPT 桌面端中的 Codex。官方当前提供 Ubuntu、Debian 的
`.deb` 与 Fedora 的 `.rpm`，具体发行版和架构范围以
[OpenAI 官方文档](https://learn.chatgpt.com/docs/linux/linux-app)为准。

## 用户级安装

从源码目录执行：

```bash
./linux/scripts/install-aurora-skin-linux.sh
```

安装完成后，从应用菜单打开 “Codex Aurora Skin”。安装器只写入当前用户的 XDG
数据目录和桌面入口，不需要修改 ChatGPT 安装目录，也不创建登录启动项。

如果只需部署文件而不立即打开管理器：

```bash
./linux/scripts/install-aurora-skin-linux.sh --no-launch
```

## DEB、RPM 和 TAR

开发者可运行：

```bash
./linux/installer/build-release.sh
```

生成的 DEB/RPM 将只读引擎安装到 `/opt/codex-aurora-skin`，用户主题和会话状态
仍位于当前用户的 XDG 数据目录。系统包管理器不会在卸载时猜测或终止其他登录
用户的 ChatGPT 进程；卸载前必须先恢复官方外观。

## 恢复官方外观

在管理器中点击“恢复官方外观”，或运行：

```bash
~/.local/bin/codex-aurora-skin-restore --restart-chatgpt
```

恢复流程会：

1. 验证状态文件记录的注入器身份并停止它；
2. 确认 CDP 端口属于包管理器登记的 ChatGPT 主程序；
3. 在实时页面移除皮肤并验证；
4. 关闭带 CDP 参数的 ChatGPT；
5. 按官方启动命令重新打开 ChatGPT；
6. 删除单个主题会话状态文件，保留用户主题。

## 诊断

```bash
./linux/scripts/doctor-linux.sh
./linux/scripts/doctor-linux.sh --require-live
```

诊断输出包含 ChatGPT 包类型、版本、架构、随包 Node.js、是否修改 `app.asar`、
实时会话状态和活动主题摘要，不包含账号、任务内容或用户导入图片内容。
