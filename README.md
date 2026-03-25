# AiCodeSwitch

AiCodeSwitch 是一个 macOS 菜单栏应用，用来管理和切换多个 Codex 账号。

## 功能

- 自动导入当前 `~/.codex/auth.json` 中正在使用的账号
- 展示当前账号的 `5 Hours` 和 `Weekly` 用量
- 展示当前账号的 `Cost` 概览
- 切换账号后重写 Codex 认证并重新打开 Codex
- 添加账号、删除账号、显示/隐藏邮箱
- 开机自启动、中文/英文切换、定时刷新

## 技术栈

- Swift 6
- SwiftUI
- macOS 14+
- Xcode 工程：`CodexSwitcher.xcodeproj`

## 本地运行

```bash
xcodebuild -project CodexSwitcher.xcodeproj -scheme CodexSwitcher -destination 'platform=macOS' build
```

也可以直接用 Xcode 打开 `CodexSwitcher.xcodeproj`，Scheme 选择 `CodexSwitcher`，Destination 选择 `My Mac`。

## 测试

```bash
xcodebuild -project CodexSwitcher.xcodeproj -scheme CodexSwitcher -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test
```

## 目录结构

```text
Sources/CodexSwitcher/
  App/                应用入口与容器
  Behavior/           协调器与业务逻辑
  Domain/             模型、协议、本地化
  Features/           账号页、设置页、代理页
  Infrastructure/     auth、usage、文件、命令、启动项等实现
  Layout/             布局常量
  Resources/          图标、本地化、菜单栏资源
  UI/                 通用 UI 组件
Tests/CodexSwitcherTests/
```

## 数据与凭证

- 账号元数据保存在 `~/Library/Application Support/CodexSwitcher`
- 凭证优先保存在 Keychain
- 如果独立打包环境下 Keychain 不可用，会回退到应用私有本地存储

## 仓库说明

- 仓库不包含打包产物、桌面导出包、DerivedData、dist 目录和本地规划文件
- 当前发布方式更适合本地自用；如果需要稳定的 Keychain 行为，建议后续补正式开发者签名
