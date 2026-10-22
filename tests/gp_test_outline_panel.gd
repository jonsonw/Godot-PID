extends "res://tests/gp_test.gd"
# Copyright © 2026 Jonson Wang
#
# Headless tests for the hierarchy outline panel (R1).
# 层级大纲面板（R1）的 headless 测试。
#
# Three promises are guarded here / 此处守护三条承诺：
#   1. THE TREE MATCHES THE DATA. Top-level rows are the nodes with no host on this sheet —
#      including a child whose host lives on ANOTHER sheet, which must NOT disappear from the
#      list just because its parent is missing here.
#      **树与数据一致**。顶层行是本图纸上没有宿主的节点 —— 含「宿主在另一张图纸上」的子件，
#      它绝不能因为父件不在本图纸上就从列表里消失。
#   2. REPARENT RULES LIVE IN ONE PURE FUNCTION. Self-mount, cycles, non-mountable definitions and
#      a wrong mount kind are all refused by GPOutlinePanel.gpMountTuple() — testable with no UI,
#      and impossible for the panel to bypass.
#      **改挂规则集中于一个纯函数**。自挂、成环、不可挂载定义、挂载类型不符，全部由
#      GPOutlinePanel.gpMountTuple() 拒绝 —— 无需界面即可测试，面板也无法绕过。
#   3. THE PANEL BUILDS AND REBUILDS WITHOUT A LIVE APP. It is constructed off-tree with a bare
#      canvas, exactly like the headless regression checkers do.
#      **面板在无活动现场也能构建与重建**。与 headless 回归检查器一样，脱离场景树、只给一个裸画布
#      即可构建。

const GP_EPS: float = 0.0001

# Keys the panel reads. Hard-coded so a rename fails loudly instead of silently printing the id
# (gpTr() falls back to the raw key, which is exactly how a stale id reaches the UI unnoticed).
# 面板读取的键。硬编码，使改名直接报错而不是静默打印键名
#（gpTr() 会回退为裸键，这正是过时 id 悄悄溜进界面的方式）。
const GP_OUTLINE_KEYS: Array[String] = [
	"outline.title", "outline.col_node", "outline.col_type", "outline.hint",
	"outline.ctx_detach", "outline.ctx_mount_to", "outline.ctx_none",
]


# ---------------------------------------------------------------------------
# Fixtures / 夹具
# ---------------------------------------------------------------------------

# A 64x48 host with one unrestricted, uncapped anchor per side.
# 一台 64x48 的宿主，四边各一个不限种类、不限占用的锚点。
func _gpHostDef() -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = "host_mnt"
	gpD.gpCategory = "tank"
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


# A nozzle: a DIFFERENT mount kind, so "wrong kind" can be told apart from "no anchors".
# 一个管口：另一种挂载类型，使「类型不符」能与「没有锚点」区分开。
func _gpNozzleDef() -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = "nozzle_mnt"
	gpD.gpDefaultSize = Vector2(12.0, 12.0)
	gpD.gpMountKind = "NOZZLE"
	return gpD


# A host whose only anchors accept NOZZLE — an ACTUATOR has nowhere to go.
# 一台只接受 NOZZLE 的宿主 —— ACTUATOR 无处可去。
func _gpTypedHostDef() -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = "typed_host"
	gpD.gpDefaultSize = Vector2(64.0, 48.0)
	var gpAccepts: Array[String] = ["NOZZLE"]
	var gpA: Array[GPAttachPoint] = []
	gpA.append(GPAttachPoint.gpMake("nz_top", Vector2(0.5, 0.0), Vector2(0.0, -1.0), gpAccepts))
	gpD.gpAttachPoints = gpA
	return gpD


func _gpLookup() -> Callable:
	return func(gpId: String) -> GPSymbolDef:
		if gpId == "host_mnt":
			return _gpHostDef()
		if gpId == "child_mnt":
			return _gpChildDef()
		if gpId == "nozzle_mnt":
			return _gpNozzleDef()
		if gpId == "typed_host":
			return _gpTypedHostDef()
		return null


func _gpNode(gpId: String, gpSymbolId: String) -> GPPIDNode:
	var gpN: GPPIDNode = GPPIDNode.new()
	gpN.gpInstanceId = gpId
	gpN.gpSymbolId = gpSymbolId
	return gpN


func _gpMounted(gpId: String, gpSymbolId: String, gpParent: String, gpAnchor: String) -> GPPIDNode:
	var gpN: GPPIDNode = _gpNode(gpId, gpSymbolId)
	gpN.gpParentUid = gpParent
	gpN.gpMountAnchor = gpAnchor
	return gpN


