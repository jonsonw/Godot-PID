# P4 连线属性面板 / i18n / 回归 交付说明

> P4 = 属性面板 + i18n + 回归。P1（数据模型）、P2（渲染）、P3（交互）已落地全绿。
> 本文件沉淀「边属性面板字段映射 + 线型样式表 + 设置 + 右键菜单 + 验收」，作为架构知识库一致视图。

## 1. 边属性面板字段（按 kind 区分）

字段集由纯函数 `GPInspector.gpEdgeFieldKeys(kind)` 决定；SIGNAL 隐藏管道专属字段。

| 字段 | 含义 | 适用 kind |
|------|------|-----------|
| `kind` | 类型（PROCESS / UTILITY / SIGNAL） | 全部 |
| `tag` | 管线号（Line Number） | 全部 |
| `show_arrow` | 流向箭头 | 全部 |
| `show_tag` | 显示编号 | 全部（SIGNAL 默认关，管道默认开） |
| `signal_type` | 信号类型 | 仅 SIGNAL（ELECTRIC / PNEUMATIC / HYDRAULIC / DATA / CAPILLARY） |
| `dn` | 公称直径 DN | PROCESS / UTILITY |
| `medium` | 介质 | PROCESS / UTILITY |
| `spec` | 管道等级 | PROCESS / UTILITY |
| `insulation` | 保温 | PROCESS / UTILITY |

表单提交经 `GPInspector.gpEdgeAttrChanged` → `main_window._gpOnEdgeAttrChanged` 路由到对应的可撤销意图：
`kind/signal_type → gpSetEdgeKind`，`tag → gpSetEdgeTag`，其余 → `gpSetEdgeAttr`。改 kind 后表单即时重建（字段显隐随类型变化），画布在 `gpGraphChanged` 时重绘。

## 2. 线型样式表（纯函数 `GPEdgeStyle.gpStyleFor`）

样式是 `(kind, signal_type, zoom)` 的纯函数，故改线型无需数据迁移、旧档自动跟随。屏幕空间下限 `GP_MIN_PX=1.2`、`GP_MIN_DASH_PX=2.0`（世界单位换算回 `gpZoom`）。

| kind | signal_type | 线宽 | 颜色 | 线型（世界单位，空=实线） |
|------|-------------|------|------|----------------------------|
| PROCESS | — | 3.0 | `#DCE3F0` | 实线 |
| UTILITY | — | 1.6 | `#9AA6BE` | 实线 |
| SIGNAL | ELECTRIC | 1.4 | `#F2C14E` | 点划线 `10,3,2,3` |
| SIGNAL | PNEUMATIC | 1.4 | `#7FD1E8` | 虚线 `6,4` |
| SIGNAL | HYDRAULIC | 1.4 | `#B98BE8` | 点划线 `10,3,2,3,2,3` |
| SIGNAL | DATA | 1.2 | `#77C7A8` | 虚线 `2,4` |
| SIGNAL | CAPILLARY | 1.4 | `#E88B8B` | 虚线 `12,4` |
| SIGNAL | （空 / 未知） | 1.4 | `#F2C14E` | 点划线 `10,3,2,3` |

线型名键（`GPEdgeStyle.gpLineTypeKey` → i18n）：`line_type_process / line_type_utility / line_type_electric / line_type_pneumatic / line_type_hydraulic / line_type_data / line_type_capillary / line_type_unknown`。

> 端口端点唯一来源 `GPPortResolver`；视图与连线都调它，圆点与管线端点永不分家。流箭头仅管道绘制（信号线已用线型表达方向）。

## 3. i18n（P4 新增键，zh/en 双语）

- 边表单：`prop.edge`、`edge.kind`、`edge.signal_type`、`edge.tag`、`edge.dn`、`edge.medium`、`edge.spec`、`edge.insulation`、`edge.show_arrow`、`edge.show_tag`
- 枚举文案：`edge.kind_process/utility/signal`、`edge.type_electric/pneumatic/hydraulic/data/capillary`
- 线型名：`line_type_process/utility/electric/pneumatic/hydraulic/data/capillary/unknown`
- 右键菜单：`canvas.ctx_delete_edge/set_process/set_utility/set_signal/resnap_ends/clear_vertices/renumber`
- 状态栏：`status.edge_tag_manual/renumbered/resnapped`
- 设置：`settings.pipe_tag_rotate`、`settings.pipe_tag_font_size`

