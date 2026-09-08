# Architecture · 架构（精简版）

> English: a quick-read for GitHub visitors. Authoritative full version: `G-PID_项目架构说明_20260908.html` (in the workspace `架构/交付/`).
> 中文：供 GitHub 访客速读。权威完整版见工作区 `架构/交付/G-PID_项目架构说明_20260908.html`。
>
> ⚠️ **2026-09-08 重写说明**：本文件曾长期落后于实现（类名写成 `PIDGraph`、分层含不存在的 `src/model`、
> 独档格式宣称「含全部文档 + 跨图连接」、CI 指向未安装的 GUT）。现已按实际代码重写；
> 与代码冲突之处一律以代码为准。

## Layers · 分层

| 层 | 路径 | 职责 | 说明 |
|---|---|---|---|
| UI | `src/ui` | shell（组合根/菜单栏）、canvas（主画布 + 工具契约）、panels、dialogs（含 `symbol_editor/`） | 唯一依赖 Godot 控件的层 |
| App | `src/app` | 用例编排：命令栈 + 8 条命令 + `GPEditService` + `GPAppDocumentManager` + `GPEventBus` | 纯 `RefCounted`，无 UI 引用 |
| Core | `src/core` | model（`GPPIDGraph` 聚合根）、geometry、symbol、view（画布纯状态）、platform、service | **无 UI 依赖 → 可 headless 测试** |
| IO | `src/io` | `*.pid.json` 读写（`GPProjectIO` + `GPIOResult`） | DXF / PDF / 清单导出目前为**空桩** |
| Render | `src/render` | `GPSymbolView` / `GPEdgeView` 视图节点与绘制 | 3D 构建为空桩 |
| Autoload | `src/autoload` | `I18n`（zh/en）、`Settings`（`user://settings.cfg`） | 全局单例，先于主场景初始化 |
| Addons | `src/addons` | `GPIPIDAddon` 商业化插件契约（8 个钩子） | **仅契约，无加载器** |

依赖方向严格自上而下：`ui → app → core`、`io/render → core`。
`core` 与 `app` 均不引用 `ui`、`autoload`、`addons` —— 这是 headless 可测的前提。

## Single-file format · 独档格式

一个工程 = 一个 `*.pid.json`，顶层 5 键：

```
meta / nodes / edges / shapes / user_symbol_packs
```

用户自定义图元包（`user_symbol_packs`）**内嵌进存档**，因此文件自包含、可移植、无供应商锁定 —— 这是 G-PID 数据主权主张的落点。
当前为**单图**；多文档与跨图连接属 W21 / W22 计划，**尚未实现**。

## Extension seams · 扩展接缝

- `GPCommand` + `GPCommandStack` —— 撤销/重做与未来协同共用的同一条命令流（命令是「自我求逆的值对象」）。
- `GPEventBus` —— 每张图纸一条总线；UI 与插件据此订阅 `gpGraphChanged`。
- `GPIPIDAddon` —— 商业化插件契约：`_gpGetName` / `_gpGetTools` / `_gpGetPanels` / `_gpOnGraphChanged` /
  `_gpRegisterExporters` / `_gpRegisterSymbolPacks` / `_gpOnLoad` / `_gpOnSync`。
  **当前仅契约、无加载器**（Open-Core 的隔离边界，Pro 代码不进本仓）。

## Testing & CI · 测试与持续集成

测试采用**双轨**：

| 轨 | 位置 | 规模 | 运行命令 |
|---|---|---|---|
| 自研 `GPGTest` | `tests/gp_test_*.gd` | 21 套 / **443 条断言** | `godot --headless --script res://tests/run_core_tests.gd` |
| `GUT 9.6.1` | `addons/gut`（vendored，MIT） | 桥接 + 原生用例 | `godot --headless --script res://addons/gut/gut_cmdln.gd -gexit` |

桥接脚本 `tests/gut/test_gp_suites.gd` 让 GUT 反射驱动既有 21 套 GPGTest（每个 `gpTest*` 方法折算 2 条 GUT 断言），
**无需改写任何既有测试**；代价是 GUT 侧报告粒度为方法级而非单条断言级。新测试请直接用 `extends GutTest`。

`.github/workflows/ci.yml`（Godot 4.7，由 `GODOT_TAG` 单点控制版本）四道门禁：

1. `godot --headless --import` —— 注册 `GutTest` 等 class_name（缺此步 GUT 无法启动）
2. `godot --headless --editor --quit` —— 编译扫描
3. `godot --headless --script res://tests/run_core_tests.gd` —— GPGTest 全套
4. `godot --headless --script res://addons/gut/gut_cmdln.gd … -gexit` —— GUT（含桥接），产出 JUnit artifact

任一步失败即 CI 红（GUT 失败时退出码为 1，已实测）。
