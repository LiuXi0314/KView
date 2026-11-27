# KMark

极简深色模式 macOS 原生 Markdown、代码与图片预览编辑器（SwiftUI + AppKit + WKWebView）。

## 核心特性
- **纯深色极简界面**：macOS 原生隐形标题栏，支持 `⌘1` 仅编辑 / `⌘2` 双栏 / `⌘3` 仅预览，以及 `⌘[` / `⌘]` / `⌘0` 自由调节预览行宽与满宽模式
- **多类型代码预览与高亮**：自动识别 Swift、Python、JS/TS、JSON、HTML/CSS/XML、Java/Kotlin、Go、Rust、C/C++、Shell、YAML、SQL 等代码文件，带行号与语法高亮
- **一键代码格式化（`⇧⌥F`）**：支持 JSON、HTML/XML、大括号语言缩进与 Markdown 排版整理
- **新建空文件（`⌘N` / `⇧⌘N`）**：支持新建未命名空草稿或在当前目录直接创建空文件
- **图片与 SVG 预览**：支持 PNG / JPG / GIF / WebP / HEIC / SVG 等格式，内置适应窗口与自由缩放
- **Markdown UML 类图离线展示**：支持 ```` ```mermaid ````（`classDiagram`）与 ```` ```uml ```` 代码块离线矢量渲染

## 本地编译打包

```bash
./build_app.sh
```

执行后会在当前目录生成可直接双击运行的 `KMark.app`。
