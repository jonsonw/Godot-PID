# ============================================================================
# GPPlaceTool — 调色板图元放置
# Palette symbol placement .
#
# 本类（经 gpCtx.gpCv 读写画布状态，行为零变更）。
# When the canvas has a pending symbol (gpPendingDef != null), a left press places it. The
# placement branch of the former _gpOnLeftDown() lives here (reads/writes canvas state via
# gpCtx.gpCv, zero behavior change).
#
# M4 续：模型改动不再由本工具直接调 gpAddNode()，而是经画布端口 gpRequestPlaceNode() 进入
# GPEditService → GPAddNodeCommand，于是「放置」也成为一步可撤销的编辑。本工具只保留视图侧
# 后果（清空待放置、选中新节点、重绘、状态栏）。
# M4 cont: the model mutation no longer calls gpAddNode() directly; it goes through the canvas
# port gpRequestPlaceNode() into GPEditService -> GPAddNodeCommand, so placing becomes one
# undoable step. This tool keeps only the view-side consequences (clear the pending def,
# select the new node, repaint, status bar).
#
# 放置虚影预览 / Place-ghost preview：
# 从调色板选中一个图元后光标变手型，鼠标在画布内移动时以「半透明实形」实时跟随——
# 复用画布图元同一套 GPSymbolPainter 绘制逻辑，完整保留图元真实形状轮廓，类似建筑放置类
# 游戏的放置预览。左键落点正式放置并清除虚影；落点若压到既有连线，随即弹出「绕行 / 拆分」二选一。
# After picking a symbol from the palette the cursor becomes a hand; moving over the canvas
# tracks a translucent silhouette in real time — reusing the canvas symbol's own GPSymbolPainter
# so the real shape outline is fully preserved (building-style placement preview). A left press
# places for real and clears it; if the drop lands on an existing pipe, "reroute / split" pops up.
# ============================================================================

class_name GPPlaceTool
extends GPCanvasTool

# 放置虚影：半透明实形预览（建筑放置类）。不再用红框，而是复用 GPSymbolPainter 画出图元真实形状。
# Place-ghost: a translucent silhouette preview (building-style). Instead of a red box we reuse
# GPSymbolPainter to paint the symbol's real shape.
const GP_GHOST_FILL_ALPHA: float = 0.20    # 填充透明度 / fill opacity
const GP_GHOST_STROKE_ALPHA: float = 0.80  # 轮廓透明度 / outline opacity
const GP_GHOST_BORDER: float = 2.0         # 基线描边宽度（世界单位），绘制时再乘缩放 / base border (world), multiplied by zoom at draw time

# ---- 放置虚影预览状态 / Place-ghost preview state ----
# 虚影中心的世界坐标（= 当前鼠标所在世界坐标），以及是否正在显示虚影。
# World centre of the ghost (= the cursor's world position), and whether the ghost is showing.
var _gpGhostWorld: Vector2 = Vector2.ZERO
var _gpGhostOn: bool = false


# 鼠标移动：有待放置图元时虚影实时跟随光标。
# Mouse move: while a symbol is pending the ghost tracks the cursor.
#
# 本钩子是运动链路的**最末端**（见 input_router 的 InputEventMouseMotion 分支），因此在这里重申
# 手型光标能覆盖前面位号 / 端口悬停逻辑设下的箭头 —— 否则手型会被改回箭头、看似失效。
# This hook is the LAST stop in the motion chain (see the InputEventMouseMotion branch of
# input_router), so re-asserting the hand cursor here overrides the arrow set by the earlier
# tag / port hover handlers — otherwise the hand would flip back and look broken.
#
# 没有待放置图元时收起虚影；光标的箭头形态由 gpPendingDef 的 setter 负责恢复（兜底）。
# With nothing pending the ghost retracts; the arrow cursor is restored by the gpPendingDef
# setter (the fallback path).
func gpOnMove(gpWorld: Vector2) -> bool:
	var gpCv: GPCanvas2D = gpCtx.gpCv
	if gpCv.gpPendingDef == null:
		_gpGhostOn = false
		return false
	_gpGhostWorld = gpWorld
	_gpGhostOn = true
	gpCv.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	gpCv.queue_redraw()
	return true


