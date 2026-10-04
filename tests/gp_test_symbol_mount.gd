extends "res://tests/gp_test.gd"
# Copyright © 2026 Jonson Wang
# Headless regression tests for P3 of the 主图元 / 次级图元 feature.
# 主图元 / 次级图元功能 P3 的 headless 回归测试。
#
# Five promises are guarded here / 此处守护五条承诺：
#   1. THE TWO LAYOUT TABLES STAY IN SYNC. The GDScript anchor table and the generator's Python
#      table describe the same library twice (one serves the built-in pack, the other serves a
#      USER symbol created from a category). A drift would mean a user-made pump cannot host the
#      same nozzles as the built-in one — a difference no user could ever explain.
#      **两张版面表保持同步**。GDScript 锚点表与生成器的 Python 表把同一个图元库描述了两遍
#      （一者服务内置包，另一者服务按类别新建的**用户**图元）。一旦脱节，用户自建的泵就无法
#      承载与内置泵相同的管口 —— 一个用户永远解释不清的差别。
#   2. PLACING A HOST INSTANTIATES ITS BUILT-IN PARTS (规划 §16), as ONE undo step.
#      **放置宿主即实例化其自带部件**（规划 §16），且只算**一个**撤销步。
#   3. THOSE PARTS DO NOT CONSUME PROJECT TAG NUMBERS, and a required one cannot be removed
#      (规划 §16.2). **这些部件不消耗项目位号**，且必需部件不可移除（规划 §16.2）。
#   4. THE ACTUATOR CONTRACT (§14): one top signal terminal, and the mechanical link is a MOUNT
#      rather than a stem EDGE — so the derived rotation must land the upright glyph correctly.
#      **执行机构契约**（§14）：一个顶部信号端子，机械联系由**挂载**而非阀杆**边**表达 ——
#      故推导出的旋转必须让直立字形正确落位。
#   5. THE NOZZLE'S TWO TEXT LINES (§13) live on the definition, not on the instance.
#      **管口的两行文本**（§13）挂在定义上，而非实例上。
#
# NOTE: gpAttachPoints / gpLabelSlots are TYPED arrays (Array[GPAttachPoint] / Array[GPLabelSlot]),
# so they are read through their typed fields, never via string keys.
# 注意：gpAttachPoints / gpLabelSlots 是**强类型**数组，须通过其类型化字段读取，不可用字符串键索引。

const GP_EPS: float = 0.0001

# Mount kinds a socket may accept although NO symbol declares them yet. A reserved socket is a
# deliberate design statement (规划 §16.4 parks the stirrer there before any stirrer symbol
# exists); listing it here keeps that statement visible instead of weakening the check.
# 插座可以接受、但尚无任何图元声明该挂载类型的那些类型。预留插座是刻意的设计表态
# （规划 §16.4 在任何搅拌图元存在之前就把该位置留出来）；在此列出它，可让该表态保持可见，
# 而不是把检查削弱。
const GP_RESERVED_KINDS: Array[String] = ["AGITATOR"]

# Symbols allowed to be BOTH a host and a part (规划 §3.1's "Both" classification). Empty on
# purpose: §14 turned the actuator's stem socket into the act of mounting it, so nothing needs to
# be both. If a future symbol genuinely must be, ADD IT HERE rather than deleting the assertion —
# that way the decision stays deliberate and reviewable.
# 允许**既是宿主又是部件**的图元（规划 §3.1 的「Both」分类）。刻意留空：§14 把执行机构的
# 阀杆插座变成了「把它挂上去」这个动作，故没有任何图元需要兼具两重身份。若将来确有图元必须如此，
# 请**加到此处**而不是删掉断言 —— 这样这个决定才是刻意且可复核的。
const GP_BOTH_ALLOWED: Array[String] = []


# ---------------------------------------------------------------------------
# Fixtures / 夹具
# ---------------------------------------------------------------------------

func _gpBuiltinDefs() -> Array[GPSymbolDef]:
	return GPSymbolPackDexpi.gpDefs()


func _gpDefById(gpId: String) -> GPSymbolDef:
	for gpD in _gpBuiltinDefs():
		if gpD.gpId == gpId:
			return gpD
	return null


# The definition lookup shape every mount query expects. Backed by the live library, exactly like
# GPCanvasSymbolLayer.gpDefLookupCallable() in the app.
# 各挂载查询所期望的定义查找器形态。以活动图元库为后盾，与应用中的
# GPCanvasSymbolLayer.gpDefLookupCallable() 完全一致。
func _gpLookup() -> Callable:
	return func(gpId: String) -> GPSymbolDef:
		return GPSymbolLibrary.gpFindById(gpId)


# A bound edit service over the given graph, with no tag registry (tag behaviour has its own suite
# — gp_test_tag_registry.gd pins "a part consumes no tag number").
# 在给定图上绑定的编辑服务，不带位号注册表（位号行为有自己的套件 ——
# gp_test_tag_registry.gd 钉住「部件不消耗位号」）。
func _gpServiceFor(gpG: GPPIDGraph) -> GPEditService:
	var gpSvc: GPEditService = GPEditService.new()
	gpSvc.gpBindGraph(gpG, GPIdGen.new())
	return gpSvc


