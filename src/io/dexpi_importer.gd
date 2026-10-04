class_name GPDexpiImporter
extends RefCounted

# Turn a DEXPI intermediate structure into a G-PID v3 container, ready for the EXISTING
# gpValidate -> gpMergeInto pipeline.
# 把 DEXPI 中间结构转为 G-PID v3 容器，交给**既有**的 gpValidate -> gpMergeInto 管线。
#
# WHY NOT BUILD OBJECTS DIRECTLY / 为何不直接构造对象：
# gpMergeInto already handles uid collision reassignment, tag de-duplication and non-destructive
# merging. Producing the container and handing it over means an imported DEXPI file gets every
# one of those guarantees for free — and none of them get a second, divergent implementation.
# gpMergeInto 已经处理 uid 冲突重分配、位号去重与非破坏合并。产出容器并交出去，
# 意味着导入的 DEXPI 文件免费获得这些保障 —— 且它们不会有第二套分叉的实现。
#
# The output is validated by GPProjectImport.gpValidate() in the tests: a container that the
# existing gate rejects is a bug here, not a special case there.
# 产出在测试中由 GPProjectImport.gpValidate() 校验：
# 一个被既有门禁拒收的容器是本模块的缺陷，而非那里的特例。

const GP_KIND_PROCESS: String = "PROCESS"


static func gpToV3(gpMid: Dictionary, gpDefLookup: Callable = Callable()) -> Dictionary:
	if gpMid.is_empty():
		return {}
	var gpDiagram: Dictionary = gpMid.get(GPDexpiExporter.GP_KEY_DIAGRAM, {}) as Dictionary
	var gpNodes: Array = []
	var gpEdges: Array = []
	_gpFillNodes(gpMid, gpNodes, gpDefLookup)
	_gpFillEdges(gpMid, gpEdges, gpDefLookup, gpNodes)
	return {
		"format": GPSchemaMigrate.GP_FORMAT,
		"format_version": GPSchemaMigrate.GP_FORMAT_VERSION,
		"kind": GPSchemaMigrate.GP_KIND_PROJECT,
		"generator": GPSchemaMigrate.gpGeneratorInfo(),
		"created_at": GPSchemaMigrate.gpNowIso(),
		"doc_id": GPIdGen.gpNewDocId(),
		"meta": {
			"sheets": 1,
			"title": str(gpDiagram.get("name", "DEXPI import")),
			# Stamped with the CURRENT meta version, not a literal: an import produces a graph
			# this build just built, so it is by definition of this build's generation.
			# 盖上**当前** meta 版本而非字面量：导入产出的是本构建刚造的图，
			# 按定义就属于本构建的代号。
			"version": GPPIDGraph.GP_META_VERSION,
		},
		"config": {},
		"tag_rules": {},
		"user_symbol_packs": [],
		"library": {"packs": [], "builtin_overrides": []},
		"sheets": [{
			"id": "sheet1",
			"name": str(gpDiagram.get("name", "Sheet 1")),
			"index": 0,
			"nodes": gpNodes,
			"edges": gpEdges,
			"shapes": [],
		}],
	}


