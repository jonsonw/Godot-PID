class_name GPNodeTextEditor
extends RefCounted
# Copyright © 2026 Jonson Wang
# In-place TAG editor for a P&ID node (Rev.3 stage 1.5, R1 就地文本编辑).
# 图元位号的就地编辑器（Rev.3 阶段 1.5，R1 就地文本编辑）。
#
# The precedent is GPEdgeTagEditor: a floating LineEdit over the text; typing a new tag and
# pressing Enter (or clicking away) commits it through the canvas edit port, so the rename is
# ONE undo step. While the editor is open the canvas freezes pan/zoom so the field cannot drift
# off the symbol. This file deliberately mirrors that shape instead of inventing a new paradigm —
# R1 is "the edge's in-place edit generalised to nodes", not a new interaction.
# 先例是 GPEdgeTagEditor：文字上方的浮层 LineEdit；输入新位号并回车（或点击别处）即经画布编辑
# 端口提交，使重命名成为**一个**撤销步。编辑器打开期间画布冻结平移/缩放，字段不会偏离图元。
# 本文件刻意镜像该形态而非发明新范式 —— R1 是「把边的就地编辑推广到节点」，不是新交互。
#
# WHAT GETS EDITED / 编辑的是什么：
# Only the SINGLE-LABEL path's tag (the `位号`). A definition whose label format is not tag-like
# (e.g. "{name}" or "{prop:dn}") or that declares label SLOTS draws text that is NOT the tag;
# editing it in place and writing a tag would contradict what is on screen. Double-clicks there
# keep the old behaviour (the symbol editor dialog) — see gpWantsInPlace().
# 只有**单标签路径**的位号可就地编辑。标签格式非位号型（如 "{name}" / "{prop:dn}"）或声明了
# 文本槽的定义，画的是**非位号**文字；就地编辑却写位号会与屏幕所示矛盾。那里的双击保持旧行为
#（打开图元编辑对话框）—— 见 gpWantsInPlace()。
#
# CODING RULE (the frame_view accident, Rev.3 §9-③): the overlay is a Control in SCREEN space,
# the text anchor is WORLD mm. The conversion goes ONLY through the canvas's existing
# gpScreenFromWorld() — never a second conversion, because the zoom-scaling bug hides at 100%.
# 编码铁律（frame_view 事故，Rev.3 §9-③）：浮层是**屏幕空间**的 Control，文字锚点是**世界毫米**。
# 换算只走画布既有的 gpScreenFromWorld() —— 绝不另写一套，因为缩放 bug 在 100% 缩放下隐身。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# The canvas that owns the live graph + the edit ports. / 持有实时图与编辑端口的画布。
var gpCv: GPCanvas2D

# The LineEdit overlay (created lazily on first open so headless import stays node-free).
# 浮层 LineEdit（首次打开时惰性创建，使无界面导入不引入节点）。
var _gpEdit: LineEdit = null

# The multi-line TextEdit overlay for GENERATOR text blocks (user feedback 2026-10-17: a
# text block's whole point is multi-line content; a single-line LineEdit structurally
# cannot express it). Same lazy pattern, same screen-space rule as the LineEdit.
# 多行文本块的 TextEdit 浮层（用户实测反馈 2026-10-17：文本块的全部意义就是多行内容；
# 单行 LineEdit 结构上无法表达）。同一惰性模式、同一屏幕空间铁律。
var _gpMulti: TextEdit = null

# Which overlay is live for the CURRENT edit session: true = TextEdit (gpProps path),
# false = LineEdit (tag path). Decided in gpOpen and read by commit/close/reposition.
# 当前编辑会话使用哪个浮层：真 = TextEdit（gpProps 路径），假 = LineEdit（位号路径）。
# 由 gpOpen 决定，提交/关闭/定位读取。
var _gpIsMulti: bool = false

# Node id currently being edited ("" = none). / 当前正在编辑的节点 id（"" 表示无）。
var _gpNodeId: String = ""