# The anchor of the host that a child sits in, or null when the host / anchor does not exist.
# 子件所落座的宿主锚点；宿主 / 锚点不存在时返回 null。
func _gpAnchorOf(gpGraph: GPPIDGraph, gpLookup: Callable, gpHostUid: String,
		gpChild: GPPIDNode) -> GPAttachPoint:
	var gpHost: GPPIDNode = gpGraph.gpGetNode(gpHostUid)
	if gpHost == null:
		return null
	var gpDef: GPSymbolDef = GPMountResolver.gpDefFor(gpLookup, gpHost.gpSymbolId)
	if gpDef == null:
		return null
	return gpDef.gpAttachPointByName(gpChild.gpMountAnchor)


# ---------------------------------------------------------------------------
# 1. The two layout tables must agree
# 1. 两张版面表必须一致
# ---------------------------------------------------------------------------

# The GDScript anchor table and the generator's Python table must agree on EVERY field, not just
# the count: a symbol whose anchor count matches but whose `accepts` list drifted would silently
# refuse a part that the built-in twin accepts.
# GDScript 锚点表与生成器的 Python 表必须在**每个字段**上一致，而不只是数量：
# 数量相同但 `accepts` 表脱节的图元，会静默拒绝内置孪生图元所接受的部件。
func gpTestAttachTableMatchesGeneratedPack() -> void:
	for gpD in _gpBuiltinDefs():
		var gpFromTable: Array[GPAttachPoint] = GPSymbolCategories.gpAttachPointsForSymbol(
			gpD.gpId, gpD.gpCategory)
		gpEq(gpFromTable.size(), gpD.gpAttachPoints.size(),
			"table and pack agree on the anchor count: %s" % gpD.gpId)
		for gpI in range(mini(gpFromTable.size(), gpD.gpAttachPoints.size())):
			var gpA: GPAttachPoint = gpFromTable[gpI]
			var gpB: GPAttachPoint = gpD.gpAttachPoints[gpI]
			var gpHint: String = "anchor %d of %s" % [gpI, gpD.gpId]
			gpEq(gpA.gpName, gpB.gpName, "table and pack agree on the name of %s" % gpHint)
			gpEq(gpA.gpPos, gpB.gpPos, "table and pack agree on the position of %s" % gpHint)
			gpEq(gpA.gpDir, gpB.gpDir, "table and pack agree on the direction of %s" % gpHint)
			gpEq(gpA.gpAccepts, gpB.gpAccepts,
				"table and pack agree on the accepted kinds of %s" % gpHint)
			gpEq(gpA.gpDefaultChild, gpB.gpDefaultChild,
				"table and pack agree on the default child of %s" % gpHint)
			gpEq(gpA.gpRequired, gpB.gpRequired,
				"table and pack agree on the required flag of %s" % gpHint)
			gpEq(gpA.gpDefaultProps, gpB.gpDefaultProps,
				"table and pack agree on the default properties of %s" % gpHint)


# Every anchor name must be unique inside its definition: GPPIDNode.gpMountAnchor stores the NAME,
# so a duplicate would make "which socket is this part in?" unanswerable.
# 每个锚点名在其定义内必须唯一：GPPIDNode.gpMountAnchor 存的是**名字**，
# 故重名会让「这个部件装在哪个插座里」无法回答。
func gpTestAnchorNamesAreUniquePerDefinition() -> void:
	for gpD in _gpBuiltinDefs():
		gpCheck(gpD.gpAttachNamesUnique(),
			"anchor names are unique so gpMountAnchor can be a plain name: %s" % gpD.gpId)


# A part must not also be a host in this pack: §14 turned the actuator's stem socket into the act
# of MOUNTING it, so nothing needs to be both.
# 本包中部件的不能同时是宿主：§14 把执行机构的阀杆插座变成了「把它挂上去」这个动作，
# 故没有任何图元需要兼具两重身份。
func gpTestPartsAreNotCarriers() -> void:
	var gpChecked: int = 0
	for gpD in _gpBuiltinDefs():
		if gpD.gpMountKind == "":
			continue
		gpChecked += 1
		gpCheck(gpD.gpAttachPoints.is_empty() or (gpD.gpId in GP_BOTH_ALLOWED),
			"%s is a part, so it carries no anchors of its own" % gpD.gpId)
	# Guard against the loop silently becoming vacuous (every symbol a host = nothing checked).
	# 防止该循环静默变成空转（所有图元都成了宿主 = 什么都没检查）。
	gpCheck(gpChecked >= 5,
		"the pack still declares at least five mountable parts, got %d" % gpChecked)


