extends "res://tests/gp_test.gd"
# Off-page CONNECTOR symbols (ADR-43 D3 / W12-S2).
# 跨图纸**连接符**图元（ADR-43 D3 / W12-S2）。
#
# The failure modes being guarded against: (1) the two family members render as the same generic
# rectangle in the palette and cannot be told apart (the 2026-10-17 text/table defect, repeated);
# (2) the reference text gets STORED instead of derived, so it goes stale the moment the peer
# sheet is renumbered; (3) the glyph and its port drift apart, so a pipe lands beside the flag
# instead of on it; (4) the canvas and the print model disagree, so paper shows a different
# reference than the screen.
# 所防范的失效模式：(1) 同族两个成员在图元库里画成同一个通用矩形、无法分辨（2026-10-17 的
# 文本/表格缺陷重演）；(2) 交叉编号被**存储**而非推导，故对端图号一重编就过期；(3) 字形与端口
# 分开，管线落在旗标旁边而不是落在其上；(4) 画布与打印模型不一致，纸面显示的编号与屏幕不同。

# The two ids, read from the pack so the test cannot drift from the definitions.
# 两个 id，取自图元包，使测试不可能与定义脱节。
const GP_ID_PIPE: String = GPSymbolPackOffpage.GP_ID_PIPE
const GP_ID_SIGNAL: String = GPSymbolPackOffpage.GP_ID_SIGNAL


func _gpDef(gpId: String) -> GPSymbolDef:
	for gpD in GPSymbolPackOffpage.gpDefs():
		if gpD.gpId == gpId:
			return gpD
	return null


# A connector node standing for a link end. gpProps carries ONLY the link id — the reference
# number is never a property (that is the whole rule being pinned here).
# 代表一个 link 端的连接符节点。gpProps **只**带 link id —— 交叉编号绝不是属性（这正是此处要钉的规则）。
static func _gpConnectorNode(gpNodeId: String, gpLinkId: String) -> GPPIDNode:
	var gpN: GPPIDNode = GPPIDNode.new()
	gpN.gpInstanceId = gpNodeId
	gpN.gpSymbolId = GP_ID_PIPE
	gpN.gpPosition = Vector2.ZERO
	if gpLinkId != "":
		gpN.gpProps[GPOffPageLink.GP_KEY_LINK_ID] = gpLinkId
	return gpN


# Two links' worth of container context: sheet-1 (node n1) <-> sheet-2 (node n2), tagged "3-1";
# plus an untagged link sheet-1 (node n3) <-> sheet-3 (node n4).
# 两套容器上下文：sheet-1(n1) ↔ sheet-2(n2) 带编号 "3-1"；以及未编号的 sheet-1(n3) ↔ sheet-3(n4)。
static func _gpContext() -> Array[GPOffPageLink]:
	var gpTagged: GPOffPageLink = GPOffPageLink.new()
	gpTagged.gpInstanceId = "xlink-1"
	gpTagged.gpKind = GPPIDEdge.GP_PROCESS
	gpTagged.gpA = {"sheet_id": "sheet-1", "node_id": "n1", "port_id": "ref"}
	gpTagged.gpB = {"sheet_id": "sheet-2", "node_id": "n2", "port_id": "ref"}
	gpTagged.gpTag = "3-1"
	var gpBare: GPOffPageLink = GPOffPageLink.new()
	gpBare.gpInstanceId = "xlink-2"
	gpBare.gpKind = GPPIDEdge.GP_SIGNAL
	gpBare.gpA = {"sheet_id": "sheet-1", "node_id": "n3", "port_id": "ref"}
	gpBare.gpB = {"sheet_id": "sheet-3", "node_id": "n4", "port_id": "ref"}
	var gpOut: Array[GPOffPageLink] = [gpTagged, gpBare]
	return gpOut


static func _gpNumbers() -> Dictionary:
	return {"sheet-1": "1", "sheet-2": "3", "sheet-3": "7"}


# The per-sheet graphs the DERIVED texts reach into: on sheet-2 the twin n2 is terminated by
# an edge from a tagged vessel ("T-101"), so the link's target tag is derivable; sheet-3's
# twin n4 has no edge yet (its served tag is honestly blank).
# **推导**文字所要探入的各图：sheet-2 上孪生体 n2 由一根来自带位号容器（"T-101"）的边终结，
# 故 link 的目标端位号可推导；sheet-3 的孪生体 n4 尚无边（其服务位号诚实地为空）。
static func _gpGraphs() -> Dictionary:
	var gpG2: GPPIDGraph = GPPIDGraph.new()
	gpG2.gpNodes.append(_gpConnectorNode("n2", "xlink-1"))
	var gpVessel: GPPIDNode = GPPIDNode.new()
	gpVessel.gpInstanceId = "v-101"
	gpVessel.gpSymbolId = "LTANK001"
	gpVessel.gpTag = "T-101"
	gpG2.gpNodes.append(gpVessel)
	gpG2.gpAddEdge(gpG2.gpNewEdge("e-1", "n2", "v-101"))
	var gpG3: GPPIDGraph = GPPIDGraph.new()
	gpG3.gpNodes.append(_gpConnectorNode("n4", "xlink-2"))
	return {"sheet-2": gpG2, "sheet-3": gpG3}


# Install the snapshot and make sure no assertion leaves it behind for the next suite.
# 安装快照，并确保没有任何断言把它留给后续套件。
func _gpInstallContext() -> void:
	GPOffPageIndex.gpSetContext(_gpContext(), _gpNumbers(), _gpGraphs())


func _gpClearContext() -> void:
	GPOffPageIndex.gpClear()


