extends "res://tests/gp_test.gd"
# Rev.3 stage 1.5 (R1): the in-place NODE tag editor's pure logic.
# Rev.3 阶段 1.5（R1）：图元就地位号编辑器的**纯逻辑**。
#
# Only the pure half is pinned here (same split as GPLabelGripOps): WHICH nodes accept in-place
# tag editing, and WHERE the click target sits. The live LineEdit overlay mirrors GPEdgeTagEditor
# and needs a scene tree — the canvas wiring (port + dispatch order) is pinned by the
# wiring test at the bottom, which only checks STRUCTURE (members exist, port routes), not focus.
# 此处只钉**纯函数**半边（与 GPLabelGripOps 同一拆分）：哪些图元接受就地位号编辑、点击目标
# 在哪里。实时 LineEdit 浮层镜像 GPEdgeTagEditor、需要场景树 —— 画布接线（端口 + 分派）由
# 底部的接线测试钉住，只查**结构**（成员存在、端口可达），不碰焦点。

# A minimal tag-like definition (default format = "{tag}").
# 一个最小的位号型定义（默认格式即 "{tag}"）。
func _gpDef() -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = "DPUMP001"
	gpD.gpCategory = "pump"
	gpD.gpDefaultSize = Vector2(20.0, 12.0)
	return gpD


func _gpNode() -> GPPIDNode:
	var gpN: GPPIDNode = GPPIDNode.new()
	gpN.gpInstanceId = "N1"
	gpN.gpSymbolId = "DPUMP001"
	gpN.gpTag = "P-1001"
	gpN.gpPosition = Vector2(100.0, 100.0)
	return gpN


# ---- which nodes accept in-place editing / 哪些图元接受就地编辑 ----

func gpTestFormatIsTagLike() -> void:
	gpCheck(GPNodeTextEditor.gpFormatIsTagLike(null),
		"an unknown definition behaves like the default (tag)")
	var gpD: GPSymbolDef = _gpDef()
	gpCheck(GPNodeTextEditor.gpFormatIsTagLike(gpD), "the default format is tag-like")
	gpD.gpLabelFormat = "{tag}"
	gpCheck(GPNodeTextEditor.gpFormatIsTagLike(gpD), "an explicit {tag} is tag-like")
	gpD.gpLabelFormat = "{name}"
	gpCheck(not GPNodeTextEditor.gpFormatIsTagLike(gpD), "a name format is NOT")
	gpD.gpLabelFormat = "{tag} / {prop:dn}"
	gpCheck(not GPNodeTextEditor.gpFormatIsTagLike(gpD),
		"a compound format draws more than the tag, so it is NOT")


func gpTestWantsInPlaceFollowsLabelPath() -> void:
	var gpN: GPPIDNode = _gpNode()
	gpCheck(GPNodeTextEditor.gpWantsInPlace(gpN, _gpDef()),
		"single-label path + tag format => in-place editing is offered")
	gpCheck(not GPNodeTextEditor.gpWantsInPlace(null, _gpDef()), "no node, no editor")
	var gpD: GPSymbolDef = _gpDef()
	# A definition with label SLOTS draws several independent texts, none of which is simply
	# "the tag" — the double click must keep the dialog there.
	# 带文本槽的定义画的是**多段**独立文字，没有哪一段单纯「就是位号」——
	# 那里的双击必须保持对话框。
	var gpSlots: Array[GPLabelSlot] = [GPLabelSlot.gpMake("dn", "{prop:dn}",
		GPLabelAnchor.GPAnchor.GP_BELOW)]
	gpD.gpLabelSlots = gpSlots
	gpCheck(not GPNodeTextEditor.gpWantsInPlace(gpN, gpD), "slot-bearing definitions refuse in-place")


# ---- the click target / 点击目标 ----

func gpTestTextRectCoversTheAnchor() -> void:
	var gpN: GPPIDNode = _gpNode()
	var gpD: GPSymbolDef = _gpDef()
	# NOTE: headless stub-font metrics are wildly wrong in absolute terms (a tag has measured
	# hundreds of mm wide) — so this test pins STRUCTURE, never exact numbers.
	# 注意：headless 桩字体的绝对度量严重失真（一个位号曾量出数百 mm 宽）——
	# 故本测试只钉**结构**，绝不钉具体数字。
	var gpRect: Rect2 = GPNodeTextEditor.gpTextRectWorld(gpN, gpD)
	gpCheck(gpRect.size != Vector2.ZERO, "the tag path produces a hit rect")
	# The rect is centred on the LABEL ANCHOR (below the envelope by default), NOT on the node
	# position — the anchor point is what gpTextOrigin places the text around.
	# 矩形以**标签锚点**为中心（默认在包络下方），而不是节点原点 —— gpTextOrigin 正是
	# 绕锚点摆放文字的。
	var gpAnchorPos: Vector2 = GPLabelGripOps.gpWorldPos(gpN, gpD)
	gpCheck(gpRect.has_point(gpAnchorPos),
		"the label anchor (a centred anchor here) sits inside the rect")
	gpCheck(not gpRect.has_point(gpAnchorPos + Vector2(10000.0, 10000.0)),
		"a far-away point is a miss")


