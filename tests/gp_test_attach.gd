extends "res://tests/gp_test.gd"
# Headless tests for the ATTACH layer (P2 of the 主图元 / 次级图元 feature).
# 主图元 / 次级图元功能 P2 —— 附件层（添加 / 卸载 / 改挂 / 拖动内核 / 级联）的 headless 测试。
#
# Five promises are guarded here / 此处守护五条承诺：
#   1. A PART IS ALWAYS MOUNTED. Attaching without a host is REFUSED rather than silently
#      degraded to a top-level symbol — an orphaned part is the very defect being removed.
#      **部件永远挂载**。找不到宿主时**拒绝**创建，而不是静默降级为顶层图元 ——
#      孤儿附件正是本功能要消灭的缺陷。
#   2. NOTHING JUMPS. Detaching bakes the derived world transform into the node's own fields
#      BEFORE cutting the link, so the symbol stays exactly where the user saw it.
#      **任何东西都不跳位**。卸载前先把推导出的世界变换烘焙进节点自身字段，再切断链接，
#      故图元精确停在用户看到的位置。
#   3. VALUE OBJECTS. Redo replays the recorded tuple verbatim and never re-derives, so a change
#      made to the host between undo and redo cannot make a redo drift.
#      **值对象**。重做逐字重放记录的元组、绝不重新推导，故撤销与重做之间对宿主的改动
#      不会让重做漂移。
#   4. NO PHANTOM UNDO STEPS. A no-op re-mount / an all-unmounted detach returns false, so the
#      stack records nothing.
#      **无幽灵撤销步**。无变化的改挂 / 全未挂载的卸载返回 false，栈什么也不记。
#   5. MOUNT-AWARE CONSUMERS. Hit-testing prefers the DEEPER part, collision ignores parts, and
#      the derived origin (not the stale stored coordinate) drives both.
#      **感知挂载的消费方**。命中测试优先**更深**的部件、碰撞忽略部件，且两者都由推导原点
#      （而非过期的存储坐标）驱动。

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


func _gpStr4(gpA: String, gpB: String, gpC: String, gpD: String) -> Array[String]:
	var gpOut: Array[String] = _gpStr(gpA, gpB, gpC)
	gpOut.append(gpD)
	return gpOut


# A 64x48 valve with one anchor per side, all unrestricted and uncapped. Anchor locals therefore
# are (0,-24) top / (-32,0) left / (32,0) right / (0,24) bottom.
# 一台 64x48 的阀门，四边各一个锚点，全部不限种类且不限占用。故锚点本地坐标为
# 上 (0,-24) / 左 (-32,0) / 右 (32,0) / 下 (0,24)。
func _gpHostDef() -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = "host_mnt"
	gpD.gpCategory = "valve"
	gpD.gpDefaultSize = Vector2(64.0, 48.0)
	var gpA: Array[GPAttachPoint] = []
	gpA.append(GPAttachPoint.gpMake("top", Vector2(0.5, 0.0), Vector2(0.0, -1.0)))
	gpA.append(GPAttachPoint.gpMake("left", Vector2(0.0, 0.5), Vector2(-1.0, 0.0)))
	gpA.append(GPAttachPoint.gpMake("right", Vector2(1.0, 0.5), Vector2(1.0, 0.0)))
	gpA.append(GPAttachPoint.gpMake("bot", Vector2(0.5, 1.0), Vector2(0.0, 1.0)))
	gpD.gpAttachPoints = gpA
	return gpD


# A 16x16 mountable part (ACTUATOR), no anchors of its own.
# 一台 16x16 的可挂载部件（ACTUATOR），自身无锚点。
func _gpChildDef() -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = "child_mnt"
	gpD.gpCategory = "instrument"
	gpD.gpDefaultSize = Vector2(16.0, 16.0)
	gpD.gpMountKind = "ACTUATOR"
	return gpD


# A nozzle: a DIFFERENT mount kind, so kind filtering can be told apart from mere emptiness.
# 一个管口：另一种挂载类型，使「按类型过滤」能与「仅仅为空」区分开。
func _gpNozzleDef() -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = "nozzle_mnt"
	gpD.gpDefaultSize = Vector2(12.0, 12.0)
	gpD.gpMountKind = "NOZZLE"
	return gpD


# A host whose anchors are type-restricted, one of them capped (occupancy 1).
# 一台锚点带类型限制、其中一个是限额（占用 1）的宿主。
func _gpTypedHostDef() -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = "typed_host"
	gpD.gpDefaultSize = Vector2(64.0, 48.0)
	var gpA: Array[GPAttachPoint] = []
	gpA.append(GPAttachPoint.gpMake("nz_a", Vector2(0.5, 0.0), Vector2(0.0, -1.0), _gpStr("NOZZLE")))
	var gpB: GPAttachPoint = GPAttachPoint.gpMake("nz_b", Vector2(0.5, 1.0), Vector2(0.0, 1.0),
		_gpStr("NOZZLE"))
	gpB.gpMaxOccupancy = 1
	gpA.append(gpB)
	gpA.append(GPAttachPoint.gpMake("gen", Vector2(1.0, 0.5), Vector2(1.0, 0.0)))
	gpD.gpAttachPoints = gpA
	return gpD


func _gpLookup() -> Callable:
	return func(gpId: String) -> GPSymbolDef:
		if gpId == "host_mnt":
			return _gpHostDef()
		if gpId == "child_mnt":
			return _gpChildDef()
		if gpId == "typed_host":
			return _gpTypedHostDef()
		if gpId == "nozzle_mnt":
			return _gpNozzleDef()
		return null


func _gpGraph() -> GPPIDGraph:
	return GPPIDGraph.new()


func _gpNode(gpId: String, gpSymbolId: String, gpPos: Vector2 = Vector2.ZERO) -> GPPIDNode:
	var gpN: GPPIDNode = GPPIDNode.new()
	gpN.gpInstanceId = gpId
	gpN.gpSymbolId = gpSymbolId
	gpN.gpPosition = gpPos
	return gpN


func _gpMounted(gpId: String, gpSymbolId: String, gpParent: String, gpAnchor: String) -> GPPIDNode:
	var gpN: GPPIDNode = _gpNode(gpId, gpSymbolId)
	gpN.gpParentUid = gpParent
	gpN.gpMountAnchor = gpAnchor
	return gpN


# A ready command context: graph + id generator, no tag registry (so tags stay caller-supplied
# and the tests never depend on the numbering rules).
# 一个就绪的命令上下文：图 + id 生成器，不带标签注册表（故位号由调用方给出，
# 测试绝不依赖编号规则）。
func _gpCtx(gpGraph: GPPIDGraph) -> GPCommandContext:
	return GPCommandContext.new(gpGraph, GPIdGen.new(), null)


# A binder carrying the fixtures' definitions, so hit-testing can resolve nominal sizes.
# 一个携带夹具定义的绑定器，使命中测试能解析标称尺寸。
func _gpBinder(gpG: GPPIDGraph) -> GPGraphBinder:
	var gpB: GPGraphBinder = GPGraphBinder.new()
	gpB.gpGraph = gpG
	var gpDefs: Array[GPSymbolDef] = []
	gpDefs.append(_gpHostDef())
	gpDefs.append(_gpChildDef())
	gpB.gpDefs = gpDefs
	return gpB


# ---------------------------------------------------------------------------
# GPAttachNodeCommand — a part is always mounted
# GPAttachNodeCommand —— 部件永远挂载
# ---------------------------------------------------------------------------

func gpTestAttachCommandCreatesMountedNode() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddNode(_gpNode("H", "host_mnt", Vector2(0.0, 0.0)))
	var gpCtx: GPCommandContext = _gpCtx(gpG)
	var gpCmd: GPAttachNodeCommand = GPAttachNodeCommand.new("child_mnt", "H", "top", "AC1")
	gpCheck(gpCmd.gpExecute(gpCtx), "attaching onto a real host succeeds")
	gpEq(gpCmd.gpRefusal, "", "a successful attach reports no refusal")
	var gpNid: String = gpCmd.gpCreatedId
	gpCheck(gpNid != "", "the command reports the id it created")
	var gpChild: GPPIDNode = gpG.gpGetNode(gpNid)
	gpCheck(gpChild != null, "the child really is in the graph")
	gpEq(gpChild.gpParentUid, "H", "the child points at its host")
	gpEq(gpChild.gpMountAnchor, "top", "the child records its anchor NAME, not a coordinate")
	gpEq(gpChild.gpTag, "AC1", "the tag is carried onto the instance")
	gpEq(gpChild.gpPosition, Vector2.ZERO,
		"the stored position stays ZERO on purpose: it is derived from the chain and never read")
	var gpWT: Dictionary = GPMountResolver.gpWorldTransform(gpG, _gpLookup(), gpChild)
	gpEq(gpWT["origin"], Vector2(0.0, -24.0),
		"the world origin comes from the anchor, so a ZERO stored position is not a lie")


func gpTestAttachCommandRefusesWithoutHost() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	var gpCtx: GPCommandContext = _gpCtx(gpG)
	var gpCmd: GPAttachNodeCommand = GPAttachNodeCommand.new("child_mnt", "ghost", "top")
	gpCheck(not gpCmd.gpExecute(gpCtx), "attaching to a missing host is refused")
	gpEq(gpCmd.gpRefusal, "no_host", "the refusal token is machine-readable for the status bar")
	# The token must be PREFIX-FREE. The "attach." namespace is added exactly ONCE, downstream, by
	# GPCanvasEditFacade.gpReportRefusal() — the same convention as GPConnectEdgeCommand storing
	# "edge_self_loop" while the facade resolves "edge.edge_self_loop". Carrying the namespace here
	# as well would resolve "attach.attach.no_host": a MISSING key, which gpTr() does not report —
	# it prints the raw key into the status bar instead.
	# 记号必须**不带前缀**。"attach." 命名空间在下游由 GPCanvasEditFacade.gpReportRefusal()
	# 恰好添加**一次** —— 与 GPConnectEdgeCommand 存 "edge_self_loop"、门面解析
	# "edge.edge_self_loop" 同一约定。若在此也带命名空间，会解析成 "attach.attach.no_host"：
	# 一个**缺失**的键，gpTr() 不会报错，而是把裸键名打印进状态栏。
	gpCheck(not gpCmd.gpRefusal.begins_with("attach."),
		"the refusal token is namespace-free, so the facade's prefix can only yield a REAL key")
	var gpResolved: String = "attach." + gpCmd.gpRefusal
	gpCheck(I18n.GP_STRINGS.has(gpResolved),
		"facade prefix + token resolves to an existing i18n key: " + gpResolved)
	gpEq(gpG.gpNodes.size(), 0, "nothing at all was created")
	gpEq(gpCmd.gpCreatedId, "", "a refused attach reports no id")

	# An EMPTY host uid is refused the same way — the part must not become a top-level symbol.
	# 空的宿主 uid 同样被拒 —— 部件绝不能变成顶层图元。
	var gpCmd2: GPAttachNodeCommand = GPAttachNodeCommand.new("child_mnt", "", "top")
	gpCheck(not gpCmd2.gpExecute(gpCtx), "an empty host uid is refused (a part is never top-level)")
	gpEq(gpCmd2.gpRefusal, "no_host", "the same refusal token covers an empty host uid")

	# A null / unready context refuses too, rather than crashing on a nil dereference.
	# 空 / 未就绪的上下文同样拒绝，而不是空引用崩溃。
	var gpCmd3: GPAttachNodeCommand = GPAttachNodeCommand.new("child_mnt", "H", "top")
	gpCheck(not gpCmd3.gpExecute(null), "a null context is refused")
	gpCheck(not gpCmd3.gpExecute(GPCommandContext.new(null, null, null)),
		"an unready context (no graph / no id source) is refused")


func gpTestAttachCommandUndoRedoKeepsId() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddNode(_gpNode("H", "host_mnt", Vector2(0.0, 0.0)))
	var gpCtx: GPCommandContext = _gpCtx(gpG)
	var gpCmd: GPAttachNodeCommand = GPAttachNodeCommand.new("child_mnt", "H", "top")
	gpCmd.gpExecute(gpCtx)
	var gpNid: String = gpCmd.gpCreatedId
	var gpChild: GPPIDNode = gpG.gpGetNode(gpNid)
	gpCmd.gpUndo(gpCtx)
	gpEq(gpG.gpGetNode(gpNid), null, "undo removes the attached child")
	gpEq(gpG.gpNodes.size(), 1, "only the host is left after the undo")
	gpCmd.gpRedo(gpCtx)
	gpEq(gpG.gpGetNode(gpNid), gpChild, "redo re-adds the SAME object, so the id stays stable")
	gpEq(gpG.gpGetNode(gpNid).gpParentUid, "H", "the re-added child is still mounted on its host")