# Whether the outline's leftmost vertical span covers the box's mid height — the port's y.
# 轮廓最左侧的纵向跨度是否覆盖盒中高（端口所在 y）。
# Both silhouettes are required to satisfy this: the pennant for its full-height left edge, the
# hexagon for the apex that sits exactly at mid height.
# 两个轮廓都必须满足：旗标靠其整高左边，六边形靠恰好落在中高的那个尖点。
static func _gpLeftEdgeCoversMid(gpPts: Array, gpBox: Rect2) -> bool:
	var gpMid: float = gpBox.get_center().y
	var gpTop: float = 1e9
	var gpBottom: float = -1e9
	for gpPt in gpPts:
		var gpP: Array = gpPt as Array
		if absf(float(gpP[0]) - gpBox.position.x) < 0.001:
			gpTop = minf(gpTop, float(gpP[1]))
			gpBottom = maxf(gpBottom, float(gpP[1]))
	return gpTop <= gpMid + 0.001 and gpBottom >= gpMid - 0.001


# ---- the pack / 图元包 ------------------------------------------------

# Two symbols, both built-in, both generator-driven, two ports each (inbound ref + outbound
# cont) — process vs signal.
# 两个符号，均内置、均由生成器驱动、各两个端口（入站 ref + 出站 cont）—— 工艺与信号之分。
func gpTestPackCarriesTwoConnectors() -> void:
	var gpDefs: Array[GPSymbolDef] = GPSymbolPackOffpage.gpDefs()
	gpEq(gpDefs.size(), 2, "the off-page pack holds exactly two symbols")
	for gpD in gpDefs:
		gpEq(gpD.gpCategory, GPSymbolPackOffpage.GP_CATEGORY, "both belong to the offpage category")
		gpCheck(gpD.gpBuiltin, "library connectors are read-only built-ins: " + gpD.gpId)
		gpEq(gpD.gpGeometrySource,
			GPSymbolDef.GP_GEOMETRY_GENERATOR_PREFIX + "offpage",
			"the glyph AND the derived text come from one generator: " + gpD.gpId)
		gpCheck(gpD.gpShapes.is_empty(),
			"no static shapes — a second copy of the glyph would be free to drift: " + gpD.gpId)
		gpEq(gpD.gpPorts.size(), 2,
			"a connector has TWO halves — in through ref, out through cont: " + gpD.gpId)
		gpEq(gpD.gpPorts[0].gpName, GPSymbolPackOffpage.GP_PORT_NAME,
			"the inbound port keeps its declared name: " + gpD.gpId)
		gpEq(gpD.gpPorts[1].gpName, GPSymbolPackOffpage.GP_PORT_CONT,
			"the outbound port keeps its declared name: " + gpD.gpId)
		gpCheck(gpD.gpPortNamesUnique(), "port names unique: " + gpD.gpId)


# The port PURPOSE is the whole discrimination between the two: pipes take a NOZZLE connector,
# signal lines take a SIGNAL one. Pinned because the generator reads exactly this.
# 端口**用途**就是两者全部的区别：管道配 NOZZLE 连接符、信号线配 SIGNAL。之所以钉它，是因为生成器
# 读的正是这一项。
func gpTestPipeAndSignalPortsDiffer() -> void:
	var gpPipe: GPSymbolDef = _gpDef(GP_ID_PIPE)
	var gpSig: GPSymbolDef = _gpDef(GP_ID_SIGNAL)
	gpCheck(gpPipe != null and gpSig != null, "both connectors exist")
	if gpPipe == null or gpSig == null:
		return
	gpEq(gpPipe.gpPorts[0].gpType, GPPort.GP_NOZZLE, "the pipe connector takes process piping")
	gpEq(gpSig.gpPorts[0].gpType, GPPort.GP_SIGNAL, "the signal connector takes signal lines")
	# The port sits on the LEFT edge — the face the line leaves from, and the face the glyph
	# draws a full-height vertical on, so the dot lands ON the flag.
	# 端口位于**左**边缘 —— 管线离开的那一面，也是字形画出整高竖线的那一面，故圆点落在旗标**上**。
	for gpD in [gpPipe, gpSig]:
		gpApprox(gpD.gpPorts[0].gpPos.x, 0.0, 0.0001, "port on the left edge: " + gpD.gpId)
		gpApprox(gpD.gpPorts[0].gpPos.y, 0.5, 0.0001, "port at mid height: " + gpD.gpId)


# A connector is not equipment: it must never mint a project tag, never weld onto a vessel, and
# carry no mounting anchors.
# 连接符不是设备：绝不铸项目位号、绝不焊到容器上、也不带挂载锚点。
func gpTestConnectorIsNotEquipment() -> void:
	for gpD in GPSymbolPackOffpage.gpDefs():
		gpCheck(not gpD.gpTaggable, "no project tag for a connector: " + gpD.gpId)
		gpCheck(not gpD.gpMountable, "dropping one on a vessel must not mount it: " + gpD.gpId)
		gpCheck(gpD.gpAttachPoints.is_empty(), "a connector hosts nothing: " + gpD.gpId)


# Display names are i18n keys that resolve in BOTH languages — a raw English string would show
# up untranslated on a Chinese drawing (same rule the DEXPI pack obeys).
# 显示名是能同时解析中英的 i18n 键 —— 裸英文串会在中文图纸上裸奔（与 DEXPI 包同一规则）。
func gpTestConnectorDisplayNamesResolveBilingually() -> void:
	for gpD in GPSymbolPackOffpage.gpDefs():
		var gpZh: String = I18n.gpTrIn(gpD.gpDisplayName, "zh", gpD.gpDisplayName)
		var gpEn: String = I18n.gpTrIn(gpD.gpDisplayName, "en", gpD.gpDisplayName)
		gpCheck(gpZh != gpD.gpDisplayName, "chinese name resolves: " + gpD.gpDisplayName)
		gpCheck(gpEn != gpD.gpDisplayName, "english name resolves: " + gpD.gpDisplayName)


