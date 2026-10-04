# Architecture · 架构（精简版）

> English: a quick read for GitHub visitors. Authoritative full version: `G-PID_项目架构说明_20260908.html` (workspace `架构/交付/`).
> 中文：供 GitHub 访客速读。权威完整版见工作区 `架构/交付/G-PID_项目架构说明_20260908.html`。
>
> **基线 2026-09-26**：`src/**/*.gd` **175 文件 / 32,376 行**，Godot 4.7。门禁：编译 0 错 · GPGTest **2,901 / 0** · SCRIPT ERROR **0** · GUT 5 passing / 1,261 asserts · 运行时冒烟 exit=0。
> 与代码冲突之处，一律以代码为准。

## Layers · 分层

| 层 | 路径 | 职责 | 说明 |
|---|---|---|---|
| UI | `src/ui` | shell（组合根 `GPMainWindow` + 7 协调者）、canvas（`GPCanvas2D` + **5 实现类**）、tools、panels、dialogs（含 `symbol_editor/`） | 唯一依赖 Godot 控件与 autoload 的层 |
| App | `src/app` | 用例编排：命令栈 + **29 条命令** + `GPEditService` + `GPAppDocumentManager` + `GPEventBus` + 自动保存服务 | 纯 `RefCounted`，无 UI 引用 |
| Core | `src/core` | model（`GPPIDGraph` 聚合根）、geometry、symbol、view（画布纯状态 + 画布文字档位）、platform、service、`gp_constants` | **49 个类无一个是 `Node`** → 可 headless 测试 |
| IO | `src/io` | `*.pid.json` 读写（`GPProjectIO`）+ 原子写 + schema 迁移 + 导入导出 + **DEXPI（Proteus XML）导入导出** | 唯一允许碰 `FileAccess` 的层；DXF / PDF 导出目前为**空桩** |

**DEXPI 子模块（第二个外部方言适配器，与 `*.pid.json` 平级）**：`GPDexpiSchema`（常量/版本能力表）、
`GPXmlText`（转义单点）、`GPDexpiMapping`（映射表 + `gpFlipY`/`gpNormRgb` 单点）、
`GPDexpiExporter`、`GPDexpiReader`、`GPDexpiValidator`、`GPDexpiImporter`、
`GPExporterRegistry`（新增格式不再改 UI 分发）。
三条硬不变量：① 所有世界坐标必须落在 Diagram Extent 之内（Extent 随几何一起翻转）；
② null 一律**省略** `Value` 属性，绝不写 `Value=""`；③ RDL URI 绝不臆造 ——
只有规范已核实的才写，其余留空并进报告。
| Render | `src/render` | `GPSymbolView` / `GPEdgeView` 视图节点与绘制器、`GPFrameView`（图框）/ `GPBackgroundView`（底图） | 只读模型；3D 构建为空桩 |
| Autoload | `src/autoload` | `I18n`（zh/en）、`Settings`（`user://settings.cfg`）、`SnapState`（CAD 开关） | 3 个全局单例，**仅 ui 可依赖** |
| Addons | `src/addons` | `GPIPIDAddon` 商业化插件契约（8 个钩子） | **仅契约，无加载器** |

依赖方向严格自上而下：`ui → {app, io, render} → core`。
`core` / `app` / `io` / `render` 均**不引用** `ui` 与 `autoload`（实测 0 处）——这是 headless 可测的前提，也是 2,901 条断言成立的原因。

> **门面约定**：`GPMainWindow` / `GPCanvas2D` 对外只暴露语义化公开端口（`gp*`），内部协作结构（7 协调者 / 4 实现类）不外泄；调用方在其它类 → 方法必须公开，仅类内调用 → `_gp*` 私有。

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
- `GPIPIDAddon` —— 商业化插件契约：`_gpGetName` / `_gpGetTools` / `_gpGetPanels` / `_gpOnGraphChanged` /
  `_gpRegisterExporters` / `_gpRegisterSymbolPacks` / `_gpOnLoad` / `_gpOnSync`。
  **当前仅契约、无加载器**（Open-Core 的隔离边界，Pro 代码不进本仓）。

## Testing & CI · 测试与持续集成

测试采用**双轨**：

| 轨 | 位置 | 规模 | 运行命令 |
|---|---|---|---|
| 自研 `GPGTest` | `tests/gp_test_*.gd` | **61 套 / 2,901 条断言** | `godot --headless --script res://tests/run_core_tests.gd` |
| `GUT 9.7.1` | `addons/gut`（vendored，MIT） | 桥接 + 原生用例 | `godot --headless --script res://addons/gut/gut_cmdln.gd -gexit` |

桥接脚本 `tests/gut/test_gp_suites.gd` 让 GUT 反射驱动既有 GPGTest 套件，
**无需改写任何既有测试**；新增套件后必须同步 `GP_EXPECTED_SUITES` 常量（防套件静默不加载）。
GUT 编辑器插件默认**关闭**（常驻会占用约 35% 编辑器启动时间），命令行运行器不受影响。

`.github/workflows/ci.yml`（Godot 4.7，由 `GODOT_TAG` 单点控制版本）四道门禁：

1. `godot --headless --import` —— 注册 `GutTest` 等 class_name（缺此步 GUT 无法启动）
2. `godot --headless --editor --quit` —— 编译扫描
3. `godot --headless --script res://tests/run_core_tests.gd` —— GPGTest 全套
4. `godot --headless --script res://addons/gut/gut_cmdln.gd … -gexit` —— GUT（含桥接），产出 JUnit artifact

任一步失败即 CI 红（GUT 失败时退出码为 1，已实测）。
本地另有两道：单文件 `--check-only` 与运行时冒烟 `--quit-after 90 res://scenes/main.tscn`。
