extends "res://tests/gp_test.gd"
# Headless tests for the MOUNT-AWARE resolution + label slots (P1 of the 主图元 / 次级图元 feature).
# 主图元 / 次级图元功能 P1 —— 感知挂载的解析层 + 标签槽的 headless 测试。
#
# Three promises are guarded here / 此处守护三条承诺：
#   1. CLOSED UNDER REFACTOR: for an UNMOUNTED node every new world-space function returns exactly
#      what the old `node.position + gpPortLocalOriented(...)` arithmetic returned, so swapping the
#      resolver into canvas / pipes / snap / hit-test changed nothing for existing drawings.
#      **重构封闭**：未挂载节点下，每个新的世界坐标函数与旧的 `节点坐标 + 端口本地偏移` 完全相等，
#      故把解析器换进画布 / 管线 / 吸附 / 命中后，存量图纸行为不变。
#   2. OPEN FOR MOUNTING: for a MOUNTED child every one of those consumers now reads the position
#      DERIVED from the host chain, and the legacy formula is provably different — so the pins
#      cannot pass by accident.
#      **对挂载开放**：挂载子件的每个消费方都读到由宿主父链**推导**的位置，且旧公式可证不同 ——
#      故钉子不可能靠巧合通过。
#   3. LABEL SLOTS: a definition with slots renders N independent texts with their own anchor /
#      tier, and the tier maps onto the EXISTING text-height table (no new font size is invented).
#      **标签槽**：带槽的定义渲染 N 段独立文字，各带锚点 / 字高档，且字高档映射到**既有**字高表
#      （不发明新字号）。

const GP_EPS: float = 0.0001


# ---------------------------------------------------------------------------
# Fixtures / 夹具
# ---------------------------------------------------------------------------

# A 64x48 vessel: one process port on the right, one actuator socket on top.
# 一台 64x48 的容器：右侧一个工艺口、顶部一个执行机构插座。
func _gpHostDef() -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = "hx_mount_test"
	gpD.gpCategory = "tank"
	gpD.gpDefaultSize = Vector2(64.0, 48.0)
	var gpPorts: Array[GPPort] = []
	gpPorts.append(GPPort.gpMake("out", Vector2(1.0, 0.5), Vector2(1.0, 0.0), GPPort.GP_NOZZLE))
	gpD.gpPorts = gpPorts
	var gpAnchors: Array[GPAttachPoint] = []
	gpAnchors.append(GPAttachPoint.gpMake("top_actuator", Vector2(0.5, 0.0), Vector2(0.0, -1.0)))
	gpD.gpAttachPoints = gpAnchors
	return gpD


# A 16x16 actuator mounted on top: one SIGNAL port at its own top edge.
# 一台 16x16 的执行机构，装在顶部：自身顶边一个 SIGNAL 端口。
func _gpChildDef() -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = "act_mount_test"
	gpD.gpCategory = "instrument"
	gpD.gpDefaultSize = Vector2(16.0, 16.0)
	gpD.gpMountKind = "ACTUATOR"
	gpD.gpBaseMountRot = 90.0
	var gpPorts: Array[GPPort] = []
	gpPorts.append(GPPort.gpMake("sig", Vector2(0.5, 0.0), Vector2(0.0, -1.0), GPPort.GP_SIGNAL))
	gpD.gpPorts = gpPorts
	return gpD


# A port-less mountable child, so the "centre" degradation step can be exercised while mounted.
# 一个无端口但可挂载的子件，用于在挂载状态下演练「中心」降级阶梯。
func _gpPortlessChildDef() -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = "blank_mount_test"
	gpD.gpCategory = "general"
	gpD.gpDefaultSize = Vector2(10.0, 10.0)
	gpD.gpMountKind = "ACTUATOR"
	gpD.gpBaseMountRot = 90.0
	return gpD


func _gpLookup() -> Callable:
	return func(gpId: String) -> GPSymbolDef:
		if gpId == "hx_mount_test":
			return _gpHostDef()
		if gpId == "act_mount_test":
			return _gpChildDef()
		if gpId == "blank_mount_test":
			return _gpPortlessChildDef()
		if gpId == "noz_host_test":
			return _gpNozHostDef()
		if gpId == "noz_slot_test":
			return _gpSlotNozzleDef()
		return null


func _gpGraphOf(gpA: GPPIDNode, gpB: GPPIDNode = null) -> GPPIDGraph:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	if gpA != null:
		gpG.gpNodes.append(gpA)
	if gpB != null:
		gpG.gpNodes.append(gpB)
	return gpG


func _gpHost(gpAt: Vector2 = Vector2(100.0, 100.0)) -> GPPIDNode:
	var gpN: GPPIDNode = GPPIDNode.new()
	gpN.gpInstanceId = "host"
	gpN.gpSymbolId = "hx_mount_test"
	gpN.gpPosition = gpAt
	return gpN


func _gpChild(gpSymbolId: String = "act_mount_test", gpAnchor: String = "top_actuator") -> GPPIDNode:
	var gpN: GPPIDNode = GPPIDNode.new()
	gpN.gpInstanceId = "child"
	gpN.gpSymbolId = gpSymbolId
	gpN.gpParentUid = "host"
	gpN.gpMountAnchor = gpAnchor
	gpN.gpPosition = Vector2(999.0, 999.0)  # must be ignored while mounted / 挂载时必须被忽略
	return gpN