# The category table is what a USER connector created from "offpage" inherits, so it must list the
# same ports as the built-in pack — otherwise the built-in and the derived copy would accept
# different line kinds (the same pin the DEXPI pack carries).
# 类别表是「按 offpage 类别新建的用户连接符」所继承的端口，故必须与内置包列出的端口一致 —— 否则
# 内置件与派生副本接受不同种类的线（与 DEXPI 包所带的那条钉相同）。
func gpTestCategoryTableMirrorsPack() -> void:
	gpCheck(GPSymbolCategories.gpHasCategory(GPSymbolPackOffpage.GP_CATEGORY),
		"the offpage category exists in the nominal size table")
	var gpSize: Vector2 = GPSymbolCategories.gpSizeFor(GPSymbolPackOffpage.GP_CATEGORY)
	for gpD in GPSymbolPackOffpage.gpDefs():
		gpApprox(gpD.gpDefaultSize.x, gpSize.x, 0.0001,
			"envelope comes from the category table (x): " + gpD.gpId)
		gpApprox(gpD.gpDefaultSize.y, gpSize.y, 0.0001,
			"envelope comes from the category table (y): " + gpD.gpId)
		var gpFromTable: Array[Dictionary] = GPSymbolCategories.gpPortsForSymbol(gpD.gpId,
			gpD.gpCategory)
		gpEq(gpFromTable.size(), gpD.gpPorts.size(),
			"table and pack agree on the port count: " + gpD.gpId)
		if gpFromTable.is_empty() or gpD.gpPorts.is_empty():
			continue
		gpEq(str(gpFromTable[0].get("name", "")), gpD.gpPorts[0].gpName,
			"table and pack agree on the port name: " + gpD.gpId)
		gpEq(str(gpFromTable[0].get("type", "")), gpD.gpPorts[0].gpType,
			"table and pack agree on the port purpose: " + gpD.gpId)
	# The palette group needs a DISPLAY NAME: a raw category id printed in the dock (it did read
	# "offpage" before this was added) is a user-visible defect no geometry test would catch.
	# 图元库分组必须有**显示名**：停靠栏里印出裸类目 id（本行加之前就显示 "offpage"）是用户
	# 直接看到的缺陷，任何几何断言都抓不到。
	var gpCat: String = GPSymbolPackOffpage.GP_CATEGORY
	var gpLabels: Dictionary = I18n.GP_STRINGS.get(gpCat, {}) as Dictionary
	gpCheck(not gpLabels.is_empty(), "the offpage palette group has a display name")
	gpCheck(str(gpLabels.get("zh", "")) != gpCat,
		"the Chinese label is not the raw category id")


# The library actually registers the pack (a hand-written pack that nobody loads is dead code).
# 图元库确实加载了该包（没人加载的手写包就是死代码）。
func gpTestLibraryRegistersConnectors() -> void:
	for gpD in GPSymbolPackOffpage.gpDefs():
		var gpFound: GPSymbolDef = GPSymbolLibrary.gpFindById(gpD.gpId)
		gpCheck(gpFound != null, "the library resolves the connector id: " + gpD.gpId)
		gpCheck(GPSymbolLibrary.search("offpage").size() >= 2,
			"the palette search finds the offpage family: " + gpD.gpId)


# ---- the glyph / 字形 -------------------------------------------------

# The glyph fills the envelope EXACTLY and its left edge — where the port sits — is the
# envelope's left edge. Without this the uniform fit letterboxes the flag and the pipe's end
# floats beside it (the class of defect this pin exists for).
# 字形**恰好**填满包络，其左边缘（端口所在）即包络左边缘。缺了这一点，均匀适配会把旗标缩进包络
# 中部、管线尽头悬在旁边（本钉正是为这一类缺陷而生）。
func gpTestGlyphFillsEnvelopeAndPortSitsOnTheEdge() -> void:
	var gpDef: GPSymbolDef = _gpDef(GP_ID_PIPE)
	gpCheck(gpDef != null, "pipe connector exists")
	if gpDef == null:
		return
	var gpGen: Dictionary = GPSymbolGeneratorRegistry.gpGenerate(gpDef,
		_gpConnectorNode("n-cost", ""))
	var gpSpec: Dictionary = gpGen.get("spec", {}) as Dictionary
	gpCheck(not gpSpec.is_empty(), "the generator produces a glyph spec")
	if gpSpec.is_empty():
		return
	var gpBox: Rect2 = GPSymbolGeometry.gpUnitBox(gpSpec)
	var gpK: float = GPSymbolGeometry.gpFitScale(gpBox, gpDef.gpDefaultSize)
	# Width-filling: the unit box's aspect matches the envelope's by construction.
	# 按宽度贴合：单位框的长宽比按构造与包络一致。
	gpApprox(gpBox.size.x * gpK, gpDef.gpDefaultSize.x, 0.001,
		"the glyph spans the full envelope width (no letterboxing)")
	gpApprox(gpBox.size.y * gpK, gpDef.gpDefaultSize.y, 0.001,
		"the glyph spans the full envelope height (no letterboxing)")
	# The leftmost drawn geometry maps onto the envelope's left edge AND spans the port's height,
	# so the port dot sits ON the flag rather than beside it.
	# 最左侧的绘制几何映射到包络左边缘，且**跨过**端口的纵向位置，故端口圆点落在旗标**上**而非旁边。
	var gpPaths: Array = gpSpec.get("paths", []) as Array
	gpEq(gpPaths.size(), 1, "one outline path")
	var gpPts: Array = (gpPaths[0] as Dictionary).get("pts", []) as Array
	var gpMinX: float = 1e9
	for gpPt in gpPts:
		gpMinX = minf(gpMinX, float((gpPt as Array)[0]))
	var gpLocalLeft: float = (gpMinX - gpBox.get_center().x) * gpK
	gpApprox(gpLocalLeft, -gpDef.gpDefaultSize.x * 0.5, 0.001,
		"the drawn left edge IS the envelope's left edge (the port has geometry under it)")
	gpCheck(_gpLeftEdgeCoversMid(gpPts, gpBox), "the left edge spans the port's height: "
		+ str(gpPts))