func gpTestTextRectRefusesNonTagLabels() -> void:
	var gpN: GPPIDNode = _gpNode()
	var gpD: GPSymbolDef = _gpDef()
	gpD.gpLabelFormat = "{name}"
	gpEq(GPNodeTextEditor.gpTextRectWorld(gpN, gpD).size, Vector2.ZERO,
		"a non-tag label builds NO hit rect (the double click keeps the dialog)")


# The select tool's R1 dispatch entry: the FIRST node whose editable text contains the point,
# declaration order. A non-tag-like label must NEVER be returned, or the double click would
# open the tag editor over text that is not the tag.
# 选择工具 R1 分派入口：文字包含该点的**第一个**节点（声明序）。非位号型的标签**绝不**返回，
# 否则双击会在「不是位号」的文字上打开位号编辑器。
func gpTestHitTextAnyDispatchesFirstMatch() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpA: GPPIDNode = _gpNode()
	gpA.gpInstanceId = "A"
	gpA.gpPosition = Vector2(0.0, 0.0)
	var gpB: GPPIDNode = _gpNode()
	gpB.gpInstanceId = "B"
	gpB.gpPosition = Vector2(200.0, 0.0)
	gpG.gpAddNode(gpA)
	gpG.gpAddNode(gpB)
	var gpDef: GPSymbolDef = _gpDef()
	# The anchor point of each label is inside its own rect (headless stub font makes the rect
	# huge, but never so huge that it swallows the OTHER node 200 mm away... except it CAN —
	# so resolve through each node's own anchor and assert only self-hits).
	# 各标签锚点必在自己的矩形内（headless 桩字体让矩形巨大，可能吞掉 200mm 外的邻件）——
	# 故逐节点用**自己的锚点**解析，只断言自命中。
	var gpHitA: String = GPNodeTextEditor.gpHitTextAny(gpG,
		func(_gpId: String) -> GPSymbolDef: return gpDef,
		GPLabelGripOps.gpWorldPos(gpA, gpDef, gpG, Callable()))
	gpEq(gpHitA, "A", "the point on A's text resolves to A")
	var gpHitB: String = GPNodeTextEditor.gpHitTextAny(gpG,
		func(_gpId: String) -> GPSymbolDef: return gpDef,
		GPLabelGripOps.gpWorldPos(gpB, gpDef, gpG, Callable()))
	gpEq(gpHitB, "B", "and B's text resolves to B")
	# A non-tag-like def makes the dispatch return "" for ANY point.
	# 非位号型定义下，任何点都返回 ""。
	var gpNameDef: GPSymbolDef = _gpDef()
	gpNameDef.gpLabelFormat = "{name}"
	gpEq(GPNodeTextEditor.gpHitTextAny(gpG,
		func(_gpId: String) -> GPSymbolDef: return gpNameDef,
		GPLabelGripOps.gpWorldPos(gpA, gpNameDef, gpG, Callable())), "",
		"a non-tag-like label is never dispatched")


# ---- canvas wiring / 画布接线 ----

func gpTestCanvasExposesEditorAndPort() -> void:
	var gpCv: GPCanvas2D = GPCanvas2D.new()
	# Off-tree the delegate is NULL — it is built in _ready, exactly like gpEdgeEditor. This is
	# the known headless fact (gp_test_canvas_ports), pinned here so nobody "fixes" it by
	# assuming _ready ran.
	# 树外时委托为 **null** —— 它在 _ready 中构建，与 gpEdgeEditor 完全一致。这是已知的
	# headless 事实（gp_test_canvas_ports），在此钉住，免得有人误以为 _ready 已运行而「修」它。
	gpCheck(gpCv.gpNodeEditor == null, "树外 gpNodeEditor 为 null（_ready 构建，与边编辑器一致）")
	# The commit port must still be null-safe off-tree: it routes through the facade (assembled
	# in _init) to the service, which refuses a node that does not exist — no script errors.
	# 提交端口在树外仍必须空安全：它经 facade（_init 装配）到服务，拒绝不存在的节点 —— 无脚本错误。
	gpCheck(not gpCv.gpRequestSetNodeTag("ghost", "X"),
		"the node-tag port routes to the service and refuses a missing node")
	gpCv.queue_free()
