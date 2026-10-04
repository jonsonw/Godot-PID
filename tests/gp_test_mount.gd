extends "res://tests/gp_test.gd"
# Headless tests for the MOUNT model (P0 of the 主图元 / 次级图元 feature).
# 主图元 / 次级图元功能 P0 —— 挂载模型的 headless 测试。
#
# Three promises are guarded here / 此处守护三条承诺：
#   1. BACKWARD COMPATIBILITY. A definition / node that carries no mounting data serialises
#      exactly as before, and a top-level node's world transform IS its own frame. Every
#      pre-mount caller can therefore swap in GPMountResolver untouched.
#      **向后兼容**。不含挂载数据的定义 / 节点序列化结果与之前完全一致；顶层节点的世界变换就是
#      它自身的坐标系。故每个挂载前的调用点都能无损换用 GPMountResolver。
#   2. DERIVATION, NOT STORAGE. A mounted child's world position is computed from the parent
#      chain; its own gpPosition is ignored. That is what makes a host's move carry its children.
#      **推导而非存储**。挂载子件的世界坐标由父链算出，其自身 gpPosition 被忽略。
#      这正是宿主移动能带走子件的原因。
#   3. NEVER FAILS. A missing host / anchor degrades along a documented ladder and never returns
#      Vector2.INF, so a stale anchor name misplaces a preview instead of crashing a drag.
#      **绝不失败**。缺失的宿主 / 锚点沿文档化阶梯降级，绝不返回 Vector2.INF，
#      故过期锚点名只会让预览错位，而不会让拖拽崩溃。

const GP_EPS: float = 0.0001


# ---------------------------------------------------------------------------
# Fixtures / 夹具
# ---------------------------------------------------------------------------

# Small helper that builds a genuine Array[String], avoiding untyped-literal coercion.
# 构造真正的 Array[String] 的小工具，规避无类型字面量的隐式转换。
func _gpStr(gpA: String, gpB: String = "", gpC: String = "") -> Array[String]:
	var gpOut: Array[String] = []
	if gpA != "":
		gpOut.append(gpA)
	if gpB != "":
		gpOut.append(gpB)
	if gpC != "":
		gpOut.append(gpC)
	return gpOut


# A 64x48 valve with two anchors: an actuator socket on top, a nozzle socket on the left.
# 一台 64x48 的阀门，带两个锚点：顶部执行机构插座、左侧管口插座。
func _gpHostDef() -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = "valve_mount_test"
	gpD.gpCategory = "valve"
	gpD.gpDefaultSize = Vector2(64.0, 48.0)
	var gpAnchors: Array[GPAttachPoint] = []
	gpAnchors.append(GPAttachPoint.gpMake("top_actuator", Vector2(0.5, 0.0), Vector2(0.0, -1.0)))
	gpAnchors.append(GPAttachPoint.gpMake("left_nozzle", Vector2(0.0, 0.5), Vector2(-1.0, 0.0)))
	gpD.gpAttachPoints = gpAnchors
	return gpD


# A 16x16 actuator: mountable (ACTUATOR) AND a carrier (it owns a "stem" socket), i.e. the
# "Both" classification from the plan §3.1.
# 一台 16x16 的执行机构：既可被挂载（ACTUATOR），又是载体（自带 "stem" 插座），
# 即规划 §3.1 的「Both」分类。
func _gpChildDef() -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = "actuator_mount_test"
	gpD.gpDefaultSize = Vector2(16.0, 16.0)
	gpD.gpMountKind = "ACTUATOR"
	gpD.gpBaseMountRot = 90.0
	var gpAnchors: Array[GPAttachPoint] = []
	gpAnchors.append(GPAttachPoint.gpMake("stem", Vector2(0.5, 1.0), Vector2(0.0, 1.0)))
	gpD.gpAttachPoints = gpAnchors
	return gpD


func _gpLookup() -> Callable:
	return func(gpId: String) -> GPSymbolDef:
		if gpId == "valve_mount_test":
			return _gpHostDef()
		if gpId == "actuator_mount_test":
			return _gpChildDef()
		return null


# Build a graph from up to four nodes, writing gpNodes directly (no signals, no side effects).
# 由至多四个节点构建图，直接写 gpNodes（不发信号、无副作用）。
func _gpGraphOf(gpA: GPPIDNode, gpB: GPPIDNode = null, gpC: GPPIDNode = null,
		gpD: GPPIDNode = null) -> GPPIDGraph:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	if gpA != null:
		gpG.gpNodes.append(gpA)
	if gpB != null:
		gpG.gpNodes.append(gpB)
	if gpC != null:
		gpG.gpNodes.append(gpC)
	if gpD != null:
		gpG.gpNodes.append(gpD)
	return gpG


func _gpHostNode(gpAt: Vector2 = Vector2(100.0, 100.0)) -> GPPIDNode:
	var gpN: GPPIDNode = GPPIDNode.new()
	gpN.gpInstanceId = "host"
	gpN.gpSymbolId = "valve_mount_test"
	gpN.gpPosition = gpAt
	return gpN


func _gpChildNode(gpParent: String = "host", gpAnchor: String = "top_actuator",
		gpId: String = "child") -> GPPIDNode:
	var gpN: GPPIDNode = GPPIDNode.new()
	gpN.gpInstanceId = gpId
	gpN.gpSymbolId = "actuator_mount_test"
	gpN.gpParentUid = gpParent
	gpN.gpMountAnchor = gpAnchor
	return gpN


