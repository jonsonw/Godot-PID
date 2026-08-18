# Contributing to G-PID · G-PID 贡献指南

## English
Thank you for your interest in G-PID — an open-source P&ID editor built with Godot.
This guide explains how to add symbols, run tests, and submit pull requests.

### How to contribute a symbol (no code needed)
- Use the in-editor **SymbolEditor** wizard to generate a `SymbolPack`.
- Drop the exported folder into `user://symbol_packs/` (or `addons/symbol_packs/<pack_id>/`).
- No core code changes required.

### How to contribute code
- Fork the repo and create a feature branch.
- Follow the coding rules: every variable declares its type explicitly; containers use typed arrays (e.g. `Array[SymbolDef]`).
- Comments are **bilingual** — an English line immediately followed by its Chinese translation — and **mandatory** in coverage (see "Comment standard" below).
- Add or update GUT tests under `tests/`.
- Open a PR with a clear description.

### Comment standard（强制 / mandatory）
All source comments are **bilingual**: an English line immediately followed by its Chinese translation. Coverage is mandatory:
- **Every declaration is commented**: `class_name` (with a class doc block), `const`, `enum` (and each value), `signal`, member `var`, local `var`, and any `Resource` / `RefCounted` subtype.
- **Every function is commented**: one line stating what it does (bilingual where helpful).
- **Every non-trivial block inside a function is commented**: `for` / `while` loops, `if` / `elif` / `else` branches, and meaningful step groupings.
- Code identifiers stay in English; Chinese appears only in comments.

### Running tests
- Install the GUT plugin, then run `tests/` from the Godot editor (Project → Tools → GUT).

### Naming convention（强制 / mandatory）
To avoid collisions with Godot's native classes and third-party plugins in the global `class_name` registry — and to reserve a namespace for the future Open-Core split — **every G-PID-owned identifier carries a prefix**:
- **Class names** (`class_name`): `GP` + PascalCase — `GPPIDGraph`, `GPCanvas2D`, `GPSymbolDef`.
- **Functions / methods**: `gp` + CamelCase — `gpAddNode`, `gpScreenFromWorld`.
- **Member variables / signals**: `gp` + CamelCase — `gpGraph`, `gpGraphChanged`, `gpSelectionChanged`.
- **Private members** (leading underscore): `_gp` + CamelCase — `_gpDrawGrid`.
- **Local variables**: `gp` + CamelCase — `gpA`, `gpNode`.
- **Constants / enum values**: `GP_` + SCREAMING_SNAKE — `GP_EQUIPMENT`.
- **Enum names**: `GP` + PascalCase — `GPSymbolCategory`, `GPMode`.
- **File names**: keep `snake_case` (Godot convention, no prefix) — `pid_graph.gd` defines class `GPPIDGraph`.

Do **not** rename: Godot virtual methods (`_ready`, `_draw`, `_gui_input`, `_process`…); engine built-ins (`position`, `name`, `size`, `visible`); dictionary keys (`"id"`, `"from"`, `"to"` — they are the data contract); single-letter coordinate loop vars (`x`, `y`, `z`, `w`, `h`).

## 中文

感谢你关注并参与 G-PID —— 一个用 Godot 引擎构建的开源 P&ID 编辑器。
本指南说明如何添加图元、运行测试并提交拉取请求。

### 如何贡献图元（无需写代码）
- 使用编辑器内的**图元编辑器（SymbolEditor）**向导生成 `SymbolPack`。
- 将导出的文件夹放入 `user://symbol_packs/`（或 `addons/symbol_packs/<pack_id>/`）。
- 无需修改核心代码。

### 如何贡献代码
- Fork 仓库并新建功能分支。
- 遵守编码规范：所有变量显式声明类型；容器使用带类型数组（如 `Array[SymbolDef]`）。
- 注释为**双语**——英文一行紧接中文一行——且**强制覆盖**（详见下方「注释规范」）。
- 在 `tests/` 下新增或更新 GUT 测试。
- 提交带清晰说明的 PR。

### 注释规范（强制）
所有源码注释均为**双语**：英文一行紧接中文一行。覆盖范围强制：
- **每个声明都要注释**：`class_name`（附类文档块）、`const`、`enum`（含每个枚举值）、`signal`、成员变量 `var`、局部变量 `var`、以及任何 `Resource` / `RefCounted` 子类型。
- **每个函数都要注释**：说明它做什么（必要时双语）。
- **函数内每个非平凡功能块都要注释**：`for` / `while` 循环、`if` / `elif` / `else` 分支、关键步骤。
- 代码标识符一律英文，中文只出现在注释里。

### 运行测试
- 安装 GUT 插件，在 Godot 编辑器内运行 `tests/`（Project → Tools → GUT）。

### 命名规范（强制）
为避免在 Godot 全局 `class_name` 注册表中与引擎原生类及第三方插件撞名，并为未来的 Open-Core 双仓预留命名空间，**所有 G-PID 自有标识符统一加前缀**：
- **类名**（`class_name`）：`GP` + PascalCase —— `GPPIDGraph`、`GPCanvas2D`、`GPSymbolDef`。
- **函数 / 方法**：`gp` + CamelCase —— `gpAddNode`、`gpScreenFromWorld`。
- **成员变量 / 信号**：`gp` + CamelCase —— `gpGraph`、`gpGraphChanged`、`gpSelectionChanged`。
- **私有成员**（下划线前缀）：`_gp` + CamelCase —— `_gpDrawGrid`。
- **局部变量**：`gp` + CamelCase —— `gpA`、`gpNode`。
- **常量 / 枚举值**：`GP_` + SCREAMING_SNAKE —— `GP_EQUIPMENT`。
- **枚举名**：`GP` + PascalCase —— `GPSymbolCategory`、`GPMode`。
- **文件名**：保持 `snake_case`（Godot 约定，不带前缀）—— `pid_graph.gd` 定义类 `GPPIDGraph`。

**禁止改名**：Godot 虚方法（`_ready`、`_draw`、`_gui_input`、`_process` 等）；引擎内置属性（`position`、`name`、`size`、`visible`）；字典键（`"id"`、`"from"`、`"to"`，属数据契约）；单字母坐标循环变量（`x`、`y`、`z`、`w`、`h`）。