# Read a DEXPI XML FILE on disk into a G-PID v3 container, ready for the existing
# gpMergeInto pipeline. This is the SINGLE entry point the UI uses: the reader, validator
# and converter are not called individually from the shell, so the import contract lives in
# exactly one place.
# 把磁盘上的 DEXPI XML **文件**读成 G-PID v3 容器，交给既有 gpMergeInto 管线。
# 这是界面使用的**唯一入口**：reader / validator / converter 不单独由外壳调用，
# 故导入契约只落在一处。
#
# On success gpPayload is { "v3": <v3 container>, "report": <GPImportReport> } so the caller
# can both MERGE the container and REPORT the source file's structural health (error/warning
# counts). On failure gpMessageKey is an i18n key (e.g. "status.import_fail").
# 成功时 gpPayload 为 { "v3": <v3 容器>, "report": <GPImportReport> }，
# 使调用方既能**合并**容器、也能**报告**源文件的结构健康度（错误/警告计数）。
# 失败时 gpMessageKey 为 i18n 键（如 "status.import_fail"）。
static func gpReadFileToV3(gpPath: String, gpDefLookup: Callable = Callable()) -> GPIOResult:
	if not FileAccess.file_exists(gpPath):
		return GPIOResult.gpFailure("io.open_failed", "status.import_fail", gpPath)
	var gpFile: FileAccess = FileAccess.open(gpPath, FileAccess.READ)
	if gpFile == null:
		return GPIOResult.gpFailure("io.open_failed", "status.import_fail", gpPath)
	var gpText: String = gpFile.get_as_text()
	gpFile.close()
	# Parse the XML into the intermediate structure (fatal parse errors return a failure).
	# 把 XML 解析为中间结构（致命解析错误直接返回失败）。
	var gpRead: GPIOResult = GPDexpiReader.gpReadXml(gpText)
	if not gpRead.gpIsOk():
		return gpRead
	var gpMid: Dictionary = gpRead.gpPayload as Dictionary
	# Validate BEFORE converting, so the report reflects the real source file, not a half-built
	# container. The converter then hands the structure to gpMergeInto unchanged.
	# 转换前先校验，使报告反映真实的源文件、而非半成品容器。转换器再把结构原样交给
	# gpMergeInto。
	var gpReport: GPImportReport = GPDexpiValidator.gpValidate(gpMid)
	var gpV3: Dictionary = GPDexpiImporter.gpToV3(gpMid, gpDefLookup)
	return GPIOResult.gpSuccessWith({"v3": gpV3, "report": gpReport}, "dexpi.imported", gpPath)