# Two silhouettes, not one: the pennant points ONE way, the signal hexagon points BOTH ways.
# 两个轮廓而非一个：旗标**单向**，信号六边形**两端**皆尖。
func gpTestSilhouettesDiffer() -> void:
	var gpPipe: Dictionary = GPSymbolGeneratorRegistry.gpGenerate(_gpDef(GP_ID_PIPE),
		_gpConnectorNode("n-p", ""))
	var gpSig: Dictionary = GPSymbolGeneratorRegistry.gpGenerate(_gpDef(GP_ID_SIGNAL),
		_gpConnectorNode("n-s", ""))
	var gpPipePts: Array = ((gpPipe.get("spec", {}) as Dictionary).get("paths", []) as Array)
	var gpSigPts: Array = ((gpSig.get("spec", {}) as Dictionary).get("paths", []) as Array)
	gpEq(gpPipePts.size(), 1, "the pipe connector draws one closed outline")
	gpEq(gpSigPts.size(), 1, "the signal connector draws one closed outline")
	if gpPipePts.is_empty() or gpSigPts.is_empty():
		return
	var gpP: Array = (gpPipePts[0] as Dictionary).get("pts", []) as Array
	var gpS: Array = (gpSigPts[0] as Dictionary).get("pts", []) as Array
	gpEq(gpP.size(), 6, "pennant: five corners + the repeated closing point")
	gpEq(gpS.size(), 7, "hexagon: six corners + the repeated closing point")
	# Closed outline: the last point repeats the first (the painter does not close for us).
	# 闭合轮廓：末点复写首点（绘制器不会替我们闭合）。
	for gpPair in [[gpP, "pipe"], [gpS, "signal"]]:
		var gpList: Array = gpPair[0] as Array
		var gpFirst: Array = gpList[0] as Array
		var gpLast: Array = gpList[gpList.size() - 1] as Array
		gpApprox(float(gpLast[0]), float(gpFirst[0]), 0.0001,
			"outline is closed (x): " + str(gpPair[1]))
		gpApprox(float(gpLast[1]), float(gpFirst[1]), 0.0001,
			"outline is closed (y): " + str(gpPair[1]))
	# BOTH silhouettes must put geometry under the port at (0, mid) — the pennant through its
	# full-height left edge, the hexagon through its apex. A future shape change that moved the
	# left edge away from x=0 would float the pipe's end, which is exactly what this pins.
	# 两个轮廓都必须在端口 (0, 中高) 处有几何 —— 旗标靠整高左边，六边形靠其尖点。将来若改形状把左边
	# 从 x=0 挪开，管线尽头就会悬空，这正是本钉要防的。
	gpCheck(_gpLeftEdgeCoversMid(gpP, GPSymbolGeometry.gpUnitBox(
		gpPipe.get("spec", {}) as Dictionary)), "pennant: left edge covers the port height")
	gpCheck(_gpLeftEdgeCoversMid(gpS, GPSymbolGeometry.gpUnitBox(
		gpSig.get("spec", {}) as Dictionary)), "hexagon: its apex sits at the port")


# ---- the derived reference text / 推导出的交叉编号 ----------------------

# THREE states, none of them stored: unlinked (blank), dangling reference ("?"), resolved (tag or
# peer number).
# **三**态，一律不存储：未连线（空）、引用悬空（「?」）、已解析（tag 或对端图号）。
func gpTestRefTextHasThreeDerivedStates() -> void:
	_gpInstallContext()
	gpEq(GPOffPageIndex.gpRefTextFor(_gpConnectorNode("n-cost", "")), "",
		"an unlinked connector says nothing (a blank flag is honest)")
	gpEq(GPOffPageIndex.gpRefTextFor(_gpConnectorNode("n-cost", "xlink-404")),
		GPOffPageIndex.GP_UNRESOLVED_TEXT,
		"a dangling link_id is reported, not silently blank")
	gpEq(GPOffPageIndex.gpRefTextFor(_gpConnectorNode("n1", "xlink-1")), "3-1",
		"a link carrying a tag shows the tag (ADR-43 D4)")
	gpEq(GPOffPageIndex.gpRefTextFor(_gpConnectorNode("n3", "xlink-2")), "7",
		"an untagged link shows the PEER sheet's drawing number")
	gpEq(GPOffPageIndex.gpRefTextFor(null), "", "a null node degrades to empty")
	_gpClearContext()


# TEXT LAYOUT (user feedback 2026-11-03, refined the same day): ALL three slots derive or
# inherit — the peer drawing number INSIDE, the TARGET end's tag ABOVE (via the index, never
# stored), the medium BELOW (inherited from the source line into the link at creation).
# 文字版式（用户反馈 2026-11-03，同日细化）：三个槽位全部**推导或继承** —— 框内对端图纸号、
# 框上**目标端**位号（经索引，绝不存储）、框下介质（创建时从源管线继承进 link）。
func gpTestLegendInsideAboveBelow() -> void:
	_gpInstallContext()
	var gpLink: GPOffPageLink = GPOffPageIndex.gpLinkById("xlink-1")
	gpLink.gpAttrs = {GPOffPageLink.GP_ATTR_MEDIUM: "NAOH 32%"}
	var gpGen: Dictionary = GPSymbolGeneratorRegistry.gpGenerate(_gpDef(GP_ID_PIPE),
		_gpConnectorNode("n1", "xlink-1"))
	var gpLines: PackedStringArray = gpGen.get("text_lines",
		PackedStringArray()) as PackedStringArray
	gpEq(gpLines.size(), 1, "only ONE line lives inside the flag")
	gpEq(str(gpLines[0]), "3-1", "the derived reference is the inside line")
	gpEq(str(gpGen.get("text_above", "")), "T-101",
		"the TARGET end's tag rides ABOVE the flag, derived through the index")
	gpEq(str(gpGen.get("text_below", "")), "NAOH 32%",
		"the inherited medium rides BELOW the flag")
	# An unlinked connector keeps the three-slot SHAPE with nothing painted anywhere.
	# 未连线的连接符仍保持三槽的**形状**，只是处处皆空。
	var gpBare: Dictionary = GPSymbolGeneratorRegistry.gpGenerate(_gpDef(GP_ID_PIPE),
		_gpConnectorNode("n-cost", ""))
	var gpBareLines: PackedStringArray = gpBare.get("text_lines",
		PackedStringArray()) as PackedStringArray
	gpEq(gpBareLines.size(), 1, "even an unlinked connector keeps the one-line shape")
	gpEq(str(gpBare.get("text_above", "")), "", "its above slot is blank")
	gpEq(str(gpBare.get("text_below", "")), "", "its below slot is blank")
	_gpClearContext()


