# ============================================================================
# GPSymbolPortTool — 点击添加连接端口（M7）
# Add a connection port by clicking in the symbol editor (M7).
#
# 对应旧 GPMakeSymbolDialog 的 GP_PORT 工具：点击 -> 插入一个归一化端口，自动命名、朝向最近的包络边。
# 提交经编辑器的可撤销命令（放置 = 一步可撤销编辑）。
# Mirrors the GP_PORT tool from the old GPMakeSymbolDialog: click -> insert a normalized port,
# auto-named and aimed at the nearest envelope edge. The commit goes through the editor's
# undoable command (placing = one undoable step).
# Copyright © 2026 Jonson Wang
# ============================================================================

class_name GPSymbolPortTool
extends GPSymbolEditorTool


func gpOnPress(gpLocal: Vector2, gpShift: bool, gpDouble: bool) -> bool:
	var gpEd: GPSymbolEditor = gpCtx.gpEditor
	var gpN: Vector2 = gpEd.gpLocalToNorm(gpLocal)
	var gpP: GPPort = GPPort.new()
	gpP.gpName = "p%d" % (gpEd.gpPorts.size() + 1)
	gpP.gpPos = gpN
	var gpEdge: Array = GPSymbolNormalizer.gpEdgeNormal(gpN)
	gpP.gpDir = Vector2(float(gpEdge[0]), float(gpEdge[1]))
	gpEd.gpAddPort(gpP)
	return true
