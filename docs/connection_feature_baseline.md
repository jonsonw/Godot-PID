# G-PID 连线功能实现基准参考（P1–P4 + 修复）

> 统一基准，确保后续连线功能修改的开发连续性。引擎 Godot 4.7 / GDScript 2.0。
> HTML 主交付：`docs/connection_feature_baseline.html`

## 0. 范围
P1 数据模型 · P2 渲染 · P3 交互 · P4 属性面板/i18n/回归 + 2026-09-09 `gpSelectionChanged` 信号类型崩溃修复。

**单一事实入口**：所有连线写操作必须经由 `GPEditService` 意图方法 → 翻译成 `GPCommand` 压栈；禁止在 UI/工具层直接改 `GPPIDGraph`。

## 1. 整体架构
分层 + 六边形端口适配器 + 命令模式 + 事件总线。
- 意图端口：`GPEditService`（核心不反向依赖 UI）
- 通知端口：`GPEventBus`（每图纸一条）`gpGraphChanged` / `gpSelectionChanged`（UI 不回写模型）
- 层序：基础设施 → 数据 → 几何/样式 → 渲染 → 命令 → 服务 → 交互 / 面板

## 2. 模块依赖（上层→下层）
| 层 | 模块 | headless 单测 |
|---|---|---|
| 基础设施 | I18n / Settings / GPEventBus / GPIdGen / GPTagGen | ✅ |
| 数据 | GPPIDGraph / GPPIDEdge / GPPIDNode / GPSymbolDef / GPPort | ✅ |
| 几何/样式 | GPEdgeRoute / GPPortResolver / GPEdgeTagLayout / GPEdgeStyle / GPEdgeDash | ✅ |
| 渲染 | GPEdgeView / GPEdgePainter | 部分 |
| 命令 | GPCommand*/Stack/Context + 9 边命令 | ✅ |
| 服务 | GPEditService | ✅ |
| 交互 | GPCanvas2D / 工具 / 菜单 | 否 |
| 面板 | GPInspector / GPSettingsDialog / GPMainWindow | 否 |

**铁律**：`core/` 下不得引用 `ui/` 或 `autoload/I18n|Settings`。

## 3. 文件清单
- 数据：`src/core/model/pid_edge.gd`（gpFromRef/gpToRef/gpKind/gpSignalType/gpOrtho/gpRouting/gpTag/gpAttrs）、`pid_graph.gd`（gpEdges/gpMeta/tag_seq/gpGetEdge/gpGraphChanged）
- 几何/样式：`edge_route.gd`(gpRoute)、`port_resolver.gd`(gpResolveEnd/gpWantTypeFor/gpSnapRef)、`edge_tag_layout.gd`(gpPlace)、`edge_style.gd`(gpStyleFor/gpLineTypeKey/gpPortColor)、`edge_dash.gd`
- 服务：`src/core/service/tag_gen.gd`(gpNextTag/gpPeek/gpIsTaken)
- 渲染：`src/render/edge_view.gd`(gpInit/gpSetView/gpPolyline/_draw)、`edge_painter.gd`
- 命令：`src/app/command_context.gd` + `src/app/commands/*edge*.gd`（connect/delete/reconnect/routing/tag/attr/kind/resnap/renumber）
- 服务：`src/app/edit_service.gd`（唯一意图入口）
- 交互：`canvas_2d.gd`、`pipe_tool.gd`、`edge_grip_ops.gd`、`edge_tag_editor.gd`、`canvas_context_menu.gd`
- 面板：`inspector.gd`(gpShowEdge/gpEdgeFieldKeys/gpEdgeInitialValues/gpEdgeAttrChanged)、`main_window.gd`(_gpOnEdgeAttrChanged/_gpOnSelectionChanged)、`settings_dialog.gd`
- 基础设施：`autoload/i18n.gd`(~40 键)、`autoload/settings.gd`(gpPipeTagRotate/gpPipeTagFontSize/gpPipeTagStyleChanged)
- 测试/文档：`tests/gp_test_i18n_keys.gd`、`tests/gp_test_edge_inspector.gd`、`tests/smoke_selection_emit.gd`、`docs/P4_CONNECTION_PANEL.md`

