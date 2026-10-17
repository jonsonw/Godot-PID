class_name GPTableGripOps
extends RefCounted
# Copyright © 2026 Jonson Wang
# Grid-table COLUMN-WIDTH drag — stage 3 S4 (the deferred piece of the table-editing set;
# row/col insert/delete shipped in S3 via the cell context menu).
# grid 表格**列宽**拖拽 —— 阶段 3 S4（表格编辑集中暂缓的那一块；行/列增删已在 S3 经
# 格子右键菜单交付）。
#
# THE GESTURE / 手势：a press on a single-selected GENERATOR:grid table whose world point
# lands on an internal vertical separator starts a boundary drag. Moving the pointer trades
# width between the two columns the boundary separates (left column takes, right column
# gives), so the TABLE's overall footprint never changes — only the shares do. The drag
# commits as ONE undo step (GPTableMutateCommand over full props snapshots), following the
# same three beats as the frame drag: rewind -> one command -> one step.
# 手势：在**单选**的 GENERATOR:grid 表格上、世界点落在内部竖向分隔线上的按下开始一次
# 边界拖拽。移动指针在边界两侧的两列之间**对冲**宽度（左列拿、右列让），故表格的整体
# 占地不变 —— 变的只是份额。拖拽以**一个**撤销步提交（GPTableMutateCommand 携完整 props
# 快照），与图框拖拽同一三拍：回退 -> 一条命令 -> 一个撤销步。
#
# THE SCALE / 比例：cells are laid out PROPORTIONALLY inside the fixed envelope (the CSV
# sums map onto gpDefaultSize), so a world-mm delta maps onto the CSV-mm axis by
# GPSymbolGeneratorRegistry.gpGridWidthScale. Both the separator hit and the delta mapping
# come from the registry — the grabbable lines ARE the drawn separators (one geometry).
# 比例：格子按**比例**铺进固定包络（CSV 总和映射到 gpDefaultSize 上），故世界 mm 位移经
# GPSymbolGeneratorRegistry.gpGridWidthScale 映射到 CSV mm 轴。分隔线命中与位移映射都来自
# 注册表 —— 可抓的线**就是**画出来的分隔线（一份几何）。
#
# Everything here touches the canvas; the PURE facts live in the registry. This class only
# decides WHICH press means a drag and drives it, and never re-derives the layout.
# 本类全部触碰画布；**纯**事实都在注册表。这里只判定哪次按下意味着拖拽并驱动它，
# 绝不重算布局。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Half-width of the grab band around each separator, in SCREEN pixels (same affordance
# width as the frame band — one "pointing" convention everywhere).
# 每条分隔线两侧抓取带的半宽（**屏幕**像素，与图框抓取带同一可及性宽度 —— 全编辑器
# 一个「指着」的约定）。
const GP_GRAB_PX: float = 6.0

# Smallest zoom the tolerance is computed against (same degenerate-zoom guard as the frame).
# 计算容差的最小缩放（与图框相同的退化缩放守卫）。
const GP_MIN_ZOOM: float = 0.0001


# The canvas state owner. / 画布状态持有者。
var gpCv: GPCanvas2D = null

# True while a boundary drag is in flight. / 边界拖拽进行中时为真。
var _gpActive: bool = false

# The table being dragged. / 正被拖拽的表格。
var _gpNodeId: String = ""

# The separator index (boundary left of column gpSep). / 分隔线下标（列 gpSep 左侧的边界）。
var _gpSep: int = 0

# World x where the drag began (the delta is measured from here, never accumulated).
# 拖拽起始的世界 x（位移自此处量起，绝不逐帧累加）。
var _gpStartWorldX: float = 0.0

# Full props snapshot at drag start (the command's "before" and the rewind baseline).
# 拖拽起始的完整 props 快照（命令的 before，也是回退基线）。
var _gpStartProps: Dictionary = {}

# The live-transformed props (the command's "after").
# 实时变换出的 props（命令的 after）。
var _gpLiveProps: Dictionary = {}

# World-mm -> CSV-mm factor captured at drag start. / 拖拽起始时捕获的世界 mm -> CSV mm 因子。
var _gpScale: float = 0.0

# Whether the pointer currently hovers a grabbable separator (decides the cursor).
# 指针当前是否悬停在可抓分隔线上（决定光标）。
var _gpHover: bool = false


func _init(gpCanvas: GPCanvas2D) -> void:
	gpCv = gpCanvas


# Grab tolerance in WORLD mm for a given canvas zoom. Pure, so it is testable without a
# canvas. / 给定画布缩放下的抓取容差（世界毫米）。纯函数，无需画布即可测试。
static func gpGrabTol(gpZoom: float) -> float:
	return GP_GRAB_PX / maxf(gpZoom, GP_MIN_ZOOM)


