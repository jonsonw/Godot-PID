# Godot-PID

基于 **Godot 引擎**的开源 **P&ID（管道及仪表流程图）编辑器**。

面向流程工业，如化工、石化、医药、食品、采矿、冶金等行业，把 P&ID 绘图、符号库管理、HAZOP 知识沉淀与导出做成一套可自托管的轻量工具。

> Open-source **P&ID (Piping and Instrumentation Diagram) editor** built on the **Godot engine**.
> A self-hostable, lightweight tool for process industries, such as chemical, petrochemical, pharmaceutical, food, mining, smelting, etc. — P&ID drawing, symbol library management, HAZOP knowledge capture, and export.

## 命名 · Naming

- **产品品牌：G-PID** —— 读作 "**G**odot **P&ID**"，是本项目对外的统一产品名（短、好记，且保留引擎暗示）。
- **GitHub 仓库名：`Godot-PID`** —— 仓库名保留 "Godot" 前缀以方便检索（搜 "Godot P&ID" 可命中）；仓库名负责"被发现"，品牌名 `G-PID` 负责"被记住"。
- **官网（预留）：[g-pid.com](https://g-pid.com)** —— 域名已注册，正式主页将于首个可演示版本（v1）就绪后上线（先用 GitHub Pages 起步）。

> - **Product brand: G-PID** — short for "**G**odot **P&ID**", the unified public product name.
> - **GitHub repo: `Godot-PID`** — keeps the "Godot" prefix for discoverability; the repo name aids discovery, the brand name aids recall.
> - **Official site (reserved): [g-pid.com](https://g-pid.com)** — domain registered; the homepage goes live after the first demonstrable release (v1), starting with GitHub Pages.

## 授权模式 · License

核心代码以 **MIT 授权**发布，可自由使用、修改、再分发。

> The core code is released under the **MIT License** — free to use, modify, and redistribute.

## 快速开始 · Quick Start

1. 用 **Godot 4.3+** 打开本目录（即包含 `project.godot` 的目录）。
2. 按 **F5** 运行主场景 `scenes/main.tscn`。

> 1. Open this directory (the one containing `project.godot`) with **Godot 4.3+**.
> 2. Press **F5** to run the main scene `scenes/main.tscn`.

## 目录结构 · Directory Structure

```
Godot-PID/                # GitHub 仓库根（本地工作文件夹名为 Godot-PID-Core/）
├── project.godot          # Godot 项目文件 / Godot project file
├── project.pid.json       # P&ID 数据契约示例 / P&ID data contract sample
├── scenes/                # 主场景 / 画布场景 / Main & canvas scenes
├── src/
│   ├── core/              # PIDGraph、SymbolDef、IPIDAddon（数据内核 + 插件契约）
│   │                       # PIDGraph, SymbolDef, IPIDAddon (data core + addon contract)
│   ├── model/             # 数据模型（待扩展）/ Data models (to be extended)
│   └── ui/                # UI 脚本（待扩展）/ UI scripts (to be extended)
├── assets/                # 符号、主题、字体 / Symbols, themes, fonts
├── addons/                # 插件挂载点 / Addon mount point
└── tests/                 # 单元 / 冒烟测试 / Unit & smoke tests
```

## 核心概念 · Core Concepts

- **`PIDGraph`** — 节点-边图内核，2D 画布、3D 联动、清单导出都读取它。
  > Node-edge graph core; read by the 2D canvas, 3D linkage, and BOM export.
- **`SymbolDef`** — 数据驱动图元定义，避免为每个符号建一个类。
  > Data-driven symbol definition; avoids a class per symbol.
- **`IPIDAddon`** — 插件契约，外围功能通过继承此类挂载，核心代码不动。
  > Addon contract; peripheral features mount via subclassing without touching core code.

## 贡献 · Contributing

欢迎以 Issue / PR 参与。图元采用 `SymbolDef` 数据驱动，新增符号零门槛。

> Contributions are welcome via Issues / PRs. Symbols are `SymbolDef`-driven, so adding a new one has near-zero friction.

---

Copyright © 2026 Jonson Wang / LEBTC — 核心以 MIT 授权发布。

> Copyright © 2026 Jonson Wang / LEBTC — core released under the MIT License.
