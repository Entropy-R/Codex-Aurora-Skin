# 双平台架构

## 共享层

`manager/theme-store.mjs` 负责读取 v1/v2 主题、合并浅暗覆盖值、验证图片和缩略图、
原子切换活动主题，以及保护内置主题。`manager/server.mjs` 提供只监听
`127.0.0.1` 临时端口的认证 API。浏览器前端位于 `manager/web/`。

`library/catalog.json` 索引只读内置资源。用户主题和 `overrides.json` 位于平台状态
目录，不随引擎升级覆盖。

`runtime/` 是 CSS、渲染器与选择器契约的唯一源文件；运行
`node tools/sync-runtime-assets.mjs` 同步到两个平台的 `assets/`。

## Windows

- 只接受身份可验证的 Microsoft Store Codex 包；
- 固定 Node.js 运行时随 Setup.exe 分发；
- 引擎原子安装到 `%LOCALAPPDATA%\CodexAuroraSkin\engine`；
- 开始菜单入口启动浏览器管理器，不创建托盘或登录启动项；
- 恢复脚本关闭注入器与 CDP 会话，并通过注册包身份重新启动 Codex。

## macOS

- 校验官方 Codex App 签名身份，并使用 App 内已签名 Node.js；
- 通用 Swift App 仅负责原子安装/升级引擎、启动管理器后退出；
- 不常驻菜单栏，不安装 SwiftBar 或登录项；
- 用户状态位于
  `~/Library/Application Support/CodexAuroraSkin`。

## 主题与外观

主题固定 `appearance: auto`。渲染器观察 Codex 官方浅暗外观，切换到对应的
`visual.light` 或 `visual.dark` 参数。亮度和背景压暗只作用于背景层，
`surfaceOpacity` 只控制原生面板底色强度，不过滤文字和图标。

v1 用户主题仍可读取；运行时生成 v2 活动快照，但不批量重写用户原文件。