## F. 功能实现总览

当前已落地功能按五类归类，逐项目给出关键模块 / 核心逻辑流程 / 相关函数职责（与 HTML 主交付 §F 同步）。

**速查表**

| 编号 | 功能 | 类别 | 关键模块 |
|---|---|---|---|
| F1 | 创建连线（端口吸附→建边→分配位号） | 创建与几何 | GPPipeTool · GPEditService · GPConnectEdgeCommand · GPTagGen |
| F2 | 端点改接（grip 拖拽重连） | 创建与几何 | GPEdgeGripOps · GPReconnectEdgeCommand |
| F3 | 折点/管线走向编辑 | 创建与几何 | GPEdgeGripOps · GPSetEdgeRoutingCommand |
| F4 | 边位号编辑（双击） | 创建与几何 | GPEdgeTagEditor · GPSetEdgeTagCommand |
| F5 | 删除边 | 创建与几何 | canvas_context_menu · GPDeleteEdgesCommand |
| F6 | 边属性面板（动态表单） | 属性与样式 | GPInspector · GPMainWindow · SetEdge*Command |
| F7 | 线型与配色（kind+signal_type 驱动） | 属性与样式 | GPEdgeStyle · GPEdgeView · GPEdgePainter |
| F8 | 竖管位号旋转/字号（全局设置） | 属性与样式 | Settings · edge_view.gd · GPSettingsDialog |
| F9 | 端点重吸附（幂等） | 批量与智能 | GPResnapEdgeCommand · GPPortResolver |
| F10 | 全图纸重编号（跳过 SIGNAL/手工号） | 批量与智能 | GPRenumberCommand · GPTagGen |
| F11 | 边选择 + 选择变更信号 | 选择交互 | GPCanvas2D · GPEventBus |
| F12 | 边级右键菜单（7 项） | 选择交互 | canvas_context_menu.gd · GPEditService |
| F13 | 端点实时解析（端口跟随） | 底层支撑 | GPPortResolver |
| F14 | 几何布线（正交/直连/用户路径） | 底层支撑 | GPEdgeRoute |
| F15 | 位号生成（高水位不回收） | 底层支撑 | GPTagGen |
| F16 | i18n 多语（~40 连线键） | 底层支撑 | I18n (autoload) |
| F20 | 选中管线高亮（光晕+亮色描边，根因修复） | 选择交互 | graph_binder · edge_view · edge_style |
| F21 | 路径拖拽编辑增强（实时断线 + 编辑态高亮） | 创建与几何 | GPEdgeGripOps · graph_binder · edge_view |
| F22 | 选中管线按 Del 删除（并入单撤销步） | 选择交互 | canvas_2d · edit_service · delete_selection_command |

### F.1 创建与几何编辑

- **F1 创建连线**：`GPPipeTool` 经 `GPSnapResolver.gpSnap` 取两端点 ref → `gpActions.gpConnect/gpConnectEdge` → `GPConnectEdgeCommand` 内 `graph.gpAddEdge` + `GPTagGen.gpNextTag` 分配位号 → `emit gpGraphChanged` → 画布 `gpRefreshEdges` 实例化 `GPEdgeView`。`GPPipeTool` 只产 ref 不写模型；`GPTagGen` 基于 `gpMeta["tag_seq"]` 高水位不回收分配。
- **F2 端点改接**：拖端点 grip → `gpSnap` 新 ref → `gpActions.gpReconnectEdge(edgeId,isFrom,newRef)` → 改 `gpFromRef/gpToRef` 之一 → 重绘。拖拽态「先回退再命令重放」避免垃圾撤销步。`GPReconnectEdgeCommand` 捕获旧 ref 还原。
- **F3 折点编辑**：拖折点 → 更新 `gpRouting`（仅中间点）→ `GPEdgeRoute.gpRoute` 串成折线；绝不改用户顶点；清空即回自动布线。`GPSetEdgeRoutingCommand` 捕获旧 routing 撤销。
- **F4 位号编辑**：边双击 → `gpActions.gpSetEdgeTag(edgeId,tag)` → 改 `gpTag` → 重绘。单撤销步，位号不回收。`GPSetEdgeTagCommand` 捕获旧 tag。
- **F5 删除边**：右键/Delete → `gpActions.gpDeleteEdges([id])` → 移出 `gpEdges` → 重绘。多选中合并单撤销步；`GPDeleteEdgesCommand` 恢复边但不回收位号。