# ---------------------------------------------------------------------------
# Clause 1: closed under refactor (unmounted nodes are byte-identical)
# 第 1 条：重构封闭（未挂载节点完全等价）
# ---------------------------------------------------------------------------

func gpTestPortWorldMatchesLegacyArithmeticWhenUnmounted() -> void:
	var gpHost: GPPIDNode = _gpHost()
	var gpDef: GPSymbolDef = _gpHostDef()
	var gpPort: GPPort = gpDef.gpPortByName("out")
	var gpLegacy: Vector2 = gpHost.gpPosition \
		+ GPPortResolver.gpPortLocalOriented(gpDef, gpHost, gpPort)
	var gpNew: Vector2 = GPPortResolver.gpPortWorld(_gpGraphOf(gpHost), _gpLookup(), gpDef, gpHost,
		gpPort)
	gpApprox(gpNew.x, gpLegacy.x, GP_EPS, "an unmounted port's world x equals the legacy arithmetic")
	gpApprox(gpNew.y, gpLegacy.y, GP_EPS, "an unmounted port's world y equals the legacy arithmetic")
	gpApprox(gpNew.x, 132.0, GP_EPS, "the right-hand port sits 32 right of the centre")

	# The same must hold once the node is rotated and flipped — the ordering trap.
	# 旋转 + 翻转后同样必须成立 —— 这正是顺序陷阱所在。
	gpHost.gpRotationDeg = 90.0
	gpHost.gpFlipped = true
	var gpLegacy2: Vector2 = gpHost.gpPosition \
		+ GPPortResolver.gpPortLocalOriented(gpDef, gpHost, gpPort)
	var gpNew2: Vector2 = GPPortResolver.gpPortWorld(_gpGraphOf(gpHost), _gpLookup(), gpDef, gpHost,
		gpPort)
	gpApprox(gpNew2.x, gpLegacy2.x, GP_EPS, "a rotated+flipped unmounted port still matches (x)")
	gpApprox(gpNew2.y, gpLegacy2.y, GP_EPS, "a rotated+flipped unmounted port still matches (y)")

	var gpDirA: Vector2 = GPPortResolver.gpPortDirOriented(gpHost, gpPort)
	var gpDirB: Vector2 = GPPortResolver.gpPortWorldDir(_gpGraphOf(gpHost), _gpLookup(), gpHost,
		gpPort)
	gpApprox(gpDirB.x, gpDirA.x, GP_EPS, "an unmounted port's world normal matches the legacy one")


func gpTestNodeWorldOriginFastPathMatchesPosition() -> void:
	var gpHost: GPPIDNode = _gpHost(Vector2(7.0, 8.0))
	var gpG: GPPIDGraph = _gpGraphOf(gpHost)
	gpEq(GPPortResolver.gpNodeWorldOrigin(gpG, _gpLookup(), gpHost), Vector2(7.0, 8.0),
		"an unmounted node's world origin is its own position")
	gpEq(GPPortResolver.gpNodeWorldOrigin(gpG, _gpLookup(), null), Vector2.ZERO,
		"a null node degrades to the origin")


# ---------------------------------------------------------------------------
# Clause 2: open for mounting (every consumer reads the derived position)
# 第 2 条：对挂载开放（每个消费方都读到推导位置）
# ---------------------------------------------------------------------------

# The child sits 24 above the host centre and its own "sig" port is 8 above the child centre,
# so the derived port position is (100, 68) while the legacy formula would give (999, 991).
# 子件在宿主中心上方 24，其自身 "sig" 端点在子件中心上方 8，
# 故推导出的端口位置是 (100, 68)，而旧公式会给出 (999, 991)。
func gpTestMountedChildPortWorldIsDerivedNotStored() -> void:
	var gpHost: GPPIDNode = _gpHost()
	var gpChild: GPPIDNode = _gpChild()
	var gpG: GPPIDGraph = _gpGraphOf(gpHost, gpChild)
	var gpChildDef: GPSymbolDef = _gpChildDef()
	var gpSig: GPPort = gpChildDef.gpPortByName("sig")

	var gpLegacy: Vector2 = gpChild.gpPosition \
		+ GPPortResolver.gpPortLocalOriented(gpChildDef, gpChild, gpSig)
	var gpWorld: Vector2 = GPPortResolver.gpPortWorld(gpG, _gpLookup(), gpChildDef, gpChild, gpSig)
	gpApprox(gpWorld.x, 100.0, GP_EPS, "the mounted signal port follows its host in x")
	gpApprox(gpWorld.y, 68.0, GP_EPS, "the mounted signal port sits 32 above the host centre")
	gpCheck(absf(gpWorld.y - gpLegacy.y) > 100.0,
		"the legacy formula is provably different, so this pin cannot pass by accident")

	# The node's own world origin is derived too — that is what the snap "centre" step and the
	# view transform both read.
	# 节点自身的世界原点同样是推导的 —— 吸附的「中心」档与视图变换都读它。
	gpApprox(GPPortResolver.gpNodeWorldOrigin(gpG, _gpLookup(), gpChild).y, 76.0, GP_EPS,
		"the mounted child's world origin is 24 above the host centre")