# The TARGET end's tag is a DERIVED quantity with its own states — never a stored attribute:
# a plain item end shows its own tag, a twin end shows the tag across ITS edge, an edgeless
# twin and anything unresolvable show nothing.
# **目标端**位号是**推导**量，有自己的状态集 —— 绝不是存储属性：普通对象端显示它自己的位号、
# 孪生体端显示横过它那条边的位号、无边的孪生体与一切无法解析者显示空。
func gpTestTargetTagIsDerivedNotStored() -> void:
	_gpInstallContext()
	# n1's link points at twin n2 on sheet-2, whose edge serves vessel "T-101".
	# n1 的 link 指向 sheet-2 上的孪生体 n2，后者的边服务于容器 "T-101"。
	gpEq(GPOffPageIndex.gpTargetTagFor(_gpConnectorNode("n1", "xlink-1")), "T-101",
		"the source connector derives the target tag across the twin's edge")
	# The twin shows the SAME tag — both ends of one link agree (one connection, one tag).
	# 孪生体显示**同一个**位号 —— 一条 link 的两端一致（一个连接、一个位号）。
	gpEq(GPOffPageIndex.gpTargetTagFor(_gpConnectorNode("n2", "xlink-1")), "T-101",
		"the twin derives the same target tag")
	# An edgeless twin: nothing to derive, nothing guessed.
	# 无边的孪生体：无可推导，绝不臆造。
	gpEq(GPOffPageIndex.gpTargetTagFor(_gpConnectorNode("n4", "xlink-2")), "",
		"an edgeless twin shows a blank slot")
	gpEq(GPOffPageIndex.gpTargetTagFor(_gpConnectorNode("n-cost", "")), "",
		"an unlinked connector shows a blank slot")
	gpEq(GPOffPageIndex.gpTargetTagFor(null), "", "a null node degrades to empty")
	_gpClearContext()


# MIRRORED TWIN, second round (user feedback 2026-11-03): the twin is minted UNFLIPPED now,
# but a user may still flip ANY connector by hand — the mirror itself is the BODY's transform
# (exactly ONE mirroring, positions and glyphs), so the generator must stay FLIP-AGNOSTIC — a
# second mirror in the paths would cancel the first and the flag would print unmirrored with
# its legend shoved off the body (caught by the visual probe, 2026-11-03).
# 镜像（用户反馈 2026-11-03 第二轮）：孪生体现以**不翻转**态创建，但用户仍可手动翻转**任何**
# 连接符 —— 镜像本身归 body 的变换所有（恰好**一次**镜像，位置与字形一起），故生成器必须对
# 翻转**无感** —— 路径里再镜像一次会与第一次相消，旗标将画成未镜像、图例被推离主体
#（2026-11-03 由视觉探针抓到）。
func gpTestGeneratorIsFlipAgnostic() -> void:
	var gpPlain: Dictionary = GPSymbolGeneratorRegistry.gpGenerate(_gpDef(GP_ID_PIPE),
		_gpConnectorNode("n-cost", ""))
	var gpNode: GPPIDNode = _gpConnectorNode("n-cost", "")
	gpNode.gpFlipped = true
	var gpFlip: Dictionary = GPSymbolGeneratorRegistry.gpGenerate(_gpDef(GP_ID_PIPE), gpNode)
	gpEq(gpFlip.get("text_center_u", 0.0), gpPlain.get("text_center_u", -1.0),
		"the text column is decided ONCE, not re-mirrored by the generator")
	var gpPlainPts: Array = ((gpPlain.get("spec", {}) as Dictionary).get("paths",
		[]) as Array)
	var gpFlipPts: Array = ((gpFlip.get("spec", {}) as Dictionary).get("paths",
		[]) as Array)
	gpEq(gpFlipPts.size(), gpPlainPts.size(), "the mirrored twin draws the same outlines")
	if gpPlainPts.is_empty() or gpFlipPts.is_empty():
		return
	var gpPlainList: Array = (gpPlainPts[0] as Dictionary).get("pts", []) as Array
	var gpFlipList: Array = (gpFlipPts[0] as Dictionary).get("pts", []) as Array
	gpEq(gpFlipList.size(), gpPlainList.size(), "the outlines have the same vertex count")
	for gpI in range(mini(gpPlainList.size(), gpFlipList.size())):
		var gpA: Array = gpPlainList[gpI] as Array
		var gpB: Array = gpFlipList[gpI] as Array
		gpCheck(absf(float(gpA[0]) - float(gpB[0])) < 0.0001
			and absf(float(gpA[1]) - float(gpB[1])) < 0.0001,
			"vertex %d is identical — the flip belongs to the body transform, not the data"
			% gpI)


