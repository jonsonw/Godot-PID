class_name GPTranslateSheetCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
# Move the WHOLE SHEET — paper, frame and every graphic — as ONE undo step (Rev.3 stage 0d).
# 平移**整张图纸** —— 纸面、图框与全部图形 —— 作为**一个**撤销步（Rev.3 阶段 0d）。
#
# WHY THIS IS NOT GPMutateSheetCommand / 为何不能复用 GPMutateSheetCommand：
# that command is built on a WHITELIST of sheet-level FIELD keys (today exactly one: `frame_margins`),
# and every key it can write lives on GPSheet. A whole-sheet move is not a sheet field — it is a
# TRANSFORMATION of four families of absolute world coordinates, three of which live on the GRAPH
# (nodes, edges, annotation shapes) and one on the sheet (the paper origin). No field whitelist can
# express "shift all of the geometry", and a node/edge-shaped command cannot express "and the paper
# too". This command therefore owns the pairing, and names its four families in one place.
# 那条命令建立在图纸级**字段**键的白名单之上（今天恰有一个：`frame_margins`），而它能写的每个键都住在
# GPSheet 上。整图平移不是一个图纸字段 —— 它是四族绝对世界坐标的一次**变换**，其中三族住在**图**上
# （图元、边、注释图形）、一族住在图纸上（纸面原点）。没有任何字段白名单能表达「把所有几何都挪一下」，
# 而节点 / 边形态的命令也表达不了「连纸一起」。故本命令持有这个配对，并在**一处**点名它的四族。
#
# ⚠️ WHAT IS *NOT* HERE, AND WHY THAT IS THE POINT / ⚠️ **不在**此处的东西，以及它为何正是要点：
# nothing in this file enumerates the four families. It asks the graph for a snapshot
# (GPPIDGraph.gpCaptureGeometry / gpRestoreGeometry, which own that enumeration so it exists once) and
# writes the paper origin. The failure mode of a second enumeration is SILENT — one kind of object
# stays behind while the rest of the sheet travels, and no assertion about the others can notice.
# 本文件没有任何一处枚举那四族。它向图要一份快照（GPPIDGraph.gpCaptureGeometry / gpRestoreGeometry，
# 二者持有那份枚举、从而只存在一处），并写纸面原点。第二份枚举的失效是**静默**的 —— 某一类对象留在原地、
# 图纸其余部分却走了，且没有任何关于其它对象的断言能察觉。
#
# ⚠️ THE SHEET IS CAPTURED HERE, THE GRAPH COMES FROM THE CONTEXT / ⚠️ 图纸由本命令捕获、图取自上下文：
# these two arrive by DIFFERENT routes on purpose. The context carries the graph (every command needs it,
# and the canvas binds it through GPCanvas2D._gpSetGraph), but it carries no sheet — the canvas binds the
# sheet through a different setter (gpSetSheet), so putting it in the context would mean two places must
# keep it in step, and the failure mode of a stale sheet is silent (the command would move last tab's
# paper). Holding the sheet the command was built for is the same rule GPMutateSheetCommand follows, and
# for the same reason.
# 二者刻意走不同的路。上下文携带图（每条命令都要，画布经 GPCanvas2D._gpSetGraph 绑定它），但**不**携带
# 图纸 —— 画布经另一个 setter（gpSetSheet）绑定图纸，故把它放进上下文就等于要求两处保持同步，而「图纸
# 引用陈旧」的失效是静默的（命令会去移动上一个标签页的纸面）。持有「本命令为之而建」的那张图纸，与
# GPMutateSheetCommand 遵循的是同一条规则、同一个理由。
#
# ⚠️ WHY THE SNAPSHOT IS TAKEN ONCE, AT EXECUTE / ⚠️ 为何快照只在执行时取一次：
# the snapshot is the coordinate system this command inverts itself in. Undo replays it with a ZERO
# delta and redo with the ORIGINAL delta, so both land on bit-identical states — no arithmetic is ever
# reversed, and Vector2's 32-bit components cannot creep. Re-capturing on redo would capture the state
# undo just restored and make redo a no-op.
# 快照是本命令赖以自我求逆的坐标系。撤销以**零**位移重放它、重做以**原始**位移重放它，故两者都落到逐位
# 相同的状态 —— 从不做逆运算，Vector2 的 32 位分量也就不可能漂移。重做时重新捕获，捕获到的正是撤销刚恢复
# 的那个状态，重做于是变成空操作。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Undo-menu label used when the caller does not supply one.
# 调用方未提供时所用的撤销菜单标签。
const GP_DEFAULT_LABEL: String = "移动图纸"


# The sheet whose paper (and whose graph's geometry) this command translates.
# Captured at construction; never looked up later.
# 本命令平移其纸面（以及其图的几何）的图纸。构造时捕获，此后永不回查。
var _gpSheet: GPSheet = null

