# 文件拖拖

一个基于 SwiftUI 的 macOS 菜单栏文件管理工具。点击菜单栏图标即可打开面板，快速切换常用文件夹，并把文件直接拖到桌面或其他软件。

![文件拖拖预览](assets/readme-preview.png)

## 功能

- 菜单栏常驻入口
- 常用文件夹添加/删除与持久化
- 文件列表搜索、排序、隐藏文件切换
- 最近使用文件区
- 文件/文件夹拖拽到桌面、Finder、聊天工具、浏览器上传框
- 全局快捷键呼出浮窗（默认 `Option + Command + F`）

## 环境要求

- macOS 13+
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## 本地运行

```bash
xcodegen generate
open FileDrap.xcodeproj
```

或命令行构建：

```bash
xcodebuild -project FileDrap.xcodeproj -scheme FileDrap -configuration Debug -sdk macosx build
```

## 本地打包（非 App Store）

```bash
./scripts/package_local.sh
```

打包后会在 `dist/` 目录生成：

- `文件拖拖.app`
- `文件拖拖-local-<时间戳>.zip`
- `文件拖拖-local-<时间戳>.dmg`

## 项目结构

- `Sources/FileDrap/`：应用源码
- `Sources/FileDrap/Assets.xcassets/`：图标与资源
- `Tests/`：单元测试
- `scripts/package_local.sh`：本地打包脚本