# The CELL key being edited ("" = not a cell edit — either the tag path or the props-text
# path). Stage 3 S2: a grid table's double-click opens the field over ONE cell; commit
# writes gpProps[cellKey] through the same request port as the props-text path.
# 正在编辑的**格子**键（"" = 非格子编辑 —— 位号路径或 props 文字路径）。阶段 3 S2：
# grid 表格的双击把字段开在**单个格子**上；提交经与 props 文字路径相同的请求端口
# 写 gpProps[cellKey]。
var _gpCellKey: String = ""

# True while the field is open and capturing input. / 字段打开并接收输入时为真。
var _gpActive: bool = false


# ---------------------------------------------------------------- pure helpers
# ---------------------------------------------------------------- 纯辅助

# May a double-click on this node open the in-place tag editor? True only when the drawn label
# IS the tag: the single-label path (no slots) and a tag-like format.
# 双击该节点可否打开就地位号编辑器？仅当画出的标签**就是位号**时为真：
# 单标签路径（无槽）且格式为位号型。
static func gpWantsInPlace(gpNode: GPPIDNode, gpDef: GPSymbolDef) -> bool:
	if gpNode == null:
		return false
	if gpDef != null and not gpDef.gpLabelSlots.is_empty():
		return false
	# Stage 3: a GRID table edits CELLS, not the tag — the cell dispatch owns the table's
	# double-clicks (see select_tool). Falling through here would open a TAG editor on the
	# whole table, which contradicts what the user clicked.
	# 阶段 3：grid 表格编辑的是**格子**而非位号 —— 表格的双击归格子分派管（见 select_tool）。
	# 若在此放行，双击整表会打开位号编辑器，与用户所点自相矛盾。
	if gpDef != null and GPSymbolGeneratorRegistry.gpGeneratorId(gpDef.gpGeometrySource) == "grid":
		return false
	return gpFormatIsTagLike(gpDef)


# Whether a definition's label format resolves to the tag (or the definition is unknown, which
# behaves the same: the default format is "{tag}").
# 定义的表情格式是否解析为位号（定义未知时同样成立：默认格式即 "{tag}"）。
static func gpFormatIsTagLike(gpDef: GPSymbolDef) -> bool:
	if gpDef == null:
		return true
	return gpDef.gpLabelFormat == "" or gpDef.gpLabelFormat == "{tag}"