# ---------------------------------------------------------------------------
# GPDetachNodesCommand — nothing jumps
# GPDetachNodesCommand —— 任何东西都不跳位
# ---------------------------------------------------------------------------

func gpTestDetachCommandBakesDerivedTransform() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddNode(_gpNode("H", "host_mnt", Vector2(0.0, 0.0)))
	var gpChild: GPPIDNode = _gpMounted("C", "child_mnt", "H", "top")
	# A deliberately absurd own position: while mounted it is ignored, and after detaching it
	# must be REPLACED by the baked world transform rather than read back.
	# 故意给一个荒谬的自身坐标：挂载时它被忽略，卸载后必须被烘焙的世界变换**替换**而非读回。
	gpChild.gpPosition = Vector2(999.0, 999.0)
	gpG.gpAddNode(gpChild)
	var gpCtx: GPCommandContext = _gpCtx(gpG)
	var gpCmd: GPDetachNodesCommand = GPDetachNodesCommand.new(_gpStr("C"), _gpLookup())
	gpCheck(gpCmd.gpExecute(gpCtx), "detaching a mounted child succeeds")
	gpEq(gpChild.gpParentUid, "", "the host link is cut")
	gpEq(gpChild.gpMountAnchor, "", "the anchor name is cleared")
	gpEq(gpChild.gpMountOffset, Vector2.ZERO, "the fine-tune nudge is cleared with the link")
	gpApprox(gpChild.gpPosition.x, 0.0, GP_EPS, "the derived world x is baked in")
	gpApprox(gpChild.gpPosition.y, -24.0, GP_EPS, "the derived world y is baked in, so nothing jumps")
	gpApprox(gpChild.gpRotationDeg, -90.0, GP_EPS, "the derived world rotation is baked in too")
	gpCheck(gpChild.gpPosition.y != 999.0, "the stale stored coordinate is provably replaced")
	gpCheck(not gpChild.gpIsMounted(), "the node no longer reports itself as mounted")


func gpTestDetachCommandUndoRestoresMount() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddNode(_gpNode("H", "host_mnt", Vector2(0.0, 0.0)))
	var gpChild: GPPIDNode = _gpMounted("C", "child_mnt", "H", "top")
	gpChild.gpPosition = Vector2(999.0, 999.0)
	gpChild.gpMountOffset = Vector2(2.0, 3.0)
	gpChild.gpMountAngleDeg = 12.0
	gpG.gpAddNode(gpChild)
	var gpCtx: GPCommandContext = _gpCtx(gpG)
	var gpCmd: GPDetachNodesCommand = GPDetachNodesCommand.new(_gpStr("C"), _gpLookup())
	gpCmd.gpExecute(gpCtx)
	gpCmd.gpUndo(gpCtx)
	gpEq(gpChild.gpParentUid, "H", "undo restores the host link")
	gpEq(gpChild.gpMountAnchor, "top", "undo restores the anchor name")
	gpEq(gpChild.gpMountOffset, Vector2(2.0, 3.0), "undo restores the fine-tune nudge")
	gpApprox(gpChild.gpMountAngleDeg, 12.0, GP_EPS, "undo restores the extra mount angle")
	gpEq(gpChild.gpPosition, Vector2(999.0, 999.0),
		"undo restores the pre-detach own-field values VERBATIM (no re-derivation)")
	gpApprox(gpChild.gpRotationDeg, 0.0, GP_EPS, "undo restores the pre-detach own rotation")


func gpTestDetachCommandIgnoresUnmountedIds() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddNode(_gpNode("H", "host_mnt", Vector2(0.0, 0.0)))
	gpG.gpAddNode(_gpNode("P", "child_mnt", Vector2(50.0, 60.0)))
	var gpChild: GPPIDNode = _gpMounted("C", "child_mnt", "H", "top")
	gpG.gpAddNode(gpChild)
	var gpCtx: GPCommandContext = _gpCtx(gpG)

	# A mixed selection detaches the mounted one and leaves the free symbol untouched.
	# 混合选择集：卸载已挂载的那个，完全不碰自由图元。
	var gpCmd: GPDetachNodesCommand = GPDetachNodesCommand.new(_gpStr("P", "C"), _gpLookup())
	gpCheck(gpCmd.gpExecute(gpCtx), "a mixed list still detaches the mounted member")
	gpEq(gpChild.gpParentUid, "", "the mounted child is detached")
	gpEq(gpG.gpGetNode("P").gpPosition, Vector2(50.0, 60.0), "the free symbol keeps its exact position")
	gpEq(gpG.gpGetNode("P").gpParentUid, "", "the free symbol was never given a host")

	# All-unmounted -> false, so a stale selection records no undo step.
	# 全部未挂载 -> false，使过期选择集不产生撤销步。
	var gpCmd2: GPDetachNodesCommand = GPDetachNodesCommand.new(_gpStr("P"), _gpLookup())
	gpCheck(not gpCmd2.gpExecute(gpCtx), "detaching only unmounted nodes records nothing")
	var gpCmd3: GPDetachNodesCommand = GPDetachNodesCommand.new(_gpStr("ghost"), _gpLookup())
	gpCheck(not gpCmd3.gpExecute(gpCtx), "detaching an unknown id records nothing")


func gpTestDetachRedoReplaysBakedStateVerbatim() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	var gpHost: GPPIDNode = _gpNode("H", "host_mnt", Vector2(0.0, 0.0))
	gpG.gpAddNode(gpHost)
	var gpChild: GPPIDNode = _gpMounted("C", "child_mnt", "H", "top")
	gpG.gpAddNode(gpChild)
	var gpCtx: GPCommandContext = _gpCtx(gpG)
	var gpCmd: GPDetachNodesCommand = GPDetachNodesCommand.new(_gpStr("C"), _gpLookup())
	gpCmd.gpExecute(gpCtx)
	gpCmd.gpUndo(gpCtx)
	# Move the host BETWEEN undo and redo. A re-deriving redo would follow it to (500, 476);
	# the recorded bake must win. This is the value-object rule made observable.
	# 在撤销与重做之间移动宿主。若重做会重新推导，它会跟到 (500, 476)；
	# 记录的烘焙值必须取胜。这就是可被观察到的值对象规则。
	gpHost.gpPosition = Vector2(500.0, 500.0)
	gpCmd.gpRedo(gpCtx)
	gpApprox(gpChild.gpPosition.x, 0.0, GP_EPS, "redo replays the recorded baked x")
	gpApprox(gpChild.gpPosition.y, -24.0, GP_EPS, "redo replays the recorded baked y")
	gpCheck(gpChild.gpPosition.y != 476.0,
		"the re-derived value (host moved by 500) is provably NOT used, so redo cannot drift")


# ---------------------------------------------------------------------------
# GPSetMountCommand — the shared commit point of both drag paths
# GPSetMountCommand —— 两条拖拽路径共用的提交点
# ---------------------------------------------------------------------------

func gpTestSetMountCommandRoundTrip() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddNode(_gpNode("H", "host_mnt", Vector2(0.0, 0.0)))
	var gpChild: GPPIDNode = _gpMounted("C", "child_mnt", "H", "top")
	gpG.gpAddNode(gpChild)
	var gpCtx: GPCommandContext = _gpCtx(gpG)
	var gpTarget: Dictionary = {
		"parent_uid": "H",
		"mount_anchor": "right",
		"mount_offset": Vector2.ZERO,
	}
	var gpTargets: Array[Dictionary] = []
	gpTargets.append(gpTarget)
	var gpCmd: GPSetMountCommand = GPSetMountCommand.new(_gpStr("C"), gpTargets)
	gpCheck(gpCmd.gpExecute(gpCtx), "re-mounting onto another anchor changes something")
	gpEq(gpChild.gpMountAnchor, "right", "the new anchor is applied")
	gpEq((GPMountResolver.gpWorldTransform(gpG, _gpLookup(), gpChild)["origin"] as Vector2).x, 32.0,
		"the part really did move to the new anchor")
	gpCmd.gpUndo(gpCtx)
	gpEq(gpChild.gpMountAnchor, "top", "undo puts the old anchor back")
	gpEq((GPMountResolver.gpWorldTransform(gpG, _gpLookup(), gpChild)["origin"] as Vector2).y, -24.0,
		"and the part is back at its old anchor")
	gpCmd.gpRedo(gpCtx)
	gpEq(gpChild.gpMountAnchor, "right", "redo re-applies the new anchor")
	gpCmd.gpUndo(gpCtx)
	gpEq(gpChild.gpMountAnchor, "top", "a second undo still reaches the ORIGINAL state")


func gpTestSetMountCommandNoChangeRecordsNothing() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddNode(_gpNode("H", "host_mnt", Vector2(0.0, 0.0)))
	var gpChild: GPPIDNode = _gpMounted("C", "child_mnt", "H", "top")
	gpG.gpAddNode(gpChild)
	var gpCtx: GPCommandContext = _gpCtx(gpG)
	var gpTargets: Array[Dictionary] = []
	gpTargets.append({"parent_uid": "H", "mount_anchor": "top"})
	var gpCmd: GPSetMountCommand = GPSetMountCommand.new(_gpStr("C"), gpTargets)
	gpCheck(not gpCmd.gpExecute(gpCtx),
		"a drop that ends on the anchor it started from returns false (no phantom undo step)")
	gpEq(gpChild.gpMountAnchor, "top", "and the node is of course untouched")
	gpCheck(not gpCmd.gpExecute(null), "a null context never records anything either")


func gpTestSetMountCommandWritesOnlyGivenKeys() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddNode(_gpNode("H", "host_mnt", Vector2(0.0, 0.0)))
	var gpChild: GPPIDNode = _gpMounted("C", "child_mnt", "H", "top")
	gpChild.gpMountOffset = Vector2(5.0, 6.0)
	gpChild.gpMountAngleDeg = 30.0
	gpG.gpAddNode(gpChild)
	var gpCtx: GPCommandContext = _gpCtx(gpG)
	# Only the anchor is named: the nudge, the angle and the host must all survive untouched.
	# 只给出锚点：微调、微调角与宿主都必须原样存活。
	var gpTargets: Array[Dictionary] = []
	gpTargets.append({"mount_anchor": "right"})
	var gpCmd: GPSetMountCommand = GPSetMountCommand.new(_gpStr("C"), gpTargets)
	gpCheck(gpCmd.gpExecute(gpCtx), "naming one key is a real change")
	gpEq(gpChild.gpMountAnchor, "right", "the named anchor is written")
	gpEq(gpChild.gpParentUid, "H", "an unnamed host is left alone")
	gpEq(gpChild.gpMountOffset, Vector2(5.0, 6.0), "an unnamed nudge is left alone")
	gpApprox(gpChild.gpMountAngleDeg, 30.0, GP_EPS, "an unnamed angle is left alone")
	gpCmd.gpUndo(gpCtx)
	gpEq(gpChild.gpMountAnchor, "top", "undo restores the anchor")
	gpEq(gpChild.gpMountOffset, Vector2(5.0, 6.0), "undo does not disturb the untouched nudge")


func gpTestSetMountRedoDoesNotResnapshot() -> void:
	# gpRedo() must write the recorded targets VERBATIM; routing it through gpExecute() would
	# re-capture the "before" tuple from whatever the graph happens to hold, and a later undo
	# would then land on the modified state instead of the original.
	# The perturbation below is what makes the two implementations distinguishable.
	# gpRedo() 必须逐字写入记录的目标；若转经 gpExecute()，它会从图当前恰好持有的状态重新快照
	# 「之前」元组，于是随后的撤销会落在被改过的状态上而非原始状态。
	# 下面这次扰动正是区分两种实现的关键。
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddNode(_gpNode("H", "host_mnt", Vector2(0.0, 0.0)))
	var gpChild: GPPIDNode = _gpMounted("C", "child_mnt", "H", "top")
	gpG.gpAddNode(gpChild)
	var gpCtx: GPCommandContext = _gpCtx(gpG)
	var gpTargets: Array[Dictionary] = []
	gpTargets.append({"parent_uid": "H", "mount_anchor": "right"})
	var gpCmd: GPSetMountCommand = GPSetMountCommand.new(_gpStr("C"), gpTargets)
	gpCmd.gpExecute(gpCtx)
	gpEq(gpCmd._gpBefore.size(), 1, "the original 'before' tuple was captured on execute")
	gpCmd.gpUndo(gpCtx)
	gpEq(gpChild.gpMountAnchor, "top", "undo returns to the original anchor")
	gpChild.gpMountAnchor = "left"  # out-of-band perturbation / 带外扰动
	gpCmd.gpRedo(gpCtx)
	gpEq(gpChild.gpMountAnchor, "right", "redo writes the recorded target even over a modified state")
	gpCmd.gpUndo(gpCtx)
	gpEq(gpChild.gpMountAnchor, "top",
		"undo after a redo still reaches the ORIGINAL state — redo must not re-snapshot")