# A socket whose `accepts` list names a kind no symbol declares can NEVER be filled — the user
# drags a part at it and nothing happens, with no explanation available anywhere. A socket whose
# own default child does not fit it is worse still: the host would arrive with a part the model
# considers illegal.
# 若插座的 `accepts` 表里写着一个没有任何图元声明的类型，它就**永远**填不上 —— 用户把部件拖过去
# 什么也不会发生，而且任何地方都给不出解释。若插座连**自己**的默认子件都接不住，那就更糟：
# 宿主一被放置就带着一个模型认为非法的部件。
func gpTestEverySocketIsFillable() -> void:
	var gpKinds: Dictionary = {}
	for gpD in _gpBuiltinDefs():
		if gpD.gpMountKind != "":
			gpKinds[gpD.gpMountKind] = true
	var gpDefaultChildren: int = 0
	for gpD in _gpBuiltinDefs():
		for gpA in gpD.gpAttachPoints:
			for gpK in gpA.gpAccepts:
				gpCheck(gpKinds.has(gpK) or (gpK in GP_RESERVED_KINDS),
					"%s.%s accepts %s, which some symbol declares (or is a reserved kind)"
						% [gpD.gpId, gpA.gpName, gpK])
			if gpA.gpDefaultChild == "":
				continue
			gpDefaultChildren += 1
			var gpChild: GPSymbolDef = _gpDefById(gpA.gpDefaultChild)
			gpCheck(gpChild != null, "%s.%s names an installed default child, got %s"
				% [gpD.gpId, gpA.gpName, gpA.gpDefaultChild])
			if gpChild != null:
				gpCheck(GPMountResolver.gpCanMount(gpD, gpA, gpChild),
					"%s.%s accepts its own default child %s" % [gpD.gpId, gpA.gpName,
						gpA.gpDefaultChild])
	# Both halves must actually have been exercised, or a rename could turn this into a no-op.
	# 两半都必须真的被跑到，否则一次改名就能把它变成空转。
	gpCheck(gpDefaultChildren >= 9,
		"the pack still declares its built-in parts on anchors, got %d" % gpDefaultChildren)


# ---------------------------------------------------------------------------
# 2. Placing a host brings its parts
# 2. 放置宿主即带来其部件
# ---------------------------------------------------------------------------

# A pump is class A (规划 §16.3): its suction + discharge are fixed by the machine, so the pack
# declares them as default children carrying a per-opening nozzle number.
# 泵属 A 类（规划 §16.3）：吸入 + 排出由机器决定，故图元包把它们声明为默认子件，
# 并携带逐开孔的管口编号。
func gpTestDefaultChildrenComeFromTheHostDefinition() -> void:
	var gpPump: GPSymbolDef = _gpDefById("DPUMP001")
	gpCheck(gpPump != null, "the built-in pump exists")
	if gpPump == null:
		return
	var gpKids: Array[Dictionary] = GPMountResolver.gpDefaultChildren(_gpLookup(), gpPump)
	gpEq(gpKids.size(), 2, "a pump brings exactly two parts (suction + discharge)")
	# Declaration order is the definition's own, so the same host always yields the same order.
	# 顺序取自定义自身的声明顺序，故同一宿主每次产生的顺序都一样。
	var gpNames: Array[String] = []
	for gpK in gpKids:
		gpNames.append(str(gpK["anchor"]))
		gpEq(str(gpK["symbol_id"]), "DGENERAL008", "the pump's part is the nozzle symbol")
		gpCheck(not str(gpK["props"].get("nozzle_id", "")).is_empty(),
			"anchor %s stamps a nozzle number onto its part" % str(gpK["anchor"]))
	var gpWant: Array[String] = ["pump_suction", "pump_discharge"]
	gpEq(gpNames, gpWant, "suction is declared before discharge")
	# The two openings must carry DIFFERENT numbers, or the drawing would label both "N1".
	if gpKids.size() == 2:
		gpCheck(str(gpKids[0]["props"]["nozzle_id"]) != str(gpKids[1]["props"]["nozzle_id"]),
			"the two openings are numbered differently")
	# A reserved socket (the B-class "middle" for the stirrer) is declared but instantiates
	# NOTHING: §16.6 forbids auto-creating parts the user has not asked for.
	# 预留插座（B 类的「中间」搅拌位）只声明、不实例化任何东西：§16.6 禁止自动创建用户没要的部件。
	var gpTank: GPSymbolDef = _gpDefById("DTANK001")
	if gpTank != null:
		var gpHoles: Array[String] = []
		for gpK in GPMountResolver.gpDefaultChildren(_gpLookup(), gpTank):
			gpHoles.append(str(gpK["anchor"]))
		gpEq(gpHoles.size(), 5, "a class-B vessel brings four nozzles and one manhole")
		gpCheck(not ("ves_stirrer" in gpHoles), "the reserved stirrer socket carries no default part")


# A definition with no anchors is not a carrier, and the query must say so rather than inventing
# anything — a symbol that has no socket must not grow one.
# 无锚点的定义不是载体，查询必须如实回答而非凭空发明 —— 没有插座的图元不得长出插座。
func gpTestNonCarrierYieldsNoChildren() -> void:
	gpEq(GPMountResolver.gpDefaultChildren(_gpLookup(), _gpDefById("DGENERAL008")).size(), 0,
		"a nozzle is a part, not a carrier")
	gpEq(GPMountResolver.gpDefaultChildren(_gpLookup(), null).size(), 0,
		"a null definition yields no children instead of crashing")
	# An unresolvable child must be SKIPPED rather than returned as a broken id — a pack that names
	# a symbol which is not installed degrades to "this part is missing".
	# 无法解析的子件必须被**跳过**，而不是作为坏 id 返回 —— 引用了未安装图元的包降级为「部件缺失」。
	var gpGhost: GPSymbolDef = GPSymbolDef.new()
	gpGhost.gpId = "ghost_host"
	gpGhost.gpCategory = "general"
	var gpAnchors: Array[GPAttachPoint] = []
	gpAnchors.append(GPAttachPoint.gpMake("ghost_socket", Vector2(0.5, 0.0), Vector2(0.0, -1.0),
		["NOZZLE"], "NO_SUCH_SYMBOL_ANYWHERE"))
	gpGhost.gpAttachPoints = gpAnchors
	gpEq(GPMountResolver.gpDefaultChildren(_gpLookup(), gpGhost).size(), 0,
		"a default child whose symbol is missing is skipped, not returned as a dead id")