# The WORLD-space rectangle of the node's single-path label, for the double-click hit test.
# 单标签路径标签的**世界**矩形，供双击命中测试。
#
# WHY AN APPROXIMATION IS ENOUGH / 为何近似即可：this is a CLICK TARGET, not rendered ink, so a
# small margin of error is fine — but the anchor and alignment MUST come from the same geometry
# module the renderer uses (GPLabelGripOps), or the box will sit next to the text at some zoom.
# The text HEIGHT uses the same tier rule as the renderer (GPTextRole.gpTagMM); design pixels map
# 1:1 to world mm at font size == mm, so the measured width transfers directly.
# 为何近似即可：这是**点击目标**而非渲染墨迹，小误差无妨 —— 但锚点与对齐**必须**来自渲染器
# 同一个几何模块（GPLabelGripOps），否则盒子在某个缩放下会贴到文字旁边。文字**字高**与渲染器
# 同一档位规则（GPTextRole.gpTagMM）；字号 == 毫米数时设计像素与世界毫米 1:1，实测宽度可直接换算。
#
# Stage 2: a GENERATOR text block (content in gpProps) draws no label at all — its editable
# area IS the envelope, centred on the node's world position, sized by the definition.
# 阶段 2：GENERATOR 文本块（内容存 gpProps）根本不画标签 —— 其可编辑区域**就是包络**，
# 以节点世界位置为中心、尺寸取定义。
static func gpTextRectWorld(gpNode: GPPIDNode, gpDef: GPSymbolDef,
		gpGraph: GPPIDGraph = null, gpLookup: Callable = Callable(),
		gpLocale: String = "zh") -> Rect2:
	if gpNode == null or not gpWantsInPlace(gpNode, gpDef):
		return Rect2()
	if GPSymbolGeneratorRegistry.gpTextPropKey(gpDef) != "":
		# The centre must be the NODE's world origin (GPPortResolver), NOT the label anchor
		# (gpWorldPos) — a default BELOW anchor put the field under the block.
		# 中心必须是**节点**的世界原点（GPPortResolver），而非标签锚点（gpWorldPos）——
		# 默认 BELOW 锚点会把字段放到块的下方。
		var gpCenter: Vector2 = GPPortResolver.gpNodeWorldOrigin(gpGraph, gpLookup, gpNode)
		var gpSz: Vector2 = gpDef.gpDefaultSize if gpDef != null else Vector2(80.0, 40.0)
		return Rect2(gpCenter - gpSz * 0.5, gpSz).grow(2.0)
	var gpText: String = GPLabelGripOps.gpLabelText(gpNode, gpDef, gpLocale)
	if gpText == "":
		return Rect2()
	var gpAnchor: int = GPLabelGripOps.gpEffectiveAnchor(gpNode, gpDef)
	var gpAnchorPos: Vector2 = GPLabelGripOps.gpWorldPos(gpNode, gpDef, gpGraph, gpLookup)
	var gpH: float = GPTextRole.gpTagMM(
		gpDef.gpCategory if gpDef != null else "", GPTextRole.GP_INLINE_TAG_MM)
	var gpPx: int = maxi(int(gpH), 1)
	var gpSzPx: Vector2 = ThemeDB.fallback_font.get_string_size(gpText,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, gpPx)
	var gpSizeMM: Vector2 = Vector2(maxf(gpSzPx.x, float(gpPx)), gpH * 1.4)
	var gpRect: Rect2 = Rect2(GPLabelGripOps.gpTextOrigin(gpAnchor, gpAnchorPos, gpSizeMM),
		gpSizeMM)
	# A forgiving target: clicks near the edge should still land. / 宽容的点击目标：边缘附近的点击也算命中。
	return gpRect.grow(2.0)


# Whether a world point is on the node's editable text. / 世界点是否落在该节点的可编辑文字上。
static func gpHitText(gpWorld: Vector2, gpNode: GPPIDNode, gpDef: GPSymbolDef,
		gpGraph: GPPIDGraph = null, gpLookup: Callable = Callable(),
		gpLocale: String = "zh") -> bool:
	var gpRect: Rect2 = gpTextRectWorld(gpNode, gpDef, gpGraph, gpLookup, gpLocale)
	if gpRect.size == Vector2.ZERO:
		return false
	return gpRect.has_point(gpWorld)


# The FIRST node (declaration order, mirroring the canvas hit test's tie rule) whose editable
# text contains the world point. "" when none. The caller dispatches the in-place editor to the
# returned id — this is the R1 entry point of the select tool's double-click chain.
# 文字包含该世界点的**第一个**节点（声明序，与画布命中测试的平局规则一致）。无则 ""。
# 调用方把就地编辑器分派给返回的 id —— 这是选择工具双击链的 R1 入口。
static func gpHitTextAny(gpGraph: GPPIDGraph, gpLookup: Callable, gpWorld: Vector2,
		gpLocale: String = "zh") -> String:
	if gpGraph == null:
		return ""
	for gpN in gpGraph.gpNodes:
		var gpDef: GPSymbolDef = null
		if gpLookup.is_valid():
			gpDef = gpLookup.call(gpN.gpSymbolId) as GPSymbolDef
		if gpHitText(gpWorld, gpN, gpDef, gpGraph, gpLookup, gpLocale):
			return gpN.gpInstanceId
	return ""


# ---------------------------------------------------------------- live delegate
# ---------------------------------------------------------------- 实时委托

func _init(gpCanvas: GPCanvas2D) -> void:
	gpCv = gpCanvas


# Is the in-place editor open? The canvas polls this to freeze pan/zoom.
# 就地编辑器是否打开？画布据此冻结平移/缩放。
func gpIsEditing() -> bool:
	return _gpActive


