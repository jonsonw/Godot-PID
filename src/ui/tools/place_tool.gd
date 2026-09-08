# ============================================================================
# GPPlaceTool — 调色板图元放置（P2 拆分 · M4 续 接入命令层）
# Palette symbol placement (P2 split · M4 cont, routed through the command layer).
#
# 当画布有待放置图元（gpPendingDef 非空）时，左键按下即放置。原 _gpOnLeftDown 的放置分支已迁入
# 本类（经 gpCtx.gpCv 读写画布状态，行为零变更）。
# When the canvas has a pending symbol (gpPendingDef != null), a left press places it. The
# placement branch of the former _gpOnLeftDown lives here (reads/writes canvas state via
# gpCtx.gpCv, zero behavior change).
#
# M4 续：模型改动不再由本工具直接调 gpAddNode，而是经画布端口 gpRequestPlaceNode() 进入
# GPEditService → GPAddNodeCommand，于是「放置」也成为一步可撤销的编辑。本工具只保留视图侧
# 后果（清空待放置、选中新节点、重绘、状态栏）。
# M4 cont: the model mutation no longer calls gpAddNode directly; it goes through the canvas
# port gpRequestPlaceNode() into GPEditService -> GPAddNodeCommand, so placing becomes one
# undoable step. This tool keeps only the view-side consequences (clear the pending def,
# select the new node, repaint, status bar).
# ============================================================================

class_name GPPlaceTool
extends GPCanvasTool

func gpOnPress(gpWorld: Vector2, gpShift: bool, gpDouble: bool) -> bool:
	var gpCv := gpCtx.gpCv
	if gpCv.gpPendingDef == null:
		return false
	# Leave the label empty so the canvas renders the localized type name and it switches with the
	# UI language. The user can still type a custom label.
	# 标签留空，使画布显示本地化的类型名并随界面语言切换；用户仍可在属性面板填自定义标签。
	var gpNid: String = gpCv.gpRequestPlaceNode(gpCv.gpPendingDef.gpId, gpWorld)
	if gpNid == "":
		return false
	gpCv.gpPendingDef = null
	gpCv.gpSetSelection([gpNid])
	gpCv.queue_redraw()
	gpCv.gpEmitStatus()
	return true
