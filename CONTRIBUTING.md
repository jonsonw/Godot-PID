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
- Add tests under `tests/`: a GPGTest suite (`gp_test_*.gd`) for behaviour, and the GUT bridge picks it up once `GP_EXPECTED_SUITES` is bumped.
- Keep new logic out of the big files — see "Where new features go" below before you type the first line.
- Private members (`_gp*`) never cross an object boundary; the architecture suite fails the build if they do.
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
- **Contract hooks** (methods an addon is *meant* to override in another repository, e.g. `GPIPIDAddon`):
  public `gp` + CamelCase. The `_` prefix means "private to this class"; a hook is the opposite of private —
  and in the Open-Core split that base class is the file external implementers read first.

Do **not** rename: Godot virtual methods (`_ready`, `_draw`, `_gui_input`, `_process`…); engine built-ins (`position`, `name`, `size`, `visible`); dictionary keys (`"id"`, `"from"`, `"to"` — they are the data contract); single-letter coordinate loop vars (`x`, `y`, `z`, `w`, `h`).

### Where new features go（强制 / mandatory）
A new feature starts in a **new file**. The file you already have open is a wiring point, not a dumping ground — one addition there is reasonable, a hundred is the debt you will spend a week refactoring later.

- **R1 — new module first.** New domain responsibility → new `src/<layer>/<module>.gd` + its own `tests/gp_test_<module>.gd`. Existing large files may only gain **wiring** (instantiate, inject, connect) or **lose code** (extract).
- **R2 — budgets only shrink.** Any file over **500 lines** or any function over **200 lines** is pinned at today's size by `gp_test_architecture.gd`. The gate fails on a single added line. Raising a budget is a review-level decision, never an edit.
- **R3 — cut by "what changes together"**, not by "who calls whom". If the code needs its own test, it needs its own file.
- **R4 — cross the module boundary through a port or contract.** Private members never cross an object boundary (also gated since S8). Corollary: *whoever holds the handler holds the wiring* — connect a signal in the class that implements its handler.
- **R5 — an extraction without a test is a move, not a refactor.** Ship the suite file, a behaviour assertion, and an anti-backslide assertion in the same change.
- **R6 — exceptions are review-level, never an edit.** A budget may be raised only when the code provably cannot move, when *both* the active and the frozen table change in the same diff, and when the reason and a repayment plan are recorded. "It was easier this way" is not a reason.

What the gate says when you break R1/R2 — and what to do about it:

```
file budget exceeded — extract a module, do not raise the cap:
  src/ui/canvas/canvas_2d.gd 2026>2024
```

Move the new logic into a new file (R1) — the wiring you actually need is 1–5 lines in the old file. Never edit the number.

Full reasoning, the decision tree and the exception process: internal `docs/ADR/2026-11-06-ADR-47-模块化与新增功能落位.md`.

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
- 在 `tests/` 下补测试：行为用 GPGTest 套件（`gp_test_*.gd`），GUT 桥在 `GP_EXPECTED_SUITES` 同步后自动纳入。
- 新逻辑不要写进那几个大文件 —— 动键盘前先读下方「新增功能落位」。
- 私有成员（`_gp*`）不得跨对象边界；伸手的话架构套件会直接把构建判红。
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
- **契约钩子**（**就是给另一个仓库覆写**的方法，如 `GPIPIDAddon`）：用公开的 `gp` + CamelCase。
  `_` 前缀的含义是「本类私有」，而钩子恰恰相反 —— 且在 Open-Core 拆分中，那个基类是外部实现者
  最先读的文件。

**禁止改名**：Godot 虚方法（`_ready`、`_draw`、`_gui_input`、`_process` 等）；引擎内置属性（`position`、`name`、`size`、`visible`）；字典键（`"id"`、`"from"`、`"to"`，属数据契约）；单字母坐标循环变量（`x`、`y`、`z`、`w`、`h`）。

### 新增功能落位（强制）
新增功能**从新文件开始**。你已经打开的那个文件是**接线点**，不是堆放场 —— 往里加一次合理，加一百次就是几周后必须偿还的债。

- **R1 模块先行**：新的领域职责 → 新建 `src/<层>/<模块>.gd` 与配套 `tests/gp_test_<模块>.gd`。既有大文件只允许两种改动：**接线**（实例化、注入、连信号）或**变短**（把代码搬出去）。
- **R2 预算只减不增**：超过 **500 行**的文件、超过 **200 行**的函数，由 `gp_test_architecture.gd` 钉住今天的行数；加一行即红。上调预算属评审级决议，不是顺手改数字。
- **R3 按「谁会一起变」切**，不按「谁调用谁」切。如果这段代码需要单独的测试，它就需要单独的文件。
- **R4 跨模块只经端口/契约**，私有成员不出对象边界（自 S8 起亦有守卫）。推论：**谁持有处理器，谁持有接线** —— 信号的 `connect` 写在实现其处理器的那个类里。
- **R5 没有测试的提取只能叫「搬家」**，不算重构。同一次提交里要带上：套件文件 + 一条行为断言 + 一条防回流断言。
- **R6 例外是评审级决议，不是顺手改数**。只有「这段代码确实搬不走」、且**在用表与冻结快照在同一次 diff 里同改**、并在 ADR-47 附录 B 登记理由与偿还计划时，预算才可上调。「这样写更省事」不是理由。

破坏 R1 / R2 时门 2 会这样说话（以及你该做什么）：

```
file budget exceeded — extract a module, do not raise the cap:
  src/ui/canvas/canvas_2d.gd 2026>2024
```

把新逻辑挪进新文件（R1）—— 你真正需要的接线通常只有 1–5 行。**不要动那个数字。**

完整理由、落位决策树与例外流程见内部 `docs/ADR/2026-11-06-ADR-47-模块化与新增功能落位.md`。

### 图元标识 id 命名规则（强制）
每个图元定义的 id 形如 **`<来源码><类别码><三位序号>`**：
- `L` = **内置库**图元（随发行版自带、只读）—— `LVALVE001`、`LPUMP003`。
- `C` = **自定义**图元（用户自建，或由内置图元派生）—— `CVALVE001`。
- 类别码由 `gpCategory` 去掉非字母字符并大写得到（`valve` → `VALVE`）。
- 序号在**类别内部**计数，且**永不复用**：分配取 `max(已有) + 1`，已退役的号码绝不再次发放 ——
  复用会让旧 `*.pid.json` 静默解析到另一个图元。

禁止手写 id，一律经 `GPSymbolNaming.gpAllocate` 或 `GPSymbolLibrary.gpAllocateCustomId` 分配。
`src/core/service/symbol_naming.gd` 是唯一权威定义，由 `tests/gp_test_symbol_naming.gd` 守护。