# ---------------------------------------------------------------------------
# GPPIDGraph.gpRemoveNodesWithEdges — one model operation for a whole set
# GPPIDGraph.gpRemoveNodesWithEdges —— 整组作为一次模型操作
# ---------------------------------------------------------------------------

func gpTestRemoveNodesWithEdgesFiltersOnce() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	for gpId in _gpStr4("a", "b", "c", "d"):
		gpG.gpAddNode(_gpNode(gpId, "child_mnt"))
	gpG.gpAddEdge(gpG.gpNewEdge("e1", "a", "b"))
	gpG.gpAddEdge(gpG.gpNewEdge("e2", "b", "c"))
	gpG.gpAddEdge(gpG.gpNewEdge("e3", "c", "d"))
	gpG.gpRemoveNodesWithEdges(_gpStr("a", "b"))
	gpEq(gpG.gpNodes.size(), 2, "only the two untouched nodes remain")
	gpCheck(gpG.gpGetNode("c") != null, "a survivor is still there")
	gpEq(gpG.gpEdges.size(), 1, "the edge whose BOTH ends survive is kept")
	gpCheck(gpG.gpGetEdge("e3") != null, "the surviving edge is the one entirely outside the set")
	gpCheck(gpG.gpGetEdge("e1") == null, "an edge between two removed nodes is dropped")
	gpCheck(gpG.gpGetEdge("e2") == null, "an edge with one removed end is dropped")


func gpTestRemoveNodesWithEdgesEmitsSameSignals() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddNode(_gpNode("a", "child_mnt"))
	gpG.gpAddNode(_gpNode("b", "child_mnt"))
	var gpNodeRemovals: Array[int] = [0]
	var gpEdgeRemovals: Array[int] = [0]
	gpG.gpNodeRemoved.connect(func(_gpN: GPPIDNode) -> void: gpNodeRemovals[0] += 1)
	gpG.gpEdgeRemoved.connect(func(_gpE: GPPIDEdge) -> void: gpEdgeRemovals[0] += 1)
	gpG.gpAddEdge(gpG.gpNewEdge("e1", "a", "b"))
	gpG.gpAddEdge(gpG.gpNewEdge("e2", "b", "a"))
	gpG.gpRemoveNodesWithEdges(_gpStr("a", "b"))
	gpEq(gpNodeRemovals[0], 2, "one removal signal per node, exactly like the single-node helper")
	gpEq(gpEdgeRemovals[0], 2,
		"one removal signal per edge, including an edge whose BOTH ends went (no double filter)")
	gpEq(gpG.gpNodes.size(), 0, "both nodes are gone")
	gpEq(gpG.gpEdges.size(), 0, "both edges are gone")


func gpTestRemoveNodesWithEdgesEmptyIsNoop() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddNode(_gpNode("a", "child_mnt"))
	gpG.gpAddEdge(gpG.gpNewEdge("e1", "a", "a"))
	var gpNone: Array[String] = []
	gpG.gpRemoveNodesWithEdges(gpNone)
	gpEq(gpG.gpNodes.size(), 1, "an empty id set removes no node")
	gpEq(gpG.gpEdges.size(), 1, "…and no edge")


# ---------------------------------------------------------------------------
# Cascade delete — downward only
# 级联删除 —— 只朝下
# ---------------------------------------------------------------------------

func gpTestDeleteHostCascadesItsSubtree() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	var gpHost: GPPIDNode = _gpNode("H", "host_mnt", Vector2(0.0, 0.0))
	var gpChild: GPPIDNode = _gpMounted("C", "child_mnt", "H", "top")
	var gpGrand: GPPIDNode = _gpMounted("G", "child_mnt", "C", "top")
	var gpOther: GPPIDNode = _gpNode("O", "host_mnt", Vector2(300.0, 300.0))
	gpG.gpAddNode(gpHost)
	gpG.gpAddNode(gpChild)
	gpG.gpAddNode(gpGrand)
	gpG.gpAddNode(gpOther)
	gpG.gpAddEdge(gpG.gpNewEdge("e1", "H", "O"))
	gpG.gpAddEdge(gpG.gpNewEdge("e2", "C", "O"))
	var gpCtx: GPCommandContext = _gpCtx(gpG)
	var gpCmd: GPDeleteNodesCommand = GPDeleteNodesCommand.new(_gpStr("H"))
	gpCheck(gpCmd.gpExecute(gpCtx), "deleting the host succeeds")
	gpEq(gpG.gpGetNode("H"), null, "the host is gone")
	gpEq(gpG.gpGetNode("C"), null, "its mounted child is gone with it")
	gpEq(gpG.gpGetNode("G"), null, "and the grandchild too, all the way down")
	gpCheck(gpG.gpGetNode("O") != null, "an unrelated node survives")
	gpEq(gpG.gpEdges.size(), 0, "every edge touching the removed subtree is dropped")
	gpCmd.gpUndo(gpCtx)
	gpEq(gpG.gpGetNode("H"), gpHost, "undo restores the SAME host object")
	gpEq(gpG.gpGetNode("C"), gpChild, "undo restores the SAME child object")
	gpEq(gpG.gpGetNode("G"), gpGrand, "undo restores the SAME grandchild object")
	gpEq(gpG.gpEdges.size(), 2, "undo restores both edges")


func gpTestDeleteChildNeverTouchesItsHost() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddNode(_gpNode("H", "host_mnt", Vector2(0.0, 0.0)))
	gpG.gpAddNode(_gpMounted("C", "child_mnt", "H", "top"))
	gpG.gpAddNode(_gpMounted("G", "child_mnt", "C", "top"))
	var gpCtx: GPCommandContext = _gpCtx(gpG)
	var gpCmd: GPDeleteNodesCommand = GPDeleteNodesCommand.new(_gpStr("C"))
	gpCheck(gpCmd.gpExecute(gpCtx), "deleting a mounted child succeeds")
	gpCheck(gpG.gpGetNode("H") != null, "deleting a child never cascades UPWARD to its host")
	gpEq(gpG.gpGetNode("C"), null, "the child is gone")
	gpEq(gpG.gpGetNode("G"), null, "the child's own subtree still cascades downward")


func gpTestDeleteStaleSelectionRecordsNothing() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddNode(_gpNode("H", "host_mnt", Vector2(0.0, 0.0)))
	var gpCtx: GPCommandContext = _gpCtx(gpG)
	var gpCmd: GPDeleteNodesCommand = GPDeleteNodesCommand.new(_gpStr("ghost"))
	gpCheck(not gpCmd.gpExecute(gpCtx), "deleting only unknown ids records no undo step")
	gpEq(gpG.gpNodes.size(), 1, "nothing was removed")


# ---------------------------------------------------------------------------
# Duplicate — the copies' parent chain points at the COPIES
# 复制 —— 副本的父链指向**副本**
# ---------------------------------------------------------------------------

func gpTestDuplicateRemapsParentChainToCopies() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddNode(_gpNode("H", "host_mnt", Vector2(0.0, 0.0)))
	var gpC1: GPPIDNode = _gpMounted("C1", "child_mnt", "H", "top")
	gpC1.gpPosition = Vector2(999.0, 999.0)
	gpG.gpAddNode(gpC1)
	gpG.gpAddNode(_gpMounted("C2", "child_mnt", "H", "left"))
	var gpCtx: GPCommandContext = _gpCtx(gpG)
	var gpCmd: GPDuplicateNodesCommand = GPDuplicateNodesCommand.new(_gpStr("H"))
	gpCheck(gpCmd.gpExecute(gpCtx), "duplicating the host succeeds")
	gpEq(gpCmd.gpNewIds.size(), 3, "the whole mounted subtree is copied")
	gpEq(gpG.gpCountSymbolInstances("host_mnt"), 2, "there are now two vessels")
	gpEq(gpG.gpCountSymbolInstances("child_mnt"), 4, "and four parts (two originals, two copies)")

	var gpCopyHostId: String = ""
	for gpNid in gpCmd.gpNewIds:
		if gpG.gpGetNode(gpNid).gpParentUid == "":
			gpCopyHostId = gpNid
	gpCheck(gpCopyHostId != "", "one clone is the copy of the top-level host")
	var gpLinkedToCopy: int = 0
	var gpLinkedToOriginal: int = 0
	for gpNid in gpCmd.gpNewIds:
		var gpP: String = gpG.gpGetNode(gpNid).gpParentUid
		if gpP == gpCopyHostId:
			gpLinkedToCopy += 1
		if gpP == "H":
			gpLinkedToOriginal += 1
	gpEq(gpLinkedToCopy, 2, "both child copies hang off the COPY host, not the original")
	gpEq(gpLinkedToOriginal, 0, "no copy is left hanging off the ORIGINAL host")
	gpEq(gpG.gpGetNode("C1").gpParentUid, "H", "the originals keep their original host")

	# The subtree ROOT takes the visible offset; a mounted copy does not, or it would be offset
	# twice relative to the host it is derived from.
	# 子树**根**吃可见偏移；挂载副本不吃，否则它相对所推导的宿主会被偏移两次。
	gpEq(gpG.gpGetNode(gpCopyHostId).gpPosition, Vector2(24.0, 24.0),
		"the copied root took exactly one visible offset step")
	var gpChildCopies: Array[GPPIDNode] = []
	for gpNid in gpCmd.gpNewIds:
		var gpC: GPPIDNode = gpG.gpGetNode(gpNid)
		if gpC.gpSymbolId == "child_mnt":
			gpChildCopies.append(gpC)
	gpEq(gpChildCopies.size(), 2, "two of the three clones are the parts")
	var gpKept999: int = 0
	var gpKeptZero: int = 0
	for gpC in gpChildCopies:
		if gpC.gpPosition.x > 900.0:
			gpKept999 += 1
		if is_zero_approx(gpC.gpPosition.x):
			gpKeptZero += 1
	gpEq(gpKept999, 1, "a mounted copy keeps its source's stored 999 — no second offset is applied")
	gpEq(gpKeptZero, 1, "and the other part's copy keeps its own 0, likewise un-offset")


func gpTestDuplicateChildKeepsOutsideHost() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddNode(_gpNode("H", "host_mnt", Vector2(0.0, 0.0)))
	gpG.gpAddNode(_gpMounted("C1", "child_mnt", "H", "top"))
	var gpCtx: GPCommandContext = _gpCtx(gpG)
	var gpCmd: GPDuplicateNodesCommand = GPDuplicateNodesCommand.new(_gpStr("C1"))
	gpCheck(gpCmd.gpExecute(gpCtx), "duplicating a single child succeeds")
	gpEq(gpCmd.gpNewIds.size(), 1, "only the child is copied")
	gpEq(gpG.gpGetNode(gpCmd.gpNewIds[0]).gpParentUid, "H",
		"a copy of a part keeps the host OUTSIDE the copied set (it becomes a sibling)")


# ---------------------------------------------------------------------------
# GPMountDragOps — the kernel both attach interactions share
# GPMountDragOps —— 两种附件交互共用的内核
# ---------------------------------------------------------------------------

# Build a graph with a host at the origin plus one mounted part at [param gpAnchor].
# 构建一个图：原点处的宿主，加一个挂在 [param gpAnchor] 上的部件。
func _gpDragGraph(gpAnchor: String = "top") -> GPPIDGraph:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddNode(_gpNode("H", "host_mnt", Vector2(0.0, 0.0)))
	gpG.gpAddNode(_gpMounted("C", "child_mnt", "H", gpAnchor))
	return gpG


func gpTestMountDragRefusesUnmountedNode() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddNode(_gpNode("H", "host_mnt", Vector2(0.0, 0.0)))
	gpG.gpAddNode(_gpNode("P", "child_mnt", Vector2(50.0, 60.0)))
	var gpDrag: GPMountDragOps = GPMountDragOps.new()
	gpCheck(not gpDrag.gpBegin(gpG, _gpLookup(), "P"),
		"a top-level symbol is moved by the ordinary position drag, not by this kernel")
	gpCheck(not gpDrag.gpIsDragging(), "the kernel stays idle after the refusal")
	gpEq(gpDrag.gpNodeId(), "", "an idle kernel names no node")
	gpEq(gpDrag.gpTargetFor(Vector2.ONE, 1.0).size(), 0, "an idle kernel computes no target")
	gpCheck(not gpDrag.gpBegin(gpG, _gpLookup(), "ghost"), "an unknown id cannot start a drag")
	gpCheck(not gpDrag.gpBegin(null, _gpLookup(), "C"), "a null graph cannot start a drag")