### F.2 属性与样式

- **F6 边属性面板**：边选中 → `GPInspector.gpShowEdge` 按 `gpEdgeFieldKeys(kind)` 动态渲染（SIGNAL 隐藏 dn/medium/spec/insulation）；改值 `emit gpEdgeAttrChanged(edgeId,key,val)` → `GPMainWindow._gpOnEdgeAttrChanged` 路由：kind/signal_type→`gpSetEdgeKind`、tag→`gpSetEdgeTag`、其余→`gpSetEdgeAttr` → 改模型→重绘（改 kind 即时换线型）。相关：`gpEdgeFieldKeys`(纯函数)、`gpEdgeInitialValues`、`_gpAddEdgeField`(枚举→OptionButton / show_*→CheckBox / 其余→LineEdit)、`_gpRefreshSelection`。
- **F7 线型配色**：绘制时 `GPEdgeStyle.gpStyleFor(kind,signalType,zoom)` 返线型/色/宽；`gpLineTypeKey` 映射到 i18n。`kind+signalType` 共决线型（如 SIGNAL+ELECTRIC 实线、SIGNAL+PNEUMATIC 虚线）。`GPEdgeView._draw` 读取，`GPEdgeDash` 提供虚线。
- **F8 竖管位号设置**：设置变更 → `Settings.gpSave()` 持久化 `user://settings.cfg` 并 `emit gpPipeTagStyleChanged` → 画布 `gpRefreshEdges` → `edge_view._gpDrawTag` 以 `gpPipeTagRotate` 覆盖 `tag_rotate` attr、`gpPipeTagFontSize` 覆盖 `gpSymbolFontSize`。`GPSettingsDialog` 动态注入两行（不碰 .tscn）。

### F.3 批量与智能

- **F9 重吸附（幂等）**：右键 → `gpActions.gpSnapEdgeEnds(edgeId,defLookup)` → 两端 `GPPortResolver.gpSnapRef`（优先同名口否则首匹配 wanted type）；有变化才改 ref，否则 `gpExecute` 返回 false 不进栈；undo 还原。`gpWantTypeFor` 给边想要的端口类型。
- **F10 重编号**：右键 → `gpActions.gpRenumberEdges()` → 快照 old tags+seq → 重置 `gpMeta["tag_seq"]={}` → 遍历非 SIGNAL 且非 `tag_manual` 边 `GPTagGen.gpNextTag` 重排；0 条可重排则 `gpExecute` 返回 false；undo 还原 tags+seq。

### F.4 选择交互