func gpTestResolveEndUsesDerivedPositionForMountedChild() -> void:
	var gpHost: GPPIDNode = _gpHost()
	var gpChild: GPPIDNode = _gpChild()
	var gpG: GPPIDGraph = _gpGraphOf(gpHost, gpChild)
	var gpE: GPPIDEdge = GPPIDEdge.new()
	gpE.gpKind = GPPIDEdge.GP_SIGNAL
	gpE.gpFromRef = {"node_id": "child", "port_id": "sig"}
	var gpR: Dictionary = GPPortResolver.gpResolveEnd(gpG, _gpLookup(), gpE, true, GPPort.GP_SIGNAL)
	gpEq(str(gpR["why"]), "port", "an exact port id still resolves as 'port'")
	gpApprox((gpR["pos"] as Vector2).x, 100.0, GP_EPS, "a pipe end lands on the derived position (x)")
	gpApprox((gpR["pos"] as Vector2).y, 68.0, GP_EPS, "a pipe end lands on the derived position (y)")
	gpApprox((gpR["dir"] as Vector2).y, -1.0, GP_EPS, "the port normal is derived as well")


func gpTestResolveEndCentreFallsBackToDerivedOrigin() -> void:
	# A MOUNTED, PORT-LESS child: the ladder's step 3 must land on the derived origin, not on the
	# stored (and meaningless) gpPosition.
	# 一个**已挂载且无端口**的子件：阶梯第 3 级必须落在推导原点上，而非那个（无意义的）存储坐标。
	var gpHost: GPPIDNode = _gpHost()
	var gpChild: GPPIDNode = _gpChild("blank_mount_test")
	var gpG: GPPIDGraph = _gpGraphOf(gpHost, gpChild)
	var gpE: GPPIDEdge = GPPIDEdge.new()
	gpE.gpFromRef = {"node_id": "child", "port_id": ""}
	var gpR: Dictionary = GPPortResolver.gpResolveEnd(gpG, _gpLookup(), gpE, true, GPPort.GP_NOZZLE)
	gpEq(str(gpR["why"]), "center", "a port-less mounted child degrades to its centre")
	gpApprox((gpR["pos"] as Vector2).y, 76.0, GP_EPS,
		"the centre is the HOST-DERIVED origin, not the stored position")
	gpCheck((gpR["pos"] as Vector2).y != 999.0,
		"the stored (meaningless) position is provably not used")


func gpTestPortAnchorReadsDerivedPositions() -> void:
	var gpHost: GPPIDNode = _gpHost()
	var gpChild: GPPIDNode = _gpChild()
	var gpG: GPPIDGraph = _gpGraphOf(gpHost, gpChild)

	var gpHit: Vector2 = GPPortAnchor.gpPortWorldPos(gpG, _gpLookup(), "child", "sig")
	gpApprox(gpHit.x, 100.0, GP_EPS, "gpPortWorldPos resolves the mounted child in x")
	gpApprox(gpHit.y, 68.0, GP_EPS, "gpPortWorldPos resolves the mounted child in y")

	var gpAnchors: Array[Dictionary] = GPPortAnchor.gpAnchors(gpG, _gpLookup())
	gpEq(gpAnchors.size(), 2, "both the host's and the child's ports are offered as anchors")
	var gpFound: bool = false
	for gpA in gpAnchors:
		if str(gpA["port_id"]) == "sig":
			gpFound = true
			gpApprox((gpA["pos"] as Vector2).y, 68.0, GP_EPS,
				"the child's anchor is offered at its derived position")
	gpCheck(gpFound, "the mounted child's port is part of the anchor set")

	# The pick radius is screen-relative, so a zoomed-out sheet still hits.
	# 拾取半径与屏幕相关，故缩小的图纸仍能命中。
	var gpPick: Dictionary = GPPortAnchor.gpHitPort(gpG, _gpLookup(), Vector2(100.0, 68.0), 1.0)
	gpEq(str(gpPick.get("port_id", "")), "sig", "the hit-test finds the mounted child's port")


