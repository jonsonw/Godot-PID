class_name GPNodeCollision
extends RefCounted
# Collision detection + iterative separation for P&ID symbols (push-apart avoidance).
# P&ID 图元碰撞检测与迭代分离（推开式避让）。
#
# The canvas places symbols as axis-aligned nominal envelopes centred on each node's position
# (see GPCanvasHitTest.gpNodeRect()). This module treats those envelopes as the collision boxes and
# pushes the NON-fixed nodes apart until none overlaps a fixed node or another non-fixed node,
# leaving a configurable gap (padding) between every pair.
# 画布把图元视为以节点位置为中心、按标称包络的轴对齐包围盒（见 GPCanvasHitTest.gpNodeRect()）。
# 本模块以这些包围盒为碰撞体，把「非固定」图元推开，直到没有任何图元与固定图元或彼此重叠，
# 且每对之间留有可配置间距（padding）。
#
# "Fixed" nodes are anchors whose position must NOT change: the freshly dropped symbol during
# placement, or the node(s) the user is dragging. Only the others move, so the user's drop point
# or cursor-followed node stays exactly where intended while neighbours scatter.
# 「固定」图元是不应移动的锚点：放置时的新图元、或用户正在拖动的图元。只有其余图元被移动，
# 因此用户落点或跟随光标的图元始终待在原处，邻件向四周散开。
#
# Pure geometry + graph read; no Node/Control dependency, fully headless-testable.
# 纯几何 + 图读取，无 Node/Control 依赖，可 headless 单测。

# Default minimum gap (world units) enforced between two separated symbols' envelopes.
# 两个被分离图元包络之间强制保留的最小间距（世界单位）。
const GP_DEFAULT_PADDING: float = 20.0

# Separate overlapping symbols by nudging the non-fixed ones apart.
# 通过推动非固定图元来分离重叠的图元。
#
# [param gpGraph] The graph holding the nodes. / 持有节点的图。
# [param gpDefLookup()] Callable(symbolId: String) -> GPSymbolDef (or null); supplies each node's
# nominal size. Mirrors GPCanvasHitTest.gpHitEdge()'s gpDefLookup().
# [param gpDefLookup()] Callable(图元id) -> GPSymbolDef（或 null），给出每个节点的标称尺寸；
# 与 GPCanvasHitTest.gpHitEdge() 的 gpDefLookup() 同约。
# [param gpFixed] Node ids that must stay put (anchors). / 必须保持不动的节点 id（锚点）。
# [param gpPadding] Minimum gap to leave between envelopes. / 包络间保留的最小间距。
# [param gpMaxIter] Separation relaxation passes (more = more settled, slower). / 分离松弛迭代次数。
# [returns] Dictionary { nodeId: Vector2 } of absolute target positions for the moved
# non-fixed nodes (only entries whose position changed).
# [returns] 被移动的非固定图元的绝对目标位置字典 { 节点id: Vector2 }（仅含发生变化的项）。
static func gpResolve(gpGraph: GPPIDGraph, gpDefLookup: Callable, gpFixed: Array[String],
		gpPadding: float = GP_DEFAULT_PADDING, gpMaxIter: int = 16) -> Dictionary:
	if gpGraph == null:
		return {}
	var gpFixedSet: Dictionary = {}
	for gpId in gpFixed:
		gpFixedSet[gpId] = true
	# Mutable working copy of every node's current position + its nominal size.
	# 每个节点当前位置与标称尺寸的可变工作副本。
	var gpPos: Dictionary = {}
	var gpSize: Dictionary = {}
	for gpN in gpGraph.gpNodes:
		gpPos[gpN.gpInstanceId] = gpN.gpPosition
		var gpDef: GPSymbolDef = null
		if gpDefLookup != null:
			gpDef = gpDefLookup.call(gpN.gpSymbolId)
		gpSize[gpN.gpInstanceId] = gpDef.gpDefaultSize if gpDef != null else Vector2(64.0, 48.0)
	var gpHalfPad: float = maxf(gpPadding, 0.0) * 0.5
	for _gpIter in range(maxi(gpMaxIter, 1)):
		var gpMoved: bool = false
		for gpA in gpGraph.gpNodes:
			var gpAid: String = gpA.gpInstanceId
			if gpFixedSet.has(gpAid):
				continue
			var gpSzA: Vector2 = gpSize[gpAid]
 # Inflate A by half the padding on every side so the final gap equals gpPadding.
 # 把 A 各边外扩半间距，使最终间隙恰为 gpPadding。
			var gpRa: Rect2 = Rect2(gpPos[gpAid] - gpSzA / 2.0, gpSzA).grow(gpHalfPad)
			for gpB in gpGraph.gpNodes:
				var gpBid: String = gpB.gpInstanceId
				if gpBid == gpAid:
					continue
				var gpSzB: Vector2 = gpSize[gpBid]
				var gpRb: Rect2 = Rect2(gpPos[gpBid] - gpSzB / 2.0, gpSzB).grow(gpHalfPad)
				if not gpRa.intersects(gpRb):
					continue
 # Minimal translation vector to push A out of B along the least-penetration axis.
 # 沿穿透最浅的轴把 A 推出 B 的最小平移向量。
				var gpMtv: Vector2 = _gpSeparate(gpPos[gpAid], gpPos[gpBid], gpRa, gpRb)
				if gpMtv != Vector2.ZERO:
					gpPos[gpAid] = (gpPos[gpAid] as Vector2) + gpMtv
 # Recompute A's inflated rect for the next B in this pass.
 # 重算 A 的外扩矩形，供本趟下一个 B 复用。
					gpRa = Rect2(gpPos[gpAid] - gpSzA / 2.0, gpSzA).grow(gpHalfPad)
					gpMoved = true
		if not gpMoved:
			break
	# Only report nodes whose position actually changed.
	# 仅报告位置真正发生变化的节点。
	var gpOut: Dictionary = {}
	for gpN in gpGraph.gpNodes:
		var gpId: String = gpN.gpInstanceId
		if gpFixedSet.has(gpId):
			continue
		if (gpPos[gpId] as Vector2) != gpN.gpPosition:
			gpOut[gpId] = gpPos[gpId]
	return gpOut