# ---------------------------------------------------------------------------
# Definition-side round-trip / 定义侧往返
# ---------------------------------------------------------------------------

func gpTestAttachPointRoundTrip() -> void:
	var gpA: GPAttachPoint = GPAttachPoint.gpMake(
		"ves_bottom_nozzle", Vector2(0.5, 1.0), Vector2(0.0, 1.0),
		_gpStr("NOZZLE"), "DGENERAL008")
	gpA.gpMaxOccupancy = 1
	gpA.gpRequired = true
	var gpBack: GPAttachPoint = GPAttachPoint.new()
	gpBack.gpFromDict(gpA.gpToDict())
	gpEq(gpBack.gpName, "ves_bottom_nozzle", "the anchor name survives the round-trip")
	gpApprox(gpBack.gpPos.x, 0.5, GP_EPS, "the normalized anchor x survives")
	gpApprox(gpBack.gpPos.y, 1.0, GP_EPS, "the normalized anchor y survives (1.0 = bottom edge)")
	gpApprox(gpBack.gpDir.y, 1.0, GP_EPS, "the outward normal survives")
	gpEq(gpBack.gpAccepts.size(), 1, "the accept list survives")
	gpEq(gpBack.gpAccepts[0], "NOZZLE", "the accepted kind survives")
	gpEq(gpBack.gpDefaultChild, "DGENERAL008", "the default child survives")
	gpEq(gpBack.gpMaxOccupancy, 1, "the occupancy cap survives")
	gpEq(gpBack.gpRequired, true, "the required flag survives")


func gpTestAttachPointOmitsDefaults() -> void:
	var gpA: GPAttachPoint = GPAttachPoint.gpMake("plain", Vector2(0.5, 0.0), Vector2(0.0, -1.0))
	var gpD: Dictionary = gpA.gpToDict()
	gpEq(gpD.size(), 4, "a plain anchor serialises exactly name/pos/dir/accepts")
	gpCheck(not gpD.has("max_occupancy"), "a zero occupancy cap is omitted")
	gpCheck(not gpD.has("default_child"), "an empty default child is omitted")
	gpCheck(not gpD.has("required"), "a false required flag is omitted")
	# A hand-edited / truncated dict must still load through the get(key, default) rule.
	var gpBack: GPAttachPoint = GPAttachPoint.new()
	gpBack.gpFromDict({})
	gpEq(gpBack.gpName, "", "an empty dict still loads (never throws)")
	gpEq(gpBack.gpMaxOccupancy, 0, "a missing occupancy falls back to unlimited")
	gpEq(gpBack.gpAccepts.size(), 0, "a missing accept list falls back to empty (= accept any)")


func gpTestLabelSlotRoundTrip() -> void:
	var gpS: GPLabelSlot = GPLabelSlot.gpMake("nozzle_no", "{prop:nozzle_id}",
		GPLabelAnchor.GPAnchor.GP_ABOVE)
	gpEq(gpS.gpTier, GPLabelSlot.GP_TIER_INLINE, "a slot defaults to the in-line tier")
	var gpBack: GPLabelSlot = GPLabelSlot.new()
	gpBack.gpFromDict(gpS.gpToDict())
	gpEq(gpBack.gpKey, "nozzle_no", "the slot key survives")
	gpEq(gpBack.gpFormat, "{prop:nozzle_id}", "the value template survives")
	gpEq(gpBack.gpAnchor, GPLabelAnchor.GPAnchor.GP_ABOVE, "the slot anchor survives")
	gpEq(gpBack.gpTier, GPLabelSlot.GP_TIER_INLINE, "the tier survives")

	# The F.C. / F.O. case: a short-code map plus a visibility guard.
	var gpF: GPLabelSlot = GPLabelSlot.gpMake("fail_action", "{prop:fail_action}",
		GPLabelAnchor.GPAnchor.GP_RIGHT)
	gpF.gpShortMap = {"FC 故障关": "F.C."}
	gpF.gpVisibleWhen = "fail_action != 不适用"
	var gpF2: GPLabelSlot = GPLabelSlot.new()
	gpF2.gpFromDict(gpF.gpToDict())
	gpEq(str(gpF2.gpShortMap.get("FC 故障关", "")), "F.C.", "the short-code map survives")
	gpEq(gpF2.gpVisibleWhen, "fail_action != 不适用", "the visibility guard survives")

	# A slot on the default anchor must not carry a redundant "anchor" key.
	var gpP: GPLabelSlot = GPLabelSlot.gpMake("k", "{tag}", GPLabelAnchor.GPAnchor.GP_BELOW)
	gpCheck(not gpP.gpToDict().has("anchor"), "GP_BELOW is the default anchor and is omitted")
	gpCheck(not gpF.gpToDict().has("offset"), "a zero offset is omitted")