# ADAPTIVE BODY WIDTH (user feedback 2026-11-03): the flag hugs its reference text — a
# resolved number makes the body wider than an empty one, a longer number wider still, and no
# flag ever outgrows its envelope. At EVERY width the port's left edge stays on geometry.
# 自适应主体宽（用户反馈 2026-11-03）：旗标紧贴编号 —— 有编号比空旗标宽、更长的编号更宽、
# 且任何旗标都不超出包络。任一宽度下端口的左缘都落在几何上。
func gpTestBodyWidthAdaptsToReferenceText() -> void:
	var gpBare: Dictionary = GPSymbolGeneratorRegistry.gpGenerate(_gpDef(GP_ID_PIPE),
		_gpConnectorNode("n-cost", ""))
	var gpBareW: float = _gpBodyWidthOf(gpBare)
	gpCheck(gpBareW > 0.0, "an empty flag still draws a body (never a sliver)")
	_gpInstallContext()
	var gpLink: GPOffPageLink = GPOffPageIndex.gpLinkById("xlink-1")
	var gpShort: Dictionary = GPSymbolGeneratorRegistry.gpGenerate(_gpDef(GP_ID_PIPE),
		_gpConnectorNode("n1", "xlink-1"))
	var gpShortW: float = _gpBodyWidthOf(gpShort)
	gpCheck(gpShortW > gpBareW,
		"a resolved number widens the body: %.2f vs %.2f" % [gpShortW, gpBareW])
	gpLink.gpTag = "10-12"
	var gpLong: Dictionary = GPSymbolGeneratorRegistry.gpGenerate(_gpDef(GP_ID_PIPE),
		_gpConnectorNode("n1", "xlink-1"))
	var gpLongW: float = _gpBodyWidthOf(gpLong)
	gpCheck(gpLongW > gpShortW, "a longer number widens the body further")
	var gpEnvX: float = _gpDef(GP_ID_PIPE).gpDefaultSize.x
	gpCheck(gpLongW <= gpEnvX + 0.001,
		"no body ever outgrows its envelope (%.2f <= %.2f)" % [gpLongW, gpEnvX])
	# The port stays on drawn geometry at EVERY width: the left edge remains full-height.
	# 任一宽度下端口都落在几何上：左缘恒为整高。
	var gpSpec: Dictionary = gpLong.get("spec", {}) as Dictionary
	var gpPaths: Array = gpSpec.get("paths", []) as Array
	gpEq(gpPaths.size(), 1, "the adaptive body is still one closed outline")
	if not gpPaths.is_empty():
		gpCheck(_gpLeftEdgeCoversMid((gpPaths[0] as Dictionary).get("pts", []) as Array,
			GPSymbolGeometry.gpUnitBox(gpSpec)),
			"the adaptive body keeps the port's left edge full-height")
	_gpClearContext()


# THE CONTINUATION PORT RIDES THE BODY TIP (user feedback 2026-11-03, 2nd round): the target
# twin reads left-to-right, so its served edge must leave from the pennant's TIP — for ANY
# reference width. The generator overrides the "cont" port's unit position per instance and
# the resolver maps it with the SAME envelope algebra; the expectation here is derived from
# the DRAWN body (the other side of that algebra), never from the override itself.
# **续接端口贴着主体旗尖**（用户反馈 2026-11-03 第二轮）：目标端孪生体读向从左到右，故其
# 「去往服务对象」的边必须从旗标的**尖部**出发 —— 对**任何**编号宽度皆然。生成器逐实例覆盖
# "cont" 端口的单位位置，解析器用**同一**包络代数映射；本测试的期望值从**画出的**主体
#（该代数的另一侧）推导，绝不从覆盖值本身抄。
func gpTestContPortRidesTheBodyTip() -> void:
	var gpDef: GPSymbolDef = _gpDef(GP_ID_PIPE)
	var gpEnvW: float = gpDef.gpDefaultSize.x
	# An UNLINKED connector: minimal body, and still exactly one override.
	# **未连线**的连接符：最小主体，且仍恰好一个覆盖。
	var gpNode: GPPIDNode = _gpConnectorNode("n-cost", "")
	var gpUnits: Dictionary = GPSymbolGeneratorRegistry.gpPortUnitOverrides(gpDef, gpNode)
	gpEq(gpUnits.size(), 1, "exactly one port is overridden")
	gpCheck((gpUnits as Dictionary).has(GPSymbolPackOffpage.GP_PORT_CONT),
		"the continuation port is the overridden one")
	var gpTipU: float = (gpUnits[GPSymbolPackOffpage.GP_PORT_CONT] as Vector2).x
	gpCheck(gpTipU > 0.0 and gpTipU < 0.5,
		"a short reference keeps the tip in the envelope's left half (%.3f)" % gpTipU)
	# Resolver: the local x offset == (tip - centre) * envelope width, where the tip is the
	# DRAWN body's right edge — derived via the fit algebra, not echoed from the override.
	# 解析器：本地 x 偏移 == (旗尖 - 中心) * 包络宽，旗尖即**画出的**主体右缘 —— 经适配代数
	# 推导，而非回显覆盖值。
	var gpBodyW: float = _gpBodyWidthOf(GPSymbolGeneratorRegistry.gpGenerate(gpDef, gpNode))
	var gpPort: GPPort = gpDef.gpPortByName(GPSymbolPackOffpage.GP_PORT_CONT)
	gpCheck(gpPort != null, "the pack declares the continuation port")
	if gpPort == null:
		return
	var gpLocal: Vector2 = GPPortResolver.gpPortLocalOriented(gpDef, gpNode, gpPort)
	gpApprox(gpLocal.x, gpBodyW - gpEnvW * 0.5, 0.01,
		"the cont port lands on the drawn tip (%.2f vs %.2f)"
		% [gpLocal.x, gpBodyW - gpEnvW * 0.5])
	gpApprox(gpLocal.y, 0.0, 0.001, "the cont port sits at mid height")
	# The INBOUND port is untouched — it stays on the drawn left edge.
	# **入站**端口原封不动 —— 恒在画出的左缘上。
	var gpRefLocal: Vector2 = GPPortResolver.gpPortLocalOriented(gpDef, gpNode,
		gpDef.gpPortByName(GPSymbolPackOffpage.GP_PORT_NAME))
	gpApprox(gpRefLocal.x, -gpEnvW * 0.5, 0.001,
		"the ref port stays on the left envelope edge")
	# A longer reference widens the body AND pushes the tip right with it, never out of the
	# envelope. / 更长的编号加宽主体、旗尖随之右移，但绝不越出包络。
	_gpInstallContext()
	var gpLink: GPOffPageLink = GPOffPageIndex.gpLinkById("xlink-1")
	gpLink.gpTag = "10-12"
	var gpLinkedNode: GPPIDNode = _gpConnectorNode("n1", "xlink-1")
	var gpLongTipU: float = (GPSymbolGeneratorRegistry.gpPortUnitOverrides(gpDef,
		gpLinkedNode)[GPSymbolPackOffpage.GP_PORT_CONT] as Vector2).x
	gpCheck(gpLongTipU > gpTipU, "a longer reference pushes the tip right")
	gpCheck(gpLongTipU <= 1.0, "the tip never leaves the envelope")
	_gpClearContext()


