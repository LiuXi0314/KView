# KView

极简深色模式 macOS 原生万能预览与轻编辑器（SwiftUI + AppKit + WKWebView），支持 Markdown、各类代码文件、图片与 UML 类图。

## 核心特性
- **纯深色极简界面与多 Tab 标签页**：支持同时打开多个文件并在顶部标签栏自由切换（`⌘T` 新建、`⌘W` 关闭、`⇧⌘[`/`⇧⌘]` 切换）
- **代码文件单栏原生语法高亮 + 一键格式化（`⇧⌥F`）**：支持 Swift、Python、JS/TS、JSON、HTML/CSS/XML、Java/Kotlin、Go、Rust、C/C++、Shell、YAML、SQL 等
- **Markdown 实时预览与行宽调节**：支持 `⌘1`/`⌘2`/`⌘3` 布局切换、`⌘[`/`⌘]`/`⌘0` 调节预览行宽与满宽模式
- **Markdown UML 类图离线渲染**：支持 ```` ```mermaid ````（`classDiagram`）与 ```` ```uml ```` 离线矢量绘制
- **图片与 SVG 预览**：支持 PNG / JPG / GIF / WebP / HEIC / SVG 等格式，内置适应窗口与自由缩放
- **新建空文件（`⌘N` / `⇧⌘N`）与拖拽打开**：支持拖拽任意文件或文件夹直接在新标签页打开

## 本地编译打包

```bash
./build_app.sh
```

执行后会在当前目录生成可直接双击运行的 `KView.app`（或直接双击 `安装KView.command` 安装到 `/Applications`）。