# One node per Equipment. Pose comes from the ShapeUsage that references it, because DEXPI
# keeps placement in the graphics layer, not on the concept object.
# 每个 Equipment 一个节点。位姿来自引用它的 ShapeUsage ——
# 因为 DEXPI 把放置信息放在图形层，而非概念对象上。
static func _gpFillNodes(gpMid: Dictionary, gpOut: Array, gpDefLookup: Callable = Callable()) -> void:
	var gpUsageById: Dictionary = {}
	for gpUsage in (gpMid.get(GPDexpiExporter.GP_KEY_USAGES, []) as Array):
		var gpU: Dictionary = gpUsage as Dictionary
		var gpItemId: String = str(gpU.get("item_id", ""))
		if not gpItemId.is_empty():
			gpUsageById[gpItemId] = gpU
	var gpByUid: Dictionary = {}
	for gpEq in (gpMid.get(GPDexpiExporter.GP_KEY_EQUIPMENT, []) as Array):
		var gpE: Dictionary = gpEq as Dictionary
		var gpUsage: Dictionary = gpUsageById.get(str(gpE.get("id", "")), {}) as Dictionary
		var gpPos: Vector2 = gpUsage.get("position", Vector2.ZERO) as Vector2
		var gpNodeD: Dictionary = {
			# INVARIANT — this string must be EXACTLY what the edges put in node_id.
			# GPPIDGraph.gpGetNode() matches gpInstanceId ONLY (pid_graph.gd:159), so a
			# sequential key here ("n1","n2",...) while edges addressed the DEXPI id left
			# every end unresolved -> GPPortResolver fell to "free" -> Vector2.ZERO, and the
			# whole drawing's pipes were anchored at the ORIGIN. Using the DEXPI id for both
			# is what makes an imported sheet geometrically identical to the exported one.
			# 不变量 —— 此字符串必须与边写入 node_id 的字符串**完全一致**。
			# GPPIDGraph.gpGetNode() **只**匹配 gpInstanceId（pid_graph.gd:159），故此处若用
			# 顺序键（n1/n2…）而边用 DEXPI id，则每一个端点都解析不到 ->
			# GPPortResolver 跌到 "free" -> Vector2.ZERO，整张图的管线全部锚到**原点**。
			# 两处都用 DEXPI id，导入的图纸才与导出的原件几何一致。
			"instance_id": str(gpE.get("id", "")),
			# The DEXPI ID is the stable uid too, so the existing merge pipeline can detect
			# collisions instead of reassigning blindly.
			# DEXPI 的 ID 同时是稳定 uid，故既有合并管线可以**检测**冲突而非盲目重分配。
			"uid": str(gpE.get("id", "")),
			"symbol_id": GPDexpiMapping.gpSymbolIdFor(str(gpE.get("class", ""))),
			"tag": str(gpE.get("tag", "")),
			"position": [gpPos.x, gpPos.y],
			"rotation_deg": float(gpUsage.get("rotation_deg", 0.0)),
			"flipped": bool(gpUsage.get("mirrored", false)),
			"names": (gpE.get("names", {}) as Dictionary).duplicate(true),
			"props": (gpE.get("props", {}) as Dictionary).duplicate(true),
			"label_anchor": -1,
			# Hierarchy (P4): the host travels in parent_uid. Restored as a real mount rather
			# than flattened, because a flattened nozzle is a nozzle an edit can no longer move
			# together with its vessel.
			# 层级（P4）：宿主随 parent_uid 传回。还原为**真的挂载**而非拍平 ——
			# 拍平的管口，是编辑时再也无法随容器一起移动的管口。
			"parent_uid": str(gpE.get("parent_uid", "")),
			"mount_anchor": str(gpE.get("mount_anchor", "")),
			"mount_offset": [0.0, 0.0],
		}
		gpOut.append(gpNodeD)
		gpByUid[str(gpNodeD["instance_id"])] = gpNodeD
	# ★ Second pass — restore WHERE (and HOW ORIENTED) each mounted child sits on its host.
	# The file carries the child's WORLD placement (its ShapeUsage) and its host, but neither
	# the local offset nor the anchor name. Recover the anchor IDENTITY by position: a mounted
	# child always sits ON one of the host's anchors, so the nearest anchor's world position
	# identifies it — and its direction then explains the child's world rotation exactly.
	# What is left over becomes mount_offset / mount_angle_deg, so the reconstruction is
	# EXACT for any drag or lateral angle the user applied, and still exact when the file
	# came from another tool whose child simply sits on an anchor.
	# ★ 第二趟 —— 还原每个被挂载子件落在宿主的什么位置、**以什么朝向**。
	# 文件携带子件的**世界**放置（其 ShapeUsage）与它的宿主，但既无局部偏移也无锚点名。
	# 按**位置**找回锚点的**身份**：被挂载子件必然坐在宿主某个锚点上，
	# 故「世界位置最近的锚点」即它的锚点 —— 其方向又恰好解释子件的世界旋转。
	# 剩余量记入 mount_offset / mount_angle_deg，于是无论用户拖过、斜过多少，
	# 重建都**精确**；文件即便出自其它工具、子件只是坐在锚点上，也照样精确。
	# FALLBACK: no usable def table -> the previous behaviour (host centre + offset), and the
	# resolver's "anchor missing" rung. A visible degradation, never a wrong guess.
	# 兜底：没有可用的定义表 -> 维持原行为（宿主中心 + 偏移），解析器走
	# 「锚点缺失」那一级。是**可见**的降级，而**不是**一个错误的猜测。
	for gpNode in gpOut:
		var gpND: Dictionary = gpNode as Dictionary
		var gpHostUid: String = str(gpND.get("parent_uid", ""))
		if gpHostUid.is_empty() or not gpByUid.has(gpHostUid):
			continue
		var gpHostD: Dictionary = gpByUid[gpHostUid] as Dictionary
		var gpChildWorld: Vector2 = _gpPointOf(gpND)
		var gpHostFlip: bool = bool(gpHostD.get("flipped", false))
		var gpHostRot: float = float(gpHostD.get("rotation_deg", 0.0))
		var gpAnchorName: String = ""
		var gpAnchorWorld: Vector2 = Vector2.ZERO
		var gpAnchorRot: float = 0.0
		if gpDefLookup.is_valid():
			var gpHostDef: GPSymbolDef = gpDefLookup.call(
				str(gpHostD.get("symbol_id", ""))) as GPSymbolDef
			if gpHostDef != null and not gpHostDef.gpAttachPoints.is_empty():
				var gpChildDef: GPSymbolDef = gpDefLookup.call(
					str(gpND.get("symbol_id", ""))) as GPSymbolDef
				# The child's canonical base rotation is part of what the anchor direction
				# explains; without the child def it defaults to 0 (most child symbols).
				# 子件的正则基角是锚点方向解释的一部分；无子件定义时取默认 0（多数子图元如此）。
				var gpChildBase: float = gpChildDef.gpBaseMountRot if gpChildDef != null else 0.0
				var gpHostOrigin: Vector2 = _gpPointOf(gpHostD)
				var gpBestD2: float = INF
				for gpA in gpHostDef.gpAttachPoints:
					var gpAnchor: GPAttachPoint = gpA as GPAttachPoint
					var gpAW: Vector2 = gpHostOrigin + GPMountResolver.gpOrientLocal(
						GPMountResolver.gpAnchorLocal(gpHostDef, gpAnchor),
						gpHostFlip, gpHostRot)
					var gpD2: float = gpAW.distance_squared_to(gpChildWorld)
					if gpD2 < gpBestD2:
						gpBestD2 = gpD2
						gpAnchorName = gpAnchor.gpName
						gpAnchorWorld = gpAW
						var gpDirW: Vector2 = GPMountResolver.gpOrientDir(
							gpAnchor.gpDir, gpHostFlip, gpHostRot)
						gpAnchorRot = (GPMountResolver.gpAnchorDirToRotation(gpDirW, gpChildBase)
							if gpDirW != Vector2.ZERO else gpHostRot)
		if gpAnchorName != "":
			gpND["mount_anchor"] = gpAnchorName
			# Offset = the residue the anchor does not explain; angle = likewise for rotation.
			# 偏移 = 锚点解释不掉的剩余量；角度亦然。
			var gpRes: Vector2 = GPMountDragOps.gpUnorientLocal(gpChildWorld - gpAnchorWorld,
				gpHostFlip, gpHostRot)
			gpND["mount_offset"] = [gpRes.x, gpRes.y]
			var gpAngRes: float = wrapf(float(gpND.get("rotation_deg", 0.0)) - gpAnchorRot,
				-180.0, 180.0)
			if absf(gpAngRes) < 0.01:
				gpAngRes = 0.0
			if not is_zero_approx(gpAngRes):
				gpND["mount_angle_deg"] = gpAngRes
		else:
			var gpDelta: Vector2 = gpChildWorld - _gpPointOf(gpHostD)
			var gpLocal: Vector2 = GPMountDragOps.gpUnorientLocal(gpDelta, gpHostFlip, gpHostRot)
			gpND["mount_offset"] = [gpLocal.x, gpLocal.y]


