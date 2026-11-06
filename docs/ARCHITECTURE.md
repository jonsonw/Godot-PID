# Architecture · 架构（精简版）

> English: a quick read for GitHub visitors. Authoritative full version: `G-PID_项目架构说明_20260908.html` (workspace `架构/交付/`).
> 中文：供 GitHub 访客速读。权威完整版见工作区 `架构/交付/G-PID_项目架构说明_20260908.html`。
>
> **基线 2026-11-06（阶段 2 收口 + ADR-47）**：`src/**/*.gd` **290 文件 / 79,600 行**，Godot 4.7。
> 门禁：导入 0 错 · GPGTest **129 套 / 10,759 断言 / 0 失败** · GUT **5 passing / 3,409 asserts** · 编译与冒烟 `SCRIPT ERROR` **0**。
> **本文件是基线数字的唯一出处** —— 其它文档引用它，不复制（复制来的数字第二次修改就会变成谎）。
> 与代码冲突之处，一律以代码为准。

## Layers · 分层

| 层 | 路径 | 规模 | 职责 | 说明 |
|---|---|---|---|---|
| UI | `src/ui` | 92 文件 / 32,122 行 | shell（组合根 `GPMainWindow` + 外壳契约 `GPShellHost` + 7 协调者 + 跨图纸控制器 + DRC 呈现器）、canvas（`GPCanvas2D` + 16 个协作者）、tools、panels、dialogs（含 `symbol_editor/`） | 唯一依赖 Godot 控件与 autoload 的层 |
| App | `src/app` | 62 / 8,726 | 用例编排：命令栈 + **51 条命令** + `GPEditService` + `GPAppDocumentManager` + `GPEventBus` + 自动保存 + `rules/` 实时 DRC 调度 | 纯 `RefCounted`，无 UI 引用 |
| Core | `src/core` | 87 / 23,912 | model（`GPPIDGraph` 聚合根）· geometry · validation（DRC 快照/规则/豁免）· view · service · symbol · text · platform · constants | **87 个类无一个是 `Node`** → 可 headless 测试 |
| IO | `src/io` | 35 / 10,812 | `*.pid.json` 读写（`GPProjectIO`）+ 原子写 + schema 迁移 + **DEXPI（Proteus XML）** + **DXF R12 / PDF 1.4** + 导出注册表 | 唯一允许碰 `FileAccess` 的层；DXF/PDF 消费 `GPPrintModel`，自身不做几何 |
| Render | `src/render` | 9 / 2,224 | `GPSymbolView` / `GPEdgeView` 视图节点与绘制器、`GPFrameView`（图框）/ `GPBackgroundView`（底图） | 只读模型；3D 构建为空桩 |
| Autoload | `src/autoload` | 3 / 1,576 | `I18n`（zh/en）、`Settings`（`user://settings.cfg`）、`SnapState`（CAD 开关） | 3 个全局单例，**仅 ui 可依赖** |
| Addons | `src/addons` | 2 / 228 | `GPIPIDAddon` 商业化插件契约（**契约 v3，12 个钩子**）+ `GPAddonLoader` | 外挂能力不进入 core；⚠️ 加载器尚未被外壳挂载，见下 |

依赖方向严格自上而下：`ui → {app, io, render} → core`，`autoload` 只有 `ui` 可以碰。
`core` / `app` / `io` / `render` 对 `ui` 与 `autoload` 的引用**实测 0 处** —— 这是 headless 可测的前提，也是 10,759 条断言成立的原因。这条边界由机器守着，见下节「架构守卫」。

> **门面约定**：`GPMainWindow` / `GPCanvas2D` 对外只暴露语义化公开端口（`gp*`），内部协作结构（协调者 / 协作者）不外泄；调用方在其它类 → 方法必须公开，仅类内调用 → `_gp*` 私有。自 S8 起"私有不出对象边界"也是守卫项。