func gpTestSnapResolverSnapsAtDerivedPositions() -> void:
	var gpHost: GPPIDNode = _gpHost()
	var gpChild: GPPIDNode = _gpChild()
	var gpG: GPPIDGraph = _gpGraphOf(gpHost, gpChild)
	var gpTypes: Array[String] = []
	gpTypes.append(GPPort.GP_SIGNAL)
	var gpSnap: Dictionary = GPSnapResolver.gpSnap(gpG, _gpLookup(), Vector2(100.0, 68.0), 1.0,
		gpTypes)
	gpEq(str(gpSnap["kind"]), GPSnapResolver.GP_PORT, "a click on a mounted port snaps to a port")
	gpEq(str(gpSnap["port_id"]), "sig", "the snap reports the mounted child's port")
	gpApprox((gpSnap["pos"] as Vector2).y, 68.0, GP_EPS, "the snap position is the derived one")
	gpApprox((gpSnap["dir"] as Vector2).y, -1.0, GP_EPS, "the snap normal is derived too")

	# The node-CENTRE rung of the ladder must also read the derived origin. A port-less child is
	# used on purpose: with ports present the port rung wins first, so the centre rung would never
	# be exercised at all. (An empty wanted-types array means "any type", not "no ports".)
	# 吸附阶梯的「节点中心」一级同样必须读推导原点。此处**故意**用无端口子件：只要有端口，
	# 端口一级就先胜出，中心一级便永远演练不到。（空类型数组意为「任意类型」，而非「不要端口」。）
	var gpPortless: GPPIDNode = _gpChild("blank_mount_test")
	var gpG2: GPPIDGraph = _gpGraphOf(_gpHost(), gpPortless)
	var gpEmpty: Array[String] = []
	var gpOnChild: Dictionary = GPSnapResolver.gpSnap(gpG2, _gpLookup(), Vector2(100.0, 76.0),
		1.0, gpEmpty)
	gpEq(str(gpOnChild["kind"]), GPSnapResolver.GP_NODE,
		"a click on the derived origin snaps to a node centre")
	gpEq(str(gpOnChild["node_id"]), "child",
		"the node centre found is the mounted child, not its host")
	gpApprox((gpOnChild["pos"] as Vector2).y, 76.0, GP_EPS, "the node centre is the derived one")

	# …while the child's STALE stored position (999,999) must find nothing there at all: the
	# snap falls through to the grid. This is the negative half of the same proof.
	# ……而子件**陈旧**的存储坐标 (999,999) 在那里必须什么也找不到：吸附降级到网格。
	# 这是同一证明的反向一半。
	var gpNoNode: Dictionary = GPSnapResolver.gpSnap(gpG2, _gpLookup(), Vector2(999.0, 999.0),
		1.0, gpEmpty)
	gpEq(str(gpNoNode["kind"]), GPSnapResolver.GP_GRID,
		"a click on the stale stored position finds no node (proving derivation)")
	gpEq(str(gpNoNode["node_id"]), "", "the grid snap names no node")


func gpTestSymbolViewTransformUsesDerivedFrame() -> void:
	var gpHost: GPPIDNode = _gpHost()
	var gpChild: GPPIDNode = _gpChild()
	var gpG: GPPIDGraph = _gpGraphOf(gpHost, gpChild)
	var gpView: GPSymbolView = GPSymbolView.new()
	gpView.gpInit(gpChild, _gpChildDef(), gpG, _gpLookup())
	# gpInit reaches _gpUpdateTransform through the normal path, which is exactly what the binder
	# relies on — so this asserts the real call chain, not a hand-driven shortcut.
	# gpInit 经正常路径走到 _gpUpdateTransform，这正是绑定器所依赖的 —— 故此处断言的是真实调用链，
	# 而非手工驱动的捷径。
	gpApprox(gpView.position.x, 100.0, GP_EPS, "the view node sits at the derived world origin (x)")
	gpApprox(gpView.position.y, 76.0, GP_EPS, "the view node sits at the derived world origin (y)")
	gpView.free()

	var gpTop: GPSymbolView = GPSymbolView.new()
	gpTop.gpInit(gpHost, _gpHostDef(), gpG, _gpLookup())
	gpEq(gpTop.position, Vector2(100.0, 100.0),
		"an unmounted symbol's view still sits exactly at its own position")
	gpTop.free()


func gpTestPaintOrderPutsHostsBeforeChildren() -> void:
	var gpHost: GPPIDNode = _gpHost()
	var gpChild: GPPIDNode = _gpChild()
	var gpGrand: GPPIDNode = GPPIDNode.new()
	gpGrand.gpInstanceId = "grand"
	gpGrand.gpSymbolId = "blank_mount_test"
	gpGrand.gpParentUid = "child"
	gpGrand.gpMountAnchor = "top_actuator"
	var gpG: GPPIDGraph = GPPIDGraph.new()
	# Deliberately declared child-first, so a naive "graph order" implementation would fail.
	# 刻意按「子件在前」声明，使天真的「按图顺序」实现会失败。
	gpG.gpNodes.append(gpGrand)
	gpG.gpNodes.append(gpChild)
	gpG.gpNodes.append(gpHost)

	var gpBinder: GPGraphBinder = GPGraphBinder.new()
	gpBinder.gpGraph = gpG
	var gpOrder: Array[String] = gpBinder._gpPaintOrder()
	gpEq(gpOrder.size(), 3, "every node appears exactly once in the paint order")
	gpEq(gpOrder[0], "host", "the host is painted first")
	gpEq(gpOrder[1], "child", "the mounted child follows its host")
	gpEq(gpOrder[2], "grand", "the grandchild is painted last")
	gpBinder.free()


# ---------------------------------------------------------------------------
# Clause 3: label slots
# 第 3 条：标签槽
# ---------------------------------------------------------------------------