func gpTestMountDragSnapClearsOffset() -> void:
	var gpG: GPPIDGraph = _gpDragGraph("top")
	var gpChild: GPPIDNode = gpG.gpGetNode("C")
	gpChild.gpMountOffset = Vector2(7.0, 8.0)
	var gpDrag: GPMountDragOps = GPMountDragOps.new()
	gpCheck(gpDrag.gpBegin(gpG, _gpLookup(), "C"), "a mounted part can be dragged")
	gpEq(gpDrag.gpNodeId(), "C", "the kernel reports which part it is dragging")
	gpEq(gpDrag.gpBefore()["mount_anchor"], "top", "the before-tuple records the starting anchor")
	gpEq(gpDrag.gpBefore()["mount_offset"], Vector2(7.0, 8.0), "…and the starting nudge")

	var gpT: Dictionary = gpDrag.gpTargetFor(Vector2(32.0, 2.0), 1.0)
	gpEq(str(gpT.get("parent_uid", "")), "H", "the target names the host")
	gpEq(str(gpT.get("mount_anchor", "")), "right", "the nearest free compatible anchor wins")
	gpEq(gpT.get("mount_offset", Vector2.ONE), Vector2.ZERO,
		"a snap CLEARS the nudge, so the part sits ON the anchor instead of drifting on it")
	gpDrag.gpApply(gpT)
	gpEq(gpChild.gpMountAnchor, "right", "apply writes live, which is how the part follows the cursor")
	gpEq(gpChild.gpMountOffset, Vector2.ZERO, "apply writes the cleared nudge too")
	gpDrag.gpRestore()
	gpEq(gpChild.gpMountAnchor, "top", "restore puts the pre-drag anchor back (the ESC path)")
	gpEq(gpChild.gpMountOffset, Vector2(7.0, 8.0), "restore puts the pre-drag nudge back")
	gpDrag.gpEnd()
	gpCheck(not gpDrag.gpIsDragging(), "end() leaves the kernel idle")


func gpTestMountDragFollowsWithinCurrentHost() -> void:
	var gpG: GPPIDGraph = _gpDragGraph("top")
	var gpChild: GPPIDNode = gpG.gpGetNode("C")
	var gpDrag: GPMountDragOps = GPMountDragOps.new()
	gpDrag.gpBegin(gpG, _gpLookup(), "C")
	# At zoom 2 the world snap radius halves to 12, so the host centre (24 from every anchor)
	# is out of range -> regime 2: stay on the host and follow the cursor in ITS frame.
	# 缩放 2 时世界吸附半径减半为 12，故距各锚点均 24 的宿主中心已在范围外 ->
	# 状态 2：留在宿主上，在**宿主**坐标系内跟随光标。
	var gpT: Dictionary = gpDrag.gpTargetFor(Vector2(0.0, 0.0), 2.0)
	gpEq(str(gpT.get("parent_uid", "")), "H", "with no anchor in range the part stays on its host")
	gpEq(str(gpT.get("mount_anchor", "")), "top", "…and keeps the anchor it already had")
	gpEq(gpT.get("mount_offset", Vector2.ONE), Vector2(0.0, 24.0),
		"anchorLocal (0,-24) + offset (0,24) = (0,0): the part sits exactly at the host centre")
	# The zoom decides the verdict: at zoom 1 the very same point is within the radius and snaps.
	# 缩放决定判定：缩放 1 时同一点落入半径内，于是吸附。
	var gpT1: Dictionary = gpDrag.gpTargetFor(Vector2(0.0, 0.0), 1.0)
	gpEq(gpT1.get("mount_offset", Vector2.ONE), Vector2.ZERO,
		"at zoom 1 the same point snaps to the anchor instead of following the cursor")
	# Computing a target must NOT write the node — only gpApply() does, which is what keeps the
	# commit path able to hand a real difference to GPSetMountCommand.
	# 计算目标绝不能写节点 —— 只有 gpApply() 才写，这正是提交路径能把真实差异交给
	# GPSetMountCommand 的前提。
	gpEq(gpChild.gpMountOffset, Vector2.ZERO, "gpTargetFor only computes; it does not write the node")
	gpEq(gpChild.gpParentUid, "H", "the part was never orphaned by a follow-the-cursor target")


func gpTestUnorientIsTheInverseOfOrient() -> void:
	var gpCases: Array[Dictionary] = []
	gpCases.append({"v": Vector2(3.0, 4.0), "flip": false, "rot": 0.0})
	gpCases.append({"v": Vector2(3.0, 4.0), "flip": false, "rot": 37.0})
	gpCases.append({"v": Vector2(3.0, 4.0), "flip": true, "rot": 0.0})
	gpCases.append({"v": Vector2(-5.0, 2.0), "flip": true, "rot": -128.0})
	for gpC in gpCases:
		var gpV: Vector2 = gpC["v"]
		var gpF: bool = bool(gpC["flip"])
		var gpR: float = float(gpC["rot"])
		var gpO: Vector2 = GPMountResolver.gpOrientLocal(gpV, gpF, gpR)
		var gpBack: Vector2 = GPMountDragOps.gpUnorientLocal(gpO, gpF, gpR)
		gpApprox(gpBack.x, gpV.x, GP_EPS,
			"un-orienting undoes the forward map (x) for rot=%.1f flip=%s" % [gpR, str(gpF)])
		gpApprox(gpBack.y, gpV.y, GP_EPS,
			"un-orienting undoes the forward map (y) for rot=%.1f flip=%s" % [gpR, str(gpF)])

	# Two cases pinned numerically, so the round trip cannot pass by tautology.
	# 另有两例按数值钉死，使往返不可能靠同义反复通过。
	gpEq(GPMountDragOps.gpUnorientLocal(Vector2(3.0, 4.0), false, 0.0), Vector2(3.0, 4.0),
		"no flip and no rotation is the identity")
	gpEq(GPMountDragOps.gpUnorientLocal(Vector2(3.0, 4.0), true, 0.0), Vector2(-3.0, 4.0),
		"a flip mirrors x back")
	# Order matters: the forward map is "mirror then rotate", so the inverse must un-rotate BEFORE
	# un-mirroring. Doing it the other way round would give a visibly different answer.
	# 顺序要紧：正向映射是「先镜像再旋转」，故逆向必须在反镜像**之前**先反旋转。
	# 反过来的顺序会给出明显不同的结果。
	var gpSeq: Vector2 = GPMountDragOps.gpUnorientLocal(Vector2(1.0, 0.0), true, 90.0)
	gpApprox(gpSeq.x, 0.0, GP_EPS, "flip+rotate undoes as un-rotate-then-un-mirror (x)")
	gpApprox(gpSeq.y, -1.0, GP_EPS, "flip+rotate undoes as un-rotate-then-un-mirror (y)")


# ---------------------------------------------------------------------------
# Mount-aware consumers — hit test / centre / rect / collision
# 感知挂载的消费方 —— 命中 / 中心 / 矩形 / 碰撞
# ---------------------------------------------------------------------------

func gpTestHitNodePrefersTheDeeperPart() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddNode(_gpNode("H", "host_mnt", Vector2(0.0, 0.0)))
	gpG.gpAddNode(_gpMounted("C", "child_mnt", "H", "top"))
	var gpB: GPGraphBinder = _gpBinder(gpG)
	gpEq(GPCanvasHitTest.gpHitNode(gpG, gpB, Vector2(0.0, -20.0)), "C",
		"where a part overlaps its host the PART wins, so a nozzle stays selectable")
	gpEq(GPCanvasHitTest.gpHitNode(gpG, gpB, Vector2(20.0, 0.0)), "H",
		"outside the part's rect the host still wins")
	gpEq(GPCanvasHitTest.gpHitNode(gpG, gpB, Vector2(-8.0, 5.0)), "H",
		"a point vertically clear of the part hits the host")
	gpEq(GPCanvasHitTest.gpHitNode(gpG, gpB, Vector2(200.0, 200.0)), "",
		"a point under nothing hits nothing")
	gpB.free()


func gpTestHitNodeKeepsDeclarationOrderOnTies() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddNode(_gpNode("first", "host_mnt", Vector2(0.0, 0.0)))
	gpG.gpAddNode(_gpNode("second", "host_mnt", Vector2(0.0, 0.0)))
	var gpB: GPGraphBinder = _gpBinder(gpG)
	gpEq(GPCanvasHitTest.gpHitNode(gpG, gpB, Vector2(0.0, 0.0)), "first",
		"with no mounts the FIRST declared node still wins, exactly as before this change")
	gpB.free()


func gpTestNodeCenterAndRectFollowTheDerivedOrigin() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddNode(_gpNode("H", "host_mnt", Vector2(0.0, 0.0)))
	var gpChild: GPPIDNode = _gpMounted("C", "child_mnt", "H", "top")
	gpChild.gpPosition = Vector2(999.0, 999.0)
	gpG.gpAddNode(gpChild)
	var gpB: GPGraphBinder = _gpBinder(gpG)
	gpEq(GPCanvasHitTest.gpNodeCenter(gpG, "C", Callable(gpB, "gpDefFor")), Vector2(0.0, -24.0),
		"gpNodeCenter reads the DERIVED origin, not the stale stored coordinate")
	gpEq(GPCanvasHitTest.gpNodeCenter(gpG, "ghost", Callable(gpB, "gpDefFor")), Vector2.INF,
		"an unknown id still reports INF")
	var gpR: Rect2 = GPCanvasHitTest.gpNodeRect(gpG, gpB, "C")
	gpEq(gpR.size, Vector2(16.0, 16.0), "the rect keeps the definition's nominal envelope")
	gpEq(gpR.get_center(), Vector2(0.0, -24.0), "the rect is centred on the derived origin")
	gpCheck(gpR.get_center() != Vector2(999.0, 999.0), "the stale coordinate is provably not used")
	gpB.free()


func gpTestCollisionIgnoresMountedParts() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddNode(_gpNode("H", "host_mnt", Vector2(0.0, 0.0)))
	var gpPart: GPPIDNode = _gpMounted("C", "child_mnt", "H", "top")
	# A stale, meaningless coordinate that happens to sit on another symbol: if parts took part
	# in the relaxation, this phantom envelope would push a real node off empty ground.
	# 一个恰好落在另一图元上的、过期且无意义的坐标：若部件参与松弛，
	# 这个幽灵包络就会把一个真实图元从空地上推开。
	gpPart.gpPosition = Vector2(500.0, 500.0)
	gpG.gpAddNode(gpPart)
	gpG.gpAddNode(_gpNode("Y", "host_mnt", Vector2(500.0, 500.0)))
	var gpOut: Dictionary = GPNodeCollision.gpResolve(gpG, _gpLookup(), _gpStr("H"))
	gpCheck(not gpOut.has("C"), "a mounted part is never a collision participant")
	gpCheck(not gpOut.has("Y"), "a real node is not pushed by the part's stale phantom envelope")

	# Positive control: the very same call DOES separate two genuinely overlapping top-level
	# nodes, so the empty result above cannot be a vacuous pass.
	# 正向对照：同一次调用**确实**会分离两个真正重叠的顶层图元，
	# 故上面的空结果不可能是空转通过。
	gpG.gpGetNode("Y").gpPosition = Vector2(0.0, 0.0)
	var gpOut2: Dictionary = GPNodeCollision.gpResolve(gpG, _gpLookup(), _gpStr("H"))
	gpCheck(gpOut2.has("Y"), "the same solver separates two genuinely overlapping top-level nodes")


# ---------------------------------------------------------------------------
# GPMountResolver queries the menu and the preview depend on
# 菜单与预览所依赖的 GPMountResolver 查询
# ---------------------------------------------------------------------------