func gpTestSymbolDefMountRoundTrip() -> void:
	var gpDef: GPSymbolDef = GPSymbolDef.new()
	gpDef.gpId = "vessel_test"
	gpDef.gpMountKind = "NOZZLE"
	gpDef.gpBaseMountRot = 90.0
	var gpAnchors: Array[GPAttachPoint] = []
	gpAnchors.append(GPAttachPoint.gpMake("ves_stirrer", Vector2(0.5, 0.0), Vector2(0.0, -1.0)))
	gpDef.gpAttachPoints = gpAnchors
	var gpSlots: Array[GPLabelSlot] = []
	gpSlots.append(GPLabelSlot.gpMake("dn", "{prop:nominal_size}",
		GPLabelAnchor.GPAnchor.GP_BELOW))
	gpDef.gpLabelSlots = gpSlots
	var gpFit: Array[String] = []
	gpFit.append("ves_bottom_nozzle")
	gpDef.gpMountFit = gpFit

	var gpBack: GPSymbolDef = GPSymbolDef.new()
	gpBack.gpFromDict(gpDef.gpToDict())
	gpEq(gpBack.gpMountKind, "NOZZLE", "the mount kind survives")
	gpApprox(gpBack.gpBaseMountRot, 90.0, GP_EPS, "the canonical mount offset survives")
	gpEq(gpBack.gpMountFit.size(), 1, "the anchor whitelist survives")
	gpEq(gpBack.gpAttachPoints.size(), 1, "the anchor list survives")
	gpEq(gpBack.gpAttachPoints[0].gpName, "ves_stirrer", "the anchor name survives")
	gpEq(gpBack.gpLabelSlots.size(), 1, "the label slot list survives")
	gpEq(gpBack.gpLabelSlots[0].gpKey, "dn", "the label slot key survives")

	# Classification is DERIVED from the fields, never stored in an enum (plan §3.1).
	gpCheck(gpBack.gpIsCarrier(), "a symbol with anchors is a carrier")
	gpCheck(gpBack.gpIsMounted(), "a symbol with a mount kind is mountable")
	gpCheck(gpDef.gpAttachNamesUnique(), "anchor names are unique")
	gpCheck(gpDef.gpLabelSlotByKey("dn") != null, "a label slot is found by key")
	gpEq(gpDef.gpLabelSlotByKey("nope"), null, "an unknown slot key yields null")
	gpEq(gpDef.gpAttachPointByName("nope"), null, "an unknown anchor name yields null")


func gpTestSymbolDefDefaultsEmitNoMountKeys() -> void:
	var gpDef: GPSymbolDef = GPSymbolDef.new()
	gpDef.gpId = "plain_test"
	var gpD: Dictionary = gpDef.gpToDict()
	gpCheck(not gpD.has("attach_points"), "a carrier-less symbol writes no attach_points")
	gpCheck(not gpD.has("mount_kind"), "a non-mountable symbol writes no mount_kind")
	gpCheck(not gpD.has("mount_fit"), "an empty whitelist is not written")
	gpCheck(not gpD.has("base_mount_rot"), "a zero mount offset is not written")
	gpCheck(not gpD.has("label_slots"), "no slots means the single-label path stays intact")
	gpCheck(not gpDef.gpIsCarrier(), "a plain symbol is not a carrier")
	gpCheck(not gpDef.gpIsMounted(), "a plain symbol is not mountable")
	# Duplicate anchor names must be detectable — the invariant behind gpMountAnchor.
	var gpTwo: Array[GPAttachPoint] = []
	gpTwo.append(GPAttachPoint.gpMake("dup", Vector2(0.5, 0.0)))
	gpTwo.append(GPAttachPoint.gpMake("dup", Vector2(0.5, 1.0)))
	gpDef.gpAttachPoints = gpTwo
	gpCheck(not gpDef.gpAttachNamesUnique(), "duplicate anchor names are detected")


# ---------------------------------------------------------------------------
# Instance-side round-trip / 实例侧往返
# ---------------------------------------------------------------------------

func gpTestNodeMountRoundTrip() -> void:
	var gpN: GPPIDNode = _gpChildNode("host1", "top_actuator", "c1")
	gpN.gpMountOffset = Vector2(1.5, -2.0)
	gpN.gpMountAngleDeg = 15.0
	var gpOverride: Dictionary = {"anchor": GPLabelAnchor.GPAnchor.GP_LEFT}
	gpN.gpLabelSlotOverrides = {"fail_action": gpOverride}
	var gpD: Dictionary = gpN.gpToDict()
	gpCheck(gpD.has("parent_uid"), "a mounted node writes its host reference")
	gpCheck(gpD.has("mount_anchor"), "a mounted node writes its anchor name")
	var gpBack: GPPIDNode = GPPIDNode.new()
	gpBack.gpFromDict(gpD)
	gpEq(gpBack.gpParentUid, "host1", "the host uid survives")
	gpEq(gpBack.gpMountAnchor, "top_actuator", "the anchor name survives")
	gpApprox(gpBack.gpMountOffset.x, 1.5, GP_EPS, "the fine-tune offset x survives")
	gpApprox(gpBack.gpMountOffset.y, -2.0, GP_EPS, "the fine-tune offset y survives")
	gpApprox(gpBack.gpMountAngleDeg, 15.0, GP_EPS, "the extra mount angle survives")
	gpEq(int(gpBack.gpLabelSlotOverrides.get("fail_action", {}).get("anchor", -1)),
		GPLabelAnchor.GPAnchor.GP_LEFT, "a per-node slot override survives")
	gpCheck(gpBack.gpIsMounted(), "a node with a host uid reports itself as mounted")