# True while a boundary drag is in flight. / 边界拖拽进行中时为真。
func gpIsDragging() -> bool:
	return _gpActive


# ---------------------------------------------------------------- drag

# Begin a boundary drag when the press hit the SINGLE-selected grid table's separator.
# Returns false so the caller falls through to ordinary selection / body dragging.
# 按下命中**单选** grid 表格的分隔线时开始边界拖拽。未命中返回 false，使调用方继续走
# 普通的选择 / 本体拖拽。
#
# WHY THE SINGLE-SELECTION GATE / 为何要单选闸：the separator sits INSIDE the body, so with
# a multi-selection the same press must keep meaning "move the group"; narrowing the gesture
# to the one-selected table removes the ambiguity without a modifier key.
# 分隔线位于**本体之内**，故多选时同一次按下必须仍意味着「搬整组」；把手势收窄到
# 「单选的表格」即消除歧义，又无需修饰键。
func gpTryStart(gpWorld: Vector2, gpHitId: String) -> bool:
	if gpCv == null or gpCv.gpGraph == null or gpHitId == "":
		return false
	if gpCv.gpSelection.size() != 1 or str(gpCv.gpSelection[0]) != gpHitId:
		return false
	var gpN: GPPIDNode = gpCv.gpGraph.gpGetNode(gpHitId)
	if gpN == null:
		return false
	var gpDef: GPSymbolDef = gpCv.gpDefFor(gpN.gpSymbolId)
	if gpDef == null or GPSymbolGeneratorRegistry.gpGeneratorId(gpDef.gpGeometrySource) != "grid":
		return false
	var gpScale: float = GPSymbolGeneratorRegistry.gpGridWidthScale(gpDef, gpN)
	if gpScale <= 0.0:
		return false
	var gpOrigin: Vector2 = GPPortResolver.gpNodeWorldOrigin(gpCv.gpGraph,
		gpCv.gpDefLookupCallable(), gpN)
	var gpSep: int = GPSymbolGeneratorRegistry.gpColSeparatorAt(gpDef, gpN,
		gpWorld - gpOrigin, gpGrabTol(gpCv.gpViewZoom))
	if gpSep < 1:
		return false
	_gpActive = true
	_gpNodeId = gpHitId
	_gpSep = gpSep
	_gpStartWorldX = gpWorld.x
	_gpStartProps = gpN.gpProps.duplicate(true)
	_gpLiveProps = {}
	_gpScale = gpScale
	return true


# Live preview: an ABSOLUTE col_widths value derived from the START snapshot + the TOTAL
# delta, written on every motion. Never accumulated per-frame — replaying the same motion
# lands on the same bits (the frame-drag idempotence rule).
# 实时预览：由**起始快照 + 总位移**推导的**绝对** col_widths 值，每次移动都写下。
# 绝不逐帧累加 —— 重放同一移动落在同样的位上（图框拖拽的幂等规则）。
func gpOnGripMove(gpWorld: Vector2) -> void:
	if not _gpActive or gpCv == null or gpCv.gpGraph == null:
		return
	var gpDeltaCsv: float = (gpWorld.x - _gpStartWorldX) * _gpScale
	var gpRes: Dictionary = GPSymbolGeneratorRegistry.gpColWidthShift(_gpStartProps, _gpSep,
		gpDeltaCsv)
	if not bool(gpRes.get("ok", false)):
		return
	_gpLiveProps = gpRes["props"] as Dictionary
	var gpN: GPPIDNode = gpCv.gpGraph.gpGetNode(_gpNodeId)
	if gpN == null:
		return
	gpN.gpProps["col_widths"] = str(_gpLiveProps.get("col_widths", ""))
	gpCv.gpRefreshSymbolViews()
	gpCv.queue_redraw()