func gpTestLabelTextWithPropsExpandsPropertyTokens() -> void:
	var gpProps: Dictionary = {"nozzle_id": "N1", "nominal_size": "80"}
	gpEq(GPPropertyResolver.gpLabelTextWithProps("{prop:nozzle_id}", "N9", "nozzle", null, gpProps),
		"N1", "a {prop:<key>} token expands to the stored value")
	gpEq(GPPropertyResolver.gpLabelTextWithProps("{tag} / {prop:nominal_size}", "N9", "nozzle",
		null, gpProps), "N9 / 80", "tag and property tokens combine, exactly as a nozzle needs")
	gpEq(GPPropertyResolver.gpLabelTextWithProps("{prop:missing}", "N9", "nozzle", null, gpProps),
		"", "an unset property renders empty rather than leaving the literal token")
	gpEq(GPPropertyResolver.gpLabelTextWithProps("DN{prop:nominal_size}", "N9", "nozzle",
		null, gpProps), "DN80", "the DN slot reads DN80 once the nominal size exists")
	gpEq(GPPropertyResolver.gpLabelTextWithProps("DN{prop:nominal_size}", "N9", "nozzle",
		null, {"nozzle_id": "N1"}), "",
		"an unset nominal size darkens the whole DN slot — never a bare DN beside the nozzle")
	gpEq(GPPropertyResolver.gpLabelTextWithProps("", "N9", "nozzle", null, gpProps), "N9",
		"an empty format falls back to the default tag template")
	gpEq(GPPropertyResolver.gpLabelTextWithProps("{name}", "", "Feed Pump", null, gpProps),
		"Feed Pump", "the legacy {name} token keeps working")


func gpTestSlotTextUsesFormatAndShortMap() -> void:
	var gpDef: GPSymbolDef = GPSymbolDef.new()
	gpDef.gpId = "slot_test"
	var gpNode: GPPIDNode = GPPIDNode.new()
	gpNode.gpTag = "PV4712.02"
	gpNode.gpProps = {"fail_action": "FC 故障关"}

	var gpSlot: GPLabelSlot = GPLabelSlot.gpMake("fail_action", "{prop:fail_action}",
		GPLabelAnchor.GPAnchor.GP_RIGHT)
	gpSlot.gpShortMap = {"FC 故障关": "F.C.", "FO 故障开": "F.O."}
	gpEq(GPLabelGripOps.gpSlotText(gpNode, gpDef, gpSlot), "F.C.",
		"the canvas shows the SHORT code for a fail action")
	gpEq(str(gpNode.gpProps["fail_action"]), "FC 故障关",
		"the stored VALUE is untouched — the short code is display-only")

	# A nozzle's DN with no short map passes through verbatim.
	# 管口 DN 无短码表则原样透出。
	var gpDn: GPLabelSlot = GPLabelSlot.gpMake("dn", "{prop:nominal_size}",
		GPLabelAnchor.GPAnchor.GP_BELOW)
	gpNode.gpProps = {"nominal_size": "80"}
	gpEq(GPLabelGripOps.gpSlotText(gpNode, gpDef, gpDn), "80", "a DN renders verbatim")


func gpTestSlotVisibilityGuard() -> void:
	var gpDef: GPSymbolDef = GPSymbolDef.new()
	gpDef.gpId = "slot_test"
	var gpNode: GPPIDNode = GPPIDNode.new()
	var gpSlot: GPLabelSlot = GPLabelSlot.gpMake("fail_action", "{prop:fail_action}",
		GPLabelAnchor.GPAnchor.GP_RIGHT)
	gpSlot.gpVisibleWhen = "fail_action != 不适用"

	gpNode.gpProps = {"fail_action": "FC 故障关"}
	gpCheck(GPLabelGripOps.gpSlotVisible(gpNode, gpDef, gpSlot),
		"a slot shows when its guard's != condition holds")
	gpNode.gpProps = {"fail_action": "不适用"}
	gpCheck(not GPLabelGripOps.gpSlotVisible(gpNode, gpDef, gpSlot),
		"a slot hides when its guard's != condition fails")
	gpNode.gpProps = {}
	gpCheck(GPLabelGripOps.gpSlotVisible(gpNode, gpDef, gpSlot),
		"an unset property (empty string) satisfies '!= 不适用'")

	# An equality guard is a strict string comparison against the effective value, where an UNSET
	# property counts as the empty string — so it hides until the value matches exactly. Both
	# branches are pinned, otherwise a guard that always returned true would pass unnoticed.
	# 等值护栏是对生效取值做**严格字符串比较**，未设属性视作空串 —— 故在取值精确匹配前一直隐藏。
	# 两个分支都要钉住，否则「恒返回 true」的护栏会悄悄通过。
	var gpEqSlot: GPLabelSlot = GPLabelSlot.gpMake("k", "{tag}", GPLabelAnchor.GPAnchor.GP_BELOW)
	gpEqSlot.gpVisibleWhen = "fail_action == 不适用"
	gpCheck(not GPLabelGripOps.gpSlotVisible(gpNode, gpDef, gpEqSlot),
		"an == guard hides while the unset (empty) value does not match")
	gpNode.gpProps = {"fail_action": "不适用"}
	gpCheck(GPLabelGripOps.gpSlotVisible(gpNode, gpDef, gpEqSlot),
		"an == guard shows once the value matches exactly")
	gpNode.gpProps = {}
	var gpBad: GPLabelSlot = GPLabelSlot.gpMake("k2", "{tag}", GPLabelAnchor.GPAnchor.GP_BELOW)
	gpBad.gpVisibleWhen = "nonsense without an operator"
	gpCheck(GPLabelGripOps.gpSlotVisible(gpNode, gpDef, gpBad),
		"an unparsable guard is treated as visible, so a typo hides nothing")
	gpEq(GPLabelGripOps.gpSlotVisible(null, gpDef, gpSlot), true, "a null node hides nothing")


