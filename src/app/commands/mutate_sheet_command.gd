class_name GPMutateSheetCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
# Change one or more SHEET-LEVEL fields as ONE undo step (Rev.3 stage 0c).
# 把**图纸级**字段的一处或多处改动作为**一个**撤销步（Rev.3 阶段 0c）。
#
# WHY THIS EXISTS / 为何存在：
# every edit of the graph already travels through a command, so Ctrl+Z reverses it. The SHEET's own
# fields had no such channel at all — `src/app/commands/` contained zero references to GPSheet before
# this file, so dragging the frame (or typing a margin in the dialog) would have been an edit the user
# cannot take back. Rev.3 makes the frame draggable, and 「每次拖拽 = 一个撤销步」 is already a
# project rule (see GPSelectTool.gpOnRelease), so the channel had to land BEFORE the drag.
# 图的每一处编辑都已走命令，故 Ctrl+Z 能撤销。而**图纸**自身的字段完全没有这条通道 —— 本文件之前
# `src/app/commands/` 对 GPSheet 的引用为零，于是拖动图框（或在对话框里键入边距）会变成用户无法收回的
# 编辑。Rev.3 让图框可拖，而「每次拖拽 = 一个撤销步」已是本项目铁律（见 GPSelectTool.gpOnRelease），
# 故这条通道必须在拖拽之前落地。
#
# ⚠️ THE SHEET IS CAPTURED HERE, NOT TAKEN FROM GPCommandContext / ⚠️ 图纸由本命令捕获，而非取自上下文：
# the context carries the GRAPH (every command needs it); the sheet is needed only by sheet-level
# commands. Putting it in the context would mean two places must keep it in step (the canvas binds the
# graph and the sheet through DIFFERENT setters), and the failure mode of a stale sheet reference is
# silent: the command would write last tab's margins and the undo would look broken. Holding the sheet
# this command was built for is also what makes undo correct after a tab switch — the command stack is
# cleared when the graph changes (GPEditService.gpBindGraph), so it can never reach an absent tab.
# 上下文携带的是**图**（每条命令都要），而图纸只有图纸级命令需要。放进上下文意味着必须有两处保持同步
# （画布经**不同**的 setter 绑定图与图纸），而「图纸引用陈旧」的失效是静默的：命令会写到上一个标签页的
# 边距上，撤销看起来就是坏的。持有「本命令为之而建」的那张图纸，也正是切换标签后撤销仍然正确的原因
# —— 图变化时命令栈即被清空（GPEditService.gpBindGraph），故它绝不可能够到一个已不在的标签页。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Field key for the frame margins ([left, top, right, bottom] in mm). / 图框边距的字段键（[左, 上, 右, 下]，mm）。
const GP_FIELD_MARGINS: String = "frame_margins"

# Field key for the title block's anchor corner (a GPSheet.GP_TB_ANCHOR_* code). Rev.3 stage 1.
# 图签锚角的字段键（GPSheet.GP_TB_ANCHOR_* 编码）。Rev.3 阶段 1。
const GP_FIELD_TB_ANCHOR: String = "tb_anchor"

# Field key for the title block's docking offset (Vector2, mm into the frame). Rev.3 stage 1.
# 图签停靠偏移的字段键（Vector2，mm，向框内）。Rev.3 阶段 1。
const GP_FIELD_TB_OFFSET: String = "tb_offset"

# The keys this command may write. A WHITELIST, in the spirit of the archive migration's node-key
# whitelist: an unknown key is REFUSED (the whole command does nothing) rather than ignored, because a
# silently dropped write is indistinguishable from "the drag did not work" — the person then drags
# harder instead of reading an error.
# 本命令可写的键。**白名单**，与存档迁移的节点键白名单同一精神：未知键一律**拒绝**（整条命令不执行）
# 而不是被忽略 —— 静默丢弃的写入与「拖拽没生效」无法区分，于是用户会更用力地拖，而不是去看错误。
#
# ⚠️ THE ANCHOR AND THE OFFSET ARE TWO KEYS ON PURPOSE, AND A DRAG WRITES BOTH AT ONCE / ⚠️ 锚角与偏移
# **刻意**是两个键，而一次拖拽会把两者同时写入：the drag produces a corner AND a distance from it, and
# recording that as two undo steps would make Ctrl+Z walk the block back through a half-way state the user
# never saw. Two keys, one command, one step — which is exactly why this command takes a DICTIONARY rather
# than a single field.
# 一次拖拽同时产出「贴哪个角」与「离它多远」，把它记成两个撤销步会让 Ctrl+Z 把图签退回到一个用户从未见过的
# 中间状态。两个键、一条命令、一个撤销步 —— 这正是本命令收**字典**而不是单个字段的原因。
const GP_FIELDS: Array = [GP_FIELD_MARGINS, GP_FIELD_TB_ANCHOR, GP_FIELD_TB_OFFSET]

