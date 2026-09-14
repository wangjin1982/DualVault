# DualVault — macOS 双栏文件管理器

> 一眼看清两个目录，一键完成左右互传。

DualVault 是一款原生 macOS 双栏文件管理器（Swift 6 / SwiftUI + AppKit 混合架构），目标是对齐并超越 ForkLift / Total Commander 的日常文件操作体验——**零第三方依赖**。

![平台](https://img.shields.io/badge/platform-macOS%2013%2B-blue) ![语言](https://img.shields.io/badge/Swift-6-orange) ![依赖](https://img.shields.io/badge/dependencies-0-success)

## ✨ 功能特性

### 双栏核心
- **双栏浏览**：NSTableView 桥接，10 万文件目录打开 < 1s，交替行色防看岔行
- **中央操作栏**：复制 ⇄ 移动（方向感知，无需选方向）、同步比较、交换路径、同路径、新建文件夹、删除到废纸篓——全部一键直达
- **每栏独立标签页**：⌘T / ⌘W / 中键关闭
- **选中两档**：文件夹选中色更深一档，文件稍浅，一眼区分

### 文件操作
- **方向互传**：复制/移动只作用于焦点栏 → 对侧栏，中央按钮直达
- **冲突处理**：覆盖 / 跳过 / 保留两者 / 应用到全部，含大小日期对比
- **安全删除**：所有删除（含同步镜像、App 卸载）一律进废纸篓，⌘Z 全类型可撤销
- **后台队列**：串行 OperationQueue，进度可见、可取消，绝不阻塞 UI
- **跨卷移动**：自动降级为 复制 → 校验 → 删源

### 效率工具
- **文件夹同步/比较**：三种比较模式（名称 / 名称+大小 / 内容哈希），镜像同步干跑预览
- **重复文件查找**：大小 → 哈希两级去重，组内自选保留项
- **批量重命名**：查找替换、正则 + 捕获组、序号模板、扩展名保护、实时预览冲突标红
- **zip 只读浏览**：压缩包当文件夹逛，按条目解压提取
- **App 卸载器**：扫描关联文件（Preferences/Caches/Containers…），计划式删除
- **校验和**：MD5 / SHA256（CryptoKit），与 shasum 结果一致
- **QuickLook**：空格预览，zip 内条目也可预览
- **分支视图**（⌘⇧B）：子树拍平，批量搬运
- **输入即过滤** / **通配符选择** / **目录热列表** / **同步浏览** / **文件分割合并** / **在此处打开终端**

### 主题
- **深色 / 浅色双主题**，支持**跟随系统自动切换**（实时生效，重启保持）
- JSON 自定义皮肤：放入 `~/Library/Application Support/DualVault/Themes/*.json` 即生效
- 用户主题可携带 `lightColors` 配对色板，同样支持跟随系统

## 🔨 构建与运行

要求：macOS 13+，Xcode 命令行工具（Swift 6 工具链）。

```bash
git clone https://github.com/wangjin1982/DualVault.git
cd DualVault
swift build            # 零三方依赖，构建即用
swift test             # 116 个单元测试
.build/debug/DualVault # 启动
```

发布版构建：

```bash
swift build -c release
.build/release/DualVault
```

## 🏗 架构

```
Sources/DualVault/
├── App/          # BrowserModel（指挥中心）、布局记忆、收藏
├── Core/         # 纯逻辑层，零 UI 依赖，全部可单测
│   ├── FileSystem/   # 目录枚举、通配符、哈希、差异比较
│   ├── Operations/   # FileOperation 协议 + 串行队列（复制/移动/删除/压缩/同步/重命名…）
│   ├── Transfer/     # TransferPlanner — 方向逻辑唯一来源
│   └── Theme/        # 主题模型（Codable）
└── UI/           # SwiftUI 视图 + NSTableView 桥接
```

四条铁律：

1. **所有文件操作走 OperationQueue**——UI 层永不直接调 FileManager 写接口
2. **方向逻辑唯一来源 TransferPlanner**——按钮与未来任何入口共用一套
3. **删除永远进废纸篓**——数据安全优先
4. **颜色零硬编码**——全部走 Theme Environment，皮肤 JSON 可覆盖

## 🎨 主题 JSON 示例

```json
{
  "name": "MyTheme",
  "colors": {
    "background": "#1B1C21", "paneBackground": "#202127",
    "rowEven": "#232329", "rowOdd": "#202125",
    "selFolder": "#3A4A6B", "selFile": "#33415E",
    "accent": "#4E8CFF", "foreground": "#E6E8EE", "secondaryText": "#9DA3B0"
  },
  "font": { "fileList": 13, "pathBar": 12 },
  "directoryIconTint": "#6AA7FF",
  "lightColors": { "background": "#F5F6F8", "rowEven": "#F2F3F5", "rowOdd": "#FFFFFF" }
}
```

## 🤖 关于这个项目

本项目由 **ZCode（评审/验收）与 Kimi（开发）双 AI 协作完成**：任务单 → 交付单 → 逐条验收评审的文件驱动流水线，十轮迭代全部一次通过，116 个单元测试全绿。协作过程文档见仓库外 `协作/` 目录（不入库）。

## 📄 License

MIT