# Lazily build the LineEdit and parent it to the canvas.
# 惰性构建 LineEdit 并挂到画布。
func _gpEnsureEdit() -> LineEdit:
	if _gpEdit != null:
		return _gpEdit
	var gpEdit: LineEdit = LineEdit.new()
	gpEdit.focus_mode = Control.FOCUS_CLICK
	gpEdit.size = Vector2(120.0, 26.0)
	gpEdit.max_length = 24
	# Commit on Enter; close+commit when focus leaves (clicking another node, the canvas, etc.).
	# 回车提交；焦点离开（点另一图元、点画布等）时关闭并提交。
	gpEdit.text_submitted.connect(_gpOnSubmitted)
	gpEdit.focus_exited.connect(_gpOnFocusExited)
	# PROBE FINDING (stage 1.5): while the field holds focus, a pressed ESC is consumed by the
	# LineEdit and NEVER reaches the canvas's ESC chain — the "ESC abandons" branch in
	# GPCanvasShortcuts is dead code for a FOCUSED field. The editor therefore intercepts ESC
	# on the field's own gui_input: close WITHOUT committing, and consume the event.
	# 探针发现（阶段 1.5）：字段持有焦点时，按下的 ESC 被该 LineEdit 消费、**永远**到不了画布的
	# ESC 链 —— GPCanvasShortcuts 里的「ESC 放弃」分支对**有焦点**的字段是死代码。故编辑器
	# 在字段自身的 gui_input 上拦截 ESC：不提交地关闭，并消费该事件。
	gpEdit.gui_input.connect(_gpOnEditGuiInput)
	gpCv.add_child(gpEdit)
	_gpEdit = gpEdit
	return gpEdit


# Lazily build the multi-line TextEdit and parent it to the canvas. Enter inserts a newline
# (TextEdit's native behaviour); Ctrl/Cmd+Enter commits; ESC abandons — all handled in
# _gpOnMultiGuiInput. No max_length: a note block may be as long as its author needs.
# 惰性构建多行 TextEdit 并挂到画布。回车即换行（TextEdit 原生行为）；Ctrl/Cmd+回车提交；
# ESC 放弃 —— 全部在 _gpOnMultiGuiInput 处理。不设 max_length：备注块该多长由作者定。
func _gpEnsureMultiEdit() -> TextEdit:
	if _gpMulti != null:
		return _gpMulti
	var gpMulti: TextEdit = TextEdit.new()
	gpMulti.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	# Grow to fit the content so a short note never shows a scrollbar.
	# 随内容自适应增高，短备注永不出现滚动条。
	gpMulti.scroll_fit_content_height = true
	gpMulti.focus_mode = Control.FOCUS_CLICK
	gpMulti.custom_minimum_size = Vector2(120.0, 48.0)
	gpMulti.focus_exited.connect(_gpOnFocusExited)
	gpMulti.gui_input.connect(_gpOnMultiGuiInput)
	gpCv.add_child(gpMulti)
	_gpMulti = gpMulti
	return gpMulti


# The overlay live for the current session, as the common Control supertype.
# 当前会话的浮层，以公共 Control 超类型返回。
func _gpActiveField() -> Control:
	return _gpMulti if _gpIsMulti else _gpEdit


# ESC on the field: abandon without committing. Every other key is left to the LineEdit.
# 字段上的 ESC：不提交地放弃。其余按键一律交还 LineEdit。
func _gpOnEditGuiInput(gpEvent: InputEvent) -> void:
	if gpEvent is InputEventKey:
		var gpKey: InputEventKey = gpEvent as InputEventKey
		if gpKey.pressed and not gpKey.echo and gpKey.keycode == KEY_ESCAPE:
			_gpEdit.accept_event()
			gpClose()


