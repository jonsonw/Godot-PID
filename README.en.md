[简体中文](README.md)

# G-PID

G-PID is more than a P&ID drawing tool — it is the **data hub** spanning the full lifecycle of plant assets.

不只是一个 P&ID 画图工具——它是贯穿工厂资产全生命周期的**数据中枢**。

An open-source P&ID (Piping and Instrumentation Diagram) editor built on the Godot engine, unifying drawing, symbol libraries, and a self-contained project file into one self-hostable, fully data-sovereign package.

基于 **Godot 引擎**的开源 P&ID（管道及仪表流程图）编辑器，把绘图、符号库与自包含工程文件统一在一个可自托管、数据完全自主的载体里。

---

## Current status / 当前状态

This project is in **early development** (app version `0.1.0`, Godot 4.7). The table below honestly separates shipped from planned:

本项目处于**早期开发阶段**（应用版本 `0.1.0`，引擎 Godot 4.7）。下表如实区分已实现与规划中的能力，避免误判：

| Capability / 能力 | Status / 状态 |
|---|---|
| 2D editing: place, connect, annotate, marquee, zoom/pan | ✅ Working / 可用 |
| Undo / redo (command stack, depth 200) | ✅ Working / 可用 |
| Symbol editor: author shapes, ports, undoable | ✅ Working / 可用 |
| Multi-sheet tabs | ✅ Working / 可用 |
| `*.pid.json` read/write + embedded user symbol packs | ✅ Working / 可用 |
| Chinese / English UI | ✅ Working / 可用 |
| DXF / PDF / basic list export | 🚧 Stubs / 接口已定义，实现为空桩 |
| 3D linkage rendering | 🚧 Stub / 空桩 |
| HAZOP knowledge, compliance checks, unit-op generation | 📋 Planned, delivered via `GPIPIDAddon` in Pro / 规划中，由 Pro 版提供 |
| Cross-sheet links, off-page connectors | 📋 Planned / 规划中 |

---

## Top selling points / 头号卖点

### Data sovereignty / no lock-in · 数据主权 / 无锁定

The project lives in a single open `*.pid.json` file — local-first, Git-versionable, tied to no cloud service or proprietary format. **User-authored symbol packs are embedded in the file itself**, so it renders identically on any machine.

工程以单一开放的 `*.pid.json` 文件存储——本地优先、可 Git 版本化、不绑定任何云服务或私有格式。**用户自定义的图元包会内嵌进文件本身**，拷到任何一台机器打开都长得一样。

### Safe & trustworthy AI · 安全可信 AI

Planned AI features (unit-op generation, compliance checks) will run on a **deterministic, offline, auditable** rule engine — not a black-box cloud LLM. You keep control of both data and reasoning.

规划中的 AI 能力（单元操作生成、合规校验）将走**确定性、离线、可审计**的规则引擎，而非黑盒云端大模型——数据与推理的掌控权始终在你手里。

### Open-source MIT / self-hostable · 开源 MIT / 自托管

Core code is released under the MIT License — free to use, modify, and redistribute; runs fully offline with no external account required.

核心代码以 MIT 授权发布，可自由使用、修改、再分发；可完全离线运行，不依赖任何外部账号。

---

## Naming / 命名