# A node dict's position, as a Vector2. The projection stores it as a 2-array so the container
# stays JSON-shaped.
# 节点字典的位置，以 Vector2 表示。投影层以 2 元数组存储它，使容器保持 JSON 形态。
static func _gpPointOf(gpNodeD: Dictionary) -> Vector2:
	var gpP: Array = gpNodeD.get("position", []) as Array
	if gpP.size() >= 2:
		return Vector2(float(gpP[0]), float(gpP[1]))
	return Vector2.ZERO


# One edge per PipingNetworkSegment. The stored route holds BENDS ONLY (§9 待确认 2), so the
# two endpoints read back from the file are dropped rather than duplicated into routing.
# 每个 PipingNetworkSegment 一条边。已存的走向**只放折点**（§9 待确认 2），
# 故从文件读回的两个端点被丢弃，而不是重复写进 routing。
# PORT REBINDING / 端口重绑：
# DEXPI stores the segment ENDPOINTS but not WHICH port each end touched. Dropping that
# knowledge (port_id "") made the renderer fall down the resolver ladder to "first nozzle
# port", which re-attached pipes to the WRONG sides — the drawing rendered with pipes
# detached from where they were drawn. The polyline endpoints are still in hand here, and
# the symbol defs know every port's oriented world position, so the binding is RECONSTRUCTED
# by nearest-port match (exact for files G-PID itself wrote).
# DEXPI 只存线段**端点**，不存各端接的是**哪个端口**。丢掉这一知识（port_id 置空）会让
# 渲染器沿解析阶梯跌到「期望用途的第一个端口」，把管线接到错误的侧面 ——
# 图纸渲染出来管道全部偏离原位。此处折线端点仍在手上，符号定义又知道每个端口的
# 朝向世界坐标，故按**最近端口**重建绑定（对 G-PID 自己写出的文件是精确命中）。
# `gpDefLookup` is injected by the caller (UI passes its def table; tests pass their own),
# so this io-layer module never reaches into the autoload.
# `gpDefLookup` 由调用方注入（界面传自己的定义表；测试传自定义的），
# 故本 io 层模块绝不直接伸手拿 autoload。
static func _gpFillEdges(gpMid: Dictionary, gpOut: Array, gpDefLookup: Callable,
		gpNodes: Array) -> void:
	var gpNodeByUid: Dictionary = {}
	for gpN in gpNodes:
		var gpND: Dictionary = gpN as Dictionary
		gpNodeByUid[str(gpND.get("uid", ""))] = gpND
	for gpSeg in (gpMid.get(GPDexpiExporter.GP_KEY_SEGMENTS, []) as Array):
		var gpS: Dictionary = gpSeg as Dictionary
		var gpPts: Array = gpS.get("points", []) as Array
		var gpBends: Array = []
		var gpI: int = 1
		while gpI < gpPts.size() - 1:
			var gpV: Vector2 = gpPts[gpI] as Vector2
			gpBends.append([gpV.x, gpV.y])
			gpI += 1
		var gpFromUid: String = str(gpS.get("from_uid", ""))
		var gpToUid: String = str(gpS.get("to_uid", ""))
		# node_id must equal the node's "instance_id" (see _gpFillNodes) — both are the DEXPI
		# id here, which is exactly the invariant GPPIDGraph.gpGetNode() relies on.
		# node_id 必须等于节点的 "instance_id"（见 _gpFillNodes）—— 此处两者都是 DEXPI id，
		# 这正是 GPPIDGraph.gpGetNode() 所依赖的不变量。
		var gpFromPort: String = ""
		var gpToPort: String = ""
		if not gpPts.is_empty():
			# Rebind each end to the port nearest the stored endpoint. Only meaningful when
			# the end names a node that exists; a dangling end stays dangling.
			# 把每一端重绑到离已存端点最近的端口。仅当该端命中的节点存在时才有意义；
			# 悬空端保持悬空。
			gpFromPort = _gpNearestPortId(gpNodeByUid.get(gpFromUid, {}) as Dictionary,
				gpPts[0] as Vector2, gpDefLookup)
			gpToPort = _gpNearestPortId(gpNodeByUid.get(gpToUid, {}) as Dictionary,
				gpPts[gpPts.size() - 1] as Vector2, gpDefLookup)
		gpOut.append({
			"instance_id": str(gpS.get("id", "")),
			"from_ref": {"node_id": gpFromUid, "port_id": gpFromPort},
			"to_ref": {"node_id": gpToUid, "port_id": gpToPort},
			"kind": GP_KIND_PROCESS,
			"signal_type": "",
			"ortho": true,
			"routing": gpBends,
			"tag": str(gpS.get("tag", "")),
			"attrs": (gpS.get("attrs", {}) as Dictionary).duplicate(true),
		})