func gpTestFreeAnchorsForDefHonoursKindFitAndCap() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddNode(_gpNode("H", "typed_host", Vector2(0.0, 0.0)))
	var gpNozzle: GPSymbolDef = _gpNozzleDef()
	var gpFree: Array[String] = GPMountResolver.gpFreeAnchorsForDef(gpG, _gpLookup(), "H", gpNozzle)
	gpEq(gpFree.size(), 3, "every anchor accepting a NOZZLE is offered, the universal one included")
	gpCheck("nz_a" in gpFree, "the uncapped nozzle socket is offered")
	gpCheck("nz_b" in gpFree, "the capped-but-empty nozzle socket is offered")
	gpCheck("gen" in gpFree, "an unrestricted anchor accepts a NOZZLE as well")

	# Fill the capped socket: 1 == gpMaxOccupancy, so it drops out.
	# 占满限额为 1 的插座：占用数 1 == gpMaxOccupancy，故它退出空闲表。
	gpG.gpAddNode(_gpMounted("occ", "nozzle_mnt", "H", "nz_b"))
	gpFree = GPMountResolver.gpFreeAnchorsForDef(gpG, _gpLookup(), "H", gpNozzle)
	gpEq(gpFree.size(), 2, "a full capped socket drops out of the free list")
	gpCheck(not ("nz_b" in gpFree), "the full socket is no longer free")
	gpEq(GPMountResolver.gpOccupancy(gpG, "H", "nz_b"), 1, "occupancy is reported for the menu")

	var gpAct: GPSymbolDef = _gpChildDef()
	gpFree = GPMountResolver.gpFreeAnchorsForDef(gpG, _gpLookup(), "H", gpAct)
	gpEq(gpFree.size(), 1, "an ACTUATOR only ever sees the one unrestricted anchor")
	gpEq(gpFree[0], "gen", "…and that anchor is the unrestricted one")

	# gpMountFit narrows a child to specific anchor NAMES, on top of the kind rule.
	# gpMountFit 在类型规则之外，把子件再收窄到特定**锚点名**。
	var gpFit: GPSymbolDef = _gpNozzleDef()
	var gpFitList: Array[String] = []
	gpFitList.append("nz_a")
	gpFit.gpMountFit = gpFitList
	gpFree = GPMountResolver.gpFreeAnchorsForDef(gpG, _gpLookup(), "H", gpFit)
	gpEq(gpFree.size(), 1, "gpMountFit narrows the child to the named anchors only")
	gpEq(gpFree[0], "nz_a", "the whitelisted anchor is the only one offered")

	gpEq(GPMountResolver.gpFirstFreeAnchorForDef(gpG, _gpLookup(), "H", gpNozzle), "nz_a",
		"the FIRST free anchor follows the host definition's own declaration order")
	gpEq(GPMountResolver.gpFirstFreeAnchorForDef(gpG, _gpLookup(), "H", gpFit), "nz_a",
		"a whitelisted child lands on its own anchor")
	gpEq(GPMountResolver.gpFirstFreeAnchorForDef(gpG, _gpLookup(), "ghost", gpNozzle), "",
		"an unknown host reports no anchor to drop onto")

	# A symbol that cannot be mounted at all has nowhere to go — the menu must grey out.
	# 完全不可挂载的图元无处可去 —— 菜单必须置灰。
	var gpPlain: GPSymbolDef = GPSymbolDef.new()
	gpPlain.gpId = "unmountable"
	gpEq(GPMountResolver.gpFreeAnchorsForDef(gpG, _gpLookup(), "H", gpPlain).size(), 0,
		"a symbol with no mount kind has nowhere to go")
	gpEq(GPMountResolver.gpFirstFreeAnchorForDef(gpG, _gpLookup(), "H", gpPlain), "",
		"…and the 'first free anchor' query reports the empty string")
	gpEq(GPMountResolver.gpFreeAnchorsForDef(gpG, _gpLookup(), "H", null).size(), 0,
		"a null child definition yields no anchor rather than crashing")


func gpTestMountableDefsFiltersAndSorts() -> void:
	var gpZ: GPSymbolDef = _gpChildDef()
	gpZ.gpId = "zeta_part"
	var gpA: GPSymbolDef = _gpChildDef()
	gpA.gpId = "alpha_part"
	gpA.gpMountKind = "NOZZLE"
	var gpPlain: GPSymbolDef = GPSymbolDef.new()
	gpPlain.gpId = "beta_plain"
	var gpDefs: Array[GPSymbolDef] = []
	gpDefs.append(gpZ)
	gpDefs.append(gpPlain)
	gpDefs.append(gpA)
	var gpOut: Array[GPSymbolDef] = GPMountResolver.gpMountableDefs(gpDefs)
	gpEq(gpOut.size(), 2, "only mountable definitions are returned")
	gpEq(gpOut[0].gpId, "alpha_part", "the list is sorted by id, so a menu order is stable")
	gpEq(gpOut[1].gpId, "zeta_part", "…and the second entry follows it")
	var gpEmpty: Array[GPSymbolDef] = []
	gpEq(GPMountResolver.gpMountableDefs(gpEmpty).size(), 0, "an empty input yields an empty list")


# ---------------------------------------------------------------------------
# A host's own ports YIELD to the nozzles mounted on it (user-reported defects)
# 宿主自身的端口**让位**于挂在其上的管嘴（用户报告的缺陷）
# ---------------------------------------------------------------------------
#
# Two reported defects share this one cause: the wall positions baked into a vessel's definition sit
# UNDER the nozzle tips standing on that same wall, so the host's port swallowed every press aimed
# at a nozzle and pipes started at the vessel wall instead of at the nozzle the drawing shows.
# 两个被报告的缺陷同出一因：内置在容器定义里的壁面位置正压在立于同一壁面的管嘴端**下面**，故宿主
# 端口吞掉了每一次指向管嘴的按下，管线也从罐壁起步、而非从图纸真正画出的管嘴起步。

# A 64x48 vessel with TWO process ports of its own AND a nozzle socket on top.
# 一台 64x48 的容器：自身**两个**工艺端口，外加顶部一个管嘴插座。
func _gpPortHostDef() -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = "port_host"
	gpD.gpDefaultSize = Vector2(64.0, 48.0)
	var gpP: Array[GPPort] = []
	gpP.append(GPPort.gpMake("in", Vector2(0.0, 0.5), Vector2(-1.0, 0.0)))
	gpP.append(GPPort.gpMake("out", Vector2(1.0, 0.5), Vector2(1.0, 0.0)))
	gpD.gpPorts = gpP
	var gpA: Array[GPAttachPoint] = []
	gpA.append(GPAttachPoint.gpMake("nz_a", Vector2(0.5, 0.0), Vector2(0.0, -1.0),
		_gpStr("NOZZLE")))
	gpD.gpAttachPoints = gpA
	return gpD


# A 4x2 NOZZLE with a port at EACH end — equip facing the host, pipe facing outboard. The real
# DGENERAL008 in miniature, and the smallest thing that can expose the pick-radius conflict.
# 一支 4x2 的管嘴，**两端**各一个端口 —— equip 朝向宿主、pipe 朝外。即真实 DGENERAL008 的缩微版，
# 也是能暴露「拾取半径冲突」的最小构造。
func _gpPortNozzleDef() -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = "port_nozzle"
	gpD.gpDefaultSize = Vector2(4.0, 2.0)
	gpD.gpMountKind = "NOZZLE"
	var gpP: Array[GPPort] = []
	gpP.append(GPPort.gpMake("equip", Vector2(0.0, 0.5), Vector2(-1.0, 0.0)))
	gpP.append(GPPort.gpMake("pipe", Vector2(1.0, 0.5), Vector2(1.0, 0.0)))
	gpD.gpPorts = gpP
	return gpD


# An ACTUATOR carrying its own SIGNAL terminal — the negative control. A signal terminal must never
# take a valve's process ports away.
# 一台自带 SIGNAL 端子的执行机构 —— 反向对照。信号端子**绝不**得剥夺阀门的工艺端口。
func _gpSignalPartDef() -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = "sig_part"
	gpD.gpDefaultSize = Vector2(16.0, 16.0)
	gpD.gpMountKind = "ACTUATOR"
	var gpP: Array[GPPort] = []
	gpP.append(GPPort.gpMake("sig", Vector2(0.5, 0.0), Vector2(0.0, -1.0), GPPort.GP_SIGNAL))
	gpD.gpPorts = gpP
	return gpD


func _gpPortLookup() -> Callable:
	return func(gpId: String) -> GPSymbolDef:
		if gpId == "port_host":
			return _gpPortHostDef()
		if gpId == "port_nozzle":
			return _gpPortNozzleDef()
		if gpId == "sig_part":
			return _gpSignalPartDef()
		return null


func gpTestHostPortsYieldToItsMountedNozzles() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddNode(_gpNode("H", "port_host", Vector2.ZERO))
	var gpLook: Callable = _gpPortLookup()
	# Baseline (and the reversibility half): with nothing mounted the host answers for itself.
	# 基线（也是可逆性的一半）：没有挂任何东西时，宿主代表自己应答。
	gpCheck(not GPMountResolver.gpPortsSuperseded(gpG, gpLook, gpG.gpGetNode("H")),
		"a host with no nozzle mounted keeps its own ports")
	gpEq(GPMountResolver.gpServingPorts(gpG, gpLook, gpG.gpGetNode("H")).size(), 2,
		"a bare host serves its own two ports")
	gpEq(GPPortAnchor.gpAnchors(gpG, gpLook, _gpStr("H")).size(), 2,
		"a bare host exposes its own two anchors")

	var gpNoz: GPPIDNode = _gpMounted("N", "port_nozzle", "H", "nz_a")
	gpG.gpAddNode(gpNoz)
	gpCheck(GPMountResolver.gpPortsSuperseded(gpG, gpLook, gpG.gpGetNode("H")),
		"a mounted process nozzle supersedes the host's own ports")
	gpEq(GPMountResolver.gpServingPorts(gpG, gpLook, gpG.gpGetNode("H")).size(), 2,
		"the nozzle answers with its own two ports in the host's place")

	# Selecting the vessel must show the NOZZLE's connection points — that is what "all pipes come
	# out of the nozzles" means on screen.
	# 选中容器时必须显示**管嘴的**接点 —— 这正是屏幕上「所有管线从管嘴连出」的含义。
	var gpAnchors: Array[Dictionary] = GPPortAnchor.gpAnchors(gpG, gpLook, _gpStr("H"))
	gpEq(gpAnchors.size(), 2, "the selected host still exposes two anchors — the nozzle's")
	for gpA in gpAnchors:
		gpEq(str(gpA["node_id"]), "N", "every anchor of a nozzle-bearing host is owned by its nozzle")
	# Asking for EVERY node must not double the dots: the host yields to ports the nozzle also
	# contributes, so the sheet-wide list stays at one anchor per nozzle port.
	# 索取**每个**节点时绝不能让锚点翻倍：宿主让出的端口由管嘴另行贡献，故全图列表仍是每个管嘴端口一个。
	gpEq(GPPortAnchor.gpAnchors(gpG, gpLook).size(), 2,
		"the sheet-wide list shows one anchor per nozzle port, not two overlapping dots")

	# Reversibility: detaching the nozzle hands the host its own ports back, with no file migration
	# — the port NAME an edge stores still resolves for the life of the drawing.
	# 可逆性：卸下管嘴即把自身端口还给宿主，且无需文件迁移 —— 边存的端口**名**在图纸存续期内仍可解析。
	gpNoz.gpParentUid = ""
	gpNoz.gpMountAnchor = ""
	gpCheck(not GPMountResolver.gpPortsSuperseded(gpG, gpLook, gpG.gpGetNode("H")),
		"detaching the nozzle gives the host its own ports back")
	var gpBack: Array[Dictionary] = GPPortAnchor.gpAnchors(gpG, gpLook, _gpStr("H"))
	gpEq(gpBack.size(), 2, "the host exposes its own two anchors again")
	for gpA in gpBack:
		gpEq(str(gpA["node_id"]), "H", "and they belong to the host once more")


func gpTestASignalPartNeverTakesTheHostPortsAway() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddNode(_gpNode("H", "port_host", Vector2.ZERO))
	gpG.gpAddNode(_gpMounted("A", "sig_part", "H", "nz_a"))
	var gpLook: Callable = _gpPortLookup()
	gpCheck(not GPMountResolver.gpPortsSuperseded(gpG, gpLook, gpG.gpGetNode("H")),
		"an actuator carries a SIGNAL terminal, so the host keeps its process ports")
	var gpSrv: Array[Dictionary] = GPMountResolver.gpServingPorts(gpG, gpLook, gpG.gpGetNode("H"))
	gpEq(gpSrv.size(), 2, "the host still serves its own two ports")
	for gpS in gpSrv:
		var gpOwner: GPPIDNode = gpS["node"]
		gpEq(gpOwner.gpInstanceId, "H", "the serving ports still belong to the host itself")