**英文界面无中文残留**由 `gp_test_i18n_keys.gd` 全表扫描守护（CJK 检测覆盖整张表，防未来回归）。本轮据此修复了既有 bug：`settings.lang_zh` 的 `en` 值原为 `"中文"` → 改正为 `"Chinese"`。

## 4. 设置（竖管位号）

- `gpPipeTagRotate: bool = true` — 竖管位号旋转 -90°；边显式 `tag_rotate` 属性可逐边覆盖（属性优先级：边 attr > 全局设置 > 硬编码默认）。
- `gpPipeTagFontSize: int = 0` — 位号字号；`0` 表示继承图元字号 `gpSymbolFontSize`，正数仅对位号覆盖。
- 设置弹窗新增「竖管位号旋转」「位号字号（0=图元字号）」两行（代码动态注入 VBox，不改动 `.tscn`）。
- 变更经 `Settings.gpApplyPipeTagStyle()` → 信号 `gpPipeTagStyleChanged` → 画布 `gpRefreshEdges()` 重绘全部边视图。
- 持久化到 `user://settings.cfg` 的 `[pipe]` 段（`tag_rotate` / `tag_font_size`）。

## 5. 右键菜单（边级动作）

| 动作 | 意图（经 edit service） | 撤销 |
|------|--------------------------|------|
| 删除连线 | `gpDeleteEdges([id])` | 单步（按原下标恢复） |
| 改为主工艺管线 | `gpSetEdgeKind(id, PROCESS)` | 单步 |
| 改为公用工程管线 | `gpSetEdgeKind(id, UTILITY)` | 单步 |
| 改为信号线 | `gpSetEdgeKind(id, SIGNAL, ELECTRIC)` | 单步 |
| 重新吸附端点 | `gpSnapEdgeEnds(id, defLookup)` | 单步（幂等：无变化则不记步） |
| 清除拐点 | `gpSetEdgeRouting(id, [])` | 单步 |
| 重新编号（全图纸） | `gpRenumberEdges()` | 单步（保留手工号与信号线） |

## 6. 验收状态

- 断言 **888 → 1024（0 失败）**；新增 2 套件：`gp_test_i18n_keys`（115）+ `gp_test_edge_inspector`（21），远超 +60 目标。
- 英文界面无中文残留：已修复 `settings.lang_zh` 的 `en` 值（"中文" → "Chinese"）。
- 重新吸附端点可撤销：`GPResnapEdgeCommand`（幂等 + undo）已落地并测试。
- 老档往返无损：`GPProjectIO` 往返测试仍全绿（本次未改动模型边字段）。
- 编译扫描（`--editor --quit`）无 `SCRIPT/Parse/Compile Error`。

## 7. 关键变更文件

- `src/ui/panels/inspector.gd` — 边表单（`gpShowEdge` / `gpEdgeFieldKeys` / `gpEdgeInitialValues`）
- `src/autoload/i18n.gd` — P4 新增 ~40 键 + 修复 lang_zh
- `src/autoload/settings.gd` — `gpPipeTagRotate` / `gpPipeTagFontSize` + 加载/保存/信号
- `src/render/edge_view.gd` — 位号旋转/字号读设置
- `src/ui/canvas/canvas_2d.gd` — 连接 `gpPipeTagStyleChanged → gpRefreshEdges`
- `src/ui/dialogs/settings_dialog.gd` — 动态注入两行 + 处理函数
- `src/ui/shell/main_window.gd` — 边选择 → 表单，`gpEdgeAttrChanged` 路由
- `src/ui/canvas/canvas_context_menu.gd` — 边级右键菜单（修复 `gMenu→gpMenu` 笔误）
- `src/app/commands/set_edge_kind_command.gd`、`resnap_edge_command.gd`、`renumber_edges_command.gd` — 可撤销意图
- `tests/gp_test_i18n_keys.gd`、`tests/gp_test_edge_inspector.gd` — 新增回归套件