func gpTestPlacingAHostInstantiatesItsParts() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpSvc: GPEditService = _gpServiceFor(gpG)
	var gpLookup: Callable = _gpLookup()
	var gpHost: String = gpSvc.gpPlaceNode("DPUMP001", Vector2(120.0, 90.0), "", gpLookup)
	gpCheck(gpHost != "", "the pump was placed")
	gpEq(gpG.gpNodes.size(), 3,
		"placing one pump produced three nodes (host + suction + discharge)")
	var gpKids: Array[GPPIDNode] = GPMountResolver.gpChildrenOf(gpG, gpHost)
	gpEq(gpKids.size(), 2, "both parts are mounted on the pump")
	for gpK in gpKids:
		gpEq(gpK.gpSymbolId, "DGENERAL008", "the part is the nozzle symbol")
		gpEq(gpK.gpTag, "", "an auto-created part carries no project tag")
		gpCheck(not str(gpK.gpProps.get("nozzle_id", "")).is_empty(),
			"the part received its anchor's default property values")
		gpCheck(gpK.gpIsMounted(), "the part is mounted, so its world transform is derived")
		# The part must sit on a REAL anchor of the host, or the mount ladder would degrade to
		# "host centre" and every nozzle would pile up in the middle of the pump.
		# 部件必须坐在宿主的**真实**锚点上，否则挂载阶梯会降级为「宿主中心」，
		# 于是所有管口都会堆在泵的正中间。
		gpCheck(_gpAnchorOf(gpG, gpLookup, gpHost, gpK) != null,
			"the part sits on a declared anchor: %s" % gpK.gpMountAnchor)
	# The two parts must land on DIFFERENT anchors, or the host would have one opening drawn twice.
	# 两个部件必须落在**不同**锚点上，否则宿主的同一个开孔会被画两遍。
	if gpKids.size() == 2:
		gpCheck(gpKids[0].gpMountAnchor != gpKids[1].gpMountAnchor,
			"the two parts occupy two different sockets")


# The parts are inside the SAME undo step as the host: undoing a placement must not need one
# Ctrl+Z per nozzle (the "undo granularity matches the perceived action" rule).
# 部件与宿主处在**同一个**撤销步内：撤销一次放置不该每个管口按一次 Ctrl+Z
# （「撤销粒度必须与感知到的一次操作对齐」规则）。
func gpTestPlacingIsOneUndoStep() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpSvc: GPEditService = _gpServiceFor(gpG)
	var gpHost: String = gpSvc.gpPlaceNode("DPUMP001", Vector2(10.0, 20.0), "", _gpLookup())
	if gpHost == "":
		return
	gpEq(gpG.gpNodes.size(), 3, "three nodes before the undo")
	gpEq(gpSvc.gpUndo(), true, "one undo step is available")
	gpEq(gpG.gpNodes.size(), 0, "a single undo removed the host AND its parts")
	gpEq(gpSvc.gpRedo(), true, "redo is available")
	gpEq(gpG.gpNodes.size(), 3, "redo put all three back")
	# Id stability: redo replays the kept objects, so nothing downstream (edges, references) can be
	# silently re-pointed at a node that no longer exists.
	# id 稳定性：重做重放保留的对象，故下游任何东西（边、引用）都不会被静默改指到已不存在的节点。
	var gpIds: Array[String] = []
	for gpN in gpG.gpNodes:
		gpIds.append(gpN.gpInstanceId)
	gpCheck(gpHost in gpIds, "redo restored the host under its original id")
	gpEq(GPMountResolver.gpChildrenOf(gpG, gpHost).size(), 2,
		"redo restored both parts, still mounted on the host")


# ---------------------------------------------------------------------------
# 3. Required parts cannot be removed
# 3. 必需部件不可移除
# ---------------------------------------------------------------------------

