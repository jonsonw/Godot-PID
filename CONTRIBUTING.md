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

> Godot 4.7 is required. The `GODOT` variable below points at the engine binary — set it to your
> own path (a bare `godot` works when the binary is on `PATH`).

Three commands, run from the repo root (the folder holding `project.godot`). All three must be green
before a PR is reviewable.

```bash
# macOS/Linux: give the engine a WRITABLE HOME. Without it, `user://` (which lives under
# ~/Library/Application Support on macOS) cannot be created inside a sandbox and the process dies
# with SIGSEGV + a MoltenVK backtrace before any test runs. Windows: point APPDATA at a writable dir.
mkdir -p /tmp/gpidhome
GODOT="/path/to/Godot"   # macOS app bundle: .../Godot.app/Contents/MacOS/Godot; PATH install: godot

# 1) Core suite — the home-grown GPGTest suites (tests/gp_test_*.gd, aggregated by run_core_tests.gd)
HOME=/tmp/gpidhome "$GODOT" --headless --path . --script res://tests/run_core_tests.gd
# expect the last line:  TOTAL  passed=<N> failed=0

# 2) GUT bridge — the editor-facing suites, including the suite-count pin
HOME=/tmp/gpidhome "$GODOT" --headless --path . --script res://addons/gut/gut_cmdln.gd \
  -gdir=res://tests -ginclude_subdirs -gprefix=test_ -gsuffix=.gd -gexit
# expect:  Passing Tests 5   Failing Tests 0

# 3) Parse check — every script must compile (autoloads ARE available here)
HOME=/tmp/gpidhome "$GODOT" --headless --path . --editor --quit
# expect: no "SCRIPT ERROR" / "Parse Error" / "Compile Error" lines
```

Two traps worth knowing:

- **Do not use `--check-only --script <file>` as a gate.** That mode does not register autoloads, so
  every UI script reports false `Identifier not found: I18n / Settings / SnapState`. Use gate 3.
- **After a fresh clone (or any new `class_name`), run gate 3 before the other two.** Without the
  import/scan GUT fails with `class_names have not been imported`, and the headless runner silently
  cannot resolve the new class.
- **Adding a `tests/gp_test_*.gd` requires bumping `GP_EXPECTED_SUITES`** in
  `tests/gut/test_gp_suites.gd`, or gate 2 fails on the count assertion (that pin exists so a suite
  cannot be silently skipped). Also run gate 3 once before gate 1 after adding a new `class_name`:
  the headless runner resolves classes from `.godot/global_script_class_cache.cfg`, which the editor
  scan refreshes.

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

### Symbol id rule（强制 / mandatory）
Every symbol definition carries an id of the form **`<source><CATEGORY><3-digit sequence>`**:
- `L` = **library** symbol (ships with the release, read-only) — `LVALVE001`, `LPUMP003`.
- `C` = **custom** symbol (user-authored, or derived from a built-in) — `CVALVE001`.
- The category code is `gpCategory` with non-letters dropped and upper-cased (`valve` → `VALVE`).
- The sequence counts **within** a category and is **never recycled**: allocation is
  `max(existing) + 1`, so a retired number is never handed out again — reusing one would make
  an old `*.pid.json` silently resolve to a different symbol.

Never hand-write an id; always go through `GPSymbolNaming.gpAllocate` or
`GPSymbolLibrary.gpAllocateCustomId`. `src/core/service/symbol_naming.gd` is the single
authoritative definition, guarded by `tests/gp_test_symbol_naming.gd`.

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

> 需要 Godot 4.7。下面的 `GODOT` 变量指向引擎可执行文件 —— 填你自己的路径（已在 PATH 上时直接写 `godot`）。

在仓库根目录（含 `project.godot` 的那一层）执行下列三条命令。PR 可评审前，三条必须全绿。

```bash
# macOS / Linux：必须给引擎一个**可写 HOME**。否则 `user://`（macOS 下位于
# ~/Library/Application Support）在沙箱内建不出来，进程会以 SIGSEGV + MoltenVK backtrace 崩溃，
# 根本跑不到测试。Windows 上把 APPDATA 指到可写目录即可。
mkdir -p /tmp/gpidhome
GODOT="/path/to/Godot"   # macOS 应用包：.../Godot.app/Contents/MacOS/Godot；已在 PATH 上则填 godot

# 1) 核心套件 —— 自研 GPGTest（tests/gp_test_*.gd，由 run_core_tests.gd 聚合）
HOME=/tmp/gpidhome "$GODOT" --headless --path . --script res://tests/run_core_tests.gd
# 期望最后一行：TOTAL  passed=<N> failed=0

# 2) GUT 桥 —— 面向编辑器的套件，含套件数钉子
HOME=/tmp/gpidhome "$GODOT" --headless --path . --script res://addons/gut/gut_cmdln.gd \
  -gdir=res://tests -ginclude_subdirs -gprefix=test_ -gsuffix=.gd -gexit
# 期望：Passing Tests 5   Failing Tests 0

# 3) 解析检查 —— 每个脚本都必须编译通过（此模式下 autoload 可用）
HOME=/tmp/gpidhome "$GODOT" --headless --path . --editor --quit
# 期望：没有任何 "SCRIPT ERROR" / "Parse Error" / "Compile Error" 行
```

两个必须知道的坑：

- **不要用 `--check-only --script <文件>` 当门禁。** 该模式不注册 autoload，于是每个界面脚本都会
  报假的 `Identifier not found: I18n / Settings / SnapState`。请用第 3 条。
- **全新克隆（或任何新增 `class_name`）后，先跑第 3 条再跑前两条。** 没有 import / 扫描，GUT 会报
  `class_names have not been imported`，而 headless runner 也无法解析新类。
- **新增 `tests/gp_test_*.gd` 必须同步 `tests/gut/test_gp_suites.gd` 的 `GP_EXPECTED_SUITES`**，
  否则第 2 条会因套件数断言失败（这个钉子存在的意义就是防止某个套件被悄悄跳过）。另外，新增
  `class_name` 后先跑一次第 3 条再跑第 1 条：headless runner 从
  `.godot/global_script_class_cache.cfg` 解析类名，而这份缓存由编辑器扫描刷新。

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

### 图元标识 id 命名规则（强制）
每个图元定义的 id 形如 **`<来源码><类别码><三位序号>`**：
- `L` = **内置库**图元（随发行版自带、只读）—— `LVALVE001`、`LPUMP003`。
- `C` = **自定义**图元（用户自建，或由内置图元派生）—— `CVALVE001`。
- 类别码由 `gpCategory` 去掉非字母字符并大写得到（`valve` → `VALVE`）。
- 序号在**类别内部**计数，且**永不复用**：分配取 `max(已有) + 1`，已退役的号码绝不再次发放 ——
  复用会让旧 `*.pid.json` 静默解析到另一个图元。

禁止手写 id，一律经 `GPSymbolNaming.gpAllocate` 或 `GPSymbolLibrary.gpAllocateCustomId` 分配。
`src/core/service/symbol_naming.gd` 是唯一权威定义，由 `tests/gp_test_symbol_naming.gd` 守护。