# Minimal-translation push of A out of B (axis-aligned). Returns Vector2.ZERO when not overlapping.
# 把 A 沿最小平移推出 B（轴对齐）。未重叠时返回零向量。
#
# The push axis is the one on which the two CENTERS are already most separated (the offset-dominant
# axis), not the axis of least penetration. For cluster avoidance this scatters neighbours to
# OPPOSITE sides of a fixed node instead of piling them on the same side, and it never flips
# direction between iterations, so the relaxation converges instead of oscillating.
# 推送所沿的轴是两个中心「已经」相距最大的轴（偏移主导轴），而非穿透最浅的轴。对成簇避让而言，
# 这会把邻件散射到固定节点的「两侧」，而非堆到同一侧，且方向不会在迭代间翻转，故松弛收敛而非振荡。
static func _gpSeparate(gpA: Vector2, gpB: Vector2, gpRa: Rect2, gpRb: Rect2) -> Vector2:
	var gpOX: float = minf(gpRa.end.x, gpRb.end.x) - maxf(gpRa.position.x, gpRb.position.x)
	var gpOY: float = minf(gpRa.end.y, gpRb.end.y) - maxf(gpRa.position.y, gpRb.position.y)
	if gpOX <= 0.0 or gpOY <= 0.0:
		return Vector2.ZERO
	var gpDX: float = gpA.x - gpB.x
	var gpDY: float = gpA.y - gpB.y
	if absf(gpDX) >= absf(gpDY):
 # Push along X, away from B. Tie-break a perfectly aligned pair by nudging +X so it still separates.
 # 沿 X 朝远离 B 推出。对完全对齐的一对以 +X 作兜底，使其仍能分开。
		var gpDir: float = 1.0 if gpDX >= 0.0 else -1.0
		if gpDX == 0.0:
			gpDir = 1.0
		return Vector2(gpDir * gpOX, 0.0)
	else:
		var gpDir: float = 1.0 if gpDY >= 0.0 else -1.0
		if gpDY == 0.0:
			gpDir = 1.0
		return Vector2(0.0, gpDir * gpOY)