func gpTestATinyPartsBodyBeatsItsOwnAnchors() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddNode(_gpNode("H", "port_host", Vector2.ZERO))
	gpG.gpAddNode(_gpMounted("N", "port_nozzle", "H", "nz_a"))
	var gpLook: Callable = _gpPortLookup()
	var gpSel: Array[String] = _gpStr("H")
	# With the vessel selected the anchors belong to the 4x2 nozzle, which spans y -26..-22 around a
	# centre at -24 and carries one port at EACH end. A 10 px pick radius therefore covers the whole
	# part, and without a rule the part could never be grabbed — the reported "the built-in parts
	# cannot be dragged".
	# 选中容器时锚点属于那支 4x2 管嘴：它跨 y -26..-22、中心在 -24、**两端**各一个端口。
	# 故 10px 的拾取半径盖住整个部件，若没有规则，部件便永远抓不住 —— 即用户报告的「自带部件拖不动」。
	var gpAtBody: Dictionary = GPPortAnchor.gpHitPort(gpG, gpLook, Vector2(0.0, -24.0), 1.0, gpSel)
	gpCheck(gpAtBody.is_empty(),
		"pressing the part's BODY grabs no port, so the part itself can be picked up and dragged")
	# …while the tip still snaps, so a pipe can still be started from the nozzle.
	# ……而按端头仍然吸附，故仍可从管嘴接出管线。
	var gpAtTip: Dictionary = GPPortAnchor.gpHitPort(gpG, gpLook, Vector2(0.0, -26.0), 1.0, gpSel)
	gpEq(str(gpAtTip.get("node_id", "")), "N", "pressing a nozzle tip still grabs its port")
	gpEq(str(gpAtTip.get("port_id", "")), "pipe", "the outboard tip is the pipe port")
	var gpAtRoot: Dictionary = GPPortAnchor.gpHitPort(gpG, gpLook, Vector2(0.0, -22.0), 1.0, gpSel)
	gpEq(str(gpAtRoot.get("port_id", "")), "equip", "the inboard tip is the equip port")
	# Positive control: a wire hunting for a landing point anywhere is left completely alone — the
	# nearest port wins as it always did, so the rule cannot be a blanket refusal.
	# 正向对照：一条在全图寻找落点的连线完全不受影响 —— 仍是最近端口取胜，故该规则不可能是无差别拒绝。
	var gpLoose: Dictionary = GPPortAnchor.gpHitPort(gpG, gpLook, Vector2(0.0, -24.0), 1.0)
	gpCheck(not gpLoose.is_empty(),
		"a wire landing keeps snapping to the nearest port, exactly as before")


func gpTestAPartNeverPushesTheHostItCouldAttachTo() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddNode(_gpNode("H", "port_host", Vector2.ZERO))
	# NOT mounted: this is a part being dragged across the sheet, which is when the collision pass
	# used to shove the vessel away (the reported "a nozzle dragged onto the vessel pushed the vessel").
	# **未挂载**：这是被拖过图纸的部件，也正是碰撞松弛过去把容器推开的时刻
	#（即用户报告的「把管嘴拖到罐上却把罐推开了」）。
	gpG.gpAddNode(_gpNode("N", "port_nozzle", Vector2(8.0, 0.0)))
	var gpLook: Callable = _gpPortLookup()
	gpCheck(GPMountResolver.gpAcceptsPartKind(gpG, gpLook, gpG.gpGetNode("H"), _gpPortNozzleDef()),
		"a vessel with a NOZZLE socket could host a nozzle")
	gpCheck(not GPMountResolver.gpAcceptsPartKind(gpG, gpLook, gpG.gpGetNode("H"),
		_gpSignalPartDef()),
		"…but the same socket refuses an actuator, so an actuator never pins it")
	gpCheck(not GPMountResolver.gpAcceptsPartKind(gpG, gpLook, gpG.gpGetNode("N"),
		_gpPortNozzleDef()),
		"a part is not a host for anything")

	var gpPins: Array[String] = GPMountResolver.gpPinnedHosts(gpG, gpLook, _gpStr("N"))
	gpEq(gpPins.size(), 1, "the one node that could host the nozzle is pinned")
	if gpPins.size() == 1:
		gpEq(gpPins[0], "H", "and it is the vessel")

	# Control: without the pin the very same overlap DOES shove the host, so the green result below
	# cannot be a vacuous pass.
	# 对照：不加钉子时同样的重叠**确实**会把宿主推开，故下方变绿不可能是空转。
	var gpUnpinned: Dictionary = GPNodeCollision.gpResolve(gpG, gpLook, _gpStr("N"),
		GPNodeCollision.GP_DEFAULT_PADDING)
	gpCheck(gpUnpinned.has("H"), "control: an unpinned overlap pushes the vessel")
	var gpPinned: Dictionary = GPNodeCollision.gpResolve(gpG, gpLook, _gpStr("N", "H"),
		GPNodeCollision.GP_DEFAULT_PADDING)
	gpCheck(not gpPinned.has("H"), "with the host pinned it stays exactly where the user put it")

	# And an ordinary drag — one that moves no part — pins nothing, so every pre-existing drag
	# behaves exactly as before, including which neighbours it scatters.
	# 而一次**未移动任何部件**的普通拖拽不钉任何节点，故既有的每一次拖拽行为完全不变，
	# 包括它会散开哪些邻件。
	gpEq(GPMountResolver.gpPinnedHosts(gpG, gpLook, _gpStr("H")).size(), 0,
		"dragging a non-part pins nothing at all")


# A host with a socket on EACH vertical face, so "nearest" has something to choose between.
# 一个上下两面各有一个插座的宿主，使「最近」有得可选。
func _gpTwoAnchorDef() -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = "two_anchor"
	gpD.gpDefaultSize = Vector2(20.0, 20.0)
	var gpA: Array[GPAttachPoint] = []
	gpA.append(GPAttachPoint.gpMake("nz_top", Vector2(0.5, 0.0), Vector2(0.0, -1.0),
		_gpStr("NOZZLE")))
	gpA.append(GPAttachPoint.gpMake("nz_bottom", Vector2(0.5, 1.0), Vector2(0.0, 1.0),
		_gpStr("NOZZLE")))
	gpD.gpAttachPoints = gpA
	return gpD


# The context-menu attach choice must honour WHERE the user right-clicked: the free anchor
# nearest to the click wins, so a click on the vessel's upper half adds a nozzle at the top
# facing up. The declared order stays the fallback when no position is known.
# 右键附件选择必须尊重用户**点在哪里**：距点击最近的空闲锚点取胜，故点容器上半部添加的管嘴
# 落在上部朝上。无位置信息时仍以声明顺序兜底。
func gpTestTheAttachMenuPicksTheAnchorNearestTheClick() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddNode(_gpNode("T", "two_anchor", Vector2(500.0, 400.0)))
	var gpLook: Callable = func(gpId: String) -> GPSymbolDef:
		if gpId == "two_anchor":
			return _gpTwoAnchorDef()
		return null
	var gpNames: Array[String] = _gpStr("nz_top", "nz_bottom")
	gpEq(GPMountResolver.gpNearestAnchorName(gpG, gpLook, "T", gpNames, Vector2(500.0, 392.0)),
		"nz_top", "a click on the upper half picks the top anchor")
	gpEq(GPMountResolver.gpNearestAnchorName(gpG, gpLook, "T", gpNames, Vector2(500.0, 408.0)),
		"nz_bottom", "a click on the lower half picks the bottom anchor")
	gpEq(GPMountResolver.gpNearestAnchorName(gpG, gpLook, "T", gpNames, Vector2.ZERO),
		"nz_top", "no click position keeps the declared order")


# A drop INSIDE a host but beyond every anchor's snap radius must still attach — to the nearest
# anchor of the containing host. The old behaviour let the part fall through to a loose top-level
# placement: horizontal, directionless, sitting on the very host it was aimed at.
# 落点在宿主**体内**却超出所有锚点吸附半径时仍须挂载 —— 挂到该宿主最近的锚点。旧行为会让部件
# 降级成松散顶层放置：水平、无方向、恰好压在它所瞄准的宿主上。
func gpTestADropOnTheHostBodyStillAttaches() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddNode(_gpNode("H", "port_host", Vector2(500.0, 400.0)))
	var gpLook: Callable = _gpPortLookup()
	var gpC: Dictionary = GPMountResolver.gpBodyCandidate(gpG, gpLook, Vector2(510.0, 406.0),
		"NOZZLE")
	gpCheck(bool(gpC.get("hit", false)), "a drop on the host's belly is a hit")
	gpEq(str(gpC.get("parent_uid", "")), "H", "the belly drop lands on the host under the cursor")
	gpEq(str(gpC.get("anchor", "")), "nz_a", "the belly drop takes the host's nearest anchor")
	gpCheck(not bool(GPMountResolver.gpBodyCandidate(gpG, gpLook, Vector2(600.0, 400.0),
		"NOZZLE").get("hit", false)), "a drop in open space stays a loose placement")
	gpCheck(not bool(GPMountResolver.gpBodyCandidate(gpG, gpLook, Vector2(510.0, 406.0),
		"MANHOLE").get("hit", false)), "a kind the host does not accept is refused inside too")

# ---------------------------------------------------------------------------
# Auto part numbering — "M1 / M2 per host, never repeated" (user's real-usage rule)
# 部件自动编号 —— 「每台宿主内 M1 / M2、绝不重复」（用户实测规则）
# ---------------------------------------------------------------------------

# A part def carrying the numbering contract. / 带编号契约的部件定义。
func _gpTaggedDef(gpId: String, gpKind: String, gpKey: String, gpPrefix: String) -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = gpId
	gpD.gpMountKind = gpKind
	gpD.gpPartTagKey = gpKey
	gpD.gpPartTagPrefix = gpPrefix
	return gpD


func gpTestPartsNumberSequentiallyPerHost() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddNode(_gpNode("H", "host_mnt", Vector2.ZERO))
	var gpNozDef: GPSymbolDef = _gpTaggedDef("tag_noz", "NOZZLE", "nozzle_id", "N")
	var gpMhDef: GPSymbolDef = _gpTaggedDef("tag_mh", "MANHOLE", "manhole_id", "M")
	var gpActDef: GPSymbolDef = _gpTaggedDef("tag_act", "ACTUATOR", "", "")
	gpEq(GPMountResolver.gpNextPartTag(gpG, gpNozDef, "H"), "N1", "an empty host mints N1")
	# An existing sibling pushes the water mark. / 已有兄弟件把水位线推上去。
	var gpSib: GPPIDNode = _gpMounted("S1", "tag_noz", "H", "a")
	gpSib.gpProps["nozzle_id"] = "N2"
	gpG.gpAddNode(gpSib)
	gpEq(GPMountResolver.gpNextPartTag(gpG, gpNozDef, "H"), "N3",
		"the next number is max existing + 1, so it can never repeat inside the host")
	var gpSib2: GPPIDNode = _gpMounted("S2", "tag_noz", "H", "b")
	gpSib2.gpProps["nozzle_id"] = "N7"
	gpG.gpAddNode(gpSib2)
	gpEq(GPMountResolver.gpNextPartTag(gpG, gpNozDef, "H"), "N8", "N7 pushes the mark to N8")
	# A hand-typed non-numeric value neither blocks nor crashes the scan.
	# 手打的非数字取值既不阻塞也不会使扫描崩溃。
	var gpSib3: GPPIDNode = _gpMounted("S3", "tag_noz", "H", "c")
	gpSib3.gpProps["nozzle_id"] = "N9A"
	gpG.gpAddNode(gpSib3)
	gpEq(GPMountResolver.gpNextPartTag(gpG, gpNozDef, "H"), "N8",
		"a non-numeric N9A is skipped, not treated as a number")
	# Numbering is PER HOST: another host starts from 1 again.
	# 编号按宿主隔离：另一台宿主重新从 1 起。
	gpG.gpAddNode(_gpNode("H2", "host_mnt", Vector2.ZERO))
	gpEq(GPMountResolver.gpNextPartTag(gpG, gpNozDef, "H2"), "N1", "numbering is per host")
	# The two series never collide: M never sees the N numbers.
	# 两个系列永不相撞：M 系看不到 N 系的号。
	gpEq(GPMountResolver.gpNextPartTag(gpG, gpMhDef, "H"), "M1",
		"the manhole series is independent of the nozzle numbers")
	# A part without a numbering contract assigns nothing.
	# 无编号契约的部件不赋任何值。
	gpEq(GPMountResolver.gpNextPartTag(gpG, gpActDef, "H"), "",
		"a part without a numbering contract gets no number")
	gpEq(GPMountResolver.gpNextPartTag(gpG, gpNozDef, ""), "",
		"no host, no number")


func gpTestAttachMintsTheNextPartNumber() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddNode(_gpNode("H", "host_mnt", Vector2.ZERO))
	var gpCtx: GPCommandContext = _gpCtx(gpG)
	# The real pack defs carry the contract, so the real ids drive the real behaviour.
	# 真实 pack 定义自带契约，故用真实 id 驱动真实行为。
	var gpCmd: GPAttachNodeCommand = GPAttachNodeCommand.new("DGENERAL008", "H", "top", "")
	gpCheck(gpCmd.gpExecute(gpCtx), "attaching a nozzle succeeds")
	var gpN: GPPIDNode = gpG.gpGetNode(gpCmd.gpCreatedId)
	gpCheck(gpN != null, "the new nozzle exists")
	if gpN != null:
		gpEq(str(gpN.gpProps.get("nozzle_id", "")), "N1",
			"a nozzle attached to an empty host is numbered N1 automatically")
	# A sibling holding N4 forces the next attach past it.
	# 占用 N4 的兄弟件迫使下一次挂载跳过它。
	var gpSib: GPPIDNode = _gpMounted("S", "DGENERAL008", "H", "t2")
	gpSib.gpProps["nozzle_id"] = "N4"
	gpG.gpAddNode(gpSib)
	var gpCmd2: GPAttachNodeCommand = GPAttachNodeCommand.new("DGENERAL008", "H", "top", "")
	gpCheck(gpCmd2.gpExecute(gpCtx), "attaching a second nozzle succeeds")
	var gpN2: GPPIDNode = gpG.gpGetNode(gpCmd2.gpCreatedId)
	gpCheck(gpN2 != null, "the second nozzle exists")
	if gpN2 != null:
		gpEq(str(gpN2.gpProps.get("nozzle_id", "")), "N5",
			"the second nozzle skips the taken N4 — no duplicate inside the host")
	# The manhole series is independent: M1 even though N1/N5 exist.
	# 人孔系列独立：即便 N1/N5 已存在也拿到 M1。
	var gpCmd3: GPAttachNodeCommand = GPAttachNodeCommand.new("DGENERAL007", "H", "side", "")
	gpCheck(gpCmd3.gpExecute(gpCtx), "attaching a manhole succeeds")
	var gpN3: GPPIDNode = gpG.gpGetNode(gpCmd3.gpCreatedId)
	gpCheck(gpN3 != null, "the new manhole exists")
	if gpN3 != null:
		gpEq(str(gpN3.gpProps.get("manhole_id", "")), "M1",
			"the manhole gets M1 — its own series, never colliding with N")