- **Product brand / 产品品牌：G-PID**
- **GitHub repo / 仓库：`Godot-PID`**
- **Official site / 官网：[g-pid.com](https://g-pid.com)**

## License / 授权

The core code is released under the **MIT License** — free to use, modify, and redistribute.

核心代码以 **MIT 授权**发布，可自由使用、修改、再分发。

---

## Quick Start / 快速开始

1. Open this directory (the one containing `project.godot`) with **Godot 4.7**.
2. Press **F5** to run the main scene `scenes/main.tscn`.

1. 用 **Godot 4.7** 打开本目录（即包含 `project.godot` 的目录）。
2. 按 **F5** 运行主场景 `scenes/main.tscn`。

### Run the tests / 运行测试

```bash
# Home-grown GPGTest: 21 suites / 443 assertions
godot --headless --script res://tests/run_core_tests.gd

# Required after a fresh clone or whenever a class_name is added,
# otherwise GUT reports "class_names have not been imported"
godot --headless --import

# GUT 9.6.1 (vendored under addons/gut/)
godot --headless --script res://addons/gut/gut_cmdln.gd -gexit
```

CI runs four gates on every push: **import → compile scan → GPGTest → GUT**.

CI 对每次 push 执行四道门禁：**import → 编译扫描 → GPGTest → GUT**。

---

## Directory Structure / 目录结构

```
Godot-PID/                # GitHub repo root (local working folder: Godot-PID-Core/)
├── project.godot          # Godot project config (autoloads, editor plugins)
├── project.pid.json       # *.pid.json data contract sample
├── scenes/                # Main & dialog scenes
├── src/
│   ├── core/              # UI-free kernel, headless-testable
│   │   ├── model/         # GPPIDGraph / GPPIDNode / GPPIDEdge / GPSymbolDef / GPShape
│   │   ├── geometry/      # Geometry, grip editing, coordinate transforms
│   │   ├── symbol/        # Symbol library, ISO 10628 pack, normalizer
│   │   ├── view/          # Camera, selection, marquee, hit test, interact state
│   │   ├── platform/      # DPI window, popup helpers
│   │   └── service/       # GPIdGen, GPIOResult
│   ├── app/               # Application services: commands, undo stack, event bus, documents
│   │   └── commands/      # 8 concrete commands (add/delete/move node, shape, edge)
│   ├── render/            # GPSymbolView / GPEdgeView / painter
│   ├── io/                # *.pid.json read/write; DXF / PDF / list export are stubs
│   ├── ui/
│   │   ├── shell/         # Main window composition root, menu bar
│   │   ├── canvas/        # Canvas shell, incremental sync, shortcuts, context menu
│   │   ├── tools/         # Canvas tools: select / place / draw / grip
│   │   ├── panels/        # Multi-sheet area, palette, inspector, toolbar
│   │   └── dialogs/       # Settings, new symbol; symbol_editor/ edits geometry
│   ├── addons/            # GPIPIDAddon: commercial addon contract
│   └── autoload/          # Singletons: I18n (i18n), Settings (fonts & config)
├── addons/gut/            # GUT 9.6.1 test framework (vendored, MIT)
├── assets/                # Symbol SVGs, CJK fonts, theme
├── tools/                 # Symbol pack generator (Python)
├── tests/                 # GPGTest suites + GUT cases and bridge
└── docs/                  # Architecture docs: ARCHITECTURE.md, beginner's guide
```

---

## Core Concepts / 核心概念

- **`GPPIDGraph`** — the node-edge graph core (`RefCounted`). The 2D canvas, view rendering, and persistence all revolve around it; serialization is a hand-written `gpToDict()` emitting five top-level keys: `meta` / `nodes` / `edges` / `shapes` / `user_symbol_packs`.
- **`GPCommand` + `GPCommandStack`** — every mutation is wrapped in a command and pushed onto a stack, so **editing is undoable by construction** (depth 200). Features that bypass the command layer lose undo support and headless testability.
- **`GPSymbolDef`** — data-driven symbol definition; avoids a class per symbol. Built-in ISO 10628 symbols are generated by `tools/gen_symbol_packs.py`.
- **`GPEventBus`** — application-level event bus, one per sheet. Lets `RefCounted` services communicate without a scene tree.
- **`GPIPIDAddon`** — addon contract. Peripheral and commercial features mount by subclassing it; core code stays untouched.

- **`GPPIDGraph`** — 节点-边图内核（`RefCounted`）。2D 画布、视图渲染、存读都围绕它；序列化走手写的 `gpToDict()`，产出 `meta` / `nodes` / `edges` / `shapes` / `user_symbol_packs` 五个顶层键。
- **`GPCommand` + `GPCommandStack`** — 所有修改都包装成命令再入栈，因此**任何编辑天然可撤销**（栈深 200）。新功能若绕过命令层，就拿不到撤销能力，也无法 headless 单测。
- **`GPSymbolDef`** — 数据驱动图元定义，避免为每个符号建一个类。内置 ISO 10628 图元由 `tools/gen_symbol_packs.py` 生成。
- **`GPEventBus`** — 应用级事件总线，每图纸一条。供服务层那些不进场景树的 `RefCounted` 对象通信。
- **`GPIPIDAddon`** — 插件契约。外围与商业化功能通过继承此类挂载，核心代码不动。

### Learn more / 了解更多

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — architecture overview (layering, dependency rules, call chains)
- [`docs/ARCHITECTURE_FOR_BEGINNERS.md`](docs/ARCHITECTURE_FOR_BEGINNERS.md) — **beginner's guide**, from Godot concepts to "where to add a feature"
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — coding & naming rules (`gp` / `GP` prefixes, explicit types, bilingual comments)

---

## Contributing / 贡献

Contributions are welcome via Issues / PRs. Symbols are `GPSymbolDef`-driven, so adding one has near-zero friction; new edit operations should go through the command layer (see Beginner's Guide §11.2).

欢迎以 Issue / PR 参与。图元采用 `GPSymbolDef` 数据驱动，新增符号零门槛；新增编辑操作请走命令层（见新手导读 §11.2）。

---

Copyright © 2026 Jonson Wang