**DEXPI 子模块（第二个外部方言适配器，与 `*.pid.json` 平级）**：`GPDexpiSchema`（常量/版本能力表）、
`GPXmlText`（转义单点）、`GPDexpiMapping`（映射表 + `gpFlipY`/`gpNormRgb` 单点）、
`GPDexpiExporter`、`GPDexpiReader`、`GPDexpiValidator`、`GPDexpiImporter`、
`GPExporterRegistry`（新增格式不再改 UI 分发）。
三条硬不变量：① 所有世界坐标必须落在 Diagram Extent 之内（Extent 随几何一起翻转）；
② null 一律**省略** `Value` 属性，绝不写 `Value=""`；③ RDL URI 绝不臆造 ——
只有规范已核实的才写，其余留空并进报告。

## Architecture guard · 架构守卫

分层这类的说法，最容易被写进文档然后悄悄失效。本项目把它们变成 `tests/gp_test_architecture.gd`
里的断言（属于第 2 道门，随每次 GPGTest 全量运行）：

| 守卫 | 判据 | 违规键 |
|---|---|---|
| 层间引用 | 层矩阵白名单（`GP_LAYER_ALLOWED`）之外的类引用一律红 | `class\|<文件>\|<类>` |
| 资源路径 | `res://src/<层>/…` 只能指向本层或允许的同级层 | `path\|<文件>\|<路径>` |
| autoload 访问 | 不得绕过场景树取单例 | `autoload\|<文件>\|<名字>` |
| 文件写入 | `FileAccess.WRITE` 仅允许 `atomic_file.gd`（与 xlsx 模板例外） | `io\|<文件>\|<类>` |
| 跨对象私有 · 静态形态 | `Class._gpX` 且该类声明在**另一个文件** | `private\|<文件>\|Class._gpX` |
| 跨对象私有 · 实例形态 | `var x: GP某类` 的声明类型是**外来类**（自身类实例＝工厂，豁免；未标注/内建类型不判） | `private\|<文件>\|Class._gpX` |

- **已知违规登记表**（只减不增，当前 **0 条 / 上限 0**）：新增违规则红；修好却不删登记行报 `stale`，同样红。
- **预算门（ADR-47）**：文件软上限 **500 行**、函数软上限 **200 行**。超限者必须登记预算行，行值＝登记当天的实测值；当前 **35 个文件 / 4 个函数**超限。在用表与冻结快照**逐键一致**，**只减不增** —— 上调转红、陈旧行（文件已回落到阈值内却没删行）转红。
  含义很直接：**往最大的那几个文件里加一行，门 2 就会红**；新功能默认落新文件。
- **接线归属**：`connect` 必须写在持有该处理器的类里（"谁持有处理器，谁持有接线"）。三条钉分别覆盖跨图纸画布接线、面板接线、DRC 呈现 —— 因为"函数还在"不等于"有人调用它"。

> 守卫本身也被反向验证过：注入一条违规 → 对应键转红 → 还原 → 回绿。没做过反向验证的钉，只是一句注释。

## Single-file format · 独档格式

一个工程 = 一个 `*.pid.json`，当前 schema **v3**：

```
meta / sheets[] / library / config
```

每张图纸的 `nodes` / `edges` / `shapes` 收在 `sheets[]` 元素内（v1 时代的平铺键已迁移）。
用户自定义图元包（`library.packs`）**内嵌进存档**，因此文件自包含、可移植、无供应商锁定 —— 这是 G-PID 数据主权主张的落点。
写入采用**原子写**（`tmp → 校验 → bak → rename`，失败回滚）；schema 迁移链 v1→v2→v3 **幂等且只在读取路径**执行。
当前为**单图**；多文档与跨图连接属 W21 / W22 计划，**尚未实现**。

## Extension seams · 扩展接缝

