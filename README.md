[English](README.en.md)

# G-PID

不只是一个 P&ID 画图工具——它是贯穿工厂资产全生命周期的**数据中枢**。

G-PID is more than a P&ID drawing tool — it is the **data hub** spanning the full lifecycle of plant assets.

基于 **Godot 引擎**的开源 P&ID（管道及仪表流程图）编辑器，把绘图、符号库与自包含工程文件统一在一个可自托管、数据完全自主的载体里。

An open-source P&ID (Piping and Instrumentation Diagram) editor built on the Godot engine, unifying drawing, symbol libraries, and a self-contained project file into one self-hostable, fully data-sovereign package.

---

## 下载 / Downloads

**v0.1.0** —— 首个可使用的桌面版本（引擎 Godot 4.7）。

**v0.1.0** — the first usable desktop release (engine Godot 4.7).

| 平台 / Platform | 下载 / Download |
|---|---|
| Windows x86_64 | [Godot-PID-windows-v0.1.0.zip](https://github.com/jonsonw/Godot-PID/releases/download/v0.1.0/Godot-PID-windows-v0.1.0.zip) · exe 内嵌 pck，单文件即可运行 / single-file exe with embedded pck |
| macOS (Apple Silicon / Intel) | [Godot-PID-macos-v0.1.0.zip](https://github.com/jonsonw/Godot-PID/releases/download/v0.1.0/Godot-PID-macos-v0.1.0.zip) · .app 包 / .app bundle |

⚠️ macOS 版为**未签名**构建，系统首申会被 Gatekeeper 拦下，二选一即可：右键以「打开」运行，或在终端执行 `xattr -cr Godot-PID.app`。

⚠️ The macOS build is **unsigned**, so Gatekeeper may block it on first launch. Either right-click and choose *Open*, or run `xattr -cr Godot-PID.app` in Terminal.

想看全部版本（含历史与更新日志）请到 [Releases 页](https://github.com/jonsonw/Godot-PID/releases)。

See the [Releases page](https://github.com/jonsonw/Godot-PID/releases) for all versions and the changelog.

---

## 当前状态 / Current status

本项目处于**早期开发阶段**（应用版本 `0.1.0`，引擎 Godot 4.7）。下表如实区分已实现与规划中的能力，避免误判：

This project is in **early development** (app version `0.1.0`, Godot 4.7). The table below honestly separates shipped from planned:

| 能力 / Capability | 状态 / Status |
|---|---|
| 2D 图纸编辑：图元放置、连线、注释图形、框选、缩放平移 | ✅ 可用 / Working |
| 撤销 / 重做（命令栈，深度 200） | ✅ 可用 / Working |
| 图元编辑器：自绘图元、端口定义、可撤销 | ✅ 可用 / Working |
| 多图纸标签页 | ✅ 可用 / Working |
| `*.pid.json` 存读 + 内嵌用户图元包 | ✅ 可用 / Working |
| 中英双语界面 | ✅ 可用 / Working |
| 边路径编辑：拖动段中点 / 角点改路径，自动重正交 | ✅ 可用 / Working |
| 边标签（管线号）拖拽 + 引出线 | ✅ 可用 / Working |
| 图框与标题栏、画布文字档位（mm↔px 单一换算源） | ✅ 可用 / Working |
| 自动保存：首次保存后启用（脏 1 min / 净 5 min） | ✅ 可用 / Working |
| **DEXPI 1.4 导出 / 导入**（Proteus XML 4.2.0） | ✅ 可用 / Working（概念层 + 图形层 + Extent；导出入口：导出子菜单） |
| DXF / PDF / 基础清单导出 | 🚧 接口已定义，实现为空桩 / Stubs |
| 3D 联动渲染 | 🚧 空桩 / Stub |
| HAZOP 知识沉淀、合规校验、单元操作生成 | 📋 规划中，经 `GPIPIDAddon` 由 Pro 版提供 / Planned via Pro |
| 跨图连接、off-page 连接符 | 📋 规划中 / Planned |

---

## 头号卖点 / Top selling points

### 数据主权 / 无锁定 · Data sovereignty / no lock-in

工程以单一开放的 `*.pid.json` 文件存储——本地优先、可 Git 版本化、不绑定任何云服务或私有格式。**用户自定义的图元包会内嵌进文件本身**，拷到任何一台机器打开都长得一样。

The project lives in a single open `*.pid.json` file — local-first, Git-versionable, tied to no cloud service or proprietary format. **User-authored symbol packs are embedded in the file itself**, so it renders identically on any machine.

### 安全可信 AI · Safe & trustworthy AI

规划中的 AI 能力（单元操作生成、合规校验）将走**确定性、离线、可审计**的规则引擎，而非黑盒云端大模型——数据与推理的掌控权始终在你手里。

Planned AI features (unit-op generation, compliance checks) will run on a **deterministic, offline, auditable** rule engine — not a black-box cloud LLM. You keep control of both data and reasoning.

### 开源 MIT / 自托管 · Open-source MIT / self-hostable

核心代码以 MIT 授权发布，可自由使用、修改、再分发；可完全离线运行，不依赖任何外部账号。

Core code is released under the MIT License — free to use, modify, and redistribute; runs fully offline with no external account required.

---

## 命名 / Naming

- **产品品牌 / Product brand：G-PID**
- **GitHub 仓库 / Repo：`Godot-PID`**
- **官网 / Site：[g-pid.com](https://g-pid.com)**

## 授权 / License

核心代码以 **MIT 授权**发布，可自由使用、修改、再分发。

The core code is released under the **MIT License** — free to use, modify, and redistribute.

---

## 快速开始 / Quick Start

1. 用 **Godot 4.7** 打开本目录（即包含 `project.godot` 的目录）。
2. 按 **F5** 运行主场景 `scenes/main.tscn`。

1. Open this directory (the one containing `project.godot`) with **Godot 4.7**.
2. Press **F5** to run the main scene `scenes/main.tscn`.

### 运行测试 / Run the tests

```bash
# 自研 GPGTest：61 套 / 2,901 断言（编译 0 错 · SCRIPT ERROR 0）
godot --headless --script res://tests/run_core_tests.gd

# 首次克隆或新增 class_name 后必须先 import，否则 GUT 报 "class_names have not been imported"
godot --headless --import

# GUT 9.7.1（已 vendored 至 addons/gut/）
godot --headless --script res://addons/gut/gut_cmdln.gd -gexit
```

CI 对每次 push 执行四道门禁：**import → 编译扫描 → GPGTest → GUT**。

CI runs four gates on every push: **import → compile scan → GPGTest → GUT**.

---

## 目录结构 / Directory Structure

```
Godot-PID/                # GitHub 仓库根（本地工作目录为 Godot-PID-Core/）
├── project.godot          # Godot 项目配置（autoload、编辑器插件）
├── project.pid.json       # *.pid.json 数据契约示例
├── scenes/                # 主场景与对话框场景
├── src/
│   ├── core/              # 与 UI 无关的内核，可 headless 单测
│   │   ├── model/         # GPPIDGraph / GPPIDNode / GPPIDEdge / GPSymbolDef / GPShape
│   │   ├── geometry/      # 几何算法、抓取点编辑、坐标变换
│   │   ├── symbol/        # 图元库、DEXPI C01 图元包（25 符号）、归一化
│   │   ├── view/          # 相机、选择集、框选、命中测试、交互状态
│   │   ├── platform/      # DPI 窗口、弹窗辅助
│   │   └── service/       # GPIdGen、GPIOResult
│   ├── app/               # 应用服务层：命令、撤销栈、事件总线、文档管理
│   │   └── commands/      # 29 条具体命令（增删移图元/图形/连线、路径与标签编辑、落点恢复）
│   ├── render/            # GPSymbolView / GPEdgeView / 图框 GPFrameView / 背景 GPBackgroundView / 绘制器
│   ├── io/                # *.pid.json 读写；DEXPI（Proteus XML）导入导出；DXF / PDF / 清单导出为桩
│   │   ├── dexpi_schema.gd    # 版本常量 / RDL 双域 / 保留 Set 名 / 版本能力表
│   │   ├── xml_text.gd        # XML 转义与缩进单点；gpLang2() 语言标签两字母
│   │   ├── dexpi_mapping.gd   # 数据驱动映射表；gpFlipY() / gpNormRgb() 唯一实现
│   │   ├── dexpi_exporter.gd  # 预检 → 投影 → 序列化 → 原子写
│   │   ├── dexpi_reader.gd    # XML → 与导出同构的中间结构
│   │   ├── dexpi_validator.gd # L1 结构 + L2 规则 → GPImportReport
│   │   ├── dexpi_importer.gd  # 中间结构 → v3 容器（喂既有 gpMergeInto）
│   │   └── exporter_registry.gd # 导出器注册表：新增格式不再改 UI 分发
│   ├── ui/
│   │   ├── shell/         # 主窗口组合根、菜单栏、7 个协调者、快捷命令条、自动保存
│   │   ├── canvas/        # 画布外壳 + 5 个实现类、增量同步、快捷键、右键菜单
│   │   ├── tools/         # 画布交互工具：选择 / 放置 / 绘制 / 抓取点
│   │   ├── panels/        # 多标签绘图区、图元库、属性面板、工具栏
│   │   └── dialogs/       # 设置、新建图元（含端口编辑面板）、标题栏；symbol_editor/ 为图元几何编辑
│   ├── addons/            # GPIPIDAddon：商业化插件契约
│   └── autoload/          # 3 个全局单例：I18n（翻译）、Settings（字体与配置）、SnapState（CAD 开关）
├── addons/gut/            # GUT 9.7.1 测试框架（vendored，MIT）
├── assets/                # 图元 SVG、中文字体、主题
├── tools/                 # 图元包生成脚本（Python）
├── tests/                 # GPGTest 套件 + GUT 用例与桥接
└── docs/                  # 架构文档：ARCHITECTURE.md、新手导读
```

---

## 核心概念 / Core Concepts

- **`GPPIDGraph`** — 节点-边图内核（`RefCounted`）。2D 画布、视图渲染、存读都围绕它；序列化走手写的 `gpToDict()`。单档 schema 现为 **v3**，顶层键 `meta` / `sheets[]` / `library` / `config`（v1 的 `nodes` / `edges` / `shapes` / `user_symbol_packs` 已并入 `sheets[]`）。
- **`GPCommand` + `GPCommandStack`** — 所有修改都包装成命令再入栈，因此**任何编辑天然可撤销**（栈深 200）。新功能若绕过命令层，就拿不到撤销能力，也无法 headless 单测。
- **`GPSymbolDef`** — 数据驱动图元定义，避免为每个符号建一个类。内置 **DEXPI C01（25 个符号，提取自国际标准示例 P&ID）** 由 `tools/gen_symbol_packs.py` 生成；ISO 10628 包已移除。
- **`GPEventBus`** — 应用级事件总线，每图纸一条。供服务层那些不进场景树的 `RefCounted` 对象通信。
- **`GPIPIDAddon`** — 插件契约。外围与商业化功能通过继承此类挂载，核心代码不动。

- **`GPPIDGraph`** — the node-edge graph core (`RefCounted`). The 2D canvas, view rendering, and persistence all revolve around it; serialization is a hand-written `gpToDict()`. The single-file schema is now **v3**, with top-level keys `meta` / `sheets[]` / `library` / `config` (v1's `nodes` / `edges` / `shapes` / `user_symbol_packs` folded into `sheets[]`).
- **`GPCommand` + `GPCommandStack`** — every mutation is wrapped in a command and pushed onto a stack, so **editing is undoable by construction** (depth 200). Features that bypass the command layer lose undo support and headless testability.
- **`GPSymbolDef`** — data-driven symbol definition; avoids a class per symbol. The built-in **DEXPI C01 pack (25 symbols, extracted from the international reference P&ID)** is generated by `tools/gen_symbol_packs.py`; the old ISO 10628 pack has been removed.
- **`GPEventBus`** — application-level event bus, one per sheet. Lets `RefCounted` services communicate without a scene tree.
- **`GPIPIDAddon`** — addon contract. Peripheral and commercial features mount by subclassing it; core code stays untouched.

### 了解更多 / Learn more

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — 架构总览（分层、依赖规则、调用链路）
- [`docs/ARCHITECTURE_FOR_BEGINNERS.md`](docs/ARCHITECTURE_FOR_BEGINNERS.md) — **新手导读**，从 Godot 概念讲到「加功能该改哪里」
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — 编码与命名规范（`gp` / `GP` 前缀、显式类型、中英双语注释）

---

## 贡献 / Contributing

欢迎以 Issue / PR 参与。图元采用 `GPSymbolDef` 数据驱动，新增符号零门槛；新增编辑操作请走命令层（见新手导读 §11.2）。

Contributions are welcome via Issues / PRs. Symbols are `GPSymbolDef`-driven, so adding one has near-zero friction; new edit operations should go through the command layer (see Beginner's Guide §11.2).

---

Copyright © 2026 Jonson Wang