# 规划 §16.2: an A-class nozzle has a count and a position fixed by the machine, so pulling it off
# would leave a drawing that no longer describes the equipment.
# 规划 §16.2：A 类管口的数量与位置由机器决定，故把它摘下来会留下不再描述该设备的图纸。
func gpTestRequiredPartCannotBeDetachedOrDeleted() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpSvc: GPEditService = _gpServiceFor(gpG)
	var gpLookup: Callable = _gpLookup()
	var gpHost: String = gpSvc.gpPlaceNode("DPUMP001", Vector2.ZERO, "", gpLookup)
	if gpHost == "":
		return
	var gpKids: Array[GPPIDNode] = GPMountResolver.gpChildrenOf(gpG, gpHost)
	gpEq(gpKids.size(), 2, "the pump has its two required parts")
	if gpKids.is_empty():
		return
	var gpNozzle: String = gpKids[0].gpInstanceId
	gpEq(GPMountResolver.gpRequiredAnchorName(gpG, gpLookup, gpKids[0]), "pump_suction",
		"the suction anchor is flagged required")
	# Detach: refused, and the node stays mounted.
	# 卸载：被拒，且节点保持挂载。
	gpEq(gpSvc.gpDetachNodes([gpNozzle], gpLookup), false, "detaching a required part is refused")
	gpCheck(gpG.gpGetNode(gpNozzle) != null and gpG.gpGetNode(gpNozzle).gpIsMounted(),
		"the refused part is still there and still mounted")
	# Delete: refused as well. A refusal means "no undo step was recorded", so the stack must not
	# have grown — otherwise Ctrl+Z would appear to do nothing.
	# 删除：同样被拒。拒绝意味着「没有记录撤销步」，故栈不得增长 —— 否则 Ctrl+Z 会看起来毫无作用。
	gpEq(gpSvc.gpDeleteSelection([gpNozzle], [], [], gpLookup), false,
		"deleting a required part is refused")
	gpCheck(gpG.gpGetNode(gpNozzle) != null, "the refused part survived the delete")
	gpEq(gpSvc.gpUndo(), true, "the stack still holds exactly the placement step")
	gpEq(gpG.gpNodes.size(), 0, "one undo still removes the whole placement")
	gpEq(gpSvc.gpRedo(), true, "redo works again after the refusals")
	gpEq(gpG.gpNodes.size(), 3, "the placement came back intact")
	# Deleting the HOST is allowed and takes the required parts with it (they are parts of it).
	# 删除**宿主**是允许的，并带走了必需部件（它们是它的一部分）。
	gpEq(gpSvc.gpDeleteSelection([gpHost], [], [], gpLookup), true,
		"deleting the host is allowed")
	gpEq(gpG.gpNodes.size(), 0, "the host and its required parts went together")


# A class-B vessel's openings are NOT required (规划 §16.4: the count follows the process), so the
# same gesture must succeed on them. Pinning only the refusal half would leave the guard free to
# overreach and block legitimate edits.
# B 类设备的开孔**不是**必需的（规划 §16.4：数量随工艺而变），故同样的手势在它上面必须成功。
# 只钉住「拒绝」那一半，会让这枚护栏有机会越界并阻断合法编辑。
func gpTestOptionalPartCanBeDetached() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpSvc: GPEditService = _gpServiceFor(gpG)
	var gpLookup: Callable = _gpLookup()
	var gpHost: String = gpSvc.gpPlaceNode("DTANK001", Vector2.ZERO, "", gpLookup)
	if gpHost == "":
		return
	var gpKids: Array[GPPIDNode] = GPMountResolver.gpChildrenOf(gpG, gpHost)
	gpEq(gpKids.size(), 5, "the vessel brought four nozzles and one manhole")
	if gpKids.is_empty():
		return
	var gpPart: GPPIDNode = gpKids[0]
	gpEq(GPMountResolver.gpRequiredAnchorName(gpG, gpLookup, gpPart), "",
		"a vessel opening is not flagged required")
	# Where it currently sits, so the bake can be checked against a real position rather than
	# against "somewhere".
	# 它当前所在的位置，使烘焙可以对一个真实位置进行核对，而不是对「某个地方」核对。
	var gpBefore: Vector2 = GPMountResolver.gpWorldTransform(gpG, gpLookup, gpPart)["origin"]
	gpEq(gpSvc.gpDetachNodes([gpPart.gpInstanceId], gpLookup), true,
		"an optional part can be detached")
	var gpAfter: GPPIDNode = gpG.gpGetNode(gpPart.gpInstanceId)
	gpCheck(gpAfter != null and not gpAfter.gpIsMounted(), "the detached part is now top-level")
	# The bake must have kept it exactly where the user saw it, not teleported it to the origin.
	# 烘焙必须让它精确停在用户看到的位置，而不是瞬移到原点。
	gpCheck(gpAfter != null and gpAfter.gpPosition.distance_to(gpBefore) <= GP_EPS,
		"the detached part stayed where it was drawn")


# ---------------------------------------------------------------------------
# 4. The actuator contract (§14)
# 4. 执行机构契约（§14）
# ---------------------------------------------------------------------------