# Keys on the multi-line field: ESC abandons without committing (same contract as the
# LineEdit); Ctrl/Cmd+Enter commits (plain Enter must stay a NEWLINE — that is the entire
# reason this overlay exists). Everything else is left to the TextEdit.
# 多行字段上的按键：ESC 不提交地放弃（与 LineEdit 同一契约）；Ctrl/Cmd+回车提交
#（普通回车必须是**换行** —— 这正是本浮层存在的全部理由）。其余按键交还 TextEdit。
func _gpOnMultiGuiInput(gpEvent: InputEvent) -> void:
	if gpEvent is InputEventKey:
		var gpKey: InputEventKey = gpEvent as InputEventKey
		if gpKey.pressed and not gpKey.echo and gpKey.keycode == KEY_ESCAPE:
			_gpMulti.accept_event()
			gpClose()
		elif gpKey.pressed and not gpKey.echo and gpKey.keycode == KEY_ENTER \
				and (gpKey.ctrl_pressed or gpKey.meta_pressed):
			_gpMulti.accept_event()
			_gpCommit()


# Open the editor for gpNodeId, pre-filled with its current content, and grab focus. The
# content source follows the commit target (stage 2): a GENERATOR text block reads gpProps
# and edits in the MULTI-LINE TextEdit (user feedback 2026-10-17), everything else reads the
# tag in the single-line LineEdit — the two can never disagree about what is on screen.
# 为 gpNodeId 打开编辑器，预填当前内容，并夺取焦点。内容来源跟随提交目标（阶段 2）：
# GENERATOR 文本块读 gpProps 并在**多行** TextEdit 中编辑（用户实测反馈 2026-10-17），
# 其余读位号、用单行 LineEdit —— 两者对「屏幕上是什么」永不分歧。
func gpOpen(gpNodeId: String) -> void:
	if gpCv.gpGraph == null:
		return
	var gpN: GPPIDNode = gpCv.gpGraph.gpGetNode(gpNodeId)
	if gpN == null:
		return
	_gpNodeId = gpNodeId
	_gpCellKey = ""
	var gpDef: GPSymbolDef = gpCv.gpDefFor(gpN.gpSymbolId)
	var gpPropKey: String = GPSymbolGeneratorRegistry.gpTextPropKey(gpDef)
	_gpIsMulti = gpPropKey != ""
	if _gpIsMulti:
		_gpEnsureMultiEdit().text = str(gpN.gpProps.get(gpPropKey, ""))
	else:
		var gpEdit: LineEdit = _gpEnsureEdit()
		gpEdit.text = gpN.gpTag
		gpEdit.editable = true
		# The tag path keeps its 24-char cap (the cell path lifts it in gpOpenCell).
		# 位号路径保持 24 字上限（格子路径在 gpOpenCell 里解除）。
		gpEdit.max_length = 24
	gpCv.gpSetSelection([gpNodeId])
	_gpReposition()
	var gpField: Control = _gpActiveField()
	gpField.show()
	gpField.grab_focus()
	if not _gpIsMulti and _gpEdit != null:
		_gpEdit.select_all()
	_gpActive = true
	gpCv.queue_redraw()


# Open the CELL editor for one grid-table cell (stage 3 S2). The field covers the cell's
# screen rect; commit writes gpProps[cellKey] (ONE undo step via gpRequestSetNodeProp —
# the same channel the props-text path uses). No length cap: a cell holds a real value.
# 为 grid 表格的一个格子打开编辑器（阶段 3 S2）。字段覆盖格子的屏幕矩形；提交写
# gpProps[cellKey]（经 gpRequestSetNodeProp 一个撤销步 —— 与 props 文字路径同一通道）。
# 不设长度上限：格子里放的是真实参数值。
# NOTE (v1): the cell rect is node-LOCAL and the field position ignores node rotation /
# flip — the same axis-aligned-envelope concession the hit test makes. Rotated tables
# remain movable/selectable; only the field overlay may sit axis-aligned over a rotated
# cell. / 注意（v1）：格子矩形是节点**本地**的，字段定位忽略节点旋转/翻转 —— 与命中
# 测试同一种「轴对齐包络」让步。旋转的表格仍可移动/选中；仅浮层相对已旋转格子保持轴对齐。
func gpOpenCell(gpNodeId: String, gpCellKey: String, gpCellRectLocal: Rect2) -> void:
	if gpCv.gpGraph == null or gpCellKey == "":
		return
	var gpN: GPPIDNode = gpCv.gpGraph.gpGetNode(gpNodeId)
	if gpN == null:
		return
	_gpNodeId = gpNodeId
	_gpCellKey = gpCellKey
	_gpIsMulti = false
	var gpEdit: LineEdit = _gpEnsureEdit()
	gpEdit.text = str(gpN.gpProps.get(gpCellKey, ""))
	gpEdit.editable = true
	gpEdit.max_length = 0
	gpCv.gpSetSelection([gpNodeId])
	_gpRepositionCell(gpCellRectLocal)
	gpEdit.show()
	gpEdit.grab_focus()
	gpEdit.select_all()
	_gpActive = true
	gpCv.queue_redraw()