# The drawn body width of a generator result, in ENVELOPE mm: the outline's x-span times the
# spec box's uniform fit — the SAME algebra every consumer (view, print, palette) applies, so
# the pin reads the number the user actually sees.
# 生成器结果画出的主体宽（包络 mm）：轮廓 x 跨度 × spec 盒均匀适配 —— 与所有消费方
#（视图、打印、图元库）**同一**代数，故本钉读到的就是用户看到的数字。
func _gpBodyWidthOf(gpGen: Dictionary) -> float:
	var gpSpec: Dictionary = gpGen.get("spec", {}) as Dictionary
	var gpK: float = GPSymbolGeometry.gpFitScale(GPSymbolGeometry.gpUnitBox(gpSpec),
		_gpDef(GP_ID_PIPE).gpDefaultSize)
	var gpPaths: Array = gpSpec.get("paths", []) as Array
	if gpPaths.is_empty():
		return 0.0
	var gpMinX: float = 1e9
	var gpMaxX: float = -1e9
	for gpPt in (gpPaths[0] as Dictionary).get("pts", []) as Array:
		gpMinX = minf(gpMinX, float((gpPt as Array)[0]))
		gpMaxX = maxf(gpMaxX, float((gpPt as Array)[0]))
	return (gpMaxX - gpMinX) * gpK


# Each end shows the OTHER end's sheet — the flag must read "see the other sheet", never its own.
# 每一端显示**另一端**的图纸 —— 旗标必须读作「见另一张图」，绝不能是自己这张。
func gpTestEachEndShowsTheOtherSheet() -> void:
	_gpInstallContext()
	gpEq(GPOffPageIndex.gpPeerSheetNumberOf("n1"), "3", "end on sheet-1 points at sheet-2 (no 3)")
	gpEq(GPOffPageIndex.gpPeerSheetNumberOf("n2"), "1", "end on sheet-2 points back at sheet-1")
	gpEq(GPOffPageIndex.gpPeerSheetNumberOf("n9"), "",
		"a node that is in no link resolves to nothing")
	gpEq(GPOffPageIndex.gpSheetNumber("sheet-3"), "7", "the index answers sheet numbers")
	gpEq(GPOffPageIndex.gpSheetNumber(""), "", "an empty sheet id is not looked up")
	gpEq(GPOffPageIndex.gpSheetNumber("sheet-404"), "", "an unknown sheet has no number")
	_gpClearContext()


# The index is a SNAPSHOT: replacing the context must not mutate the caller's arrays, and
# clearing it must degrade to "unresolved" rather than to a stale answer.
# 索引是**快照**：替换上下文不得改动调用方的数组，清空后必须退化为「未解析」而不是给出陈旧答案。
func gpTestContextIsASnapshot() -> void:
	_gpInstallContext()
	var gpLinks: Array[GPOffPageLink] = _gpContext()
	gpEq(gpLinks.size(), 2, "the caller's own array is untouched by installing it")
	gpEq(GPOffPageIndex.gpLinkById("xlink-1") != null, true, "links are reachable by id")
	gpEq(GPOffPageIndex.gpLinkById(""), null, "an empty id matches nothing")
	_gpClearContext()
	gpEq(GPOffPageIndex.gpRefTextFor(_gpConnectorNode("n1", "xlink-1")),
		GPOffPageIndex.GP_UNRESOLVED_TEXT,
		"after clearing, a formerly resolved connector reports unresolved (never stale)")