func gpTestNodeUnmountedEmitsNoMountKeys() -> void:
	var gpN: GPPIDNode = GPPIDNode.new()
	gpN.gpInstanceId = "plain"
	var gpD: Dictionary = gpN.gpToDict()
	gpCheck(not gpD.has("parent_uid"), "an unmounted node writes no host reference")
	gpCheck(not gpD.has("mount_anchor"), "an unmounted node writes no anchor")
	gpCheck(not gpD.has("mount_offset"), "an unmounted node writes no offset")
	gpCheck(not gpD.has("mount_angle_deg"), "an unmounted node writes no mount angle")
	gpCheck(not gpD.has("label_slots"), "an unmounted node writes no slot overrides")
	gpCheck(not gpN.gpIsMounted(), "a plain node is not mounted")
	# A stray nudge with no host is meaningless and must never leak into the archive.
	var gpM: GPPIDNode = GPPIDNode.new()
	gpM.gpMountOffset = Vector2(3.0, 3.0)
	gpCheck(not gpM.gpToDict().has("mount_offset"),
		"a nudge without a host is meaningless and is not written")


# ---------------------------------------------------------------------------
# World transform / 世界变换
# ---------------------------------------------------------------------------

func gpTestWorldTransformTopLevelIsOwnFrame() -> void:
	var gpHost: GPPIDNode = _gpHostNode()
	gpHost.gpRotationDeg = 30.0
	gpHost.gpFlipped = true
	var gpWT: Dictionary = GPMountResolver.gpWorldTransform(_gpGraphOf(gpHost), _gpLookup(), gpHost)
	gpEq(gpWT["origin"], Vector2(100.0, 100.0),
		"an unmounted node's world origin IS its own position (pre-mount behaviour preserved)")
	gpApprox(float(gpWT["rot_deg"]), 30.0, GP_EPS, "an unmounted node keeps its own rotation")
	gpEq(bool(gpWT["flipped"]), true, "an unmounted node keeps its own flip")
	# A null node / null graph must degrade, not throw.
	var gpNullWT: Dictionary = GPMountResolver.gpWorldTransform(null, Callable(), null)
	gpEq(gpNullWT["origin"], Vector2.ZERO, "a null node resolves to a drawable origin")
	gpCheck(gpNullWT["origin"] != Vector2.INF, "a null node never yields Vector2.INF")


func gpTestWorldTransformDerivesAndIgnoresOwnPosition() -> void:
	var gpHost: GPPIDNode = _gpHostNode()
	var gpChild: GPPIDNode = _gpChildNode()
	# A deliberately absurd own position: a mounted child must IGNORE it (derived, never stored).
	# 故意给一个荒谬的自身坐标：挂载子件必须**忽略**它（推导而非存储）。
	gpChild.gpPosition = Vector2(999.0, 999.0)
	var gpWT: Dictionary = GPMountResolver.gpWorldTransform(_gpGraphOf(gpHost, gpChild),
		_gpLookup(), gpChild)
	gpApprox((gpWT["origin"] as Vector2).x, 100.0, GP_EPS,
		"a mounted child ignores its own x (derived from the host)")
	gpApprox((gpWT["origin"] as Vector2).y, 76.0, GP_EPS,
		"top_actuator sits 24 above the host centre of a 48-tall envelope")
	gpApprox(float(gpWT["rot_deg"]), 0.0, GP_EPS,
		"an up-facing anchor plus a +90 canonical offset yields an upright actuator")
	gpEq(bool(gpWT["flipped"]), false, "an unflipped host leaves the child unflipped")


func gpTestWorldTransformChildFollowsHostMove() -> void:
	var gpHost: GPPIDNode = _gpHostNode()
	var gpChild: GPPIDNode = _gpChildNode()
	var gpG: GPPIDGraph = _gpGraphOf(gpHost, gpChild)
	var gpBefore: Dictionary = GPMountResolver.gpWorldTransform(gpG, _gpLookup(), gpChild)
	# Move the host only. The child has no code of its own to run — this is the whole point.
	# 只移动宿主。子件没有任何自己的代码要跑 —— 这正是关键所在。
	gpHost.gpPosition = Vector2(300.0, 400.0)
	var gpAfter: Dictionary = GPMountResolver.gpWorldTransform(gpG, _gpLookup(), gpChild)
	gpApprox((gpAfter["origin"] as Vector2).x - (gpBefore["origin"] as Vector2).x, 200.0, GP_EPS,
		"the child inherits the host's x move exactly")
	gpApprox((gpAfter["origin"] as Vector2).y - (gpBefore["origin"] as Vector2).y, 300.0, GP_EPS,
		"the child inherits the host's y move exactly")
	gpApprox((gpAfter["origin"] as Vector2).y, 376.0, GP_EPS,
		"the child ends 24 above the host's new centre")


func gpTestWorldTransformRotatedHostCarriesChild() -> void:
	var gpHost: GPPIDNode = _gpHostNode()
	gpHost.gpRotationDeg = 90.0
	var gpChild: GPPIDNode = _gpChildNode()
	var gpWT: Dictionary = GPMountResolver.gpWorldTransform(_gpGraphOf(gpHost, gpChild),
		_gpLookup(), gpChild)
	# Rotating the host 90 degrees swings the top anchor to the host's right-hand side.
	# 宿主旋转 90 度后，顶部锚点摆到宿主右侧。
	gpApprox((gpWT["origin"] as Vector2).x, 124.0, GP_EPS,
		"rotating the host 90 deg swings the anchor 24 to the right")
	gpApprox((gpWT["origin"] as Vector2).y, 100.0, GP_EPS,
		"the anchor stays level with the host centre")
	gpApprox(float(gpWT["rot_deg"]), 90.0, GP_EPS,
		"the child inherits the host rotation (anchor normal now points +X)")