- `GPCommand` + `GPCommandStack` —— 撤销/重做与未来协同共用的同一条命令流（命令是「自我求逆的值对象」，重做复用原对象）。
- `GPEventBus` —— 领域事件总线；UI 与插件据此订阅 `gpGraphChanged` 等事件，发布者无需知道订阅者。
- `GPCanvasToolRegistry` —— 新增画布交互 = 新增一个文件 + 注册表加一行，画布主体不改。
- `gen_symbol_packs.py` —— 图元数据驱动：声明几何与端口即可生成图元，无需为每个图元写类。
- `GPIPIDAddon` + `GPAddonLoader` —— 商业化插件契约**与加载器**：扫描目录 → 实例化 → 每条候选一条诊断 →
  隔离坏插件 → 按类返回要注入的工具 / 面板 / 导出器 / 图元包（Pro 代码不进本仓，核心只认契约）。
  **契约 v3** 共 12 个钩子，全部公开 `gp*` 命名（钩子是给另一个仓库覆写的，`_` 前缀会把它误标成私有）；
  除工具/面板/导出器/图元包外还有三处挂载点：`gpGetChatPanel()`（对话面板场景路径）、
  `gpGetToolDefs()`（与 MCP 共用的 `{id, description, args, handler}`）、`gpGetValidationHooks()`（追加校验规则）。
  版本协商：`gpContractVersion()` + `GPAddonContract.gpContractVerdict()` → `ok` / `older` / `newer` / `unknown`，结论进加载诊断的 `contract` 键。
  ⚠️ **诚实说明**：`GPAddonLoader` 在 `src/` 里目前**零调用点** —— 外壳还没挂载插件系统，契约只被测试行使。
  挂载属未排期功能，不是已有能力。
- `GPRulePack` + `GPFinding`（`src/core/validation/`）—— DRC 纯规则集（`GPDRCRules`，按 `drc.topo.*` / `drc.sem.*` / `drc.symbol.*` / `drc.doc.*` 等族组织）与发现值对象：不碰 Node、
  不碰 autoload，故 GUI 面板、headless 测试与将来的 CLI 门禁共用同一份实现。

## Testing & CI · 测试与持续集成

测试采用**双轨**：

| 轨 | 位置 | 规模 | 运行命令 |
|---|---|---|---|
| 自研 `GPGTest` | `tests/gp_test_*.gd` | **129 套 / 10,759 条断言**（含架构守卫） | `godot --headless --script res://tests/run_core_tests.gd` |
| `GUT 9.7.1` | `addons/gut`（vendored，MIT） | 5 passing / **3,409 asserts**（桥接 + 原生用例） | `godot --headless --script res://addons/gut/gut_cmdln.gd -gexit` |

桥接脚本 `tests/gut/test_gp_suites.gd` 让 GUT 反射驱动既有 GPGTest 套件，
**无需改写任何既有测试**；新增套件后必须同步 `GP_EXPECTED_SUITES` 常量（防套件静默不加载）。
GUT 的断言数是**弱信号**（桥接对每个方法只加 2 条），**权威永远是 GPGTest 的总断言数**。
GUT 编辑器插件默认**关闭**（常驻会占用约 35% 编辑器启动时间），命令行运行器不受影响。

`.github/workflows/ci.yml`（Godot 4.7，由 `GODOT_TAG` 单点控制版本）四道门禁：

1. `godot --headless --import` —— 注册 `GutTest` 等 class_name（缺此步 GUT 无法启动）
2. `godot --headless --editor --quit` —— 编译扫描
3. `godot --headless --script res://tests/run_core_tests.gd` —— GPGTest 全套（含架构守卫与预算门）
4. `godot --headless --script res://addons/gut/gut_cmdln.gd … -gexit` —— GUT（含桥接），产出 JUnit artifact

任一步失败即 CI 红（GUT 失败时退出码为 1，已实测）。
本地另有两道：单文件 `--check-only` 与运行时冒烟 `--quit-after 90 res://scenes/main.tscn`。

**三项必须同时看**：`failed=0` · 断言总数不下降 · `SCRIPT ERROR` 计数为 0。GDScript 只报错不中断，
套件也可能静默不加载 —— 只看第一项会漏掉后两类事故。