func gpTestSlotAnchorAndOffsetHonourPerNodeOverride() -> void:
	var gpDef: GPSymbolDef = GPSymbolDef.new()
	gpDef.gpId = "slot_test"
	gpDef.gpDefaultSize = Vector2(20.0, 20.0)
	var gpNode: GPPIDNode = GPPIDNode.new()
	var gpSlot: GPLabelSlot = GPLabelSlot.gpMake("nozzle_no", "{prop:nozzle_id}",
		GPLabelAnchor.GPAnchor.GP_ABOVE)
	gpEq(GPLabelGripOps.gpSlotAnchor(gpNode, gpDef, gpSlot), GPLabelAnchor.GPAnchor.GP_ABOVE,
		"without an override the slot's own anchor applies")
	var gpDefaultLocal: Vector2 = GPLabelGripOps.gpSlotOffsetLocal(gpNode, gpDef, gpSlot)
	gpCheck(gpDefaultLocal.y < 0.0, "an ABOVE slot sits above the symbol's centre")

	var gpOverride: Dictionary = {"anchor": GPLabelAnchor.GPAnchor.GP_LEFT}
	gpNode.gpLabelSlotOverrides = {"nozzle_no": gpOverride}
	gpEq(GPLabelGripOps.gpSlotAnchor(gpNode, gpDef, gpSlot), GPLabelAnchor.GPAnchor.GP_LEFT,
		"a per-node override wins over the definition's slot anchor")
	var gpOverridden: Vector2 = GPLabelGripOps.gpSlotOffsetLocal(gpNode, gpDef, gpSlot)
	gpCheck(gpOverridden.x < 0.0, "the overridden slot moves to the left of the symbol")
	gpCheck(absf(gpOverridden.x - gpDefaultLocal.x) > 1.0, "the override visibly moves the slot")

	# An override may also carry a normalised offset, given as an array (the JSON shape).
	# 覆盖也可以带归一化偏移，且以数组形态给出（即 JSON 形态）。
	gpNode.gpLabelSlotOverrides = {"nozzle_no": {"offset": [0.0, 0.5]}}
	gpEq(GPLabelGripOps.gpSlotOffset(gpNode, gpDef, gpSlot), Vector2(0.0, 0.5),
		"an array-shaped offset override is accepted")
	gpEq(GPLabelGripOps.gpSlotOffset(GPPIDNode.new(), gpDef, gpSlot), Vector2.ZERO,
		"a slot with no offset reports zero")


func gpTestSlotTierMapsOntoExistingTextTiers() -> void:
	gpApprox(GPTextRole.gpTierMM(GPLabelSlot.GP_TIER_INLINE, 3.0), GPTextRole.GP_INLINE_TAG_MM,
		GP_EPS, "the in-line tier maps onto the measured 3.0 mm in-line height")
	gpApprox(GPTextRole.gpTierMM(GPLabelSlot.GP_TIER_EQUIPMENT, 3.0), GPTextRole.GP_EQUIPMENT_TAG_MM,
		GP_EPS, "the equipment tier maps onto the measured 4.5 mm equipment height")
	gpApprox(GPTextRole.gpTierMM("unknown-tier", 3.0), GPTextRole.GP_INLINE_TAG_MM, GP_EPS,
		"an unknown tier falls back to the in-line height instead of inventing a size")
	# The ratio the standard fixes must survive an arbitrary user font size.
	# 标准固定的比例必须在任意用户字号下成立。
	gpApprox(GPTextRole.gpTierMM(GPLabelSlot.GP_TIER_EQUIPMENT, 4.0),
		GPTextRole.gpTierMM(GPLabelSlot.GP_TIER_INLINE, 4.0) * GPTextRole.GP_EQUIPMENT_SCALE,
		GP_EPS, "the two tiers keep the standard's 1.5 ratio at any base size")


func gpTestSlotHelpersAreNullSafe() -> void:
	var gpDef: GPSymbolDef = GPSymbolDef.new()
	gpEq(GPLabelGripOps.gpSlotText(null, gpDef, null), "", "a null node/slot yields no text")
	gpEq(GPLabelGripOps.gpSlotAnchor(GPPIDNode.new(), gpDef, null),
		GPLabelAnchor.GPAnchor.GP_BELOW, "a null slot falls back to the below anchor")
	# A null slot degrades to BELOW at zero offset — so the promise is "finite, never a crash / NaN",
	# NOT "zero": BELOW is by definition below the symbol's centre. Pinned against an EXPLICIT
	# below-anchored slot and against the sign of y, so it cannot pass by tautology.
	# 空槽降级为 BELOW、零偏移 —— 故承诺的是「有限、不崩溃/不 NaN」，而非「为零」：
	# BELOW 按定义就在符号中心下方。用**显式**below 锚点的真实槽与 y 的正负共同钉住，避免同义反复。
	var gpZeroBelow: GPLabelSlot = GPLabelSlot.gpMake("k", "{tag}", GPLabelAnchor.GPAnchor.GP_BELOW)
	var gpNullLocal: Vector2 = GPLabelGripOps.gpSlotOffsetLocal(null, gpDef, null)
	gpCheck(gpNullLocal.is_finite(), "a null slot yields a finite local offset")
	gpCheck(gpNullLocal.y > 0.0, "a null slot lands below the symbol, per its BELOW fallback")
	gpEq(gpNullLocal, GPLabelGripOps.gpSlotOffsetLocal(GPPIDNode.new(), gpDef, gpZeroBelow),
		"a null slot places exactly where an explicit below-anchored slot does")
	gpEq(GPLabelGripOps.gpSlotOffset(null, gpDef, null), Vector2.ZERO,
		"a null slot has no NORMALISED offset")
	var gpSlot: GPLabelSlot = GPLabelSlot.gpMake("k", "{tag}", GPLabelAnchor.GPAnchor.GP_BELOW)
	gpEq(GPLabelGripOps.gpSlotText(GPPIDNode.new(), null, gpSlot), "",
		"a tagless node with no definition yields no text")
	gpCheck(not GPLabelGripOps.gpSlotVisible(GPPIDNode.new(), gpDef, null),
		"a null slot is never visible")