func gpTestWorldTransformFlippedHostMirrorsChild() -> void:
	var gpHost: GPPIDNode = _gpHostNode()
	gpHost.gpFlipped = true
	var gpChild: GPPIDNode = _gpChildNode("host", "left_nozzle")
	var gpWT: Dictionary = GPMountResolver.gpWorldTransform(_gpGraphOf(gpHost, gpChild),
		_gpLookup(), gpChild)
	# left_nozzle lives at local (-32, 0); mirroring the host must move it to (+32, 0).
	# left_nozzle 本地在 (-32, 0)；镜像宿主后必须移到 (+32, 0)。
	gpApprox((gpWT["origin"] as Vector2).x, 132.0, GP_EPS,
		"a flipped host mirrors the left anchor to the right side")
	gpApprox((gpWT["origin"] as Vector2).y, 100.0, GP_EPS, "mirroring does not move the anchor down")
	gpEq(bool(gpWT["flipped"]), true,
		"flipping the host flips the whole assembly (parity of host and child)")


func gpTestGrandchildChainsThroughParentChain() -> void:
	var gpHost: GPPIDNode = _gpHostNode()
	var gpChild: GPPIDNode = _gpChildNode()
	var gpGrand: GPPIDNode = _gpChildNode("child", "stem", "grand")
	var gpWT: Dictionary = GPMountResolver.gpWorldTransform(
		_gpGraphOf(gpHost, gpChild, gpGrand), _gpLookup(), gpGrand)
	# child sits at (100, 76) upright; its "stem" anchor is 8 below its own centre.
	# child 直立落在 (100, 76)；其 "stem" 锚点在自身中心下方 8。
	gpApprox((gpWT["origin"] as Vector2).x, 100.0, GP_EPS, "a grandchild chains through two hosts")
	gpApprox((gpWT["origin"] as Vector2).y, 84.0, GP_EPS,
		"the grandchild adds its own anchor offset to the child's frame")
	gpApprox(float(gpWT["rot_deg"]), 180.0, GP_EPS,
		"a down-facing anchor flips the child 180 deg from the up-facing case")


func gpTestAnchorDirToRotationAxisPairs() -> void:
	gpApprox(GPMountResolver.gpAnchorDirToRotation(Vector2(0.0, -1.0), 0.0), -90.0, GP_EPS,
		"an up-facing anchor reads -90 degrees")
	gpApprox(GPMountResolver.gpAnchorDirToRotation(Vector2(0.0, 1.0), 0.0), 90.0, GP_EPS,
		"a down-facing anchor reads +90 degrees")
	gpApprox(GPMountResolver.gpAnchorDirToRotation(Vector2(1.0, 0.0), 0.0), 0.0, GP_EPS,
		"a right-facing anchor reads 0 degrees")
	gpApprox(GPMountResolver.gpAnchorDirToRotation(Vector2(-1.0, 0.0), 0.0), 180.0, GP_EPS,
		"a left-facing anchor reads 180 degrees")
	# The invariant a symbol author relies on: opposite anchors differ by exactly 180 degrees.
	# 图元作者依赖的不变式：相对的两个锚点恰好相差 180 度。
	var gpUp: float = GPMountResolver.gpAnchorDirToRotation(Vector2(0.0, -1.0), 45.0)
	var gpDown: float = GPMountResolver.gpAnchorDirToRotation(Vector2(0.0, 1.0), 45.0)
	gpApprox(absf(gpDown - gpUp), 180.0, GP_EPS, "up and down anchors differ by exactly 180 deg")
	var gpLeft: float = GPMountResolver.gpAnchorDirToRotation(Vector2(-1.0, 0.0), 45.0)
	var gpRight: float = GPMountResolver.gpAnchorDirToRotation(Vector2(1.0, 0.0), 45.0)
	gpApprox(absf(gpRight - gpLeft), 180.0, GP_EPS, "left and right anchors differ by exactly 180 deg")
	# No direction at all -> fall back to the bare canonical offset.
	# 完全无方向 -> 回落到裸的规范偏置。
	gpApprox(GPMountResolver.gpAnchorDirToRotation(Vector2.ZERO, 37.0), 37.0, GP_EPS,
		"an anchor with no direction falls back to the canonical offset alone")


# ---------------------------------------------------------------------------
# Compatibility / occupancy / candidate ladder / 兼容性 / 占用 / 候选阶梯
# ---------------------------------------------------------------------------