# The actuator is a PART of the valve (§14.2), so the rule that makes it land correctly is that a
# valve offers an ACTUATOR socket on TOP, facing outward, with no default child.
# 执行机构是阀门的**部件**（§14.2），故让它正确落位的规则是：阀门在**顶部**提供一个朝外的
# ACTUATOR 插座，且不带默认子件。
func gpTestValveOffersAnActuatorSocketOnTop() -> void:
	var gpFound: int = 0
	for gpD in _gpBuiltinDefs():
		for gpA in gpD.gpAttachPoints:
			if not ("ACTUATOR" in gpA.gpAccepts):
				continue
			gpFound += 1
			gpCheck(gpA.gpPos.y <= GP_EPS,
				"%s.%s is on the TOP edge, got y=%f" % [gpD.gpId, gpA.gpName, gpA.gpPos.y])
			gpEq(gpA.gpDir, Vector2(0.0, -1.0),
				"%s.%s faces outward (up)" % [gpD.gpId, gpA.gpName])
			# No default child: §14.2 mounts an actuator on demand, and §16.6 forbids auto-creating
			# parts the user did not ask for. A plain valve needs none.
			# 无默认子件：§14.2 按需挂载执行机构，§16.6 禁止自动创建用户没要的部件。
			gpEq(gpA.gpDefaultChild, "", "%s.%s instantiates nothing by default"
				% [gpD.gpId, gpA.gpName])
	gpCheck(gpFound >= 1, "at least one built-in symbol offers an actuator socket")


# End to end: mount the actuator on a valve's socket and check the DERIVED rotation. This is the
# only assertion that can catch a wrong gpBaseMountRot, because a wrong angle produces a symbol
# that is placed, saved and rendered without complaint — just lying on its side.
# 端到端：把执行机构挂到阀门插座上并检查**推导**出的旋转。只有这个断言能抓到错误的
# gpBaseMountRot，因为角度错了图元照样能被放置、保存、渲染，只是横躺着而已。
func gpTestActuatorLandsUprightOnTheValveSocket() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpSvc: GPEditService = _gpServiceFor(gpG)
	var gpLookup: Callable = _gpLookup()
	var gpActuator: GPSymbolDef = _gpDefById("DGENERAL004")
	if gpActuator == null:
		return
	var gpValve: String = gpSvc.gpPlaceNode("DVALVE002", Vector2(200.0, 150.0), "", gpLookup)
	if gpValve == "":
		return
	var gpAnchor: String = GPMountResolver.gpFirstFreeAnchorForDef(gpG, gpLookup, gpValve,
		gpActuator)
	gpEq(gpAnchor, "top_actuator", "the actuator's first free socket on a valve is the top one")
	if gpAnchor == "":
		return
	var gpChild: String = gpSvc.gpAttachNode("DGENERAL004", gpValve, gpAnchor, "", Vector2.ZERO,
		0.0)
	gpCheck(gpChild != "", "the actuator was attached")
	var gpN: GPPIDNode = gpG.gpGetNode(gpChild)
	if gpN == null:
		return
	var gpRot: float = float(GPMountResolver.gpWorldTransform(gpG, gpLookup, gpN)["rot_deg"])
	# The glyph is drawn upright (its body points along local -Y) and the socket faces up, so the
	# actuator must NOT be turned at all. Any other value means it lies on its side.
	# 字形按直立绘制（本体沿局部 -Y），而插座朝上，故执行机构**完全不应**被转动。
	# 其他任何值都意味着它横躺着。
	gpApprox(fposmod(gpRot, 360.0), 0.0, 0.01,
		"the actuator lands upright on an up-facing socket, got rot=%f" % gpRot)
	# ...and it sits ABOVE the valve, not on top of it: the socket is on the envelope's upper edge.
	# ……并且它在阀门**上方**，而不是压在阀体上：插座位于包络上边。
	var gpOrigin: Vector2 = GPMountResolver.gpWorldTransform(gpG, gpLookup, gpN)["origin"]
	gpCheck(gpOrigin.y < gpG.gpGetNode(gpValve).gpPosition.y,
		"the actuator is drawn above the valve, got y=%f vs valve y=%f"
			% [gpOrigin.y, gpG.gpGetNode(gpValve).gpPosition.y])
	# The half-turn self-check documented on GPMountResolver itself: the same part on a DOWN-facing
	# socket must differ by exactly 180 degrees. Asserting it ties the formula to a physical
	# consequence instead of to one number.
	# GPMountResolver 自身文档里的半圈自检：同一部件落在**朝下**的插座上，旋转必须恰好相差 180 度。
	# 在此断言它，可把公式绑定到一个物理后果上，而不是绑定到某一个数字上。
	var gpDownRot: float = GPMountResolver.gpAnchorDirToRotation(Vector2(0.0, 1.0),
		gpActuator.gpBaseMountRot)
	gpApprox(fposmod(gpDownRot - gpRot, 360.0), 180.0, 0.01,
		"the same part on a down-facing socket differs by exactly 180 degrees")


# ---------------------------------------------------------------------------
# 5. The nozzle's two text lines (§13)
# 5. 管口的两行文本（§13）
# ---------------------------------------------------------------------------