- **F11 边选择**：`gpSetEdgeSelection(ids:Array[String])` 设 `gpEdgeSel` 并清空节点/形状选择 → `emit gpSelectionChanged(gpSelection)`（已声明类型变量，非裸 []；2026-09-09 修复点）→ 面板 `_gpOnSelectionChanged` 刷新。守护：`tests/smoke_selection_emit.gd`。
- **F12 右键菜单（7 项）**：`gpOnRightDown` 命中边→`gpSetEdgeSelection`+记 `_gpCtxEdge`+开菜单；`gpOnContext` 分派 删除→`gpDeleteEdges`、改 PROCESS/UTILITY/SIGNAL→`gpSetEdgeKind`、重吸附→`gpSnapEdgeEnds`、清拐点→`gpSetEdgeRouting(id,[])`、重编号→`gpRenumberEdges()`；全 `queue_redraw()`。常量 GP_CTX_DELETE_EDGE=20…RENUMBER=26。
- **F20 选中管线高亮（根因修复）**：选中边现以**整条路径发亮**呈现，而非仅抓取点三角。根因：边选择存于独立数组 `gpEdgeSel`，而 `GPGraphBinder._gpSyncEdgeViews` 此前只把节点选择 `gpSelection` 透传给 `GPEdgeView.gpSetView`，导致 `edge_view.gpSelected` 恒为 false、选中光晕从未点亮。`gpSync` 现新增 `gpEdgeSelection`/`gpEditingEdgeId` 参数并下传 → 边视图选中态生效；选中时画 `GP_SEL_HALO` 加宽光晕 + 墨线之上叠 `GP_SEL_OUTLINE` 亮色细描边（仅底部光晕易误读为单纯变粗）。
- **F22 选中管线按 Del 删除（单撤销步）**：`KEY_DELETE/BACKSPACE`→`gpRequestDeleteSelected` 现把 `gpEdgeSel` 并入删除请求（过去只删节点/图形，边被忽略 → Del 对选中管线无效）。为避免与节点删除重复删除其附属边，`gpRequestDeleteSelected` 先剔除「端点正被删除」的边，余下经 `GPDeleteSelectionCommand` 的**边半步**与节点/图形合并为**一个撤销步**。`GPDeleteSelectionCommand` 现含 `GPDeleteNodesCommand`+`GPDeleteShapesCommand`+`GPDeleteEdgesCommand` 三部分，`gpUndo/gpRedo` 按 shapes→edges→nodes 顺序回放。

### F.5 底层支撑

- **F13 端点解析**：`GPPortResolver.gpResolveEnd(graph,defLookup,edge,isFrom)` 三级降级返世界坐标；移动图元自动跟随，故 `gpRouting` 只存中间折点。`gpWantTypeFor`/`gpSnapRef` 复用。
- **F14 几何布线**：`GPEdgeRoute.gpRoute(from,to,routing,ortho)` 有折点用用户路径，否则直连/正交（L/Z/U）；`GP_STUB=14` 有管口端引出段。纯函数、headless 可测。
- **F15 位号生成**：`GPTagGen.gpNextTag/gpPeek/gpIsTaken` 基于 `gpMeta["tag_seq"]` 高水位；永不回收。与边模型解耦，被建边/重编号命令复用。
- **F16 i18n**：连线 ~40 键分域 `edge.*`/`line_type.*`/`canvas.ctx_*`/`status.*`/`settings.pipe_tag_*`。`I18n.gpTr(key)` 按 locale 返中/英；`gp_test_i18n_keys.gd` 守护英文零中文残留（已修 `settings.lang_zh.en="中文"→"Chinese"`）。

### F.6 端点连接 · 自动布线 · 交叉断线（2026-09-09 新增）