# ---------------------------------------------------------------------------
# Facing-side adaptation — "drop a nozzle at the bottom and it faces down"
# (user's real-usage rule, round 4)
# 朝向随边自适应 —— 「管嘴放到宿主下方就朝下」（用户实测规则，第四轮）
# ---------------------------------------------------------------------------

func gpTestSideOutwardDirFollowsTheDropPoint() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddNode(_gpNode("H", "host_mnt", Vector2.ZERO))
	var gpLook: Callable = _gpLookup()
	var gpHost: GPPIDNode = gpG.gpGetNode("H")
	gpEq(GPMountResolver.gpSideOutwardDir(gpG, gpLook, gpHost, Vector2(40.0, 10.0)),
		Vector2(1.0, 0.0), "a drop right of the centre faces RIGHT")
	gpEq(GPMountResolver.gpSideOutwardDir(gpG, gpLook, gpHost, Vector2(10.0, 40.0)),
		Vector2(0.0, 1.0), "a drop below the centre faces DOWN")
	gpEq(GPMountResolver.gpSideOutwardDir(gpG, gpLook, gpHost, Vector2(-10.0, 0.0)),
		Vector2(-1.0, 0.0), "a drop left of the centre faces LEFT")
	gpEq(GPMountResolver.gpSideOutwardDir(gpG, gpLook, gpHost, Vector2(0.0, -5.0)),
		Vector2(0.0, -1.0), "a drop above the centre faces UP")
	gpEq(GPMountResolver.gpSideOutwardDir(gpG, gpLook, gpHost, Vector2.ZERO), Vector2.ZERO,
		"a drop at the centre names no side, so the native orientation stays")


func gpTestBodyCandidatePrefersTheFacingSideOverRawDistance() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddNode(_gpNode("H", "host_mnt", Vector2.ZERO))
	var gpLook: Callable = _gpLookup()
	# The drop (10,10) lies on the RIGHT half (|x| >= |y|), yet the BOTTOM anchor (0,24) is
	# measurably nearer than the RIGHT one (32,0): 17.2 vs 24.2. The facing side must win —
	# the old nearest-only rule picked the bottom anchor and the part faced down while sitting
	# on the right half.
	# 落点 (10,10) 位于右半（|x| >= |y|），但「下」锚点 (0,24) 明显近于「右」锚点 (32,0)：
	# 17.2 对 24.2。朝向侧必须取胜 —— 旧的纯最近规则会选中下锚，部件压在右半却朝下。
	var gpR: Dictionary = GPMountResolver.gpBodyCandidate(gpG, gpLook, Vector2(10.0, 10.0),
		"ACTUATOR")
	gpCheck(bool(gpR["hit"]), "a drop inside the envelope still attaches")
	gpEq(str(gpR["anchor"]), "right", "the anchor FACING the drop side wins over a nearer one")
	# Mirror check: a drop in the lower half (|y| dominant) picks the bottom anchor.
	# 镜像核查：下半部（|y| 主导）的落点选中「下」锚。
	var gpD: Dictionary = GPMountResolver.gpBodyCandidate(gpG, gpLook, Vector2(5.0, 15.0),
		"ACTUATOR")
	gpEq(str(gpD["anchor"]), "bot", "a drop in the lower half faces DOWN")


func gpTestLooseReleaseOnAHostMountsInsteadOfLandingLoose() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddNode(_gpNode("H", "host_mnt", Vector2.ZERO))
	gpG.gpAddNode(_gpNode("P", "child_mnt", Vector2(200.0, 200.0)))
	var gpLook: Callable = _gpLookup()
	# Zoom 2 halves the snap radius to 12, so (10,10) is out of every anchor's range and the
	# BODY fallback decides — which must pick the FACING side, not the merely nearer anchor.
	# 缩放 2 把吸附半径减半为 12，故 (10,10) 在所有锚点范围之外，由**本体兜底**裁决 ——
	# 它必须选中朝向侧，而不是单纯更近的锚点。
	var gpT: Dictionary = GPMountResolver.gpLooseReleaseAttach(gpG, gpLook, "P",
		Vector2(10.0, 10.0), 2.0)
	gpCheck(not gpT.is_empty(), "a loose part released on a host yields a mount tuple")
	if not gpT.is_empty():
		gpEq(str(gpT["parent_uid"]), "H", "the tuple names the host under the release point")
		gpEq(str(gpT["mount_anchor"]), "right", "…the facing-side anchor of that host")
		gpEq(gpT["mount_offset"], Vector2.ZERO, "…sits exactly on the anchor, no stale nudge")
		gpEq(float(gpT["mount_angle_deg"]), 0.0, "…with the anchor's own native orientation")
	gpEq(GPMountResolver.gpLooseReleaseAttach(gpG, gpLook, "P", Vector2(500.0, 500.0), 1.0)
		.size(), 0, "a release in empty space stays an ordinary move")
	gpEq(GPMountResolver.gpLooseReleaseAttach(gpG, gpLook, "H", Vector2(10.0, 10.0), 1.0)
		.size(), 0, "a symbol that is not a part never mounts")
	# An already-mounted part is routed to the mount-drag kernel, not here.
	# 已挂载部件走挂载拖拽内核，不走此处。
	gpG.gpAddNode(_gpMounted("M", "child_mnt", "H", "top"))
	gpEq(GPMountResolver.gpLooseReleaseAttach(gpG, gpLook, "M", Vector2(10.0, 10.0), 1.0)
		.size(), 0, "a mounted part never re-attaches through the loose path")


func gpTestMountDragTurnsThePartTowardTheCursorSide() -> void:
	var gpG: GPPIDGraph = _gpDragGraph("right")
	var gpChild: GPPIDNode = gpG.gpGetNode("C")
	gpChild.gpMountAngleDeg = 45.0
	var gpDrag: GPMountDragOps = GPMountDragOps.new()
	gpCheck(gpDrag.gpBegin(gpG, _gpLookup(), "C"), "the drag starts")
	gpEq(float(gpDrag.gpBefore()["mount_angle_deg"]), 45.0,
		"the before-tuple records the pre-drag angle so undo can restore it")
	# Zoom 2 halves the snap radius to 12 px; every anchor of the 64x48 host at the origin is
	# farther than that from (-10, 0) -> regime 2. The cursor sits on the LEFT half, so the part
	# must turn to face LEFT: side angle 180 - anchor rotation 0 = 180.
	# 缩放 2 把吸附半径减半为 12px；原点处 64x48 宿主的各锚点距 (-10,0) 均超出 ->
	# 状态 2。光标在左半，部件必须转向**左**：侧向角 180 - 锚点角 0 = 180。
	var gpT: Dictionary = gpDrag.gpTargetFor(Vector2(-10.0, 0.0), 2.0)
	gpEq(str(gpT.get("mount_anchor", "")), "right", "regime 2 keeps the anchor it had")
	# atan2(0, -1) may return +180 or -180 depending on the zero's sign — both face LEFT.
	# atan2(0, -1) 依零的符号可能返回 +180 或 -180 —— 两者都朝左。
	gpCheck(is_equal_approx(absf(wrapf(float(gpT.get("mount_angle_deg", 999.0)), -180.0, 180.0)),
		180.0), "on the host's left half the part faces LEFT")
	gpDrag.gpApply(gpT)
	gpCheck(is_equal_approx(absf(wrapf(gpChild.gpMountAngleDeg, -180.0, 180.0)), 180.0),
		"apply writes the turned angle live")
	# Back on the right half the override dissolves: the anchor's native orientation IS right.
	# 回到右半时覆盖消解：锚点原生朝向本就是朝右。
	var gpT2: Dictionary = gpDrag.gpTargetFor(Vector2(10.0, 0.0), 2.0)
	gpApprox(float(gpT2.get("mount_angle_deg", 999.0)), 0.0, 0.001,
		"on the anchor's own side the native orientation applies untouched")
	# Below the centre (but out of every snap radius) the part faces DOWN (90): side 90 - anchor 0.
	# 中心线以下（且在各吸附半径之外）部件朝下（90）：侧向 90 - 锚点 0。
	var gpT3: Dictionary = gpDrag.gpTargetFor(Vector2(0.0, 10.0), 2.0)
	gpApprox(float(gpT3.get("mount_angle_deg", 999.0)), 90.0, 0.001,
		"below the centre the part faces DOWN")
	gpDrag.gpRestore()
	gpEq(gpChild.gpMountAngleDeg, 45.0, "restore puts the pre-drag angle back (the ESC path)")
	# A regime-1 snap resets any override to the anchor's own truth.
	# 状态 1 吸附把一切覆盖复位为锚点自身的权威。
	var gpSnap: Dictionary = gpDrag.gpTargetFor(Vector2(64.0, 24.0), 1.0)
	gpEq(str(gpSnap.get("mount_anchor", "")), "right", "the near anchor snaps")
	gpApprox(float(gpSnap.get("mount_angle_deg", 999.0)), 0.0, 0.001,
		"a snap clears the side override — the anchor's outward normal is the truth")


# ---------------------------------------------------------------------------
# The DROP must keep the facing the drag previewed
# 落位必须保留拖拽所预览的朝向
# ---------------------------------------------------------------------------

func gpTestMountDragCommitCarriesTheFacingAngle() -> void:
	var gpG: GPPIDGraph = _gpDragGraph("top")
	var gpChild: GPPIDNode = gpG.gpGetNode("C")
	var gpDrag: GPMountDragOps = GPMountDragOps.new()
	gpDrag.gpBegin(gpG, _gpLookup(), "C")
	# Zoom 2 -> radius 12; (0,10) is out of every anchor's range (the nearest, bot, is 14 away) ->
	# regime 2. The cursor sits BELOW the centre, so the part must face DOWN.
	# 缩放 2 -> 半径 12；(0,10) 在各锚点范围之外（最近的下锚相距 14）-> 状态 2。
	# 光标位于中心**下方**，故部件必须朝下。
	var gpT: Dictionary = gpDrag.gpTargetFor(Vector2(0.0, 10.0), 2.0)
	gpDrag.gpApply(gpT)
	var gpAfter: Dictionary = gpDrag.gpCommitTuple()
	gpApprox(float(gpAfter.get("mount_angle_deg", 999.0)),
		float(gpT.get("mount_angle_deg", -999.0)), 0.001,
		"the commit tuple repeats the facing the kernel just computed — no field dropped")
	# The drop asks the kernel whether anything changed, and it must ask BEFORE the rewind: a drag
	# that only turned the part is a real edit, not a no-op to be thrown away.
	# 落位向内核询问「是否发生变化」，且必须在回退**之前**问：只把部件转了个向的拖拽是真实编辑，
	# 不是可以丢弃的空操作。
	gpCheck(gpDrag.gpChanged(),
		"the kernel reports a change even though ONLY the facing differs from the drag's start")
	# The drop path proper: rewind FIRST, then let the command re-apply (one undo step).
	# 真正的落位路径：先回退，再由命令重新应用（一步撤销）。
	gpDrag.gpRestore()
	gpEq(gpChild.gpMountAngleDeg, 0.0, "restore did rewind the angle to its pre-drag value")
	var gpTs: Array[Dictionary] = [gpAfter]
	var gpCmd: GPSetMountCommand = GPSetMountCommand.new(_gpStr("C"), gpTs)
	gpCheck(gpCmd.gpExecute(_gpCtx(gpG)),
		"the drop commits even when ONLY the facing changed (a no-op by the old three fields)")
	gpApprox(gpChild.gpMountAngleDeg, float(gpT.get("mount_angle_deg", -999.0)), 0.001,
		"the released part keeps the facing the cursor previewed — it does not snap back upright")
	var gpWT: Dictionary = GPMountResolver.gpWorldTransform(gpG, _gpLookup(), gpChild)
	gpApprox(wrapf(float(gpWT["rot_deg"]), -180.0, 180.0), 90.0, 0.001,
		"top anchor (-90) + the 180 override = +90 deg: the part really points DOWN in world space")
	gpDrag.gpEnd()