# The name of the port whose oriented world position is nearest to gpWorld, or "" when the
# node is unknown, has no def, or the def has no ports (the caller's ladder then applies).
# 返回「朝向世界坐标距 gpWorld 最近」的端口名；节点未知、无定义或定义无端口时返回空串
# （此时由调用方的降级阶梯接管）。
static func _gpNearestPortId(gpNodeDict: Dictionary, gpWorld: Vector2,
		gpDefLookup: Callable) -> String:
	if gpNodeDict.is_empty() or not gpDefLookup.is_valid():
		return ""
	var gpNode: GPPIDNode = GPPIDNode.new()
	gpNode.gpSymbolId = str(gpNodeDict.get("symbol_id", ""))
	var gpPos: Array = gpNodeDict.get("position", []) as Array
	if gpPos.size() < 2:
		return ""
	gpNode.gpPosition = Vector2(float(gpPos[0]), float(gpPos[1]))
	gpNode.gpRotationDeg = float(gpNodeDict.get("rotation_deg", 0.0))
	gpNode.gpFlipped = bool(gpNodeDict.get("flipped", false))
	var gpDef: GPSymbolDef = gpDefLookup.call(gpNode.gpSymbolId) as GPSymbolDef
	if gpDef == null or gpDef.gpPorts.is_empty():
		return ""
	var gpBestName: String = ""
	var gpBestD2: float = INF
	for gpPort in gpDef.gpPorts:
		# Routed through the shared resolver so the importer agrees with the renderer. No graph is
		# available at import time, and the node built above carries no mount fields, so this
		# degrades to the node's own frame — identical to the previous arithmetic.
		# 经共用解析器，使导入器与渲染器口径一致。导入期没有图，且上面构造的节点不含挂载字段，
		# 故降级为节点自身坐标系 —— 与原先的算法完全等价。
		var gpWorldPort: Vector2 = GPPortResolver.gpPortWorld(null, gpDefLookup, gpDef, gpNode, gpPort)
		var gpD2: float = gpWorldPort.distance_squared_to(gpWorld)
		if gpD2 < gpBestD2:
			gpBestD2 = gpD2
			gpBestName = gpPort.gpName
	return gpBestName
