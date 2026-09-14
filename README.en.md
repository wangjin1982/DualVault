# DualVault — Dual-Pane File Manager for macOS

> See both directories at a glance. Move files between them in one click.

DualVault is a native macOS dual-pane file manager (Swift 6 / SwiftUI + AppKit hybrid) built to match and exceed the daily-driver experience of ForkLift and Total Commander — with **zero third-party dependencies**.

![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue) ![Swift](https://img.shields.io/badge/Swift-6-orange) ![Dependencies](https://img.shields.io/badge/dependencies-0-success)

## ✨ Features

### Dual-Pane Core
- **Dual-pane browsing**: NSTableView bridge, 100k-file folders open in under a second, alternating row colors for easy scanning
- **Center action bar**: copy / move (direction-aware — no need to pick a direction), sync compare, swap paths, mirror path, new folder, trash — all one click away
- **Independent tabs per pane**: ⌘T / ⌘W / middle-click to close
- **Two-tier selection**: selected folders get a darker tint than files, so you can tell them apart instantly

### File Operations
- **Directional transfer**: copy/move always flow from the focused pane to the opposite one
- **Conflict handling**: overwrite / skip / keep both / apply to all, with size and date comparison
- **Safe deletes**: everything (including sync mirrors and app uninstalls) goes to Trash — full ⌘Z undo across all operation types
- **Background queue**: serial OperationQueue with visible progress and cancellation; the UI never blocks
- **Cross-volume moves**: automatically degrade to copy → verify → delete source

### Power Tools
- **Folder sync/compare**: three compare modes (name / name+size / content hash), dry-run preview before mirror sync
- **Duplicate finder**: two-stage dedup (size → hash), pick which copy to keep
- **Batch rename**: find & replace, regex with capture groups, numbered templates, extension protection, live conflict preview
- **Read-only zip browsing**: browse archives like folders, extract selected entries
- **App uninstaller**: scans related files (Preferences/Caches/Containers…), plan-based removal
- **Checksums**: MD5 / SHA256 via CryptoKit, verified against `shasum`
- **QuickLook**: space-bar preview, works inside zips too
- **Branch view** (⌘⇧B): flatten a subtree for bulk moves
- **Type-to-filter** / **wildcard selection** / **directory hotlist** / **sync browsing** / **file split & join** / **open terminal here**

### Theming
- **Dark and light themes** with **follow-system auto switching** (live, persists across relaunches)
- Custom JSON themes: drop into `~/Library/Application Support/DualVault/Themes/*.json`
- User themes may carry a paired `lightColors` palette and participate in system-following

## 🔨 Build & Run

Requirements: macOS 13+, Xcode command line tools (Swift 6 toolchain).

```bash
git clone https://github.com/wangjin1982/DualVault.git
cd DualVault
swift build            # zero third-party dependencies
swift test             # 116 unit tests
.build/debug/DualVault # launch
```

Release build:

```bash
swift build -c release
.build/release/DualVault
```

## 🏗 Architecture

```
Sources/DualVault/
├── App/          # BrowserModel (command center), layout memory, favorites
├── Core/         # Pure logic, zero UI imports, fully unit-testable
│   ├── FileSystem/   # Directory enumeration, wildcards, hashing, diffing
│   ├── Operations/   # FileOperation protocol + serial queue (copy/move/trash/zip/sync/rename…)
│   ├── Transfer/     # TransferPlanner — the single source of direction truth
│   └── Theme/        # Theme model (Codable)
└── UI/           # SwiftUI views + NSTableView bridge
```

Four iron rules:

1. **Every file operation goes through OperationQueue** — the UI layer never calls FileManager write APIs directly
2. **TransferPlanner is the only source of direction logic** — buttons and any future entry point share one implementation
3. **Deletes always go to Trash** — data safety first
4. **Zero hardcoded colors** — everything flows through the Theme Environment, overridable via skin JSON

## 🎨 Theme JSON Example

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

## 🤖 About This Project

Built by a **dual-AI collaboration**: ZCode (review & acceptance) and Kimi (development), driven by a file-based pipeline of task orders → delivery notes → itemized acceptance reviews. Ten iterations, all passed on first review, 116 unit tests green.

## 📄 License

MIT