func gpTestDropCommitIsNotHandTranscribed() -> void:
	# A guard against the exact regression this suite is here for: the drop used to build its
	# "after" tuple as a hand-written THREE-field literal, so gpMountAngleDeg was silently lost
	# and every part sprang back upright on release. The tuple shape is now authored once, in
	# the kernel — this test fails if anyone transcribes the field list into the tool again.
	# 针对本套件存在的那个回归的守卫：落位曾用手写**三字段**字面量构造「之后」元组，
	# 于是 gpMountAngleDeg 被静默丢弃、每个部件释放后都弹回朝上。元组形态现由内核**一处**书写 ——
	# 若有人再把字段清单抄回工具，本测试即失败。
	var gpF: FileAccess = FileAccess.open("res://src/ui/tools/place_attach_tool.gd", FileAccess.READ)
	gpCheck(gpF != null, "the drop tool's source is readable from the test run")
	if gpF == null:
		return
	var gpSrc: String = gpF.get_as_text()
	gpF.close()
	gpCheck(gpSrc.contains("gpCommitTuple()"),
		"the drop takes its after-tuple from the kernel, so the model's field list is written once")
	gpCheck(not gpSrc.contains("\"mount_offset\": gpN.gpMountOffset"),
		"no hand-copied mount_offset survives in the drop path (that copy dropped the angle)")


func gpTestLooseReleaseOnAFullSideStillFacesTheDropSide() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddNode(_gpNode("H", "typed_host", Vector2.ZERO))
	gpG.gpAddNode(_gpMounted("N1", "nozzle_mnt", "H", "nz_b"))
	gpG.gpAddNode(_gpNode("P", "nozzle_mnt", Vector2(200.0, 200.0)))
	var gpLook: Callable = _gpLookup()
	# Zoom 2 -> radius 12, so (0,10) misses every anchor, and the bottom anchor nz_b is OCCUPIED
	# (cap 1): the body fallback can only offer nz_a (up) or gen (right), neither of which faces
	# DOWN. The side override must still aim the part at the side it was dropped on.
	# 缩放 2 -> 半径 12，故 (0,10) 未命中任何锚点；且下锚 nz_b 已被占用（限额 1）：
	# 本体兜底只能给出 nz_a（朝上）或 gen（朝右），二者都不朝下。
	# 侧向覆盖仍须把部件对准其落点所在的一侧。
	var gpT: Dictionary = GPMountResolver.gpLooseReleaseAttach(gpG, gpLook, "P",
		Vector2(0.0, 10.0), 2.0)
	gpCheck(not gpT.is_empty(), "a release on the host's body still mounts")
	if gpT.is_empty():
		return
	gpEq(str(gpT["mount_anchor"]), "gen",
		"with the bottom anchor full, the nearest free one is taken — and it faces RIGHT by nature")
	gpApprox(float(gpT.get("mount_angle_deg", 999.0)), 90.0, 0.001,
		"the override turns that natively right-facing anchor DOWN, toward the drop side")
	var gpP: GPPIDNode = gpG.gpGetNode("P")
	gpP.gpParentUid = str(gpT["parent_uid"])
	gpP.gpMountAnchor = str(gpT["mount_anchor"])
	gpP.gpMountAngleDeg = float(gpT.get("mount_angle_deg", 0.0))
	var gpWT: Dictionary = GPMountResolver.gpWorldTransform(gpG, gpLook, gpP)
	gpApprox(wrapf(float(gpWT["rot_deg"]), -180.0, 180.0), 90.0, 0.001,
		"dropped on the underside of a fully occupied host, the nozzle still points DOWN")


func gpTestMountDragChangedVerdictCoversTheAngle() -> void:
	# The verdict is a pure comparison, and it is the ONLY thing standing between a re-orient and
	# a silently discarded drop — so it is tested on its own, not just through the drop path.
	# 该判定是一个纯比较，且是「转向」与「被静默丢弃的落位」之间**唯一**的屏障 ——
	# 故单独测试它，而不只经由落位路径间接覆盖。
	var gpA: Dictionary = {
		"parent_uid": "H",
		"mount_anchor": "top",
		"mount_offset": Vector2.ZERO,
		"mount_angle_deg": 0.0,
	}
	gpCheck(not GPMountDragOps.gpTuplesDiffer(gpA, gpA.duplicate()),
		"a drop that changed nothing reports no change, so no phantom undo step appears")
	var gpB: Dictionary = gpA.duplicate()
	gpB["mount_angle_deg"] = 180.0
	gpCheck(GPMountDragOps.gpTuplesDiffer(gpA, gpB),
		"a facing-only edit IS a change — comparing three fields would have missed it")
	var gpC: Dictionary = gpA.duplicate()
	gpC["mount_anchor"] = "bot"
	gpCheck(GPMountDragOps.gpTuplesDiffer(gpA, gpC), "a new anchor is a change")
	var gpD: Dictionary = gpA.duplicate()
	gpD["mount_offset"] = Vector2(1.0, 0.0)
	gpCheck(GPMountDragOps.gpTuplesDiffer(gpA, gpD), "a new nudge is a change")
	gpCheck(not GPMountDragOps.gpTuplesDiffer({}, gpA),
		"an empty side (idle kernel / vanished node) never claims a change")
	# The static verdict must agree with the live one on the real node.
	# 静态判定必须与真实节点上的实时判定一致。
	var gpG: GPPIDGraph = _gpDragGraph("top")
	var gpDrag: GPMountDragOps = GPMountDragOps.new()
	gpDrag.gpBegin(gpG, _gpLookup(), "C")
	gpCheck(not gpDrag.gpChanged(), "an untouched part has not changed yet")
	gpDrag.gpApply(gpDrag.gpTargetFor(Vector2(0.0, 10.0), 2.0))
	gpCheck(gpDrag.gpChanged(), "after the re-orient the live verdict agrees with the static one")
	gpDrag.gpEnd()


# ---------------------------------------------------------------------------
# The palette DRAG lands where the ghost previewed — one rule, shared
# 图库拖出按幽灵预览落位 —— 一条规则，两处共用
# ---------------------------------------------------------------------------

func gpTestPlacementTupleLandsAtTheCursor() -> void:
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddNode(_gpNode("H", "host_mnt", Vector2.ZERO))
	gpG.gpAddNode(_gpNode("P", "nozzle_mnt", Vector2(500.0, 500.0)))
	var gpLook: Callable = _gpLookup()
	var gpChild: GPSymbolDef = _gpNozzleDef()
	# Zoom 2 -> radius 12, so the release at (0,10) is out of every anchor's range: the part must
	# land AT THE CURSOR, with an offset that puts its centre exactly under the pointer.
	# 缩放 2 -> 半径 12，故 (0,10) 的释放点在各锚点范围之外：部件必须落在**光标处**，
	# 其偏移恰好把中心放到指针下。
	var gpT: Dictionary = GPMountResolver.gpPlacementTuple(gpG, gpLook, Vector2(0.0, 10.0), 2.0,
		gpChild)
	gpCheck(bool(gpT.get("hit", false)), "a drop on the host's body resolves")
	if gpT.is_empty() or not bool(gpT.get("hit", false)):
		return
	gpCheck(not bool(gpT["on_anchor"]), "no anchor was in range, so this is a body landing")
	gpEq(str(gpT["anchor"]), "bot", "the anchor FACING the drop side is chosen")
	gpEq(gpT["mount_offset"], Vector2(0.0, -14.0),
		"anchorLocal (0,24) plus offset (0,-14) puts the part's centre at the cursor (0,10)")
	gpApprox(float(gpT["mount_angle_deg"]), 0.0, 0.001,
		"the bottom anchor already faces down, so no extra angle is needed")
	# THE contract: after applying the tuple, the part's world centre IS the release point.
	# 终极契约：应用元组后，部件的世界中心**就是**释放点。
	var gpP: GPPIDNode = gpG.gpGetNode("P")
	gpP.gpParentUid = str(gpT["parent_uid"])
	gpP.gpMountAnchor = str(gpT["anchor"])
	gpP.gpMountOffset = gpT["mount_offset"]
	gpP.gpMountAngleDeg = float(gpT["mount_angle_deg"])
	var gpWT: Dictionary = GPMountResolver.gpWorldTransform(gpG, gpLook, gpP)
	gpEq((gpWT["origin"] as Vector2), Vector2(0.0, 10.0),
		"the released part's centre sits exactly at the cursor, not on some distant anchor")
	# A free-anchor snap keeps the old, correct semantics: seat ON the anchor, native orientation.
	# 空闲锚点的吸附保留原有正确语义：坐在锚点上，原生朝向。
	var gpSnap: Dictionary = GPMountResolver.gpPlacementTuple(gpG, gpLook, Vector2(0.0, 24.0), 1.0,
		gpChild)
	gpCheck(bool(gpSnap.get("on_anchor", false)), "releasing within snap range seats on the anchor")
	gpEq(gpSnap["mount_offset"], Vector2.ZERO, "a snap carries no nudge")
	gpEq(GPMountResolver.gpPlacementTuple(gpG, gpLook, Vector2(900.0, 900.0), 1.0, gpChild).size(),
		0, "empty space stays unresolved — the pending gesture survives")


func gpTestPlacementTupleFacesTheSideOnAFullHost() -> void:
	# The bottom anchor is occupied (cap 1), so the body fallback can only offer the top or the
	# right anchor — neither faces DOWN. The tuple must still land at the cursor AND face down.
	# 下锚已被占用（限额 1），本体兜底只能给出上锚或右锚 —— 都不朝下。元组仍须落在光标处
	# **且**朝下。
	var gpG: GPPIDGraph = _gpGraph()
	gpG.gpAddNode(_gpNode("H", "typed_host", Vector2.ZERO))
	gpG.gpAddNode(_gpMounted("N1", "nozzle_mnt", "H", "nz_b"))
	var gpLook: Callable = _gpLookup()
	var gpT: Dictionary = GPMountResolver.gpPlacementTuple(gpG, gpLook, Vector2(0.0, 10.0), 2.0,
		_gpNozzleDef())
	gpCheck(bool(gpT.get("hit", false)), "a drop on the fully-occupied underside still resolves")
	if gpT.is_empty() or not bool(gpT.get("hit", false)):
		return
	gpEq(str(gpT["anchor"]), "gen", "the nearest free anchor is taken even though it faces right")
	gpApprox(float(gpT["mount_angle_deg"]), 90.0, 0.001,
		"…and the side override turns it DOWN toward the drop side")
	var gpP: GPPIDNode = GPPIDNode.new()
	gpP.gpInstanceId = "P"
	gpP.gpSymbolId = "nozzle_mnt"
	gpP.gpParentUid = "H"
	gpP.gpMountAnchor = str(gpT["anchor"])
	gpP.gpMountOffset = gpT["mount_offset"]
	gpP.gpMountAngleDeg = float(gpT["mount_angle_deg"])
	gpG.gpAddNode(gpP)
	var gpWT: Dictionary = GPMountResolver.gpWorldTransform(gpG, gpLook, gpP)
	gpEq((gpWT["origin"] as Vector2), Vector2(0.0, 10.0),
		"even on a full host the part's centre is exactly at the cursor")
	gpApprox(wrapf(float(gpWT["rot_deg"]), -180.0, 180.0), 90.0, 0.001,
		"and the part faces DOWN, not the way its anchor happens to face")


func gpTestPaletteDropSharesTheKernelRule() -> void:
	# Static guard: the mode-1 gesture (ghost preview AND landing) must both go through the
	# kernel's placement rule, or the two can drift apart and "what you see" stops being
	# "what you get".
	# 静态守卫：模式一手势（幽灵预览**与**落位）都必须经过内核的落位规则，
	# 否则二者会漂移，「所见」不再「即所得」。
	var gpF: FileAccess = FileAccess.open("res://src/ui/tools/place_attach_tool.gd", FileAccess.READ)
	gpCheck(gpF != null, "the attach tool's source is readable from the test run")
	if gpF == null:
		return
	var gpSrc: String = gpF.get_as_text()
	gpF.close()
	gpCheck(gpSrc.count("gpPlacementTuple(") >= 2,
		"the ghost preview and the drop BOTH resolve through gpPlacementTuple")
	gpCheck(gpSrc.contains("\"mount_offset\"], float(gpPlace[\"mount_angle_deg\"]"),
		"the drop hands the kernel's offset and angle to the attach command in ONE step")