- **F17 端点对端点连接**：`GPPortConnectOps`（画布委托，瞬态态本类持有）暴露选中图元的连接端点。**单击端点**=拾取（供 F18 自动连线选两端，再点取消）；**从端点拖到另一端点**=直接连线（合法才连，非法落点经 `gpReportRefusal` 显式提示）。hover/选中/源/合法/非法五态用 `GP_COL_*` 颜色 + 拾取框尺寸区分。实时预览线复用 `GPEdgeRoute.gpRoute`（所见即所得）。合法性规则全部下沉 `GPPortAnchor`：`gpWishFor`(端口用途→pipe/signal/any)、`gpConnectKindFor`(两端用途→kind 或 "" 非法)、`gpValidatePair`(自环/类型不符/缺失→拒绝键)、`gpAnchors`/`gpHitPort`(命中与绘制同一几何)。创建走 `gpRequestConnectEdge`→`gpActions.gpConnectEdge`→`GPConnectEdgeCommand`（同既有单一入口铁律）。
- **F18 正交自动布线（避障）**：选中两端点后右键「自动连线」(`GP_CTX_AUTO_CONNECT=27`, `canvas.ctx_auto_connect`)→`gpRequestAutoConnect`→`GPEdgeAutoRoute.gpRouteAuto`。算法：以两端点 + 所有图元包络（外扩 `GP_MARGIN=12`）构造 **Hanan 网格**，A* 带 90° 拐弯惩罚(`GP_TURN_COST=60`)、与已有连线共线时加 `GP_OVERLAP_COST=600`（避重复/重叠）、网格超 `GP_MAX_CELLS=60000` 退化为 `gpOrthoPath` 兜底。首末段沿端口法线引出(`GP_STUB=14`)。路径写为边的 `gpRouting` 中间折点（两端仍每帧按端口 ref 重算），故与手动直连/拖拽/ L-Z-U **并存可选**、仍可全量编辑。`gpExistingPolylines` 由 `GPGraphBinder` 提供。
- **F19 交叉检测与断线渲染（仅渲染不改拓扑）**：`GPGraphBinder._gpUpdateCrossings` 每帧按「节点变换+边类型+折点」指纹去抖 → `GPEdgeCrossing.gpFindCrossings`(包围盒预筛 + 线段相交) → 每条边经 `gpSetBreaks` 收到断点。`gpBreakSide` 归约为一条：**优先级低者断；同级则竖向者断**（`PROCESS>UTILITY>SIGNAL` 使次要/信号恒断于主工艺）。断口 `GPEdgePainter.gpDrawInk/gpDrawHalo` 经 `gpSplitByGaps`/`gpClipSegsByGaps`（保留虚线相位）在 `GP_BREAK_GAP=10` 处留缺口。规则：a) 主工艺×主工艺→竖向断；b) 次要×主工艺→次要断；c) 信号×任意工艺→信号断。
- **F21 路径拖拽编辑增强（实时断线 + 编辑态高亮）**：拖拽**顶点/插入抓取点**（`GPEdgeGripOps`，复用 F3 折点编辑）即实时改写 `gpRouting`；因 `GPGraphBinder._gpUpdateCrossings` 每帧重算且指纹含折点，被拖拽边与其它线的交叉在拖动中**实时断口显示**（端点拖拽只动预览橡皮筋，落点确定才改几何）。拖拽进行中 `gpEdgeGrips.gpIsDragging()` 为真，画布把该边 id 经 `gpSync` 的 `gpEditingEdgeId` 透传，使该边呈**橙色强高亮**（`GP_EDIT_HALO`，区别于普通选中的蓝色），整条路径在编辑态同样醒目。

> **修改定位**：先定位编号+关键模块+相关函数，再回 §4 看签名、§7 看坑位、§8 跑回归。所有写操作经 `GPEditService`，禁 UI 直改 `GPPIDGraph`。