# v1 (host) with n1 mounted on it, plus a loose part and an orphan whose host is on another sheet.
# v1（宿主）上挂着 n1，另有一个松散部件，以及一个宿主在别的图纸上的孤儿。
func _gpGraph() -> GPPIDGraph:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(_gpNode("v1", "host_mnt"))
	gpG.gpAddNode(_gpMounted("n1", "nozzle_mnt", "v1", "top"))
	gpG.gpAddNode(_gpNode("loose", "child_mnt"))
	gpG.gpAddNode(_gpMounted("orphan", "child_mnt", "ghost_sheet_host", "top"))
	return gpG


# ---------------------------------------------------------------------------
# gpTopLevelIds — roots AND orphans
# 顶层 id —— 根节点**与**孤儿
# ---------------------------------------------------------------------------

func gpTestTopLevelIdsFindsRootsAndOrphans() -> void:
	var gpIds: Array[String] = GPOutlinePanel.gpTopLevelIds(_gpGraph())
	gpEq(gpIds.size(), 3, "根 + 松散 + 孤儿共 3 条 / roots + loose + orphan = 3 rows")
	gpCheck(gpIds.has("v1"), "顶层宿主在列 / top-level host listed")
	gpCheck(gpIds.has("loose"), "松散部件在列 / loose part listed")
	gpCheck(gpIds.has("orphan"), "宿主不在本图纸上的子件仍在列 / orphan kept visible")
	gpCheck(not gpIds.has("n1"), "已挂载子件不进顶层 / mounted child is not a root")


func gpTestTopLevelIdsNullGraph() -> void:
	gpEq(GPOutlinePanel.gpTopLevelIds(null).size(), 0, "空图返回空列表 / null graph yields no ids")


# ---------------------------------------------------------------------------
# gpMountTuple — the four rules
# 挂载元组 —— 四条规则
# ---------------------------------------------------------------------------

func gpTestMountTupleBuildsTuple() -> void:
	var gpT: Dictionary = GPOutlinePanel.gpMountTuple(_gpGraph(), _gpLookup(), "loose", "v1")
	gpCheck(not gpT.is_empty(), "合法组合应给出元组 / valid pair yields a tuple")
	gpEq(str(gpT.get("parent_uid", "")), "v1", "宿主写进 parent_uid / host lands in parent_uid")
	gpCheck(str(gpT.get("mount_anchor", "")) != "", "锚点已选中 / an anchor was chosen")
	gpCheck(gpT.has("mount_offset"), "含偏移键 / carries mount_offset")
	gpCheck(gpT.has("mount_angle_deg"), "含角度键 / carries mount_angle_deg")


func gpTestMountTupleRejectsSelf() -> void:
	gpCheck(GPOutlinePanel.gpMountTuple(_gpGraph(), _gpLookup(), "v1", "v1").is_empty(),
		"不能挂到自己身上 / a node cannot mount onto itself")


func gpTestMountTupleRejectsCycle() -> void:
	# n1 already hangs on v1, so v1 may not be mounted onto n1.
	# n1 已挂在 v1 上，故 v1 不可再挂到 n1。
	gpCheck(GPOutlinePanel.gpMountTuple(_gpGraph(), _gpLookup(), "v1", "n1").is_empty(),
		"宿主不能是子件自己的后代 / host may not be inside the child's subtree")


func gpTestMountTupleRejectsNonMountableChild() -> void:
	# The host definition declares no gpMountKind: it is equipment, not a part.
	# 宿主定义未声明 gpMountKind：它是设备，不是部件。
	gpCheck(GPOutlinePanel.gpMountTuple(_gpGraph(), _gpLookup(), "v1", "loose").is_empty(),
		"不可挂载的定义被拒 / a definition with no mount kind is refused")


func gpTestMountTupleRejectsWrongKind() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(_gpNode("th", "typed_host"))
	gpG.gpAddNode(_gpNode("part", "child_mnt"))
	gpCheck(GPOutlinePanel.gpMountTuple(gpG, _gpLookup(), "part", "th").is_empty(),
		"锚点只收 NOZZLE，ACTUATOR 被拒 / NOZZLE-only anchors refuse an ACTUATOR")
	var gpG2: GPPIDGraph = GPPIDGraph.new()
	gpG2.gpAddNode(_gpNode("th", "typed_host"))
	gpG2.gpAddNode(_gpNode("nz", "nozzle_mnt"))
	gpCheck(not GPOutlinePanel.gpMountTuple(gpG2, _gpLookup(), "nz", "th").is_empty(),
		"同类型则应通过 / the matching kind is accepted")