# A host whose two anchors accept DIFFERENT kinds, plus one unrestricted anchor.
# 一台宿主：两个锚点分别只接受不同种类，另有一个不限种类。
func _gpTypedHostDef() -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = "typed_host"
	gpD.gpDefaultSize = Vector2(64.0, 48.0)
	var gpAnchors: Array[GPAttachPoint] = []
	var gpNozzleSocket: GPAttachPoint = GPAttachPoint.gpMake("n1", Vector2(0.5, 1.0),
		Vector2(0.0, 1.0), _gpStr("NOZZLE"))
	gpNozzleSocket.gpMaxOccupancy = 1
	gpAnchors.append(gpNozzleSocket)
	gpAnchors.append(GPAttachPoint.gpMake("free", Vector2(0.5, 0.0), Vector2(0.0, -1.0)))
	gpD.gpAttachPoints = gpAnchors
	return gpD


func gpTestCanMountCompatibility() -> void:
	var gpTyped: GPSymbolDef = _gpTypedHostDef()
	var gpNozzleSocket: GPAttachPoint = gpTyped.gpAttachPointByName("n1")
	var gpFreeSocket: GPAttachPoint = gpTyped.gpAttachPointByName("free")

	var gpNozzle: GPSymbolDef = GPSymbolDef.new()
	gpNozzle.gpId = "nozzle_x"
	gpNozzle.gpMountKind = "NOZZLE"
	var gpActuator: GPSymbolDef = GPSymbolDef.new()
	gpActuator.gpId = "actuator_x"
	gpActuator.gpMountKind = "ACTUATOR"
	var gpPlain: GPSymbolDef = GPSymbolDef.new()
	gpPlain.gpId = "plain_x"

	gpCheck(GPMountResolver.gpCanMount(gpTyped, gpNozzleSocket, gpNozzle),
		"a NOZZLE fits an anchor that accepts NOZZLE")
	gpCheck(not GPMountResolver.gpCanMount(gpTyped, gpNozzleSocket, gpActuator),
		"an ACTUATOR does not fit an anchor that only accepts NOZZLE")
	gpCheck(GPMountResolver.gpCanMount(gpTyped, gpFreeSocket, gpActuator),
		"an empty accept list accepts any kind")
	gpCheck(not GPMountResolver.gpCanMount(gpTyped, gpFreeSocket, gpPlain),
		"a symbol with no mount kind can never be mounted")
	gpCheck(not GPMountResolver.gpCanMount(null, gpNozzleSocket, gpNozzle),
		"a null definition can never be mounted")
	gpCheck(GPMountResolver.gpAcceptsKind(gpFreeSocket, "ANYTHING"), "an empty accept list is universal")
	gpCheck(not GPMountResolver.gpAcceptsKind(gpFreeSocket, ""), "an empty kind never matches")

	# gpMountFit narrows a child to specific anchor NAMES.
	# gpMountFit 把子件收窄到特定**锚点名**。
	var gpFit: Array[String] = []
	gpFit.append("n1")
	gpNozzle.gpMountFit = gpFit
	gpCheck(GPMountResolver.gpCanMount(gpTyped, gpNozzleSocket, gpNozzle),
		"a whitelisted anchor name is accepted")
	gpCheck(not GPMountResolver.gpCanMount(gpTyped, gpFreeSocket, gpNozzle),
		"an anchor outside the whitelist is refused even though it accepts the kind")


func gpTestFreeAnchorsAndOccupancy() -> void:
	var gpHost: GPPIDNode = GPPIDNode.new()
	gpHost.gpInstanceId = "tdhost"
	gpHost.gpSymbolId = "typed_host"
	gpHost.gpPosition = Vector2(0.0, 0.0)
	var gpOccupant: GPPIDNode = GPPIDNode.new()
	gpOccupant.gpInstanceId = "occ"
	gpOccupant.gpSymbolId = "nozzle_x"
	gpOccupant.gpParentUid = "tdhost"
	gpOccupant.gpMountAnchor = "n1"
	var gpG: GPPIDGraph = _gpGraphOf(gpHost)
	var gpLookup: Callable = func(gpId: String) -> GPSymbolDef:
		return _gpTypedHostDef()

	gpEq(GPMountResolver.gpOccupancy(gpG, "tdhost", "n1"), 0, "the nozzle socket starts empty")
	var gpFree: Array[String] = GPMountResolver.gpFreeAnchors(gpG, gpLookup, "tdhost", "NOZZLE")
	gpEq(gpFree.size(), 2, "both anchors accept a NOZZLE while the socket is empty")
	gpCheck("n1" in gpFree, "the nozzle socket is reported free")

	# Fill the capped socket: occupancy 1 == gpMaxOccupancy 1, so it drops out of the free list.
	# 占满限额为 1 的插座：占用数 1 == gpMaxOccupancy 1，故它退出空闲表。
	gpG.gpNodes.append(gpOccupant)
	gpEq(GPMountResolver.gpOccupancy(gpG, "tdhost", "n1"), 1, "the socket now holds one child")
	gpFree = GPMountResolver.gpFreeAnchors(gpG, gpLookup, "tdhost", "NOZZLE")
	gpEq(gpFree.size(), 1, "a capped anchor drops out once it is full")
	gpCheck("n1" not in gpFree, "the full socket is no longer free")
	gpCheck("free" in gpFree, "the unrestricted anchor stays free")
	gpCheck(GPMountResolver.gpFreeAnchors(gpG, gpLookup, "tdhost", "ACTUATOR").size() == 1,
		"an ACTUATOR only ever sees the unrestricted anchor")
	gpEq(GPMountResolver.gpFreeAnchors(gpG, gpLookup, "ghost", "NOZZLE").size(), 0,
		"an unknown host yields no free anchors")
	gpEq(GPMountResolver.gpFreeAnchors(gpG, gpLookup, "tdhost", "").size(), 0,
		"an empty mount kind yields no free anchors")