## 4. 核心 API
- `GPEdgeRoute.gpRoute(from,to,routing,ortho)`：有折点用用户路径；否则直连/正交自动布线（GP_STUB=14 有管口端引出段）。
- `GPPortResolver.gpResolveEnd/gpWantTypeFor/gpSnapRef`：唯一端点坐标来源；重吸附优先同名口否则首匹配 wanted type。
- `GPEdgeStyle.gpStyleFor(kind,signalType,zoom)`：线型由 (kind, signalType) 共决。
- `GPEditService` 意图：`gpConnect`/`gpConnectEdge`/`gpDeleteEdges`/`gpSetEdgeTag`/`gpSetEdgeAttr`/`gpSetEdgeRouting`/`gpReconnectEdge`/`gpSetEdgeKind`/`gpSnapEdgeEnds`/`gpRenumberEdges` + 撤销栈。
- `GPCanvas2D`：`gpActions:GPEditService`、`gpSetEdgeSelection`(传 gpSelection)、`gpEdgeSel:Array[String]`（边选择独立数组）、`gpHitEdge`、`gpDefLookupCallable`、`gpRequestDeleteSelected`(现并入 gpEdgeSel)、`gpRequestConnectEdge`/`gpRequestAutoConnect`、`gpPortPick`/`gpHoverPort`、`gpPortOps:GPPortConnectOps`、`gpEdgeGrips:GPEdgeGripOps`(含 `gpDraggingEdgeId`/`gpIsDragging`)。
- `GPEdgeStyle`（core/model，纯静态）：`gpStyleFor(kind,signalType,zoom)` 线型由 (kind, signalType) 共决；选中/编辑高亮常量 `GP_SEL_HALO`(蓝 0.5α 加宽)/`GP_EDIT_HALO`(橙 0.55α)/`GP_SEL_OUTLINE`(亮蓝细描边)/`GP_MIN_PX`(屏幕最小线宽下限，供描边换算)。`GPEdgeView.gpSetView(zoom,sel,hover,editing)` 第四参 `editing` 由 binder 经 `gpEditingEdgeId` 透传。
- `GPPortAnchor`（core/view，纯静态）：`gpAnchors`/`gpHitPort`/`gpAnchorOf`/`gpValidatePair`/`gpConnectKindFor`/`gpWishFor`/`gpSamePort` — 端点几何与连接合法性单一来源。
- `GPEdgeAutoRoute`（core/geometry，纯静态）：`gpObstacles`/`gpRouteAuto` — Hanan 网格 A* 正交避障。
- `GPEdgeCrossing`（core/geometry，纯静态）：`gpFindCrossings`/`gpBreakSide`/`gpBreaksFor`/`gpSplitByGaps`/`gpClipSegsByGaps` — 交叉检测 + 断线优先级 + 缺口裁剪。
- `GPGraphBinder`：`gpExistingPolylines`/`_gpUpdateCrossings` — 跨边交叉唯一可算者，逐帧指纹去抖推送到 `GPEdgeView.gpSetBreaks`。
- `GPInspector.gpShowEdge` + `signal gpEdgeAttrChanged(edgeId,key,val)`；`GPMainWindow._gpOnEdgeAttrChanged` 路由到对应意图。

## 5. 关键调用链
- 创建：`GPPipeTool → GPSnapResolver.gpSnap → gpActions.gpConnect → GPConnectEdgeCommand → graph.gpAddEdge + GPTagGen.gpNextTag → gpGraphChanged → gpRefreshEdges → GPEdgeView._draw`
- 改接：`GPEdgeGripOps → gpActions.gpReconnectEdge → GPReconnectEdgeCommand`
- 属性：`GPInspector.gpEdgeAttrChanged → GPMainWindow._gpOnEdgeAttrChanged → gpActions.gpSetEdgeKind/Tag/Attr → Command → gpGraphChanged`
- 菜单：7 项分派到 `gpActions`（清拐点=`gpSetEdgeRouting(id,[])`；重编号=`gpRenumberEdges()`）
- 重编号：跳过 SIGNAL 与 `tag_manual`，重排后更新 `gpMeta["tag_seq"]`，undo 还原。
- 重吸附：两端 `gpSnapRef`，幂等（无变化返回 false 不进栈）。
- 端点连接：`GPPortConnectOps.gpTryStartDrag(命中端点)→gpUpdateDrag(重吸附目标+合法性)→gpFinishDrag(合法则 gpRequestConnectEdge，否则 gpReportRefusal)`；单击端点→`gpTogglePick` 进 `gpPortPick`。
- 自动连线：`gpPortPick(2)→右键 GP_CTX_AUTO_CONNECT→gpRequestAutoConnect→GPEdgeAutoRoute.gpRouteAuto(障碍=全图元包络排除两端；已有线=gpExistingPolylines)→gpActions.gpConnectEdgeRouted(routing 写中间折点)→gpClearPortPick`。
- 交叉断线：`GPGraphBinder._gpUpdateCrossings → GPEdgeCrossing.gpFindCrossings → 每边 gpSetBreaks → GPEdgeView._draw 经 GPEdgePainter 留缺口（拓扑不变）`。
- 选中高亮：`gpSetEdgeSelection`→`gpEdgeSel`→`GPGraphBinder.gpSync(gpEdgeSelection=gpEdgeSel)`→`_gpSyncEdgeViews` 把 `gpSelection.has||gpEdgeSelection.has` 透传给 `edge_view.gpSetView(gpSelected)`→`_draw` 画 `GP_SEL_HALO`+`GP_SEL_OUTLINE`（此前只透传节点选择，边光晕恒不亮 → 仅见抓取点三角）。
- 拖拽编辑实时断线：`GPEdgeGripOps.gpOnGripMove(顶点)` 改写 `gpRouting`→`queue_redraw`→`_draw`→`_gpSyncViews`→`_gpUpdateCrossings`（指纹含折点）实时重算 → 被拖边 `gpSetBreaks` 更新 → 拖拽中即显示断口；同时 `gpIsDragging`→`gpEditingEdgeId` 透传使该边呈 `GP_EDIT_HALO` 橙色。
- Del 删边：`KEY_DELETE/BACKSPACE → gpRequestDeleteSelected → gpActions.gpDeleteSelection(nodes,shapes,edges)`（剔除端点正删的边）→`GPDeleteSelectionCommand`(节点+图形+边三半步，单撤销步)→`gpSetEdgeSelection([])` 清选择。