# Position the single-line field over a CELL's screen rect (the world rect = node world
# origin + the generator's local cell rect — one conversion per corner, both through the
# canvas port, per the file-header coding rule).
# 把单行字段定位到**格子**的屏幕矩形上（世界矩形 = 节点世界原点 + 生成器的本地格子矩形
# —— 每个角一次换算、都走画布端口，遵循文件头编码铁律）。
func _gpRepositionCell(gpCellRectLocal: Rect2) -> void:
	if _gpEdit == null or gpCv.gpGraph == null:
		return
	var gpN: GPPIDNode = gpCv.gpGraph.gpGetNode(_gpNodeId)
	if gpN == null:
		return
	var gpOrigin: Vector2 = GPPortResolver.gpNodeWorldOrigin(gpCv.gpGraph,
		gpCv.gpDefLookupCallable(), gpN)
	var gpWorldRect: Rect2 = Rect2(gpOrigin + gpCellRectLocal.position, gpCellRectLocal.size)
	var gpTL: Vector2 = gpCv.gpScreenFromWorld(gpWorldRect.position)
	var gpBR: Vector2 = gpCv.gpScreenFromWorld(gpWorldRect.end)
	_gpEdit.position = gpTL
	_gpEdit.size = gpBR - gpTL


# Close the editor without committing (ESC path). Both overlays are hidden — the session
# flag alone is not enough, a stale visible field from the other path would linger.
# 不提交而关闭编辑器（ESC 路径）。两个浮层都要隐藏 —— 仅靠会话标志不够，
# 另一路径的残留字段会留在屏上。
func gpClose() -> void:
	_gpActive = false
	_gpNodeId = ""
	_gpCellKey = ""
	if _gpEdit != null:
		_gpEdit.release_focus()
		_gpEdit.hide()
	if _gpMulti != null:
		_gpMulti.release_focus()
		_gpMulti.hide()
	gpCv.queue_redraw()


# Reposition the field over the label anchor in screen coordinates (canvas-local, since the
# LineEdit is a child of the canvas). Called on open; pan/zoom is frozen while editing, so the
# text never moves underneath it. The single conversion goes through the canvas port — see the
# coding rule in the file header.
# 把字段定位到标签锚点的屏幕坐标处（画布局部，因 LineEdit 是画布子节点）。打开时调用；
# 编辑期间平移/缩放被冻结，故文字不会移动到它下面。唯一一次换算走画布端口 —— 见文件头编码铁律。
func _gpReposition() -> void:
	if gpCv.gpGraph == null:
		return
	var gpN: GPPIDNode = gpCv.gpGraph.gpGetNode(_gpNodeId)
	if gpN == null:
		return
	var gpDef: GPSymbolDef = gpCv.gpDefFor(gpN.gpSymbolId)
	var gpRect: Rect2 = gpTextRectWorld(gpN, gpDef, gpCv.gpGraph, gpCv.gpDefLookupCallable())
	if gpRect.size == Vector2.ZERO:
		return
	var gpS: Vector2 = gpCv.gpScreenFromWorld(gpRect.get_center())
	# The multi-line field COVERS the envelope: its frame is the envelope's screen rect
	# (both corners through the one conversion port), so what you edit is what you see.
	# 多行字段**覆盖**包络：外框即包络的屏幕矩形（两角都走唯一换算端口），
	# 所见即所编。
	if _gpIsMulti and _gpMulti != null:
		_gpMulti.position = gpCv.gpScreenFromWorld(gpRect.position)
		_gpMulti.size = gpS * 2.0 - gpCv.gpScreenFromWorld(gpRect.position)
	elif _gpEdit != null:
		_gpEdit.position = gpS - _gpEdit.size * 0.5