func gpTestMountTupleRejectsMissingNodes() -> void:
	gpCheck(GPOutlinePanel.gpMountTuple(_gpGraph(), _gpLookup(), "nope", "v1").is_empty(),
		"子件不存在被拒 / missing child refused")
	gpCheck(GPOutlinePanel.gpMountTuple(_gpGraph(), _gpLookup(), "loose", "nope").is_empty(),
		"宿主不存在被拒 / missing host refused")


# ---------------------------------------------------------------------------
# Panel construction + tree shape
# 面板构建 + 树结构
# ---------------------------------------------------------------------------

func gpTestPanelBuildsTreeFromGraph() -> void:
	var gpCv: GPCanvas2D = GPCanvas2D.new()
	var gpG: GPPIDGraph = _gpGraph()
	gpCv.gpGraph = gpG
	var gpDefs: Array[GPSymbolDef] = [_gpHostDef(), _gpChildDef(), _gpNozzleDef(),
		_gpTypedHostDef()]
	gpCv.gpDefs = gpDefs
	# The binder is created by the live app (its gpDefs cache is what gpDefFor() reads). Under a
	# headless harness it may not exist yet, and the tree shape does not depend on the TYPE column:
	# a missing definition only leaves that column empty. Guarded so the test asserts the tree, not
	# the harness.
	# 绑定器由活动现场创建（gpDefFor() 读的是它的 gpDefs 缓存）。headless 夹具里它可能尚未存在，
	# 而树的**形状**并不依赖「类型」列：缺定义只让该列留空。故加护栏，使本测试断言树、而不是断言夹具。
	if gpCv.gpBinder != null:
		gpCv.gpBinder.gpDefs = gpDefs

	var gpPanel: GPOutlinePanel = GPOutlinePanel.new()
	add_child(gpPanel)
	gpPanel.gpBuild()
	gpPanel.gpBindCanvas(gpCv)

	var gpRoot: TreeItem = gpPanel.gpTree.get_root()
	gpCheck(gpRoot != null, "隐藏根已创建 / hidden root created")
	gpEq(gpRoot.get_child_count(), 3, "三个顶层行 / three top-level rows")
	var gpFirst: TreeItem = gpRoot.get_child(0)
	gpEq(str(gpFirst.get_metadata(GPOutlinePanel.GP_COL_NAME)), "v1", "首行是宿主 / first row is the host")
	gpEq(gpFirst.get_child_count(), 1, "宿主下有一个子件 / the host owns one child row")
	gpEq(str(gpFirst.get_child(0).get_metadata(GPOutlinePanel.GP_COL_NAME)), "n1",
		"子件行是 n1 / child row is n1")

	# Selection mirror: mark v1 on the canvas, then ask the panel to follow it.
	# 选择镜像：在画布上选中 v1，再让面板跟上。
	gpCv.gpSetSelection(["v1"])
	gpPanel.gpRefreshSelection()
	var gpSel: TreeItem = gpPanel.gpTree.get_selected()
	gpCheck(gpSel != null, "树上有选中行 / a row is selected")
	if gpSel != null:
		gpEq(str(gpSel.get_metadata(GPOutlinePanel.GP_COL_NAME)), "v1",
			"选中行与画布选择一致 / tree selection follows the canvas")

	gpPanel.free()
	gpCv.free()


func gpTestPanelWithoutCanvasIsInert() -> void:
	var gpPanel: GPOutlinePanel = GPOutlinePanel.new()
	add_child(gpPanel)
	gpPanel.gpBuild()
	gpPanel.gpRefresh()
	gpEq(gpPanel.gpTree.get_root().get_child_count(), 0, "无画布时无行 / no rows without a canvas")
	gpPanel.gpRefreshSelection()
	gpCheck(true, "无画布时刷新/同步不崩溃 / refresh is safe without a canvas")
	gpPanel.free()


# ---------------------------------------------------------------------------
# i18n keys the panel reads
# 面板读取的 i18n 键
# ---------------------------------------------------------------------------

func gpTestOutlineKeysBilingual() -> void:
	for gpKey in GP_OUTLINE_KEYS:
		var gpPair: Dictionary = I18n.GP_STRINGS.get(gpKey, {})
		gpCheck(not gpPair.is_empty(), "键存在 / key present: " + gpKey)
		gpCheck(str(gpPair.get("zh", "")) != "", "中文非空 / zh non-empty: " + gpKey)
		gpCheck(str(gpPair.get("en", "")) != "", "英文非空 / en non-empty: " + gpKey)