# The nozzle shows its number ABOVE and its nominal size BELOW. Both live on the DEFINITION (they
# are the same for every nozzle instance), and the top/bottom split is the ANCHOR, not a newline.
# 管口上方显示编号、下方显示公称通径。两者都挂在**定义**上（对每个管口实例都相同），
# 而上下分区由**锚点**表达，不是一个换行符。
func gpTestNozzleCarriesTwoTextSlots() -> void:
	var gpNozzle: GPSymbolDef = _gpDefById("DGENERAL008")
	gpCheck(gpNozzle != null, "the built-in nozzle exists")
	if gpNozzle == null:
		return
	gpEq(gpNozzle.gpLabelSlots.size(), 2, "the nozzle carries two text slots")
	var gpAbove: GPLabelSlot = gpNozzle.gpLabelSlotByKey("nozzle_no")
	var gpBelow: GPLabelSlot = gpNozzle.gpLabelSlotByKey("dn")
	gpCheck(gpAbove != null, "the number slot exists")
	gpCheck(gpBelow != null, "the nominal-size slot exists")
	if gpAbove != null:
		gpEq(gpAbove.gpAnchor, GPLabelAnchor.GPAnchor.GP_ABOVE, "the number is drawn ABOVE")
		gpCheck(gpAbove.gpFormat.contains("nozzle_id"), "the number reads the nozzle_id property")
	if gpBelow != null:
		# No explicit anchor -> the historic default, which is below. Pinned so a later "tidy-up"
		# that sets it to GP_ABOVE cannot silently stack both lines on one side.
		# 未显式指定锚点 -> 历史默认值，即下方。钉住它，使日后某次「整理」把它改成 GP_ABOVE 时，
		# 不会静默地把两行堆到同一侧。
		gpEq(gpBelow.gpAnchor, GPLabelAnchor.GPAnchor.GP_BELOW, "the DN is drawn BELOW")
		gpCheck(gpBelow.gpFormat.contains("nominal_size"), "the DN reads the nominal_size property")
	# Both fields must exist in the typed schema, or the slots render an empty string forever.
	# 两个字段都必须存在于类型化 schema 中，否则槽永远渲染空串。
	gpCheck(gpNozzle.gpSchema != null, "the nozzle has a typed schema")
	if gpNozzle.gpSchema != null:
		gpCheck(gpNozzle.gpSchema.gpFieldByKey("nozzle_id") != null,
			"the nozzle schema declares nozzle_id")
	gpCheck(gpNozzle.gpSchema.gpFieldByKey("nominal_size") != null,
		"the nozzle schema declares nominal_size")


# The mount-axis label flag must be ON for the nozzle and OFF for everything else. Switching it on
# for an actuator would tilt every controlled valve's F.C. / F.O. text, which nobody asked for.
# 「随安装轴排布」开关必须对管嘴开、对其它一切关。给执行机构打开会把每个调节阀的 F.C./F.O. 文字
# 掰歪，而无人要求如此。
func gpTestOnlyTheNozzleFollowsItsMountAxis() -> void:
	var gpOn: Array[String] = []
	for gpD in _gpBuiltinDefs():
		if gpD != null and gpD.gpLabelFollowsMount:
			gpOn.append(gpD.gpId)
	gpEq(gpOn.size(), 1, "exactly one bundled symbol lays its slots out along the mount axis")
	if gpOn.size() == 1:
		gpEq(gpOn[0], "DGENERAL008", "and it is the nozzle")
	# The flag only makes sense for a symbol that HAS slots, and the nozzle must have opted in.
	var gpNozzle: GPSymbolDef = _gpDefById("DGENERAL008")
	gpCheck(gpNozzle != null and gpNozzle.gpLabelFollowsMount,
		"the built-in nozzle opts into mount-axis layout")
	# Round-trip: the flag must survive the archive, or a saved project would silently lose it.
	# 往返：该开关必须能经由存档存活，否则已保存的工程会静默丢掉它。
	if gpNozzle != null:
		var gpBack: GPSymbolDef = GPSymbolDef.new()
		gpBack.gpFromDict(gpNozzle.gpToDict())
		gpCheck(gpBack.gpLabelFollowsMount, "the flag round-trips through the definition dictionary")
		gpEq(gpBack.gpLabelSlots.size(), 2, "and the slots survive with it")
	# A symbol that does NOT opt in must write NO new key, keeping every archive byte-stable.
	# 未开启的图元**绝不**写出新键，使每一份存档保持字节稳定。
	var gpPlain: GPSymbolDef = _gpDefById("DGENERAL004")
	gpCheck(gpPlain != null and not gpPlain.gpToDict().has("label_follows_mount"),
		"a symbol that does not opt in writes no new key at all")
	var gpBare: GPSymbolDef = GPSymbolDef.new()
	gpCheck(not gpBare.gpToDict().has("label_follows_mount"),
		"a default definition carries the flag as OFF and omits it")


# Every part name the attach submenu offers must RESOLVE through the translator.
# 附件子菜单提供的每一个部件名都必须能经翻译器解析。
#
# WHY: a DEXPI-pack display name is an i18n KEY ("dexpi.dgeneral008"), so a label that skips the
# translator reads as a raw key — exactly what the user saw in the submenu. This pins the DATA half
# (the key resolves); the call site must translate it, as the palette item already does.
# 原因：DEXPI 包的显示名是 i18n **键**（"dexpi.dgeneral008"），故跳过翻译器的标签会显示为裸键 ——
# 正是用户在子菜单里看到的现象。此处钉住**数据侧**（该键可解析）；调用点必须调用翻译器，
# 正如调色板条目已经做的那样。
func gpTestEveryPartNameOfferedByTheAttachMenuResolves() -> void:
	var gpCands: Array[GPSymbolDef] = GPMountResolver.gpMountableDefs(_gpBuiltinDefs())
	gpCheck(gpCands.size() > 0, "the bundled pack offers mountable parts to the menu")
	for gpD in gpCands:
		var gpRaw: String = gpD.gpDisplayName if gpD.gpDisplayName != "" else gpD.gpId
		var gpShown: String = I18n.gpTr(gpRaw)
		gpCheck(gpShown != "", "a part name always renders as something: " + gpRaw)
		# A dotted, unresolved name is the defect; a plain literal name (no dot) is fine as-is.
		# 带点且未解析的名字才是缺陷；不含点的普通字面名原样显示是对的。
		gpCheck(not gpRaw.contains(".") or gpShown != gpRaw,
			"the part name is translated rather than shown as a raw i18n key: " + gpRaw)