func gpTestMountCandidateNearestAndZoomGated() -> void:
	var gpHost: GPPIDNode = _gpHostNode(Vector2(0.0, 0.0))
	var gpG: GPPIDGraph = _gpGraphOf(gpHost)

	# Close to the top anchor (world (0,-24)): it must win, and hit at zoom 1.
	# 靠近顶部锚点（世界 (0,-24)）：它必须胜出，且在缩放 1 时命中。
	var gpNear: Dictionary = GPMountResolver.gpMountCandidate(gpG, _gpLookup(), Vector2(0.0, -20.0),
		1.0, "ACTUATOR")
	gpEq(str(gpNear["anchor"]), "top_actuator", "the nearest compatible anchor wins")
	gpEq(str(gpNear["parent_uid"]), "host", "the winning candidate names its host")
	gpEq(bool(gpNear["hit"]), true, "a cursor 4mm from the anchor is within the snap radius")
	gpApprox(float(gpNear["dist"]), 4.0, GP_EPS, "the reported distance is exact")

	# Far from every anchor: the radius is fixed in SCREEN pixels, so zoom decides the verdict.
	# 远离所有锚点：半径固定在**屏幕**像素，故缩放决定判定。
	var gpFar: Dictionary = GPMountResolver.gpMountCandidate(gpG, _gpLookup(), Vector2(0.0, -60.0),
		1.0, "ACTUATOR")
	gpEq(bool(gpFar["hit"]), false, "36mm away is outside the 24px radius at zoom 1")
	var gpFarZoomed: Dictionary = GPMountResolver.gpMountCandidate(gpG, _gpLookup(),
		Vector2(0.0, -60.0), 0.5, "ACTUATOR")
	gpEq(bool(gpFarZoomed["hit"]), true,
		"zooming out doubles the world radius, so the same point now hits")
	gpEq(str(gpFar["anchor"]), "top_actuator", "the nearest anchor is still reported when missing")

	# No compatible kind at all -> an explicit miss, never a silent fallback.
	# 完全没有兼容种类 -> 明确的未命中，绝不静默回落。
	var gpNone: Dictionary = GPMountResolver.gpMountCandidate(gpG, _gpLookup(), Vector2(0.0, 0.0),
		1.0, "")
	gpEq(bool(gpNone["hit"]), false, "an empty mount kind never hits")
	gpEq(float(gpNone["dist"]), INF, "an empty mount kind reports an INF distance")


# ---------------------------------------------------------------------------
# Subtree / degradation / cycle safety
# 子树 / 降级 / 环安全
# ---------------------------------------------------------------------------

func gpTestSubtreeAndChildren() -> void:
	var gpHost: GPPIDNode = _gpHostNode()
	var gpChildA: GPPIDNode = _gpChildNode("host", "top_actuator", "cA")
	var gpChildB: GPPIDNode = _gpChildNode("host", "left_nozzle", "cB")
	var gpGrand: GPPIDNode = _gpChildNode("cA", "stem", "gA")
	var gpG: GPPIDGraph = _gpGraphOf(gpHost, gpChildA, gpChildB, gpGrand)

	gpEq(GPMountResolver.gpChildrenOf(gpG, "host").size(), 2, "the host has two direct children")
	gpEq(GPMountResolver.gpChildrenOf(gpG, "cA").size(), 1, "the child has one direct child")
	gpEq(GPMountResolver.gpChildrenOf(gpG, "gA").size(), 0, "a leaf has no children")

	var gpAll: Array[String] = GPMountResolver.gpSubtree(gpG, "host")
	gpEq(gpAll.size(), 4, "the host subtree is the host plus all three descendants")
	gpCheck("gA" in gpAll, "a grandchild belongs to the host subtree")
	var gpSub: Array[String] = GPMountResolver.gpSubtree(gpG, "cA")
	gpEq(gpSub.size(), 2, "a mid-tree subtree is itself plus its descendant")
	gpEq(GPMountResolver.gpSubtree(gpG, "missing").size(), 1,
		"an unknown uid yields just itself, never an empty surprise")
	gpEq(GPMountResolver.gpSubtree(gpG, "").size(), 0, "an empty uid yields nothing")