# The sheet this command operates on. Captured at construction; never looked up later.
# 本命令操作的图纸。构造时捕获，此后永不回查。
var _gpSheet: GPSheet = null

# field key -> new value. Only keys present here are written.
# 字段键 -> 新值。只写此处出现的键。
var _gpNew: Dictionary = {}

# field key -> value captured by gpExecute(), for gpUndo().
# 由 gpExecute() 捕获的「字段键 -> 旧值」，供 gpUndo() 使用。
var _gpOld: Dictionary = {}


# [param gpSheet] the sheet to mutate (null refuses every execute) / 待修改的图纸（为 null 时拒绝执行）
# [param gpValues] field key -> new value, e.g. {"frame_margins": [25,5,5,5]}
#                  字段键 -> 新值，如 {"frame_margins": [25,5,5,5]}
# [param gpLabel] undo-menu label; defaults to the frame wording / 撤销菜单标签，默认用图框措辞
func _init(gpSheet: GPSheet, gpValues: Dictionary, gpLabel: String = "调整图框") -> void:
	_gpSheet = gpSheet
	_gpNew = gpValues.duplicate(true)
	gpLabel = gpLabel


# Apply every allowed key. Returns false when the sheet is gone, a key is outside the whitelist, or
# nothing actually changes — so a click that moved nothing records no phantom undo step.
# 应用每个允许的键。图纸不存在、键不在白名单内、或实际无变化时返回 false ——
# 使「按下但没动」不产生幽灵撤销步。
func gpExecute(_gpCtx: GPCommandContext) -> bool:
	if _gpSheet == null or _gpNew.is_empty():
		return false
	for gpKey in _gpNew.keys():
		if not GP_FIELDS.has(str(gpKey)):
			return false
	_gpOld = {}
	for gpKey in _gpNew.keys():
		_gpOld[gpKey] = _gpRead(str(gpKey))
	_gpWriteAll(_gpNew)
	# "Did anything change?" is answered by re-reading the model, NOT by comparing the request to the
	# captured old value: the write path CLAMPS (a request of -3 mm becomes 1 mm), so a request that
	# differs from the old value can still leave the sheet untouched, and comparing requests would
	# record an undo step that does nothing.
	# 「有没有变」由**重读模型**回答，而不是拿请求与捕获的旧值比较：写入路径会**钳制**（请求 −3mm 会变成
	# 1mm），故与旧值不同的请求仍可能什么都没改，而比较请求就会记下一个什么也不做的撤销步。
	var gpChanged: bool = false
	for gpKey in _gpOld.keys():
		if not _gpSame(str(gpKey), _gpOld[gpKey], _gpRead(str(gpKey))):
			gpChanged = true
			break
	if not gpChanged:
		return false
	_gpSheet.gpSheetChanged.emit()
	return true


# Restore every captured value. / 恢复每个捕获的旧值。
func gpUndo(_gpCtx: GPCommandContext) -> void:
	if _gpSheet == null or _gpOld.is_empty():
		return
	_gpWriteAll(_gpOld)
	_gpSheet.gpSheetChanged.emit()


# Re-apply the new values. Overridden rather than inherited because the default re-runs gpExecute(),
# which would RE-CAPTURE the old values — after an undo those are the NEW ones, so a second undo would
# restore the state the user just undid.
# 重新应用新值。覆写而非沿用默认，因为默认会重跑 gpExecute()，那会**重新捕获**旧值 —— 撤销之后旧值
# 就是新值，于是第二次撤销会恢复用户刚撤销掉的那个状态。
func gpRedo(_gpCtx: GPCommandContext) -> void:
	if _gpSheet == null or _gpNew.is_empty():
		return
	_gpWriteAll(_gpNew)
	_gpSheet.gpSheetChanged.emit()


# ============================ private ============================

# Read one whitelisted field off the sheet. A duplicate is returned for arrays so the command owns its
# snapshot: handing out the live array would let a later write mutate the captured "old" value in
# place, and the undo would then restore the new state under the old name.
# 读取图纸上的某个白名单字段。数组返回副本，使命令拥有自己的快照：交出活数组会让后续写入就地改写
# 已捕获的「旧值」，于是撤销会在「旧值」的名义下恢复新状态。
func _gpRead(gpKey: String) -> Variant:
	match gpKey:
		GP_FIELD_MARGINS:
			return _gpSheet.gpFrameMargins.duplicate()
		GP_FIELD_TB_ANCHOR:
			return _gpSheet.gpTbAnchor
		GP_FIELD_TB_OFFSET:
			return _gpSheet.gpTbOffset
	return null


