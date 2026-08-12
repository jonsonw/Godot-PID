# Architecture · 架构（精简版）

> English: a quick-read for GitHub visitors. The full version is `Godot-PID开发指南.html`.
> 中文：供 GitHub 访客速读。完整版见 `Godot-PID开发指南.html`。

## Layers · 分层
- **UI (`src/ui`)** — main window, toolbar, canvas, viewport, inspector.
  UI 层（主窗口、工具栏、画布、视口、属性面板）。
- **Graph engine (`src/core`)** — `PIDGraph` / `PIDNode` / `PIDEdge` / `PIDDocument` (undo/redo).
  图引擎层（拓扑内核与撤销重做）。
- **Data (`src/model` + `assets`)** — `SymbolDef` / `SymbolPack` library + `project.pid.json` (single source of truth).
  数据层（图元库与独档格式）。
- **Plugin seam (`src/addons`)** — `IPIDAddon` contract only; Pro mounts here later.
  插件预留层（仅定义契约，未来 Pro 挂载）。

Dependencies flow downward; lower layers never depend on upper ones.
依赖方向自上而下，下层不反向依赖上层。

## Single-file format · 独档格式
The whole project = one `*.pid.json` (all P&ID documents + cross links + meta).
整个工程 = 一个 `*.pid.json`（含全部 P&ID 文档 + 跨图连接 + 元数据）。

## Extension seams · 扩展接缝
`StorageBackend` (swap storage) · `PIDCommand` (undo/redo + future collaboration) · `Session` (auth stub).
存储后端抽象、操作流、会话鉴权桩——三者为未来协同/Pro 预留接口，核心零改动。