# 覆盖层：在已放置图元之上画出「半透明实形」虚影——直接复用画布图元的 GPSymbolPainter，
# 把待放置图元真实形状按当前缩放画在鼠标处。屏幕坐标系下的标称包络 = 鼠标世界坐标的屏幕投影
# 为中心、半边 = 标称尺寸 × 缩放，与画布上真实图元占用范围完全一致（见 GPSymbolView.gpDrawBody()），
# 所见即所放。
# Overlay: paint a TRANSLUCENT SILHOUETTE above the placed art — reusing the canvas symbol's own
# GPSymbolPainter so the pending symbol's real shape is drawn at the cursor at the current zoom.
# The on-screen nominal envelope is centred on the cursor's screen projection with half-extent =
# nominal size × zoom, exactly the footprint a real placed symbol would occupy (see
# GPSymbolView.gpDrawBody()), so what you see is what gets placed.
#
# 钩子契约传入的是 CanvasItem（基类签名），但虚影所需的「待放置定义 / 缩放 / 世界→屏幕换算」
# 这几个端口只存在于 GPCanvas2D 上，故绘制走 gpItem、状态从 gpCtx.gpCv 读取。
# The hook contract hands over a CanvasItem, but the ghost needs ports that exist only on
# GPCanvas2D (pending def, zoom, world->screen), so we paint through gpItem and read state from
# gpCtx.gpCv.
func gpDrawOverlay(gpItem: CanvasItem) -> void:
	if not _gpGhostOn:
		return
	var gpCv: GPCanvas2D = gpCtx.gpCv
	if gpCv.gpPendingDef == null:
		return
	var gpDef: GPSymbolDef = gpCv.gpDefFor(gpCv.gpPendingDef.gpId)
	# 屏幕坐标系下的标称包络：中心 = 鼠标世界坐标的屏幕投影，半边 = 标称尺寸 × 缩放。
	# 与画布上真实图元占用范围一致（见 gpDrawBody()），所见即所放。
	# The nominal envelope in SCREEN space: centred on the cursor's screen projection, half-extent
	# = nominal size × zoom, matching the footprint a real placed symbol would occupy.
	var gpSz: Vector2 = gpDef.gpDefaultSize if gpDef != null else Vector2(64.0, 48.0)
	var gpCenter: Vector2 = gpCv.gpScreenFromWorld(_gpGhostWorld)
	var gpRect: Rect2 = Rect2(gpCenter - gpSz * gpCv.gpViewZoom * 0.5, gpSz * gpCv.gpViewZoom)
	var gpBorder: float = GP_GHOST_BORDER * gpCv.gpViewZoom
	if gpDef == null:
 # 定义缺失时退回半透明矩形，至少给出落点范围提示。
 # Fall back to a translucent rectangle when the definition is missing.
		gpItem.draw_rect(gpRect, Color(0.6, 0.6, 0.6, GP_GHOST_FILL_ALPHA), true)
		gpItem.draw_rect(gpRect, Color(0.85, 0.85, 0.85, GP_GHOST_STROKE_ALPHA), false, gpBorder)
		return
	# 复用画布图元同一套绘制逻辑（GPSymbolPainter.gpDrawShape()），因此虚影形状与真实图元
	# 永不会脱节 —— 这正是「建筑放置类」半透明实形预览的核心。颜色取图元类目色，填充与
	# 轮廓分别压低/抬高透明度，既透出底下内容、又让形状轮廓清晰可辨。
	# Reuse the SAME painter the canvas symbols use, so the ghost can never diverge from the real
	# glyph — the heart of a building-style translucent placement preview. Colour follows the
	# symbol's category; fill and outline get separate opacities so the footprint reads through
	# yet the outline stays crisp.
	var gpBase: Color = GPSymbolPainter.gpCategoryColor(gpDef.gpCategory)
	var gpFill: Color = Color(gpBase.r, gpBase.g, gpBase.b, GP_GHOST_FILL_ALPHA)
	var gpStroke: Color = gpBase.lightened(0.25)
	gpStroke.a = GP_GHOST_STROKE_ALPHA
	if not gpDef.gpShapes.is_empty():
		GPSymbolPainter.gpDrawShape(gpItem, gpDef.gpShapeSpec(), gpRect, gpFill, gpStroke, gpBorder)
	else:
 # 无矢量形状时退回半透明矩形（与 gpDrawBody() 的兜底一致）。
 # No vector shape -> translucent rectangle (matches gpDrawBody()'s fallback).
		gpItem.draw_rect(gpRect, gpFill, true)
		gpItem.draw_rect(gpRect, gpStroke, false, gpBorder)


func gpOnPress(gpWorld: Vector2, gpShift: bool, gpDouble: bool) -> bool:
	var gpCv: GPCanvas2D = gpCtx.gpCv
	if gpCv.gpPendingDef == null:
		return false
	# Leave the label empty so the canvas renders the localized type name and it switches with the
	# UI language. The user can still type a custom label.
	# 标签留空，使画布显示本地化的类型名并随界面语言切换；用户仍可在属性面板填自定义标签。
	var gpNid: String = gpCv.gpRequestPlaceNode(gpCv.gpPendingDef.gpId, gpWorld)
	if gpNid == "":
		return false
	_gpGhostOn = false
	gpCv.gpPendingDef = null
	gpCv.gpSetSelection([gpNid])
	# 放置避让：新图元固定不动，把与之重叠的其它图元推开，保持合理间距。
	# Placement avoidance: the new symbol stays put; push overlapping neighbours aside to keep spacing.
	var gpAvoid: Dictionary = GPNodeCollision.gpResolve(gpCv.gpGraph, gpCv.gpDefFor,
			[gpNid], GPNodeCollision.GP_DEFAULT_PADDING)
	if not gpAvoid.is_empty():
		gpCv.gpRequestSetNodePositions(gpAvoid)
	# 新图元压到既有连线上 -> 弹出「绕行 / 拆分」二选一。放在最后，因为菜单要用到刚落地的节点。
	# The new symbol landed on an existing pipe -> offer "reroute / split". Runs last because the
	# menu needs the freshly placed node.
	# gpContextMenu 在无 real 路由器时（headless 测试）为 null，故必须判空。
	# gpContextMenu is null without a real router (headless tests), hence the guard.
	var gpNode: GPPIDNode = gpCv.gpGraph.gpGetNode(gpNid)
	var gpEdgeHit: String = gpCv.gpEdgeGrips.gpEdgeUnderNode(gpNode)
	if gpEdgeHit != "" and gpCv.gpContextMenu != null:
		gpCv.gpContextMenu.gpPromptDropOnEdge(gpNid, gpEdgeHit)
	gpCv.queue_redraw()
	gpCv.gpEmitStatus()
	return true