## 6. 模块化评估：高
八层清晰无逆向依赖；核心全 headless 可测；9 边命令统一撤销栈；UI 仅经意图入口+事件总线；几何为纯静态函数；面板复用同一骨架。实现方式：六边形端口适配器、命令模式、工具委托、纯函数几何、端口引用不存端口名、语义化面板信号。

## 7. 关键坑位
1. 有类型数组信号必须 emit 已声明类型变量，不可 `emit([])`（2026-09-09 崩溃根因）。
2. `Array[String]()` / `Array[int]()` 在 4.7 非法 → 变量标类型 + `[]`。
3. `Window` 非 `Control` 子类 → 枚举须 `Control.SIZE_EXPAND_FILL`。
4. 端点 ref 存 `port.id` 非显示名，改名不断链。
5. 重吸附/重编号幂等返回 false。
6. i18n 全表扫描守护英文界面零中文。
7. `gpRouting` 仅用户折点，端点实时解析。

## 8. 验证
回归三连：`--headless --import` → `--headless --script res://tests/run_core_tests.gd`（1202 断言全绿）→ `--headless --editor --quit`（零错误）。

## 9. 后续
W5 多文档撤销栈 · W10 图校验 · W20 图遍历 · 可选 `GPEdgeRoute.gpRouteAuto`(AStarGrid2D 避障，当前未用 A*)。

## 10. 修订
P1–P4（888→1024 断言）；2026-09-09 信号崩溃修复 + smoke 测试；v1.0 本文档。
v1.1（2026-09-09）新增「F. 功能实现总览」：16 项已落地功能按五类归类，逐项目给关键模块/核心流程/相关函数职责。
v1.2（2026-09-09）新增 F17 端点对端点连接 / F18 正交自动布线（Hanan 网格 A* 避障）/ F19 交叉检测与断线渲染（仅渲染不改拓扑）。回归 1166→1191 断言全绿（新增 `tests/gp_test_connection_features.gd` 25 断言）。`GPPortAnchor`·`GPEdgeAutoRoute`·`GPEdgeCrossing` 三个纯静态模块 + `GPPortConnectOps` 画布委托 + 右键「自动连线」+ 拒绝键 i18n。
v1.3（2026-09-09 晚）选中体验增强：F20 选中管线高亮（根因修复——binder 现把 `gpEdgeSel` 透传给 `edge_view`，整条路径发亮而非仅三角）、F21 拖拽编辑实时断线 + 编辑态橙色高亮、F22 选中管线按 Del 删除（并入单撤销步复合命令）。回归 1191→1202 断言全绿（新增 `tests/gp_test_edge_commands.gd` 中删边选中路径 2 例 11 断言）。改动：`graph_binder`(gpSync 增 gpEdgeSelection/gpEditingEdgeId)、`edge_view`(gpSetView+_draw 高亮)、`edge_style`(GP_SEL_HALO/GP_EDIT_HALO/GP_SEL_OUTLINE)、`edge_grip_ops`(gpDraggingEdgeId)、`canvas_2d`(gpRequestDeleteSelected 并入 gpEdgeSel)、`edit_service`+`delete_selection_command`(边半步)。
