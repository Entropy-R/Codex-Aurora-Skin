# Codex Aurora Skin 项目说明

仓库：https://github.com/Entropy-R/Codex-Aurora-Skin

当前产品是 Windows/macOS/Linux 三平台离线主题管理器，由四部分组成：

- `manager/`：共享主题协议、用户资源库、本地安全 API 与简体中文前端；
- `library/`：只读内置主题、缩略图、目录清单与许可记录；
- `runtime/`：共享 CSS、渲染器和选择器契约；
- `windows/`、`macos/`、`linux/`：官方应用发现、进程、CDP、恢复和安装包。

项目不提供赞助入口、推广网站、在线主题商店、自动更新、登录自启动或 Codex
原生配置修改。公开包只包含许可记录明确的原创内置素材；用户导入内容仅保存在
本机状态目录。

v1.0.0 发布未签名的 Windows Setup.exe 与使用 ad-hoc 签名、未经 Apple 公证的
macOS 通用 DMG，并附两类构件的 SHA-256 校验文件。Release 元数据统一指向
`Entropy-R/Codex-Aurora-Skin`。

v1.0.1 候选统一修复双平台主页布局和管理器断线提示，并改善 macOS 休眠后的
心跳租约与 CDP 自动恢复。v1.0.0 标签和既有构件保持不变。

Linux 首版新增官方 ChatGPT DEB/RPM 包身份发现、XDG 用户级安装、动态回环 CDP
会话和完整恢复流程。源码同时提供 TAR、DEB 与 RPM 构建配置；受支持发行版和
ARM64 的发布矩阵仍需在对应环境完成验收。