func gpTestDegradationLadder() -> void:
	# Ladder 2: the host was deleted without cleaning up -> the child keeps its own frame.
	# 阶梯 2：宿主被删但未清理 -> 子件保持自身坐标系。
	var gpOrphan: GPPIDNode = _gpChildNode("ghost", "top_actuator", "orphan")
	gpOrphan.gpPosition = Vector2(50.0, 60.0)
	var gpWT: Dictionary = GPMountResolver.gpWorldTransform(_gpGraphOf(gpOrphan), _gpLookup(),
		gpOrphan)
	gpEq(gpWT["origin"], Vector2(50.0, 60.0), "a vanished host degrades to the node's own frame")
	gpCheck(gpWT["origin"] != Vector2.INF, "a vanished host never yields Vector2.INF")

	# Ladder 3: the anchor name no longer exists -> sit at the host centre, still following it.
	# 阶梯 3：锚点名已不存在 -> 落在宿主中心，但仍跟随宿主。
	var gpHost: GPPIDNode = _gpHostNode()
	var gpStale: GPPIDNode = _gpChildNode("host", "anchor_from_an_older_pack", "stale")
	gpStale.gpPosition = Vector2(999.0, 999.0)
	var gpStaleWT: Dictionary = GPMountResolver.gpWorldTransform(_gpGraphOf(gpHost, gpStale),
		_gpLookup(), gpStale)
	gpEq(gpStaleWT["origin"], Vector2(100.0, 100.0),
		"an unknown anchor name lands the child on the host centre")
	gpApprox(float(gpStaleWT["rot_deg"]), 0.0, GP_EPS,
		"with no anchor direction the child takes the host's rotation")

	# gpAnchorWorld degrades the same way and reports "found".
	# gpAnchorWorld 以同样方式降级，并用 "found" 如实报告。
	var gpAW: Dictionary = GPMountResolver.gpAnchorWorld(_gpGraphOf(gpHost), _gpLookup(), gpHost,
		"anchor_from_an_older_pack")
	gpEq(bool(gpAW["found"]), false, "a missing anchor is reported as not found")
	gpEq(gpAW["pos"], Vector2(100.0, 100.0), "a missing anchor degrades to the host origin")
	gpCheck(gpAW["pos"] != Vector2.INF, "a missing anchor never yields Vector2.INF")
	var gpGoodAW: Dictionary = GPMountResolver.gpAnchorWorld(_gpGraphOf(gpHost), _gpLookup(),
		gpHost, "left_nozzle")
	gpEq(bool(gpGoodAW["found"]), true, "a real anchor is reported as found")
	gpEq(gpGoodAW["pos"], Vector2(68.0, 100.0), "left_nozzle sits 32 left of the host centre")
	gpApprox((gpGoodAW["dir"] as Vector2).x, -1.0, GP_EPS, "left_nozzle's normal points left")

	# A host with no definition at all (a pack the reader does not know).
	# 宿主完全没有定义（读取方不认识的图元包）。
	var gpUnknown: GPPIDNode = GPPIDNode.new()
	gpUnknown.gpInstanceId = "unk"
	gpUnknown.gpSymbolId = "no_such_symbol"
	gpUnknown.gpPosition = Vector2(7.0, 8.0)
	var gpChildOfUnknown: GPPIDNode = _gpChildNode("unk", "whatever", "cu")
	gpChildOfUnknown.gpPosition = Vector2(7.0, 8.0)
	var gpUWT: Dictionary = GPMountResolver.gpWorldTransform(_gpGraphOf(gpUnknown, gpChildOfUnknown),
		_gpLookup(), gpChildOfUnknown)
	gpEq(gpUWT["origin"], Vector2(7.0, 8.0), "an undefined host degrades to the child's own frame")


func gpTestCycleGuard() -> void:
	# A hand-edited archive could make A mount onto B and B back onto A. Recursion must stop.
	# 手改的存档可能让 A 挂在 B 上、B 又挂回 A。递归必须终止。
	var gpA: GPPIDNode = _gpChildNode("b", "stem", "a")
	gpA.gpPosition = Vector2(5.0, 5.0)
	var gpB: GPPIDNode = _gpChildNode("a", "stem", "b")
	gpB.gpPosition = Vector2(9.0, 9.0)
	var gpG: GPPIDGraph = _gpGraphOf(gpA, gpB)
	var gpWT: Dictionary = GPMountResolver.gpWorldTransform(gpG, _gpLookup(), gpA)
	gpCheck(gpWT["origin"] != Vector2.INF, "a parent cycle still resolves to a finite origin")
	# The cycle collapses back onto A's own frame. Compared component-wise because the path runs
	# a 180-degree rotation, which is exact only to float precision.
	# 环最终塌回 A 自身坐标系。按分量比较，因为该路径经过一次 180 度旋转，只有浮点精度。
	gpApprox((gpWT["origin"] as Vector2).x, 5.0, GP_EPS, "the cycle collapses onto the queried x")
	gpApprox((gpWT["origin"] as Vector2).y, 5.0, GP_EPS, "the cycle collapses onto the queried y")
	gpEq(GPMountResolver.gpSubtree(gpG, "a").size(), 2, "a subtree over a cycle lists each uid once")


func gpTestEmptyLookupIsSafe() -> void:
	# An invalid / empty lookup (a test harness or a headless probe) must degrade, not crash.
	# 无效 / 空的查找器（测试夹具或 headless 探针）必须降级，而不是崩溃。
	var gpHost: GPPIDNode = _gpHostNode()
	var gpChild: GPPIDNode = _gpChildNode()
	gpChild.gpPosition = Vector2(3.0, 4.0)
	var gpWT: Dictionary = GPMountResolver.gpWorldTransform(_gpGraphOf(gpHost, gpChild),
		Callable(), gpChild)
	gpEq(gpWT["origin"], Vector2(3.0, 4.0),
		"with no definition lookup a child falls back to its own frame")
	gpEq(GPMountResolver.gpDefFor(Callable(), "anything"), null, "an invalid lookup yields null")
	gpEq(GPMountResolver.gpFreeAnchors(_gpGraphOf(gpHost), Callable(), "host", "ACTUATOR").size(), 0,
		"free anchors with no lookup is an empty list, not a crash")