# ---------------------------------------------------------------------------
# Slots that follow the MOUNT AXIS (P5 follow-up: the reported nozzle text layout)
# 随**安装轴**排布的槽（P5 收尾：用户报告的管嘴文字版式）
# ---------------------------------------------------------------------------

# A vessel with one socket facing UP and one facing LEFT, so the same part can be pinned in both
# orientations by a single fixture.
# 一台容器：一个朝上、一个朝左的插座，使同一部件可用一套夹具钉住两种朝向。
func _gpNozHostDef() -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = "noz_host_test"
	gpD.gpCategory = "tank"
	gpD.gpDefaultSize = Vector2(40.0, 40.0)
	var gpA: Array[GPAttachPoint] = []
	gpA.append(GPAttachPoint.gpMake("top", Vector2(0.5, 0.0), Vector2(0.0, -1.0),
		_gpStrTyped("NOZZLE")))
	gpA.append(GPAttachPoint.gpMake("left", Vector2(0.0, 0.5), Vector2(-1.0, 0.0),
		_gpStrTyped("NOZZLE")))
	gpD.gpAttachPoints = gpA
	return gpD


# A 4x2 NOZZLE that opts into mount-axis layout, carrying the two slots the reference drawing uses.
# 一支开启「随安装轴排布」的 4x2 管嘴，带参照图所用的两个文本槽。
func _gpSlotNozzleDef() -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = "noz_slot_test"
	gpD.gpCategory = "general"
	gpD.gpDefaultSize = Vector2(4.0, 2.0)
	gpD.gpMountKind = "NOZZLE"
	gpD.gpLabelFollowsMount = true
	var gpP: Array[GPPort] = []
	gpP.append(GPPort.gpMake("equip", Vector2(0.0, 0.5), Vector2(-1.0, 0.0)))
	gpP.append(GPPort.gpMake("pipe", Vector2(1.0, 0.5), Vector2(1.0, 0.0)))
	gpD.gpPorts = gpP
	var gpS: Array[GPLabelSlot] = []
	gpS.append(GPLabelSlot.gpMake("nozzle_no", "{prop:nozzle_id}",
		GPLabelAnchor.GPAnchor.GP_ABOVE))
	gpS.append(GPLabelSlot.gpMake("dn", "{prop:nominal_size}", GPLabelAnchor.GPAnchor.GP_BELOW))
	gpD.gpLabelSlots = gpS
	return gpD


# A genuine Array[String], so an anchor's accept list is not an untyped literal.
# 构造真正的 Array[String]，使锚点的接受表不是无类型字面量。
func _gpStrTyped(gpKind: String) -> Array[String]:
	var gpOut: Array[String] = []
	gpOut.append(gpKind)
	return gpOut


func _gpNozHost(gpAt: Vector2) -> GPPIDNode:
	var gpN: GPPIDNode = GPPIDNode.new()
	gpN.gpInstanceId = "nh"
	gpN.gpSymbolId = "noz_host_test"
	gpN.gpPosition = gpAt
	return gpN


func _gpNozChild(gpAnchor: String) -> GPPIDNode:
	var gpN: GPPIDNode = GPPIDNode.new()
	gpN.gpInstanceId = "nn"
	gpN.gpSymbolId = "noz_slot_test"
	gpN.gpParentUid = "nh"
	gpN.gpMountAnchor = gpAnchor
	gpN.gpPosition = Vector2(999.0, 999.0)  # must be ignored while mounted / 挂载时必须被忽略
	return gpN


func _gpNozGraph(gpAnchor: String) -> GPPIDGraph:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpNodes.append(_gpNozHost(Vector2(100.0, 100.0)))
	gpG.gpNodes.append(_gpNozChild(gpAnchor))
	return gpG


