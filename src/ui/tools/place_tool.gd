# ============================================================================
# GPPlaceTool — 调色板图元放置（P2 拆分）
# Palette symbol placement (P2 split).
#
# 当画布有待放置图元（gpPendingDef 非空）时，左键按下即放置。原 _gpOnLeftDown 的放置分支已迁入
# 本类（经 gpCtx.gpCv 读写画布状态，行为零变更）。
# When the canvas has a pending symbol (gpPendingDef != null), a left press places it. The placement
# branch of the former _gpOnLeftDown now lives here (reads/writes canvas state via gpCtx.gpCv, zero
# behavior change).
# ============================================================================

class_name GPPlaceTool
extends GPCanvasTool

func gpOnPress(gpWorld: Vector2, gpShift: bool, gpDouble: bool) -> bool:
	var gpCv := gpCtx.gpCv
	# Leave the label empty so the canvas renders the localized type name and it switches with the
	# UI language. The user can still type a custom label.
	# 标签留空，使画布显示本地化的类型名并随界面语言切换；用户仍可在属性面板填自定义标签。
	var gpNid: String = gpCv._gpState.gpIds.gpNext("n")
	gpCv.gpGraph.gpAddNode(gpCv.gpGraph.gpNewNode(gpNid, gpCv.gpPendingDef.gpId, "", gpWorld, {}))
	gpCv.gpPendingDef = null
	gpCv._gpSetSelection([gpNid])
	gpCv.queue_redraw()
	gpCv.gpGraphChanged.emit()
	gpCv._gpEmitStatus()
	return true