# The text height is DECLARED BY THE GENERATOR and bounded by the flag, so both consumers
# (canvas + print model) read one number instead of two mirrored literals.
# 字高**由生成器声明**、由旗标定界，故两个消费方（画布 + 打印模型）读同一个数字，而不是两份镜像字面量。
func gpTestGeneratorDeclaresItsTextHeight() -> void:
	var gpGen: Dictionary = GPSymbolGeneratorRegistry.gpGenerate(_gpDef(GP_ID_PIPE),
		_gpConnectorNode("n-cost", ""))
	gpEq(float(gpGen.get("text_mm", 0.0)), GPTextRole.GP_OFFPAGE_REF_MM,
		"the generator declares the reference-number height")
	# User feedback 2026-11-03 (2nd round): the sheet glyph was too small and got DOUBLED —
	# the reference now reads LARGER than an in-line tag, a deliberate prominence for the
	# cross-sheet number.
	# 用户反馈 2026-11-03（第二轮）：图面字形太小、整体翻倍 —— 编号字高现在**大于**在管标注档，
	# 这是给跨图编号的刻意醒目。
	# Iron rule 86 guard: the two checks above compare against the SAME constant the generator
	# echoes, so on their own they only catch "the generator stopped declaring the key" (proved
	# by deleting it: exactly one assertion went red). This one derives the limit from the OTHER
	# side — the pack's envelope — so the flag can drift away from its defining proportion
	# (user feedback 2026-11-03: the flag is ~1.25x the reference text tall) without a red gate.
	# 铁律 86 防线：上面两条读的是生成器回显的**同一个**常量，单靠它们只能抓「生成器不再声明
	# 该键」（已用删除该键反验：恰好一条转红）。本条从**另一侧** —— 包的包络 —— 推导上限，
	# 使旗标偏离其定义性比例（用户反馈 2026-11-03：旗标高 ≈ 编号字高 1.25 倍）时门禁必红。
	var gpEnv: Vector2 = _gpDef(GP_ID_PIPE).gpDefaultSize
	gpApprox(gpEnv.y, GPTextRole.GP_OFFPAGE_REF_MM * 1.25, 0.01,
		"the flag is ~1.25x the reference text tall (not the old 3-line block)")
	# The note block and the table declare NO such key, so their sizing chain is untouched.
	# 备注块与表格**不**声明该键，故它们的换算链原封不动。
	for gpD in GPSymbolLibrary.gpDefaultDefs():
		if gpD.gpId == GPSymbolAnnotationTemplates.GP_TEXT_MULTILINE_ID:
			var gpNote: Dictionary = GPSymbolGeneratorRegistry.gpGenerate(gpD, GPPIDNode.new())
			gpCheck(not gpNote.has("text_mm"),
				"the note block keeps the annotation tier (no absolute override)")


# ---- screen vs paper / 屏幕与纸面 --------------------------------------

# The print model must carry BOTH the flag and the reference text — a connector that exports as a
# bare flag (or vanishes) is an incomplete drawing on paper.
# 打印模型必须同时带出旗标与交叉编号 —— 导出成光秃旗标（或整个消失）的连接符，在纸面上就是一张
# 不完整的图。
func gpTestPrintModelCarriesFlagAndReference() -> void:
	_gpInstallContext()
	var gpGraph: GPPIDGraph = GPPIDGraph.new()
	var gpNode: GPPIDNode = _gpConnectorNode("n1", "xlink-1")
	gpGraph.gpNodes.append(gpNode)
	var gpOut: Array[Dictionary] = []
	GPPrintModel.gpOneSymbol(gpGraph, Callable(self, "_gpPrintDef"), gpNode, gpOut)
	var gpPolys: int = 0
	var gpTexts: Array[String] = []
	for gpE in gpOut:
		match str(gpE.get("op", "")):
			GPPrintModel.GP_OP_POLY:
				gpPolys += 1
			GPPrintModel.GP_OP_TEXT:
				gpTexts.append(str(gpE.get("s", "")))
	gpCheck(gpPolys >= 1, "the flag reaches the paper as a polyline entity")
	gpCheck(gpTexts.has("3-1"), "the derived reference reaches the paper too, got %s" % [gpTexts])
	# The legend slots ride OUTSIDE the flag but must still reach the paper — an export that
	# silently dropped the outside slots would ship half a legend. The ABOVE slot is the
	# DERIVED target tag ("T-101" across the twin's edge on sheet-2), the BELOW slot the
	# inherited medium.
	# 图例槽位悬在旗标**外**，但同样必须落到纸面 —— 静默丢掉外部槽位的导出交出去的就是半份
	# 图例。**上**槽是**推导**的目标端位号（横过 sheet-2 上孪生体那条边得到的 "T-101"），
	# **下**槽是继承的介质。
	var gpL: GPOffPageLink = GPOffPageIndex.gpLinkById("xlink-1")
	gpL.gpAttrs = {GPOffPageLink.GP_ATTR_MEDIUM: "NAOH 32%"}
	var gpOut2: Array[Dictionary] = []
	GPPrintModel.gpOneSymbol(gpGraph, Callable(self, "_gpPrintDef"), gpNode, gpOut2)
	var gpTexts2: Array[String] = []
	for gpE in gpOut2:
		if str(gpE.get("op", "")) == GPPrintModel.GP_OP_TEXT:
			gpTexts2.append(str(gpE.get("s", "")))
	gpCheck(gpTexts2.has("T-101"), "the derived target tag ABOVE the flag reaches paper")
	gpCheck(gpTexts2.has("NAOH 32%"), "the inherited medium BELOW the flag reaches paper")
	_gpClearContext()


# Grading helper for the print model (the def lookup it takes as a callable).
# 打印模型（以可调用对象接收定义查找）所用的查找助手。
func _gpPrintDef(gpSymbolId: String) -> GPSymbolDef:
	return _gpDef(gpSymbolId)


# ---- palette / 图元库 -------------------------------------------------

# Both connectors classify as their OWN thumbnail kind and the bare-node spec is non-empty, so the
# palette draws the real flag instead of the generic grey rectangle.
# 两个连接符都归入自己的缩略图种类，且裸节点规格非空，故图元库画的是真旗标而非通用灰矩形。
func gpTestPaletteThumbKindIsOffpage() -> void:
	for gpD in GPSymbolPackOffpage.gpDefs():
		gpEq(GPSymbolPaletteItem.gpThumbKind(gpD), "offpage",
			"connector defs get their own thumbnail kind: " + gpD.gpId)
		var gpSpec: Dictionary = GPSymbolGeneratorRegistry.gpGenerate(gpD,
			GPPIDNode.new()).get("spec", {}) as Dictionary
		gpCheck(not gpSpec.is_empty(),
			"a BARE node still yields a glyph — the tile can never go blank: " + gpD.gpId)