func gpTestNozzleSlotsTurnWithTheMountAxis() -> void:
	var gpLook: Callable = _gpLookup()
	var gpDef: GPSymbolDef = _gpSlotNozzleDef()
	var gpNo: GPLabelSlot = gpDef.gpLabelSlots[0]   # the number, authored ABOVE / 编号，本定义在上
	var gpDn: GPLabelSlot = gpDef.gpLabelSlots[1]   # the DN, authored BELOW / 公称直径，本定义在下

	# ---- VERTICAL mount (a riser on a vessel top): number LEFT, DN RIGHT ----
	# ---- 竖直安装（罐顶立管）：编号在左、公称直径在右 ----
	var gpGv: GPPIDGraph = _gpNozGraph("top")
	var gpNv: GPPIDNode = gpGv.gpGetNode("nn")
	gpEq(GPLabelGripOps.gpLabelQuarters(gpGv, gpLook, gpDef, gpNv), -1,
		"a nozzle standing on a vertical face turns its layout one quarter turn")
	gpEq(GPLabelGripOps.gpSlotAnchor(gpNv, gpDef, gpNo, gpGv, gpLook),
		GPLabelAnchor.GPAnchor.GP_LEFT, "the number moves to the LEFT of the riser")
	gpEq(GPLabelGripOps.gpSlotAnchor(gpNv, gpDef, gpDn, gpGv, gpLook),
		GPLabelAnchor.GPAnchor.GP_RIGHT, "the DN moves to the RIGHT of the riser")
	var gpNoV: Vector2 = GPLabelGripOps.gpSlotOffsetLocal(gpNv, gpDef, gpNo, gpGv, gpLook)
	var gpDnV: Vector2 = GPLabelGripOps.gpSlotOffsetLocal(gpNv, gpDef, gpDn, gpGv, gpLook)
	# The returned vector rides the VIEW frame, whose axes ARE the world's axes: the text node
	# never rotates (labels stay upright by design), so a world-side assertion reads it directly.
	# Rotating it "back" into the mount frame put the number on the riser's TIP — the user's
	# screenshot — which is exactly what this pin forbids.
	# 返回向量处于**视图系**，而视图系的轴就是世界的轴：文字节点从不旋转（标签按设计恒为正立），
	# 故世界侧别断言直接读它。若把向量「旋回」挂载系，编号会落到竖管端头 —— 即用户截图所示，
	# 正是本钉所禁止的。
	gpCheck(gpNoV.x < 0.0 and is_zero_approx(gpNoV.y),
		"the number sits purely to the LEFT of the riser, in the frame the renderer draws in")
	gpCheck(gpDnV.x > 0.0 and is_zero_approx(gpDnV.y),
		"the DN sits purely to the RIGHT of the riser")
	# The reported "too far" defect, numerically: half the riser's 2 mm WIDTH plus the 1 mm gap
	# (half the shorter side). The old local formula used the 4 mm LENGTH and put the number
	# 3 mm off centre against a 1 mm half-width.
	# 用户报告的「太远」缺陷，量化钉住：竖管 2mm **宽度**的一半加上 1mm 间距（短边的一半）。
	# 旧的本地公式用的是 4mm **长度**，把编号放到离中心 3mm 处，而半宽只有 1mm。
	gpApprox(gpNoV.x, -(2.0 * 0.5 + GPLabelGripOps.gpGapFor(Vector2(4.0, 2.0))), GP_EPS,
		"the number sits just off the riser, not a symbol-length away")

	# ---- HORIZONTAL mount (the same nozzle on a vessel side): number ABOVE, DN BELOW ----
	# ---- 水平安装（同一管嘴装在罐侧）：编号在上、公称直径在下 ----
	var gpGh: GPPIDGraph = _gpNozGraph("left")
	var gpNh: GPPIDNode = gpGh.gpGetNode("nn")
	gpEq(GPLabelGripOps.gpLabelQuarters(gpGh, gpLook, gpDef, gpNh), 0,
		"a nozzle on a horizontal face keeps the sheet-aligned layout")
	gpEq(GPLabelGripOps.gpSlotAnchor(gpNh, gpDef, gpNo, gpGh, gpLook),
		GPLabelAnchor.GPAnchor.GP_ABOVE, "the number stays ABOVE a horizontal nozzle")
	gpEq(GPLabelGripOps.gpSlotAnchor(gpNh, gpDef, gpDn, gpGh, gpLook),
		GPLabelAnchor.GPAnchor.GP_BELOW, "the DN stays BELOW a horizontal nozzle")
	var gpNoH: Vector2 = GPLabelGripOps.gpSlotOffsetLocal(gpNh, gpDef, gpNo, gpGh, gpLook)
	var gpDnH: Vector2 = GPLabelGripOps.gpSlotOffsetLocal(gpNh, gpDef, gpDn, gpGh, gpLook)
	gpCheck(gpNoH.y < 0.0 and is_zero_approx(gpNoH.x), "the number sits purely above")
	gpCheck(gpDnH.y > 0.0 and is_zero_approx(gpDnH.x), "the DN sits purely below")

	# ---- A symbol that does NOT opt in is untouched by all of this ----
	# ---- 未开启该开关的图元完全不受影响 ----
	var gpPlain: GPSymbolDef = _gpHostDef()
	gpEq(GPLabelGripOps.gpLabelQuarters(gpGh, gpLook, gpPlain, gpNh), 0,
		"a symbol that does not opt in never turns its layout")
	var gpAct: GPSymbolDef = _gpChildDef()
	gpEq(GPLabelGripOps.gpLabelQuarters(gpGh, gpLook, gpAct, gpGh.gpGetNode("nn")), 0,
		"an actuator mounted on the same host keeps its own layout, so no valve label tilts")