# Commit the drag: rewind the props to the snapshot, then let ONE command re-apply the
# final CSV — one undo step, never applied twice. A press without movement produces no
# command at all (the CSV compare catches it).
# 提交拖拽：把 props 回退到快照，再由**一条**命令重新应用最终 CSV —— 一个撤销步，绝不
# 叠加两次。未产生位移的按下不产生任何命令（CSV 比较把它逮住）。
func gpEndGripDrag() -> void:
	if not _gpActive:
		return
	var gpStartProps: Dictionary = _gpStartProps.duplicate(true)
	var gpAfterProps: Dictionary = _gpLiveProps.duplicate(true)
	var gpNodeId: String = _gpNodeId
	_gpClearDrag()
	if gpCv == null or gpCv.gpGraph == null:
		return
	var gpN: GPPIDNode = gpCv.gpGraph.gpGetNode(gpNodeId)
	if gpN == null:
		return
	# Rewind FIRST (union semantics on the one key the transform may touch: erase when the
	# start had no CSV, restore verbatim when it did) — then the command starts from a clean
	# baseline, exactly like the frame drag's margin rewind.
	# **先**回退（对变换可能触碰的**唯一**一键做并集语义：起始无 CSV 则擦除、有则原样还原）
	# —— 随后命令从干净基线起步，与图框拖拽的边距回退完全同构。
	if gpStartProps.has("col_widths"):
		gpN.gpProps["col_widths"] = gpStartProps["col_widths"]
	else:
		gpN.gpProps.erase("col_widths")
	var gpStartCsv: String = str(gpStartProps.get("col_widths", ""))
	var gpAfterCsv: String = str(gpAfterProps.get("col_widths", ""))
	if gpAfterCsv == "" or gpAfterCsv == gpStartCsv:
		# Nothing moved (or the transform never produced a live value): no command, no undo
		# step — but still repaint, the preview may have written and rewound the CSV.
		# 没有移动（或变换从未产出实时值）：不发命令、不产生撤销步 —— 但仍须重绘，
		# 预览可能写过又回退了 CSV。
		gpCv.gpRefreshSymbolViews()
		gpCv.queue_redraw()
		return
	gpCv.gpRequestTableSnapshot(gpNodeId, gpStartProps, gpAfterProps)
	gpCv.gpRefreshSymbolViews()
	gpCv.queue_redraw()


# Abandon the drag without committing (ESC path). / 放弃拖拽，不提交（ESC 路径）。
func gpCancelDrag() -> void:
	if not _gpActive:
		return
	var gpStartProps: Dictionary = _gpStartProps.duplicate(true)
	var gpNodeId: String = _gpNodeId
	_gpClearDrag()
	if gpCv == null or gpCv.gpGraph == null:
		return
	var gpN: GPPIDNode = gpCv.gpGraph.gpGetNode(gpNodeId)
	if gpN == null:
		return
	if gpStartProps.has("col_widths"):
		gpN.gpProps["col_widths"] = gpStartProps["col_widths"]
	else:
		gpN.gpProps.erase("col_widths")
	gpCv.gpRefreshSymbolViews()
	gpCv.queue_redraw()


# ---------------------------------------------------------------- hover + cursor

# Hover feedback: the HSIZE cursor while the pointer sits on a grabbable separator of the
# single-selected grid table, handed back to the arrow exactly once on the leave edge (the
# same state-edge discipline the frame band follows — per-motion cursor writes were the
# flicker there).
# 悬停反馈：指针落在**单选** grid 表格的可抓分隔线上时显示 HSIZE 光标，离开沿恰好一次
# 交还箭头（与图框抓取带同一「状态沿」纪律 —— 逐移动写光标正是那里闪烁的来源）。
# Returns true when the caller should consume the motion event.
# 返回 true 表示调用方应消费该移动事件。
func gpUpdateHoverCursor(gpWorld: Vector2) -> bool:
	var gpWas: bool = _gpHover
	_gpHover = false
	if gpCv != null and not _gpActive and gpCv.gpGraph != null \
			and gpCv.gpSelection.size() == 1:
		var gpN: GPPIDNode = gpCv.gpGraph.gpGetNode(str(gpCv.gpSelection[0]))
		if gpN != null:
			var gpDef: GPSymbolDef = gpCv.gpDefFor(gpN.gpSymbolId)
			if gpDef != null and GPSymbolGeneratorRegistry.gpGeneratorId(
					gpDef.gpGeometrySource) == "grid":
				var gpOrigin: Vector2 = GPPortResolver.gpNodeWorldOrigin(gpCv.gpGraph,
					gpCv.gpDefLookupCallable(), gpN)
				var gpSep: int = GPSymbolGeneratorRegistry.gpColSeparatorAt(gpDef, gpN,
					gpWorld - gpOrigin, gpGrabTol(gpCv.gpViewZoom))
				_gpHover = gpSep >= 1
	if _gpHover:
		gpCv.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	if _gpHover != gpWas and not _gpHover:
		# The LEAVE edge is the single moment this handler writes ARROW.
		# **离开沿**是本处理器写 ARROW 的唯一时机。
		gpCv.mouse_default_cursor_shape = Control.CURSOR_ARROW
	return _gpHover


# ---------------------------------------------------------------- private

# Reset every drag field. One function so neither exit path (commit / cancel) can forget a
# field and leave the tool half-armed.
# 复位全部拖拽字段。收口为一个函数，使两条退出路径（提交 / 取消）都不会漏掉字段、
# 把工具卡在半个上膛状态。
func _gpClearDrag() -> void:
	_gpActive = false
	_gpNodeId = ""
	_gpSep = 0
	_gpStartWorldX = 0.0
	_gpStartProps = {}
	_gpLiveProps = {}
	_gpScale = 0.0
	_gpHover = false
