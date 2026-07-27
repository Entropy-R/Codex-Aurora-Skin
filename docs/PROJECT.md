# Codex Aurora Skin 项目说明

仓库：https://github.com/Entropy-R/Codex-Aurora-Skin

当前产品是 Windows/macOS 双平台离线主题管理器，由四部分组成：

- `manager/`：共享主题协议、用户资源库、本地安全 API 与简体中文前端；
- `library/`：只读内置主题、缩略图、目录清单与许可记录；
- `runtime/`：共享 CSS、渲染器和选择器契约；
- `windows/`、`macos/`：官方应用发现、进程、CDP、恢复和安装包。

项目不提供赞助入口、推广网站、在线主题商店、自动更新、登录自启动或 Codex
原生配置修改。公开包只包含许可记录明确的原创内置素材；用户导入内容仅保存在
本机状态目录。

v1.0.0 只发布未签名的 Windows Setup.exe，并附 SHA-256 校验文件。macOS 保留
源码、测试与本地构建能力，不生成公开构件。Release 元数据统一指向
`Entropy-R/Codex-Aurora-Skin`。
