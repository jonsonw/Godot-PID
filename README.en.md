[简体中文](README.md)

# G-PID

G-PID is more than a P&ID drawing tool — it is the **data hub** spanning the full lifecycle of plant assets.

不只是一个 P&ID 画图工具——它是贯穿工厂资产全生命周期的**数据中枢**。

An open-source P&ID (Piping and Instrumentation Diagram) editor built on the Godot engine, unifying drawing, symbol libraries, HAZOP knowledge, compliance checks, and export into one self-hostable, fully data-sovereign engineering file.

基于 **Godot 引擎**的开源 P&ID（管道及仪表流程图）编辑器，把绘图、符号库、HAZOP 知识沉淀、合规校验与导出统一在一个可自托管、数据完全自主的工程文件里。

## Top selling points

### Data sovereignty / no lock-in

The project lives in a single open `*.pid.json` file — local-first, Git-versionable, exportable to standard formats anytime, tied to no cloud service or proprietary format. Your data stays yours.

工程以单一开放的 `*.pid.json` 文件存储——本地优先、可 Git 版本化、可随时导出为标准格式，不绑定任何云服务或私有格式。你的数据始终在你手里。

### Safe & trustworthy AI

Built-in AI (unit-op generation, compliance checks) runs on a **deterministic, offline, auditable** rule engine — not a black-box cloud LLM. You keep full control of data and reasoning.

内置 AI 能力（单元操作生成、合规校验）走**确定性、离线、可审计**的规则引擎，而非黑盒云端大模型——你拥有数据与推理的完全掌控。

### Open-source MIT / self-hostable

Core code is released under the MIT License — free to use, modify, and redistribute; runs fully offline with no external account required.

核心代码以 MIT 授权发布，可自由使用、修改、再分发；可完全离线运行，不依赖任何外部账号。

## Naming

- **Product brand: G-PID**
- **GitHub repo: `Godot-PID`**
- **Official site: [g-pid.com](https://g-pid.com)**

## 命名

- **产品品牌：G-PID**
- **GitHub 仓库名：`Godot-PID`**
- **官网：[g-pid.com](https://g-pid.com)**

## License

The core code is released under the **MIT License** — free to use, modify, and redistribute.

## 授权模式

核心代码以 **MIT 授权**发布，可自由使用、修改、再分发。

## Quick Start

1. Open this directory (the one containing `project.godot`) with **Godot 4.3+**.
2. Press **F5** to run the main scene `scenes/main.tscn`.

## 快速开始

1. 用 **Godot 4.3+** 打开本目录（即包含 `project.godot` 的目录）。
2. 按 **F5** 运行主场景 `scenes/main.tscn`。

## Directory Structure

```
Godot-PID/                # GitHub repo root (local working folder: Godot-PID-Core/)
├── project.godot          # Godot project file
├── project.pid.json       # P&ID data contract sample
├── scenes/                # Main & canvas scenes / widgets
├── src/
│   ├── core/              # PIDGraph, SymbolDef, PIDNode/Edge/Document, Session, PIDCommand
│   ├── model/             # FrameDef, SymbolPack
│   ├── render/            # 3D linkage rendering
│   ├── ai/                # Safe & trustworthy AI: unit-op generation (deterministic, offline, auditable, no cloud)
│   ├── doc/               # Multi-document management
│   ├── export/            # DXF / PDF / basic list export
│   ├── save/              # Save/load (single *.pid.json, data sovereignty)
│   ├── project/           # Project hub / registry
│   ├── autoload/          # Global singleton (AppState)
│   ├── addons/            # Addon mount point (IPIDAddon)
│   └── ui/                # Canvas / toolbar / menu bar / inspector, etc.
├── assets/                # Symbols, themes, fonts
└── tests/                 # Unit & smoke tests
```

## 目录结构

```
Godot-PID/                # GitHub 仓库根（本地工作文件夹为 Godot-PID-Core/）
├── project.godot          # Godot 项目文件
├── project.pid.json       # P&ID 数据契约示例
├── scenes/                # 主场景 / 画布场景 / 控件
├── src/
│   ├── core/              # PIDGraph、SymbolDef、PIDNode/Edge/Document、Session、PIDCommand
│   ├── model/             # FrameDef、SymbolPack
│   ├── render/            # 3D 联动渲染
│   ├── ai/                # 安全可信 AI：单元操作生成（确定性、离线、可审计，不接云端）
│   ├── doc/               # 多文档管理
│   ├── export/            # DXF / PDF / 基础清单导出
│   ├── save/              # 存档/读档（单文件 *.pid.json，数据主权）
│   ├── project/           # 工程库 / 注册表
│   ├── autoload/          # 全局单例（AppState）
│   ├── addons/            # 插件挂载点（IPIDAddon）
│   └── ui/                # 画布 / 工具栏 / 菜单栏 / 检查器 等
├── assets/                # 符号、主题、字体
└── tests/                 # 单元 / 冒烟测试
```

## Core Concepts

- **`PIDGraph`** — node-edge graph core; read by the 2D canvas, 3D linkage, and BOM export.
- **`SymbolDef`** — data-driven symbol definition; avoids a class per symbol.
- **`IPIDAddon`** — addon contract; peripheral features mount via subclassing without touching core code.

## 核心概念

- **`PIDGraph`** — 节点-边图内核，2D 画布、3D 联动、清单导出都读取它。
- **`SymbolDef`** — 数据驱动图元定义，避免为每个符号建一个类。
- **`IPIDAddon`** — 插件契约，外围功能通过继承此类挂载，核心代码不动。

## Contributing

Contributions are welcome via Issues / PRs. Symbols are `SymbolDef`-driven, so adding a new one has near-zero friction.

## 贡献

欢迎以 Issue / PR 参与。图元采用 `SymbolDef` 数据驱动，新增符号零门槛。

---

Copyright © 2026 Jonson Wang