# The net translation, in world millimetres. Applied in full; never clamped.
# 净位移（世界毫米）。完整施加，绝不钳制。
var _gpDelta: Vector2 = Vector2.ZERO

# The graph, taken from the command context on first execute.
# 图，首次执行时取自命令上下文。
var _gpGraph: GPPIDGraph = null

# The paper origin before the move, and the pre-move geometry snapshot. Both captured at execute.
# 移动前的纸面原点，以及移动前的几何快照。二者均在执行时捕获。
var _gpStartOrigin: Vector2 = Vector2.ZERO
var _gpSnap: Dictionary = {}


# [param gpSheet] the sheet to move (null refuses every execute) / 待平移的图纸（为 null 时拒绝执行）
# [param gpDelta] net translation in world millimetres / 净位移（世界毫米）
# [param gpLabel] undo-menu label; defaults to the drawing wording / 撤销菜单标签，默认用图纸措辞
func _init(gpSheet: GPSheet, gpDelta: Vector2, gpLabel: String = GP_DEFAULT_LABEL) -> void:
	_gpSheet = gpSheet
	_gpDelta = gpDelta
	gpLabel = gpLabel


# Capture the baseline and apply the move. Returns false when the sheet or graph is missing, or when
# the delta is zero — so a click that moved nothing records no phantom undo step.
# 捕获基线并施加移动。图纸或图缺失、或位移为零时返回 false —— 使「按下但没动」不产生幽灵撤销步。
#
# ⚠️ CALLED EXACTLY ONCE PER INSTANCE by GPCommandStack.gpDo. gpRedo() is overridden below, so the
# "capture once" flag never has to guard a second execute — and if it ever were re-executed, applying
# the same delta twice would move the sheet twice.
# ⚠️ 每个实例**恰好被调用一次**（由 GPCommandStack.gpDo）。下方覆写了 gpRedo()，故「只捕获一次」这个
# 标记从不需要守卫第二次执行 —— 而万一真被重执行，同一位移施加两次会把图纸挪两倍远。
func gpExecute(gpCtx: GPCommandContext) -> bool:
	if _gpSheet == null or gpCtx == null or gpCtx.gpGraph == null:
		return false
	if _gpDelta == Vector2.ZERO:
		return false
	_gpGraph = gpCtx.gpGraph
	_gpStartOrigin = _gpSheet.gpPaperOrigin
	_gpSnap = _gpGraph.gpCaptureGeometry()
	_gpApply(_gpDelta)
	return true


# Rewind to the captured baseline: the snapshot with a ZERO delta is the exact pre-execute state.
# 回退到捕获的基线：零位移下的快照就是执行前的确切状态。
func gpUndo(_gpCtx: GPCommandContext) -> void:
	if _gpSheet == null or _gpGraph == null:
		return
	_gpApply(Vector2.ZERO)


# Re-apply the ORIGINAL delta from the SAME baseline. Overridden rather than inherited because the
# default re-runs gpExecute(), which would re-apply the delta to an already-moved sheet and re-capture
# the baseline as the post-move state.
# 自**同一**基线重新施加**原始**位移。覆写而非沿用默认，因为默认会重跑 gpExecute()，那会把位移再加到
# 一张已经移过的图纸上，并把移动后的状态重新捕获为基线。
func gpRedo(_gpCtx: GPCommandContext) -> void:
	if _gpSheet == null or _gpGraph == null:
		return
	_gpApply(_gpDelta)


# ============================ private ============================

# Write the geometry for a given offset from the captured baseline, then announce it.
# 按「相对捕获基线的给定位移」写入几何，随后广播。
#
# ⚠️ ONE FUNCTION SERVES MOVE, UNDO AND REDO / ⚠️ 一个函数同时服务移动、撤销与重做：
# all three are "the baseline, offset by d", so there is exactly one place where the paper origin and
# the graph geometry are kept in step. A second place would be a second chance for them to disagree,
# and the symptom — the frame and its drawing drifting apart — would be blamed on the geometry module.
# 三者都是「基线 + 位移 d」，故「保持纸面原点与图几何同步」只有一处。有第二处就是第二次分家的机会，而
# 其症状 —— 图框与图分离 —— 会被归咎于几何模块。
#
# The sheet signal is emitted for the same reason GPMutateSheetCommand emits it: it is the ONLY emitter
# (see GPSheet.gpSheetChanged), and it is what turns the write into a repaint plus a dirty mark.
# 发射图纸信号的理由与 GPMutateSheetCommand 相同：它是**唯一**的发射点（见 GPSheet.gpSheetChanged），
# 也正是它把这次写入变成一次重绘加一次标脏。
func _gpApply(gpOffset: Vector2) -> void:
	_gpSheet.gpSetPaperOrigin(_gpStartOrigin + gpOffset)
	_gpGraph.gpRestoreGeometry(_gpSnap, gpOffset)
	_gpSheet.gpSheetChanged.emit()