# Enter commits. / 回车提交。
func _gpOnSubmitted(_gpText: String) -> void:
	_gpCommit()


# Focus lost: commit (the field is closing anyway). Guarded so an explicit gpClose() that also
# releases focus does not double-commit.
# 焦点离开：提交（字段本就要关闭）。加护栏，使显式 gpClose() 释放焦点时不会重复提交。
func _gpOnFocusExited() -> void:
	if _gpActive:
		_gpCommit()


# Write the typed content through the canvas port (one undo step) and close. Stage 2: the
# commit target follows the content source — a GENERATOR text block writes its gpProps key
# (GPEditService.gpSetProperty), everything else writes the tag. A refusal is reported through
# the FACADE the same way the tag path reports duplicates.
# 经画布端口写入键入的内容（一个撤销步）并关闭。阶段 2：提交目标跟随内容来源 —— GENERATOR
# 文本块写其 gpProps 键（GPEditService.gpSetProperty），其余写位号。拒绝原因与位号路径上报
# 重复位号的方式一致，经 **facade** 上报。
func _gpCommit() -> void:
	var gpId: String = _gpNodeId
	var gpText: String = ""
	# Read from the overlay this session actually opened, then end the session BEFORE the
	# commit writes (the focus-exit guard needs _gpActive == false to stay single-shot).
	# 从本次会话真正打开的浮层读文本，并在写入**之前**结束会话
	#（焦点离开护栏需要 _gpActive == false 才不会重复提交）。
	if _gpIsMulti and _gpMulti != null:
		gpText = _gpMulti.text
	elif _gpEdit != null:
		gpText = _gpEdit.text
	_gpIsMulti = false
	var gpCellKey: String = _gpCellKey
	_gpCellKey = ""
	_gpActive = false
	_gpNodeId = ""
	if gpCv.gpGraph != null and gpCv.gpGraph.gpGetNode(gpId) != null:
		var gpN: GPPIDNode = gpCv.gpGraph.gpGetNode(gpId)
		var gpDef: GPSymbolDef = gpCv.gpDefFor(gpN.gpSymbolId)
		var gpPropKey: String = GPSymbolGeneratorRegistry.gpTextPropKey(gpDef)
		var gpOk: bool = false
		if gpCellKey != "":
			# CELL path (stage 3): write the per-cell prop. An empty commit ERASES the key —
			# GPSetPropertyCommand's empty-means-reset rule — which is exactly "clear the cell".
			# 格子路径（阶段 3）：写逐格属性。空提交即**删键** —— GPSetPropertyCommand 的
			# 「空即复位」规则 —— 语义恰好是「清空该格」。
			gpOk = gpCv.gpRequestSetNodeProp(gpId, gpCellKey, gpText)
		elif gpPropKey != "":
			gpOk = gpCv.gpRequestSetNodeProp(gpId, gpPropKey, gpText)
		else:
			gpOk = gpCv.gpRequestSetNodeTag(gpId, gpText)
		if not gpOk:
			if gpCv.gpActions.gpLastRefusal != "":
				gpCv.gpEditFacade.gpReportRefusal(gpCv.gpActions.gpLastRefusal, "")
	gpCv.gpEmitStatus()
	if _gpEdit != null:
		_gpEdit.hide()
	if _gpMulti != null:
		_gpMulti.hide()
	gpCv.queue_redraw()