# ---------------------------------------------------------------------------
# Normalizer: a user symbol is not a second-class host
# 归一化器：用户图元不是二等宿主
# ---------------------------------------------------------------------------

# A symbol created from the symbol editor must inherit the SAME anchoring sockets as its built-in
# twin, so "make my own pump" does not quietly produce something no nozzle can be fitted to.
# 由符号编辑器新建的图元必须继承与其内置孪生图元**相同**的锚点插座，
# 使「做一个我自己的泵」不会悄悄产出一个装不上任何管口的图元。
func gpTestNormalizerInheritsCategoryAnchors() -> void:
	var gpDraft: Dictionary = {
		"id": "my_pump", "display_name": "我的泵",
		"shapes": {
			"paths": [], "circles": [],
			"rects": [{"pos": [0.0, 40.0], "size": [100.0, 40.0]}],
		},
		"ports": [],
		"attrs_schema": {},
	}
	var gpDef: GPSymbolDef = GPSymbolNormalizer.gpNormalizeSymbol(gpDraft, "pump")
	gpEq(gpDef.gpAttachPoints.size(), 2, "a user pump inherits the pump anchor template")
	var gpBuiltin: GPSymbolDef = _gpDefById("DPUMP001")
	if gpBuiltin != null:
		gpEq(gpDef.gpAttachPoints.size(), gpBuiltin.gpAttachPoints.size(),
			"the user pump offers as many sockets as the built-in one")
		for gpI in range(mini(gpDef.gpAttachPoints.size(), gpBuiltin.gpAttachPoints.size())):
			gpEq(gpDef.gpAttachPoints[gpI].gpName, gpBuiltin.gpAttachPoints[gpI].gpName,
				"socket %d is named like the built-in twin's" % gpI)
			gpEq(gpDef.gpAttachPoints[gpI].gpDefaultChild,
				gpBuiltin.gpAttachPoints[gpI].gpDefaultChild,
				"socket %d instantiates the same part as the built-in twin's" % gpI)

	# The "nothing drawn" branch has its own return statement, so it needs its own pin: an
	# assertion that only covered the normal path would let the empty-glyph branch silently lose
	# its anchors — the two branches are exactly where such a drift hides.
	# 「未绘制任何图形」分支有自己的 return，故需自己的钉子：只覆盖常规路径的断言，
	# 会让空字形分支静默丢掉锚点 —— 两个分支正是这类漂移的藏身之处。
	var gpEmpty: GPSymbolDef = GPSymbolNormalizer.gpNormalizeSymbol(
		{"id": "my_empty", "display_name": "", "shapes": {}, "ports": [], "attrs_schema": {}},
		"tank")
	gpEq(gpEmpty.gpShapes.size(), 0, "the empty draft produced no shapes")
	gpEq(gpEmpty.gpAttachPoints.size(), 6, "the empty-glyph branch inherits the vessel template")

	# Anchors are DERIVED, so the round trip must neither crash nor pretend they were drawn:
	# gpDenormalizeSymbol() returns a DRAFT, and a draft has nowhere to put them.
	# 锚点是**推导**的，故往返既不能崩溃、也不能假装它们是被画出来的：
	# gpDenormalizeSymbol() 返回的是**草稿**，而草稿里没有存放它们的位置。
	var gpBack: Dictionary = GPSymbolNormalizer.gpDenormalizeSymbol(gpDef)
	gpCheck(not gpBack.has("attach_points"),
		"the round-tripped draft carries no anchors (they are re-derived)")
	var gpAgain: GPSymbolDef = GPSymbolNormalizer.gpNormalizeSymbol(gpBack, "pump")
	gpEq(gpAgain.gpAttachPoints.size(), 2, "re-normalizing re-derives the same two sockets")

	# A category with no standard anchors must NOT gain any: "general" holds the parts and the
	# legend glyphs, and giving a user's drawing-mode symbol an actuator socket would be nonsense.
	# 无标准锚点的类别**不得**凭空得到锚点：「通用」类目装着部件与图例字形，
	# 给一个用户自绘的图元配个执行机构插座毫无道理。
	var gpPlain: GPSymbolDef = GPSymbolNormalizer.gpNormalizeSymbol(
		{"id": "my_glyph", "display_name": "", "shapes": {
			"paths": [], "circles": [], "rects": [{"pos": [0.0, 0.0], "size": [50.0, 50.0]}]},
			"ports": [], "attrs_schema": {}},
		"general")
	gpEq(gpPlain.gpAttachPoints.size(), 0, "a general-category symbol gains no anchors")