# Write one whitelisted field through the sheet's OWN setter, so the field's own normalisation lives in
# exactly one place and this command cannot bypass it.
# 经图纸**自己的** setter 写入白名单字段，使各字段自身的规范化只存在一处、且本命令无法绕过它。
#
# ⚠️ THE OFFSET IS CLAMPED HERE, WHERE THE ANCHOR AND THE INNER RECTANGLE ARE BOTH IN HAND / ⚠️ 偏移在**此处**
# 钳制，因为锚角与内框在此同时在手：GPSheet.gpTbOffset documents why its own setter cannot do it (the
# bound follows from the INNER RECTANGLE, a geometry-layer fact). This command is the write path every
# user-reachable change goes through — the dialog and the drag both arrive here — so clamping at this one
# seam is what keeps an illegal offset out of the model in the first place. GPFrameGeometry.gpTitleBlockPlaced()
# still folds once more on read, so a hand-edited archive cannot produce an illegal block either; the
# fold is idempotent, so the second pass costs nothing and changes nothing.
# GPSheet.gpTbOffset 记载了它自己的 setter 为何做不到（界限由**内框**这一几何层事实决定）。本命令是每条
# 用户可触及的改动都会经过的写入路径 —— 对话框与拖拽都到这里 —— 故在这唯一的接缝上钳制，正是「非法偏移
# 从一开始就进不了模型」的保证。GPFrameGeometry.gpTitleBlockPlaced() 在读取时仍会再折一次，故手工改过的
# 存档同样产不出非法图签；该折算幂等，故第二次遍历不花代价、也不改变任何值。
func _gpWriteAll(gpValues: Dictionary) -> void:
	for gpKey in gpValues.keys():
		match str(gpKey):
			GP_FIELD_MARGINS:
				var gpV: Variant = gpValues[gpKey]
				if gpV is Array:
					_gpSheet.gpSetFrameMargins(gpV as Array)
			GP_FIELD_TB_ANCHOR:
				_gpSheet.gpSetTbAnchor(int(gpValues[gpKey]))
			GP_FIELD_TB_OFFSET:
				var gpOff: Variant = gpValues[gpKey]
				if gpOff is Vector2:
					_gpSheet.gpSetTbOffset(_gpClampTbOffset(gpValues, gpOff as Vector2))


# Fold a docking offset into its legal set FOR THE ANCHOR THIS WRITE WILL LEAVE BEHIND.
# 针对**本次写入将留下的**锚角，把停靠偏移收进合法域。
#
# ⚠️ THE ANCHOR IS READ FROM THE REQUEST FIRST, NOT FROM THE SHEET / ⚠️ 锚角**先**从请求里读，而不是从图纸：
# a drag changes both fields at once, and a dictionary's iteration order is not something this function
# should depend on — reading "the anchor this write intends" makes the offset clamp correct regardless of
# whether the anchor has already been written. Falling back to the sheet covers the single-key case (the
# dialog changing only the offset), where the sheet's anchor IS the intended one.
# 一次拖拽同时改两个字段，而本函数不该依赖字典的遍历顺序 —— 读「本次写入意图中的锚角」使偏移钳制无论锚角是否
# 已被写入都正确。回落到图纸上的值覆盖单键情形（对话框只改偏移），那时图纸的锚角就是意图中的锚角。
func _gpClampTbOffset(gpValues: Dictionary, gpOffset: Vector2) -> Vector2:
	var gpAnchor: int = int(gpValues.get(GP_FIELD_TB_ANCHOR, _gpSheet.gpTbAnchor))
	return GPFrameGeometry.gpClampTitleBlock(GPFrameGeometry.gpFrameRect(_gpSheet), gpAnchor, gpOffset)


# Value equality per field type. Marshalled through one function so adding a field cannot forget its
# comparison and silently report "changed" on every execute.
# 按字段类型比较取值。经一个函数收口，使新增字段时不会漏掉比较、从而每次执行都静默地报告「变了」。
func _gpSame(gpKey: String, gpA: Variant, gpB: Variant) -> bool:
	match gpKey:
		GP_FIELD_MARGINS:
			if not (gpA is Array) or not (gpB is Array):
				return false
			return GPFrameGeometry.gpSameMargins(gpA as Array, gpB as Array)
		GP_FIELD_TB_ANCHOR:
			return int(gpA) == int(gpB)
		GP_FIELD_TB_OFFSET:
			if not (gpA is Vector2) or not (gpB is Vector2):
				return false
			return (gpA as Vector2).is_equal_approx(gpB as Vector2)
	return gpA == gpB
