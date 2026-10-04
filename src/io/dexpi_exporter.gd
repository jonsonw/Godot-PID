class_name GPDexpiExporter
extends RefCounted

# Export a G-PID sheet to a DEXPI 1.4 / Proteus 4.2.0 XML file.
# 把一张 G-PID 图纸导出为 DEXPI 1.4 / Proteus 4.2.0 XML 文件。
#
# PHASE 1 SCOPE (§8.4 P1, 做法 A from §5.2) / 一期范围：
# conceptual layer + Drawing extent only — NO <ShapeCatalogue>, NO <RepresentationGroup>.
# The frame is deliberately left to the receiving tool (the spec defines no frame concept at
# all), which keeps Phase 1's compliance risk at zero.
# 仅概念层 + Drawing 范围 —— **无** <ShapeCatalogue>、**无** <RepresentationGroup>。
# 图框刻意留给接收方工具（规范本身就没有图框概念），使一期的合规风险为零。
#
# WHY XML IS ASSEMBLED THROUGH GPXmlText / 为何经 GPXmlText 组装：
# every string here is a place where a spec rule can be broken invisibly (unescaped `&`,
# `Value=""` for null, `zh-CN`, 0..255 colour). Routing them through one builder means each
# rule is enforced once and asserted once. See GPXmlText's header.
# 此处每个字符串都是「规范规则可能被无声破坏」的地方（未转义的 `&`、为 null 写 `Value=""`、
# `zh-CN`、0..255 颜色）。经单一构建器流出意味着每条规则只强制一次、也只需断言一次。
#
# Dependency rule: io may reference core, never ui and never an autoload (headless-testable).
# 依赖规则：io 可引用 core，绝不引用 ui 与 autoload（保持 headless 可测）。

# Intermediate-structure keys, so the projection and the serialisation are testable apart.
# 中间结构的键，使「投影」与「序列化」可以分开测试。
const GP_KEY_PLANT: String = "plant"
const GP_KEY_DIAGRAM: String = "diagram"
const GP_KEY_EQUIPMENT: String = "equipment"
const GP_KEY_SEGMENTS: String = "segments"
const GP_KEY_SKIPPED: String = "skipped"
# P5 / D3: mounted parts whose relation says "attribute" (insulation) carry no object of their
# own, so they cannot live in GP_KEY_EQUIPMENT. They travel here instead — as
# {host_uid, kind, attrs} — and the serialiser pours them into the HOST's attribute block.
# P5 / D3：关系为 "attribute" 的被挂载件（保温）自身没有对象，故不能待在 GP_KEY_EQUIPMENT。
# 它们改在此处传递 —— 形如 {host_uid, kind, attrs} —— 由序列化器倒进**宿主**的属性块。
const GP_KEY_HOST_ATTRIBS: String = "host_attribs"
# P2 graphics layer / P2 图形层。
const GP_KEY_SHAPES: String = "shapes"
const GP_KEY_USAGES: String = "usages"
const GP_KEY_DRAWING_SHAPES: String = "drawing_shapes"

# Symbol glyphs live in a 0..100 unit box; the symbol's real size is gpDefaultSize, so the
# ShapeUsage scale is the ratio between them.
# 图元字形位于 0..100 的单位框内；图元的真实尺寸是 gpDefaultSize，
# 故 ShapeUsage 的缩放就是二者的比值。
const GP_UNIT_BOX: float = 100.0

# Report codes (stable strings, so the UI can translate them later).
# 报告码（稳定字符串，便于界面日后翻译）。
const GP_CODE_NO_SHEET: String = "dexpi.no_sheet"
const GP_CODE_BAD_EXTENT: String = "dexpi.bad_extent"
const GP_CODE_NO_SHEET_NAME: String = "dexpi.no_sheet_name"
const GP_CODE_MISSING_UID: String = "dexpi.missing_uid"
const GP_CODE_SIGNAL_UNSUPPORTED: String = "dexpi.signal_unsupported"
const GP_CODE_ANNOTATION_SKIPPED: String = "dexpi.annotation_skipped"
const GP_CODE_UNKNOWN_SYMBOL: String = "dexpi.unknown_symbol"
const GP_CODE_CUSTOM_ATTRIBUTE: String = "dexpi.custom_attribute"
const GP_CODE_MISSING_URI: String = "dexpi.missing_uri"
# Mount relations (P4). A mounted child either nests, or is REPORTED with the reason it does
# not — never dropped silently. The former GP_CODE_NOZZLES_DEFERRED ("nozzles are deferred")
# was removed here: it was declared and never used, and P4 is exactly the change that made it
# obsolete, since nozzles now nest.
# 挂载关系（P4）。被挂载子件要么嵌套，要么带上「为何不嵌套」的原因被**报告** ——
# 绝不静默丢弃。原先的 GP_CODE_NOZZLES_DEFERRED（「管口延后」）在此移除：
# 它声明了却从未使用，而 P4 正是令其过时的那次改动 —— 管口现在会嵌套了。
const GP_CODE_MOUNT_UNMAPPED: String = "dexpi.mount_unmapped"
const GP_CODE_MOUNT_NOT_NESTED: String = "dexpi.mount_not_nested"
const GP_CODE_ORPHAN_MOUNT: String = "dexpi.orphan_mount"
const GP_CODE_MOUNT_CYCLE: String = "dexpi.mount_cycle"


# ============================ pre-flight ============================

# Check that gpSheet can become a compliant <Drawing> before anything is written.
# Fatal findings are recorded as errors: the caller (gpExportFile) refuses on gpHasErrors().
# 落盘前检查 gpSheet 能否成为合规的 <Drawing>。致命问题记为 error：
# 调用方（gpExportFile）在 gpHasErrors() 为真时拒绝导出。
static func gpPreflight(gpGraph: GPPIDGraph, gpSheet: GPSheet) -> GPImportReport:
	var gpReport: GPImportReport = GPImportReport.new()
	if gpSheet == null:
		gpReport.gpAddError(GP_CODE_NO_SHEET, "sheet is required to build a Diagram")
		return gpReport
	# Extent: all four values are mandatory (§3.1). A zero-size sheet is invisible in the
	# receiving tool rather than rejected, which is the worse of the two outcomes.
	# 范围：四个值全部必填（§3.1）。零尺寸图纸在接收方是「看不见」而非「被拒收」，
	# 后者反而更好。
	if float(gpSheet.gpWidthMM) <= 0.0 or float(gpSheet.gpHeightMM) <= 0.0:
		gpReport.gpAddError(GP_CODE_BAD_EXTENT,
			"sheet is %s x %s mm" % [gpSheet.gpWidthMM, gpSheet.gpHeightMM])
	if gpSheet.gpName.strip_edges().is_empty():
		gpReport.gpAddError(GP_CODE_NO_SHEET_NAME, "Diagram.Name is mandatory (§3.1)")
	if gpGraph == null:
		return gpReport
	# Stable identity (§7.4): never export an instance id as an object ID, because instance
	# ids are reassigned on import and every cross-reference would break.
	# 稳定标识（§7.4）：绝不把 instance id 当对象 ID 导出 —— instance id 在导入时会被重分配，
	# 所有交叉引用都会断掉。
	for gpNode in gpGraph.gpNodes:
		var gpN: GPPIDNode = gpNode as GPPIDNode
		if gpN == null:
			continue
		if gpN.gpUid.strip_edges().is_empty():
			gpReport.gpAddError(GP_CODE_MISSING_UID, "node " + gpN.gpInstanceId + " has no stable uid")
		var gpRole: String = str(GPDexpiMapping.gpComponentFor(gpN.gpSymbolId).get("role", ""))
		if gpRole == GPDexpiMapping.GP_ROLE_ANNOTATION:
			gpReport.gpAddInfo(GP_CODE_ANNOTATION_SKIPPED,
				gpN.gpSymbolId + " is presentation-only; it has no concept object")
		elif bool(GPDexpiMapping.gpComponentFor(gpN.gpSymbolId).get("unknown", false)):
			gpReport.gpAddWarning(GP_CODE_UNKNOWN_SYMBOL,
				gpN.gpSymbolId + " has no mapping; exported as a Custom class")
	# --- mount relations (P4) -------------------------------------------------
	# A mounted child is one of exactly three things, and all three are decided EXPLICITLY here:
	# nested (only when the relation says "child"), reported as not-nested WITH its reason, or
	# orphaned because its host is not in this sheet. Silence is the one outcome that is not
	# allowed — an unreported drop is precisely how a nozzle leaves a drawing unnoticed.
	# --- 挂载关系（P4） -------------------------------------------------------
	# 被挂载的子件恰好是三者之一，且三者在此**全部显式**判定：
	# 嵌套（仅当关系为 "child"）、带原因报告「未嵌套」、或因宿主不在本图而成为孤儿。
	# **静默**是唯一不被允许的结果 —— 未报告的丢弃正是管口悄悄离开图纸的方式。
	# NOTE the asymmetry: this reports on the MOUNT, while gpFromGraph records the FIELDS.
	# Pre-flight owns policy (what is legal), projection owns data (what is there).
	# 注意这条分工：此处报告的是**政策**（什么合法），gpFromGraph 记录的是**数据**（有什么）。
	# ★ Keyed by INSTANCE id, because that is what gpParentUid actually holds in the live graph
	# (see GPPIDNode.gpParentUid). Comparing it against gpUid would make every healthy mount look
	# like an orphan — a false report is as bad as a missing one, only noisier.
	# ★ 以 **instance id** 为键，因为活图里 gpParentUid 存的**就是**它（见 GPPIDNode.gpParentUid）。
	# 拿它去和 gpUid 比较，会让每一个正常的挂载都看起来像孤儿 ——
	# 误报与漏报一样糟，只是更吵。
	var gpInstanceOf: Dictionary = {}
	var gpParentOf: Dictionary = {}
	for gpNode in gpGraph.gpNodes:
		var gpNU: GPPIDNode = gpNode as GPPIDNode
		if gpNU != null:
			gpInstanceOf[gpNU.gpInstanceId] = true
			gpParentOf[gpNU.gpInstanceId] = gpNU.gpParentUid
	for gpNode in gpGraph.gpNodes:
		var gpNM: GPPIDNode = gpNode as GPPIDNode
		if gpNM == null or gpNM.gpParentUid.is_empty():
			continue
		if not gpInstanceOf.has(gpNM.gpParentUid):
			gpReport.gpAddWarning(GP_CODE_ORPHAN_MOUNT,
				gpNM.gpInstanceId + " is mounted on " + gpNM.gpParentUid
				+ " which is not in this sheet; it goes out as a top-level object")
			continue
		# A parent loop (only reachable through a hand-edited file) would fold both objects into
		# each other; they would then BOTH be missing from the export. Report it and keep both
		# top-level instead.
		# 父链环（只能通过手改文件产生）会让两个对象互相折入，结果**双双**从导出中消失。
		# 报告它，并让两者都留在顶层。
		if _gpMountCycleWith(gpParentOf, gpNM.gpInstanceId, gpNM.gpParentUid):
			gpReport.gpAddWarning(GP_CODE_MOUNT_CYCLE,
				gpNM.gpInstanceId + " and " + gpNM.gpParentUid
				+ " mount each other; both are kept top-level")
			continue
		var gpKindM: String = _gpMountKindOf(gpNM.gpSymbolId)
		var gpRelM: Dictionary = GPDexpiMapping.gpMountRelationFor(gpKindM)
		var gpContainment: String = str(gpRelM.get("containment", ""))
		if gpContainment == GPDexpiMapping.GP_MOUNT_CHILD:
			pass
		elif gpContainment == GPDexpiMapping.GP_MOUNT_UNKNOWN:
			gpReport.gpAddWarning(GP_CODE_MOUNT_UNMAPPED,
				gpNM.gpSymbolId + " has mount kind '" + gpKindM
				+ "' with no relation row; it goes out as a top-level object")
		else:
			gpReport.gpAddInfo(GP_CODE_MOUNT_NOT_NESTED,
				gpNM.gpInstanceId + ": mount kind '" + gpKindM + "' is " + gpContainment
				+ ", so it is not nested (" + str(gpRelM.get("note", "")) + ")")
	# Signal lines belong to the Instrumentation package, whose classes carry URIs we have not
	# verified. Inventing them would be worse than saying so.
	# 信号线属于 Instrumentation 包，其类的 URI 尚未核实。臆造比明说更糟。
	for gpEdge in gpGraph.gpEdges:
		var gpE: GPPIDEdge = gpEdge as GPPIDEdge
		if gpE == null:
			continue
		if gpE.gpKind == GPPIDEdge.GP_SIGNAL:
			gpReport.gpAddWarning(GP_CODE_SIGNAL_UNSUPPORTED,
				"edge " + gpE.gpInstanceId + " is a signal line; Phase 1 exports process lines only")
	return gpReport


# ============================ projection ============================

# Project a live graph + sheet into the intermediate structure. No XML happens here, so the
# mapping can be asserted without parsing text.
# 把活动图 + 图纸投影为中间结构。此处不产生任何 XML，故映射可被断言而无需解析文本。
static func gpFromGraph(gpGraph: GPPIDGraph, gpSheet: GPSheet) -> Dictionary:
	if gpGraph == null or gpSheet == null:
		return {}
	var gpOut: Dictionary = {
		GP_KEY_PLANT: _gpPlantInfo(),
		GP_KEY_DIAGRAM: _gpDiagramOf(gpSheet),
		GP_KEY_EQUIPMENT: [],
		GP_KEY_SEGMENTS: [],
		GP_KEY_SKIPPED: [],
		GP_KEY_HOST_ATTRIBS: [],
		GP_KEY_SHAPES: [],
		GP_KEY_USAGES: [],
		GP_KEY_DRAWING_SHAPES: [],
	}
	# Symbol lookup handed to the port resolver. Under headless tests the library may be empty,
	# which is fine: the resolver then degrades to the node centre rather than failing.
	# 交给端口解析器的图元查找器。headless 测试下图元库可能为空 —— 这没问题：
	# 解析器会降级到节点中心，而不是失败。
	var gpLookup: Callable = GPSymbolLibrary.gpFindById
	# instance id -> stable uid. Edge references are stored as INSTANCE ids (gpFromRef.node_id),
	# while DEXPI object IDs must be STABLE uid, so every edge reference needs this translation.
	# instance id -> 稳定 uid。边的引用存的是 **instance id**（gpFromRef.node_id），
	# 而 DEXPI 的对象 ID 必须是**稳定 uid**，故每个边引用都需要这层翻译。
	var gpUidById: Dictionary = {}
	for gpNode in gpGraph.gpNodes:
		var gpN0: GPPIDNode = gpNode as GPPIDNode
		if gpN0 != null:
			gpUidById[gpN0.gpInstanceId] = gpN0.gpUid

	for gpNode in gpGraph.gpNodes:
		var gpN: GPPIDNode = gpNode as GPPIDNode
		if gpN == null:
			continue
		var gpComp: Dictionary = GPDexpiMapping.gpComponentFor(gpN.gpSymbolId)
		var gpRole: String = str(gpComp.get("role", ""))
		# Annotations have no concept object; internal roles are layout state. Both are
		# recorded in "skipped" so nothing disappears without a trace.
		# 纯图形无概念对象；internal 角色是布局状态。两者都记入 "skipped"，
		# 使任何东西都不会无痕迹地消失。
		if gpRole == GPDexpiMapping.GP_ROLE_ANNOTATION:
			# ★ D3: an insulation part is not an object — it is its host's THICKNESS ANNOTATION.
			# Skipping it as an ANNOTATION is right; skipping its ENGINEERING DATA too would
			# throw away the one number the user typed. So it is still exported, just not as an
			# element of its own. When it has no host to annotate there is nowhere for the value
			# to go, and it is reported as a plain annotation — the visible outcome.
			# ★ D3：保温件不是对象 —— 它是其宿主的**厚度注解**。把它作为**注释**跳过是对的；
			# 连它的**工程数据**一并跳过，就会丢掉用户敲进去的那个数。故它照样导出，
			# 只是不作为自己的元素。没有可注解的宿主时，该值无处可去，
			# 便按普通注释**报告** —— 那是可见的结果。
			var gpHostAttr: Dictionary = _gpHostAttribOf(gpN, gpUidById)
			if gpHostAttr.is_empty():
				(gpOut[GP_KEY_SKIPPED] as Array).append(
					{"id": gpN.gpInstanceId, "symbol": gpN.gpSymbolId, "reason": "annotation"})
			else:
				(gpOut[GP_KEY_HOST_ATTRIBS] as Array).append(gpHostAttr)
				# Kept in "skipped" as well (it is still not an object) but under its OWN reason,
				# so a receiver can tell "this branch is in the file as an attribute" apart from
				# "this branch never made it into the file at all".
				# 同时保留在 "skipped"（它确实仍不是对象），但用**自己的**原因码，
				# 使接收方能区分「这一支以属性形式进了文件」与「这一支根本没进文件」。
				(gpOut[GP_KEY_SKIPPED] as Array).append(
					{"id": gpN.gpInstanceId, "symbol": gpN.gpSymbolId,
						"reason": "annotation_as_host_attribute"})
			continue
		(gpOut[GP_KEY_EQUIPMENT] as Array).append({
			"id": gpN.gpUid,
			"class": str(gpComp.get("class", "")),
			"uri": str(gpComp.get("uri", "")),
			"role": gpRole,
			"tag": gpN.gpTag,
			"names": gpN.gpNames.duplicate(true),
			"props": gpN.gpProps.duplicate(true),
			# ★ NO POSE HERE. A DEXPI Equipment is a CONCEPT object; placement belongs to the
			# graphics layer, so the pose lives in the ShapeUsage — written world-space below.
			# This key used to be set to gpN.gpPosition, the STORED (host-local) value, while
			# the identically named key on the usages is WORLD. One spelling, two meanings, in a
			# structure that round-trips: a trap, not a redundancy. It was also dead (the
			# validator, the importer and gpWriteXml all read the pose from the usage) AND lossy
			# (the reader rebuilt it as ZERO, so it drifted on every export/import cycle).
			# ★ 此处**不**放位姿。DEXPI 的 Equipment 是**概念**对象；放置属于图形层，
			# 故位姿在 ShapeUsage 中（下方按世界坐标写出）。
			# 该键原先写 gpN.gpPosition，即**存储**的（宿主局部）值，而同名的 usage 键是**世界**值。
			# 一个拼写、两种含义、且结构会往返：是陷阱而非冗余。
			# 它同时也是死键（校验器、导入器、gpWriteXml 都从 usage 取位姿），
			# 而且有损 —— 读取器把它重建为 ZERO，故每次导出/导入都漂移。
			# --- hierarchy (P4) -------------------------------------------------
			# ★ The list stays FLAT and every entry carries its own mount fields; folding
			# children into parents is deferred to gpWriteXml(). That is deliberate: the
			# validator, the importer and the summary all iterate this array, so nesting it
			# HERE would make all three silently drop the children — the exact failure mode
			# this codebase keeps guarding against.
			# ★ 本列表保持**扁平**，每条自带挂载字段；把子件折进父件的动作推迟到
			# gpWriteXml()。这是刻意的：校验器、导入器与统计都要遍历本数组，
			# 若在**此处**嵌套，三者都会静默丢掉子件 —— 正是本代码库一直在防的失败模式。
			# Hierarchy (P4). ★ TRANSLATED, not copied: the live graph addresses a host by its
			# gpInstanceId (see GPPIDNode.gpParentUid), while a DEXPI object ID must be the
			# STABLE uid — §7.4 forbids exporting an instance id. Reusing gpUidById, the same
			# map the edge references use, keeps one translation rule for the whole file.
			# 层级（P4）。★ 是**翻译**而非拷贝：活图用 gpInstanceId 指认宿主
			#（见 GPPIDNode.gpParentUid），而 DEXPI 对象 ID 必须是**稳定 uid** ——
			# §7.4 禁止导出 instance id。复用边引用所用的同一个 gpUidById，
			# 使整个文件只有一条翻译规则。
			"parent_uid": str(gpUidById.get(gpN.gpParentUid, "")),
			"mount_anchor": gpN.gpMountAnchor,
			"mount_kind": _gpMountKindOf(gpN.gpSymbolId),
		})

	for gpEdge in gpGraph.gpEdges:
		var gpE: GPPIDEdge = gpEdge as GPPIDEdge
		if gpE == null:
			continue
		if gpE.gpKind == GPPIDEdge.GP_SIGNAL:
			(gpOut[GP_KEY_SKIPPED] as Array).append(
				{"id": gpE.gpInstanceId, "symbol": "", "reason": "signal_unsupported"})
			continue
		var gpGeo: Dictionary = _gpPointsOf(gpGraph, gpE, gpLookup)
		(gpOut[GP_KEY_SEGMENTS] as Array).append({
			# ASSUMPTION (extends §9 待确认): GPPIDEdge has NO stable uid field, so the
			# instance id is used as the DEXPI ID and flagged. Node ids are translated to uid
			# above, so the REFERENCE stays stable even though the segment's own id may not.
			# 假设（延伸自 §9 待确认）：GPPIDEdge **没有**稳定 uid 字段，故以 instance id
			# 作为 DEXPI ID 并标记。节点 id 已在上面翻译成 uid，
			# 故即便管段自身的 id 不稳定，**引用**仍然稳定。
			"id": gpE.gpInstanceId,
			"id_is_stable": false,
			"from_uid": str(gpUidById.get(str(gpE.gpFromRef.get("node_id", "")), "")),
			"to_uid": str(gpUidById.get(str(gpE.gpToRef.get("node_id", "")), "")),
			"from_port": str(gpE.gpFromRef.get("port_id", "")),
			"to_port": str(gpE.gpToRef.get("port_id", "")),
			"points": gpGeo.get("points", []),
			"why_from": str(gpGeo.get("why_from", "")),
			"why_to": str(gpGeo.get("why_to", "")),
			"attrs": gpE.gpAttrs.duplicate(true),
			"tag": gpE.gpTag,
		})
	_gpCollectGraphics(gpGraph, gpOut)
	return gpOut


# ============================ graphics layer (P2) ============================

# Collect the shape catalogue and one usage per node.
# 收集图元目录与每个节点的一个使用实例。
# ★ EVERY node gets a ShapeUsage, including the presentation-only ones (flow arrows, slope
# marks). They have no concept object, so they carry no ItemID — but they ARE graphics, and
# dropping them would silently delete the arrows off the drawing. Skipping them as EQUIPMENT
# (done above) and skipping them as GRAPHICS (avoided here) are two different decisions.
# ★ 每个节点都有 ShapeUsage，**包括**纯呈现类（流向箭头、坡度标记）。它们没有概念对象，
# 故不带 ItemID —— 但它们**是**图形，丢掉它们等于把箭头从图上静默删除。
# 跳过它们的**设备**身份（上面已做）与跳过它们的**图形**身份（此处避免）是两个不同的决定。
static func _gpCollectGraphics(gpGraph: GPPIDGraph, gpOut: Dictionary) -> void:
	var gpShapes: Array = gpOut[GP_KEY_SHAPES] as Array
	var gpUsages: Array = gpOut[GP_KEY_USAGES] as Array
	var gpSeen: Dictionary = {}
	for gpNode in gpGraph.gpNodes:
		var gpN: GPPIDNode = gpNode as GPPIDNode
		if gpN == null:
			continue
		var gpDef: GPSymbolDef = GPSymbolLibrary.gpFindById(gpN.gpSymbolId)
		var gpScale: float = _gpUsageScale(gpDef)
		# ★ WORLD, not stored. A mounted child keeps a LOCAL position in its host's frame, while
		# a ShapeUsage is a world-space placement — writing gpPosition directly would drop every
		# mounted nozzle onto its host's ORIGIN (invisible in a fixture with no mounts, glaring
		# in a real drawing). gpWorldTransform() returns a node's own frame when it is not
		# mounted, so unmounted content stays byte-identical — the same backward-compat anchor
		# GPPortResolver relies on for the pipe endpoints.
		# ★ 用**世界**而非存储值。被挂载子件在其宿主坐标系中保存的是**局部**位置，
		# 而 ShapeUsage 是世界坐标放置 —— 直接写 gpPosition 会把每个被挂载管口丢到宿主**原点**
		# （在无挂载的夹具里看不出来，在真实图纸上却触目惊心）。
		# gpWorldTransform() 在节点未挂载时返回其自身坐标系，故无挂载内容逐字节不变 ——
		# 这正是 GPPortResolver 为管线端点所依赖的同一个向后兼容锚点。
		var gpWT: Dictionary = GPMountResolver.gpWorldTransform(gpGraph,
			GPSymbolLibrary.gpFindById, gpN)
		gpUsages.append({
			"shape_id": gpN.gpSymbolId,
			# The concept object's ID, or "" for presentation-only symbols.
			# 概念对象的 ID；纯呈现图元为 ""。
			"item_id": gpN.gpUid if str(GPDexpiMapping.gpComponentFor(
				gpN.gpSymbolId).get("role", "")) != GPDexpiMapping.GP_ROLE_ANNOTATION else "",
			"instance_id": gpN.gpInstanceId,
			"position": gpWT.get("origin", gpN.gpPosition),
			# ASSUMPTION (§9 待确认 4): G-PID rotation is clockwise-positive, as in most 2D
			# engines; Proteus is counter-clockwise, so the sign inverts on write.
			# 假设（§9 待确认 4）：G-PID 的旋转以顺时针为正（与多数 2D 引擎一致）；
			# Proteus 为逆时针，故写出时符号取反。
			"rotation_deg": float(gpWT.get("rot_deg", gpN.gpRotationDeg)),
			"scale": gpScale,
			"mirrored": bool(gpWT.get("flipped", gpN.gpFlipped)),
		})
		if gpSeen.has(gpN.gpSymbolId) or gpDef == null:
			continue
		gpSeen[gpN.gpSymbolId] = true
		gpShapes.append({"id": gpN.gpSymbolId, "primitives": _gpPrimitivesOf(gpDef)})
	# Free annotation shapes on the sheet are world-space graphics in their own right.
	# 图纸上的自由注释图形本身就是世界坐标下的图形。
	for gpShape in gpGraph.gpShapes:
		var gpS: GPShape = gpShape as GPShape
		if gpS == null:
			continue
		(gpOut[GP_KEY_DRAWING_SHAPES] as Array).append({
			"kind": int(gpS.gpKind),
			"points": Array(gpS.gpPoints),
			"radius": float(gpS.gpRadius),
			"closed": bool(gpS.gpClosed),
			"color": gpS.gpColor,
		})


# ShapeUsage scale: the glyph's unit box (0..100) stretched to the symbol's real size.
# ShapeUsage 缩放：字形的单位框（0..100）拉伸到图元的真实尺寸。
# ★ RESOLVES §9 待确认 3 WITHOUT GUESSING / 无需猜测地解决 §9 待确认 3：
# the report assumed ScaleX=ScaleY=1.0 because G-PID has no per-instance scale field. That is
# true of the INSTANCE, but the scale is not missing — it is implied by the pair
# (unit box, gpDefaultSize) and can be computed. Exporting the real ratio beats shipping 1.0,
# and it is derived from project data rather than invented.
# 报告假设 ScaleX=ScaleY=1.0，因为 G-PID 没有实例级缩放字段。这对**实例**成立，
# 但缩放并未缺失 —— 它由（单位框, gpDefaultSize）这一对隐含地给出，可以算出。
# 导出真实比值优于写 1.0，且它来自项目数据而非臆造。
	# Computed HERE rather than calling GPSymbolPainter.gpFitScale(): that lives in the render
	# layer, and io must not depend on render (direction is ui -> io -> core). The formula is
	# one line, so duplicating it beats breaking the layering.
	# 在此**自行计算**，而不调用 GPSymbolPainter.gpFitScale()：后者位于 render 层，
	# 而 io 不得依赖 render（依赖方向为 ui -> io -> core）。公式只有一行，
	# 故复制它优于破坏分层。
static func _gpUsageScale(gpDef: GPSymbolDef) -> float:
	if gpDef == null:
		return 1.0
	var gpSize: Vector2 = gpDef.gpDefaultSize
	return minf(gpSize.x, gpSize.y) / GP_UNIT_BOX


# A symbol definition's glyph primitives, in unit space (0..100).
# 图元定义的字形图元，位于单位空间（0..100）。
static func _gpPrimitivesOf(gpDef: GPSymbolDef) -> Array:
	var gpOut: Array = []
	for gpShape in gpDef.gpShapes:
		var gpS: GPShape = gpShape as GPShape
		if gpS == null:
			continue
		gpOut.append({
			"kind": int(gpS.gpKind),
			"points": Array(gpS.gpPoints),
			"radius": float(gpS.gpRadius),
			"closed": bool(gpS.gpClosed),
			"color": gpS.gpColor,
		})
	return gpOut


# Diagram values in CONCEPTUAL coordinates (Y down). The Y flip happens once, at write time.
# Diagram 取值使用**概念坐标**（Y 向下）。Y 翻转只在写出时发生一次。
static func _gpDiagramOf(gpSheet: GPSheet) -> Dictionary:
	return {
		"name": gpSheet.gpName,
		"min_x": 0.0,
		"min_y": 0.0,
		"max_x": float(gpSheet.gpWidthMM),
		"max_y": float(gpSheet.gpHeightMM),
		# ASSUMPTION: BackgroundColor is serialised as #rrggbb. The spec types it as Color but
		# does not fix a textual form; #rrggbb is the conventional one. Flagged for confirmation.
		# 假设：BackgroundColor 以 #rrggbb 序列化。规范将其类型定为 Color 但未规定文本形式；
		# #rrggbb 是通行写法。已标记待确认。
		"background": "#ffffff",
	}


static func _gpPlantInfo() -> Dictionary:
	var gpNow: Dictionary = Time.get_datetime_dict_from_system()
	return {
		"date": "%04d-%02d-%02d" % [gpNow.get("year", 1970), gpNow.get("month", 1), gpNow.get("day", 1)],
		"time": "%02d:%02d:%02d" % [gpNow.get("hour", 0), gpNow.get("minute", 0), gpNow.get("second", 0)],
		"system": GPDexpiSchema.GP_ORIGINATING_SYSTEM,
		"vendor": GPDexpiSchema.GP_ORIGINATING_SYSTEM,
		"version": "0.1.0",
	}


# Full pipe geometry: start, the stored bends, then the end.
# 完整管线几何：起点、已存折点、终点。
# ASSUMPTION (§9 待确认 2): gpRouting holds BENDS ONLY, so the two endpoints must come from
# the port resolution — which is exactly how the renderer builds the same polyline. Reusing
# GPPortResolver rather than re-deriving endpoints means the exported line and the drawn line
# cannot drift apart.
# 假设（§9 待确认 2）：gpRouting **只存折点**，故两个端点必须来自端口解析 ——
# 这与渲染器构建同一条折线的方式完全一致。复用 GPPortResolver 而非自行推导端点，
# 意味着导出的线与画出的线不可能漂移。
# The resolver degrades on its own ladder (port -> typed -> center -> free) and reports which
# rung it used in "why", so a degraded endpoint is recorded rather than silently accepted.
# 解析器按自身阶梯降级（port -> typed -> center -> free），并在 "why" 中报告所用级别，
# 故端点降级会被**记录**而非静默接受。
static func _gpPointsOf(gpGraph: GPPIDGraph, gpEdge: GPPIDEdge, gpLookup: Callable) -> Dictionary:
	var gpWant: String = GPPortResolver.gpWantTypeFor(gpEdge)
	var gpA: Dictionary = GPPortResolver.gpResolveEnd(gpGraph, gpLookup, gpEdge, true, gpWant)
	var gpB: Dictionary = GPPortResolver.gpResolveEnd(gpGraph, gpLookup, gpEdge, false, gpWant)
	var gpPts: Array = []
	gpPts.append(gpA.get("pos", Vector2.ZERO) as Vector2)
	for gpP in gpEdge.gpRouting:
		gpPts.append(gpP as Vector2)
	gpPts.append(gpB.get("pos", Vector2.ZERO) as Vector2)
	return {
		"points": gpPts,
		"why_from": str(gpA.get("why", "")),
		"why_to": str(gpB.get("why", "")),
		"bound_from": bool(gpA.get("bound", false)),
		"bound_to": bool(gpB.get("bound", false)),
	}


# ============================ serialisation ============================

# Turn the intermediate structure into a Proteus XML document.
# 把中间结构转为 Proteus XML 文档。
# EVERY coordinate passes through GPDexpiMapping.gpFlipY() — the single flip point.
# 每个坐标都经 GPDexpiMapping.gpFlipY() —— 唯一的翻转点。
static func gpWriteXml(gpMid: Dictionary) -> String:
	if gpMid.is_empty():
		return ""
	var gpLines: Array[String] = []
	gpLines.append(GPXmlText.gpDeclaration())
	gpLines.append(GPXmlText.gpOpen("PlantModel", "", 0))
	gpLines.append_array(_gpPlantInformationLines(gpMid.get(GP_KEY_PLANT, {})))
	# ★ Nesting is resolved HERE, over the flat list — never in the projection.
	# The intermediate structure keeps ONE entry per object so the validator, the importer and
	# the summary all keep seeing every object; only the serialiser folds mountable children
	# into their host. Two passes, both O(n): index by uid, then bucket the children.
	# ★ 嵌套在**此处**、在扁平列表上解析 —— 绝不在投影阶段做。
	# 中间结构保持「每对象一条」，使校验器 / 导入器 / 统计都能看到全部对象；
	# 只有序列化器把可挂载子件折进宿主。两趟扫描，均为 O(n)：先按 uid 建索引，再给子件分桶。
	var gpEquipment: Array = gpMid.get(GP_KEY_EQUIPMENT, []) as Array
	var gpByUid: Dictionary = {}
	# uid -> parent uid, kept separately because the cycle walk needs only the chain, not the
	# whole entry. Built from the SAME source as gpByUid so the two can never disagree.
	# uid -> 父 uid，单独保存 —— 环检测只需要链本身而非整个条目。
	# 与 gpByUid 取自**同一**来源，故两者不可能不一致。
	var gpParentOf: Dictionary = {}
	for gpEqIdx in gpEquipment:
		var gpDIdx: Dictionary = gpEqIdx as Dictionary
		var gpUidIdx: String = str(gpDIdx.get("id", ""))
		if not gpUidIdx.is_empty():
			gpByUid[gpUidIdx] = gpDIdx
			gpParentOf[gpUidIdx] = str(gpDIdx.get("parent_uid", ""))
	var gpFolded: Dictionary = {}          # child uid -> true (emitted inside its host)
	var gpChildrenOf: Dictionary = {}      # host uid -> Array[Dictionary]
	for gpEqKid in gpEquipment:
		var gpDKid: Dictionary = gpEqKid as Dictionary
		var gpHostUid: String = str(gpDKid.get("parent_uid", ""))
		var gpKidUid: String = str(gpDKid.get("id", ""))
		# A child folds in only when BOTH sides are known: its host is in this sheet AND the
		# relation says "child". Either failure leaves it top-level — the VISIBLE choice, and
		# the only one safe to make by default.
		# 只有当**两侧**都已知时子件才折入：宿主在本图内，**且**关系判定为 "child"。
		# 任一不成立都保持顶层 —— 那是**可见**的选择，也是唯一可以安全默认的选择。
		if gpHostUid.is_empty() or gpKidUid.is_empty():
			continue
		if not gpByUid.has(gpHostUid):
			continue
		if not GPDexpiMapping.gpIsNestable(str(gpDKid.get("mount_kind", ""))):
			continue
		# Cycle guard, mirroring GPMountResolver's: a hand-edited parent loop would otherwise
		# fold the two objects into each other, so BOTH would vanish from the file and the
		# recursion below would never terminate.
		# 环护栏，与 GPMountResolver 的同理：手改出来的父链环会让两个对象互相折入，
		# 结果**双双从文件中消失**，且下面的递归永不终止。
		if _gpMountCycleWith(gpParentOf, gpKidUid, gpHostUid):
			continue
		gpFolded[gpKidUid] = true
		if not gpChildrenOf.has(gpHostUid):
			gpChildrenOf[gpHostUid] = []
		(gpChildrenOf[gpHostUid] as Array).append(gpDKid)
	# ★ A third bucket, for parts that are NOT objects (§D3 "attribute" relations). They never
	# entered gpEquipment, so they are bucketed straight from the projection. A host uid that
	# resolves to nothing in THIS sheet is skipped rather than emitted somewhere arbitrary —
	# preflight has already reported it as an orphan mount, so it is not a silent loss.
	# ★ 第三个桶，专收**不是对象**的件（§D3 的 "attribute" 关系）。它们从未进入 gpEquipment，
	# 故直接从投影分桶。宿主 uid 在**本图**解析不到时跳过，而不是随手写到别处 ——
	# 预检已把它报告为孤儿挂载，故不是静默丢失。
	var gpHostAttribs: Dictionary = {}     # host uid -> Array[Dictionary]
	for gpAttr in (gpMid.get(GP_KEY_HOST_ATTRIBS, []) as Array):
		var gpDAttr: Dictionary = gpAttr as Dictionary
		var gpHU: String = str(gpDAttr.get("host_uid", ""))
		if gpHU.is_empty() or not gpByUid.has(gpHU):
			continue
		if not gpHostAttribs.has(gpHU):
			gpHostAttribs[gpHU] = []
		(gpHostAttribs[gpHU] as Array).append(gpDAttr)
	for gpEq in gpEquipment:
		var gpDEq: Dictionary = gpEq as Dictionary
		if gpFolded.has(str(gpDEq.get("id", ""))):
			continue
		gpLines.append_array(_gpEquipmentLines(gpDEq, gpChildrenOf, 1, gpHostAttribs))
	for gpSeg in (gpMid.get(GP_KEY_SEGMENTS, []) as Array):
		gpLines.append_array(_gpSegmentLines(gpSeg as Dictionary))
	gpLines.append_array(_gpDrawingLines(gpMid.get(GP_KEY_DIAGRAM, {}), gpMid))
	gpLines.append_array(_gpShapeCatalogueLines(gpMid.get(GP_KEY_SHAPES, []) as Array))
	gpLines.append(GPXmlText.gpClose("PlantModel", 0))
	return "\n".join(gpLines)


static func _gpPlantInformationLines(gpPlant: Dictionary) -> Array[String]:
	var gpAttrs: String = GPXmlText.gpAttrs([
		GPXmlText.gpAttr("Discipline", GPDexpiSchema.GP_DISCIPLINE),
		GPXmlText.gpAttr("Is3D", "no"),
		GPXmlText.gpAttr("SchemaVersion", GPDexpiSchema.GP_PROTEUS_SCHEMA_VERSION),
		GPXmlText.gpAttr("Date", str(gpPlant.get("date", ""))),
		GPXmlText.gpAttr("Time", str(gpPlant.get("time", ""))),
		GPXmlText.gpAttr("OriginatingSystem", str(gpPlant.get("system", ""))),
		GPXmlText.gpAttr("OriginatingSystemVendor", str(gpPlant.get("vendor", ""))),
		GPXmlText.gpAttr("OriginatingSystemVersion", str(gpPlant.get("version", ""))),
		GPXmlText.gpAttr("Units", GPDexpiSchema.GP_UNITS),
	])
	var gpOut: Array[String] = []
	gpOut.append(GPXmlText.gpOpen("PlantInformation", gpAttrs, 1))
	gpOut.append(GPXmlText.gpSelf("UnitsOfMeasure", "", 2))
	gpOut.append(GPXmlText.gpClose("PlantInformation", 1))
	return gpOut


# All device classes serialise as <Equipment>; the distinction is ComponentClass (§4.3 ①).
# 所有设备类都序列化为 <Equipment>；区分靠 ComponentClass（§4.3 ①）。
static func _gpEquipmentLines(gpEq: Dictionary, gpChildrenOf: Dictionary,
		gpLevel: int = 1, gpAttribsOf: Dictionary = {}) -> Array[String]:
	# ★ The ELEMENT name comes from the mount relation, so an orphaned nozzle is still a
	# <Nozzle> to the receiver and a loose actuator is still an <ActuatingSystem>. Neither
	# dissolves into a faceless <Equipment> merely because it lost its host.
	# ★ **元素名**取自挂载关系，故成为孤儿的管口对接收方而言仍是 <Nozzle>、
	# 走失的执行机构仍是 <ActuatingSystem> —— 都**不会**仅仅因为失去宿主就溶成无名的 <Equipment>。
	var gpElement: String = gpElementFor(gpEq)
	var gpAttrs: String = GPXmlText.gpAttrs([
		GPXmlText.gpAttr("ID", str(gpEq.get("id", ""))),
		GPXmlText.gpAttr("ComponentClass", str(gpEq.get("class", ""))),
		GPXmlText.gpAttr("ComponentClassURI", str(gpEq.get("uri", ""))),
	])
	var gpOut: Array[String] = []
	gpOut.append(GPXmlText.gpOpen(gpElement, gpAttrs, gpLevel))
	# ★ SAME block, one extra source of lines. Parts that DEXPI models as an ATTRIBUTE of this
	# object (§D3 insulation) contribute here, so the file says "this vessel is insulated to
	# 80 mm" — the annotation D3 asks for — instead of inventing an element for a hatch mark.
	# WHY INSIDE THIS BLOCK AND NOT A SECOND ONE / 为何写进**同一个**块而非再开一个：
	# two <GenericAttributes> of one Set under one parent is a structural violation (§6.5 risk 9),
	# and an empty second block would be noise. Concatenating first keeps exactly one container.
	# ★ **同一个**块，只是多了一个行的来源。被 DEXPI 建模为本对象**属性**的件（§D3 保温）
	# 在此贡献，于是文件说「此容器保温 80 mm」—— 正是 D3 要的注解 ——
	# 而不是给一条剖面线臆造一个元素。
	# 为何写进**同一个**块：同一父元素下两个同 Set 的 <GenericAttributes> 属结构违规
	#（§6.5 风险 9），而空的第二块只是噪音。先拼接，容器就恰有一个。
	var gpContent: Array[String] = _gpContentAttribs(gpEq, gpLevel + 1)
	for gpAttrChild in (gpAttribsOf.get(str(gpEq.get("id", "")), []) as Array):
		var gpChildAttrs: Dictionary = (gpAttrChild as Dictionary).get("attrs", {}) as Dictionary
		for gpKey in gpChildAttrs.keys():
			gpContent.append_array(_gpPropertyLines(str(gpKey), gpChildAttrs[gpKey], gpLevel + 1))
	gpOut.append_array(_gpGenericAttributesBlock(gpContent, gpLevel + 1, GPDexpiSchema.GP_SET_DEXPI))
	# ★ Mounted children nest INSIDE the host — a nozzle is a component OF its equipment, not a
	# sibling of it. Only the "child" containment is ever bucketed here (see gpWriteXml).
	# ASSUMPTION (§9 待确认 12): the children are written AFTER the host's GenericAttributes block.
	# Godot has no XSD validator, so element order inside a parent cannot be checked here; if the
	# spec requires a strict sequence, moving this loop is the whole fix.
	# ★ 被挂载子件嵌在宿主**内部** —— 管口是其设备的组成部分，而非它的兄弟。
	# 只有 "child" 关系会被分进这个桶（见 gpWriteXml）。
	# 假设（§9 待确认 12）：子件写在宿主 GenericAttributes 块**之后**。Godot 无 XSD 校验器，
	# 故父元素内部的元素顺序在此无法校验；若规范要求严格顺序，挪动这个循环即是全部改动。
	# RECURSION, not a flat loop: a grandchild is bucketed under its own parent, so a flat loop
	# here would leave it behind without a word.
	# 用**递归**而非平铺循环：孙代子件分在其自身父件的桶下，平铺循环会把它一声不吭地落下。
	for gpChild in (gpChildrenOf.get(str(gpEq.get("id", "")), []) as Array):
		gpOut.append_array(_gpEquipmentLines(gpChild as Dictionary, gpChildrenOf, gpLevel + 1,
			gpAttribsOf))
	gpOut.append(GPXmlText.gpClose(gpElement, gpLevel))
	return gpOut


# The DEXPI element a G-PID object is written as.
# 某 G-PID 对象所写成的 DEXPI 元素。
# A mountable child keeps its relation's element name EVEN WHEN IT IS NOT NESTED, so a degraded
# object stays identifiable instead of dissolving into a generic <Equipment>.
# 可挂载子件**即使未被嵌套**也保留其关系的元素名，使降级的对象仍可辨认，
# 而不是溶成一个通用 <Equipment>。
# An empty element name (attribute-only relations, and unmapped kinds) falls back to
# <Equipment>, the spec's universal component element — never an invented tag.
# 元素名为空时（仅属性的关系，以及未映射的类别）回退为 <Equipment>（规范中的通用部件元素），
# **绝不**臆造标签。
static func gpElementFor(gpEntry: Dictionary) -> String:
	var gpRel: Dictionary = GPDexpiMapping.gpMountRelationFor(str(gpEntry.get("mount_kind", "")))
	var gpEl: String = str(gpRel.get("element", ""))
	return "Equipment" if gpEl.is_empty() else gpEl


# The <GenericAttributes> content shared by a host and its mounted children: tag, then one
# per-language name element, then the engineering properties. Factored out so a child cannot
# accidentally carry a different attribute vocabulary than its parent.
# 宿主与其被挂载子件共享的 <GenericAttributes> 内容：位号、各语言名称元素、再是工程属性。
# 抽出来是为了让子件**不可能**意外携带与宿主不同的属性词表。
static func _gpContentAttribs(gpObj: Dictionary, gpLevel: int) -> Array[String]:
	var gpAttribs: Array[String] = []
	if not str(gpObj.get("tag", "")).is_empty():
		gpAttribs.append(_gpGenericAttribute("TagNameAssignmentClass", "", gpObj.get("tag"),
			"string", "", "", "", gpLevel))
	var gpNames: Dictionary = gpObj.get("names", {}) as Dictionary
	for gpLang in gpNames.keys():
		var gpText: String = str(gpNames.get(gpLang, ""))
		if gpText.is_empty():
			continue
		gpAttribs.append(_gpGenericAttribute("DescriptionAssignmentClass", "", gpText,
			"string", "", "", GPXmlText.gpLang2(str(gpLang)), gpLevel))
	var gpProps: Dictionary = gpObj.get("props", {}) as Dictionary
	for gpKey in gpProps.keys():
		gpAttribs.append_array(_gpPropertyLines(str(gpKey), gpProps.get(gpKey), gpLevel))
	return gpAttribs


# True when walking UP the mount chain from [param gpHostUid] reaches [param gpChildUid] — i.e.
# the two sit on one parent loop, so folding the child into the host would be mutual.
# 从 [param gpHostUid] 沿挂载链**向上**走能否到达 [param gpChildUid] —— 即两者同处一个父链环，
# 那样把子件折进宿主就会变成互相折入。
# Bounded by the entry count as well as by "", so a malformed chain cannot spin forever.
# 以条目数为界并以 "" 为终止，故畸形链也不会空转。
static func _gpMountCycleWith(gpParentOf: Dictionary, gpChildUid: String, gpHostUid: String) -> bool:
	var gpAt: String = gpHostUid
	var gpGuard: int = 0
	while not gpAt.is_empty() and gpGuard <= gpParentOf.size():
		if gpAt == gpChildUid:
			return true
		gpAt = str(gpParentOf.get(gpAt, ""))
		gpGuard += 1
	return false


# The G-PID mount kind of a symbol ("" when it is not a mountable child). Read from the
# definition rather than from the node, because the node stores only the mount it HAS, never
# what kind it is — the kind is a property of the symbol, shared by every instance.
# 某图元的 G-PID 挂载类别（非可挂载子件时为 ""）。取自**定义**而非节点 ——
# 节点只存它**实际**的挂载，从不存它**是哪一类**；类别是图元的属性，为所有实例共享。
static func _gpMountKindOf(gpSymbolId: String) -> String:
	var gpDef: GPSymbolDef = GPSymbolLibrary.gpFindById(gpSymbolId)
	if gpDef == null:
		return ""
	return gpDef.gpMountKind


# The host-attribute contribution of one mounted child: which host it annotates and the values
# it contributes, or {} when there is nothing to contribute.
# 某个被挂载子件对宿主的属性贡献：它注解哪个宿主、贡献哪些值；无贡献时返回 {}。
# WHY EVERY EARLY RETURN IS A PLAIN SENTENCE / 为何每个提前返回都是平铺直叙的：
# "" from the relation means the part is not an annotator at all; an empty host_uid means this
# sheet holds no such host; an empty attrs map means the user filled nothing in. They are three
# different facts, and only the LAST one is "nothing to say" — so the caller can still record
# the part as an ordinary annotation rather than silently dropping it.
# 关系返回空列表 = 该件根本不是注解器；host_uid 为空 = 本图没有这个宿主；
# attrs 为空 = 用户什么都没填。这是三件不同的事，且只有**最后一件**是「无话可说」——
# 故调用方仍能把该件记作普通注释，而不是悄悄丢掉它。
# ★ The host is addressed by its STABLE uid, like every other cross-object reference in the
# file (§7.4): the node's gpParentUid is an instance id and must be translated, never copied.
# ★ 宿主以**稳定 uid** 指认，与本文件其它所有跨对象引用一致（§7.4）：
# 节点的 gpParentUid 是 instance id，必须**翻译**而非拷贝。
static func _gpHostAttribOf(gpN: GPPIDNode, gpUidById: Dictionary) -> Dictionary:
	var gpKind: String = _gpMountKindOf(gpN.gpSymbolId)
	var gpKeys: Array[String] = GPDexpiMapping.gpHostAttrKeys(gpKind)
	if gpKeys.is_empty() or gpN.gpParentUid.is_empty():
		return {}
	var gpHostUid: String = str(gpUidById.get(gpN.gpParentUid, ""))
	if gpHostUid.is_empty():
		return {}
	var gpAttrs: Dictionary = {}
	for gpKey in gpKeys:
		if gpN.gpProps.has(gpKey):
			gpAttrs[gpKey] = gpN.gpProps[gpKey]
	if gpAttrs.is_empty():
		return {}
	return {"host_uid": gpHostUid, "kind": gpKind, "attrs": gpAttrs}


# A Pipe is a <CenterLine> whose parent is a <PipingNetworkSegment> (§2.2, spec quote).
# Pipe 是父元素为 <PipingNetworkSegment> 的 <CenterLine>（§2.2，规范原文）。
static func _gpSegmentLines(gpSeg: Dictionary) -> Array[String]:
	var gpOut: Array[String] = []
	var gpSysAttrs: String = GPXmlText.gpAttrs([
		GPXmlText.gpAttr("ID", "pns_" + str(gpSeg.get("id", ""))),
		GPXmlText.gpAttr("ComponentClass", "PipingNetworkSystem"),
		GPXmlText.gpAttr("ComponentClassURI", GPDexpiSchema.GP_URI_PIPING_NETWORK_SYSTEM),
	])
	gpOut.append(GPXmlText.gpOpen("PipingNetworkSystem", gpSysAttrs, 1))
	var gpSegAttrs: String = GPXmlText.gpAttrs([
		GPXmlText.gpAttr("ID", str(gpSeg.get("id", ""))),
		GPXmlText.gpAttr("ComponentClass", "PipingNetworkSegment"),
		GPXmlText.gpAttr("ComponentClassURI", GPDexpiSchema.GP_URI_PIPING_NETWORK_SEGMENT),
	])
	gpOut.append(GPXmlText.gpOpen("PipingNetworkSegment", gpSegAttrs, 2))
	# Item-level references are stable uids; PORT-level (SourceNode) references are deferred
	# until nozzles are exported, because a nozzle reference needs a Nozzle ID to point at.
	# 项级引用使用稳定 uid；**管口级**（SourceNode）引用推迟到导出管口之后 ——
	# 因为管口引用需要一个可被指向的 Nozzle ID。
	var gpFromUid: String = str(gpSeg.get("from_uid", ""))
	var gpToUid: String = str(gpSeg.get("to_uid", ""))
	if not gpFromUid.is_empty():
		gpOut.append(GPXmlText.gpSelf("SourceItem", GPXmlText.gpAttr("ItemID", gpFromUid), 3))
	if not gpToUid.is_empty():
		gpOut.append(GPXmlText.gpSelf("TargetItem", GPXmlText.gpAttr("ItemID", gpToUid), 3))

	gpOut.append(GPXmlText.gpOpen("CenterLine", "", 3))
	var gpPts: Array = gpSeg.get("points", []) as Array
	gpOut.append(GPXmlText.gpOpen("PolyLine",
		GPXmlText.gpAttr("NumPoints", str(gpPts.size())), 4))
	for gpP in gpPts:
		var gpV: Vector2 = gpP as Vector2
		# THE FLIP. Concept Y is down; Proteus file Y is up (§4.4).
		# 翻转。概念 Y 向下；Proteus 文件 Y 向上（§4.4）。
		gpOut.append(GPXmlText.gpSelf("Coordinate", GPXmlText.gpAttrs([
			GPXmlText.gpAttr("X", GPXmlText.gpNum(gpV.x)),
			GPXmlText.gpAttr("Y", GPXmlText.gpNum(GPDexpiMapping.gpFlipY(gpV.y))),
		]), 5))
	gpOut.append(GPXmlText.gpClose("PolyLine", 4))
	gpOut.append(GPXmlText.gpClose("CenterLine", 3))

	var gpAttribs: Array[String] = []
	if not str(gpSeg.get("tag", "")).is_empty():
		gpAttribs.append(_gpGenericAttribute("TagNameAssignmentClass", "", gpSeg.get("tag"),
			"string", "", "", "", 3))
	var gpAttrs: Dictionary = gpSeg.get("attrs", {}) as Dictionary
	for gpKey in gpAttrs.keys():
		gpAttribs.append_array(_gpPropertyLines(str(gpKey), gpAttrs.get(gpKey), 3))
	gpOut.append_array(_gpGenericAttributesBlock(gpAttribs, 3, GPDexpiSchema.GP_SET_DEXPI))
	gpOut.append(GPXmlText.gpClose("PipingNetworkSegment", 2))
	gpOut.append(GPXmlText.gpClose("PipingNetworkSystem", 1))
	return gpOut


# <Drawing> carries the Diagram's four mandatory extent values (§3.1) — and they are flipped
# too.
# <Drawing> 承载 Diagram 的四个必填范围值（§3.1）—— 它们同样要翻转。
# ★ DEVIATION FROM THE REPORT'S LITERAL WORDING (§3.1 suggests MinY=0 / MaxY=height):
# if the extent kept concept coordinates while every coordinate is flipped, EVERY shape would
# land OUTSIDE its own drawing (all Y negative against a 0..297 extent). Flipping the extent is
# the only self-consistent reading, so it is what ships. Flagged as a confirmation item.
# ★ 偏离报告字面表述（§3.1 建议 MinY=0 / MaxY=height）：
# 若范围保留概念坐标而所有坐标都翻转，则**每个图形都会落在自己图纸之外**
# （所有 Y 为负，而范围是 0..297）。翻转范围是唯一自洽的读法，故采用之。已列为待确认项。
static func _gpDrawingLines(gpDiagram: Dictionary, gpMid: Dictionary) -> Array[String]:
	if gpDiagram.is_empty():
		return []
	var gpAttrs: String = GPXmlText.gpAttrs([
		GPXmlText.gpAttr("ID", "drawing1"),
		GPXmlText.gpAttr("Name", str(gpDiagram.get("name", ""))),
		GPXmlText.gpAttr("MinX", GPXmlText.gpNum(float(gpDiagram.get("min_x", 0.0)))),
		GPXmlText.gpAttr("MinY",
			GPXmlText.gpNum(GPDexpiMapping.gpFlipY(float(gpDiagram.get("max_y", 0.0))))),
		GPXmlText.gpAttr("MaxX", GPXmlText.gpNum(float(gpDiagram.get("max_x", 0.0)))),
		GPXmlText.gpAttr("MaxY",
			GPXmlText.gpNum(GPDexpiMapping.gpFlipY(float(gpDiagram.get("min_y", 0.0))))),
		GPXmlText.gpAttr("BackgroundColor", str(gpDiagram.get("background", "#ffffff"))),
	])
	var gpOut: Array[String] = []
	gpOut.append(GPXmlText.gpOpen("Drawing", gpAttrs, 1))
	gpOut.append_array(_gpUsageGroupLines(gpMid.get(GP_KEY_USAGES, []) as Array))
	gpOut.append_array(_gpFreeShapeGroupLines(gpMid.get(GP_KEY_DRAWING_SHAPES, []) as Array))
	gpOut.append(GPXmlText.gpClose("Drawing", 1))
	return gpOut


# One RepresentationGroup holding every ShapeUsage (§10: groups mirror the concept hierarchy).
# 一个承载全部 ShapeUsage 的 RepresentationGroup（§10：分组层次对应概念层次）。
static func _gpUsageGroupLines(gpUsages: Array) -> Array[String]:
	if gpUsages.is_empty():
		return []
	var gpOut: Array[String] = []
	gpOut.append(GPXmlText.gpOpen("RepresentationGroup",
		GPXmlText.gpAttr("ID", "rg_static"), 2))
	gpOut.append(GPXmlText.gpOpen("RepresentationTypeGroup", GPXmlText.gpAttrs([
		GPXmlText.gpAttr("ID", "rtg_static"),
		GPXmlText.gpAttr("Type", "Static"),
	]), 3))
	var gpIndex: int = 0
	for gpUsage in gpUsages:
		var gpU: Dictionary = gpUsage as Dictionary
		gpIndex += 1
		var gpScale: float = float(gpU.get("scale", 1.0))
		var gpAttrs: String = GPXmlText.gpAttrs([
			GPXmlText.gpAttr("ID", "su_%d" % gpIndex),
			# A presentation-only symbol has no concept object, so no ItemID reference.
			# 纯呈现图元没有概念对象，故无 ItemID 引用。
			GPXmlText.gpAttr("ItemID", str(gpU.get("item_id", ""))),
			GPXmlText.gpAttr("Shape", str(gpU.get("shape_id", ""))),
			GPXmlText.gpAttr("ScaleX", GPXmlText.gpNum(gpScale)),
			GPXmlText.gpAttr("ScaleY", GPXmlText.gpNum(gpScale)),
			# Clockwise in G-PID, counter-clockwise in Proteus: the sign inverts.
			# G-PID 顺时针、Proteus 逆时针：符号取反。
			GPXmlText.gpAttr("Rotation",
				GPXmlText.gpNum(GPDexpiMapping.gpFlipY(float(gpU.get("rotation_deg", 0.0))))),
			GPXmlText.gpAttr("IsMirrored", "yes" if bool(gpU.get("mirrored", false)) else "no"),
		])
		gpOut.append(GPXmlText.gpOpen("ShapeUsage", gpAttrs, 4))
		var gpPos: Vector2 = gpU.get("position", Vector2.ZERO) as Vector2
		gpOut.append(GPXmlText.gpSelf("Position", GPXmlText.gpAttrs([
			GPXmlText.gpAttr("X", GPXmlText.gpNum(gpPos.x)),
			GPXmlText.gpAttr("Y", GPXmlText.gpNum(GPDexpiMapping.gpFlipY(gpPos.y))),
		]), 5))
		gpOut.append(GPXmlText.gpClose("ShapeUsage", 4))
	gpOut.append(GPXmlText.gpClose("RepresentationTypeGroup", 3))
	gpOut.append(GPXmlText.gpClose("RepresentationGroup", 2))
	return gpOut


# Free annotation shapes drawn straight on the sheet (world coordinates).
# 直接画在图纸上的自由注释图形（世界坐标）。
static func _gpFreeShapeGroupLines(gpShapes: Array) -> Array[String]:
	if gpShapes.is_empty():
		return []
	var gpOut: Array[String] = []
	gpOut.append(GPXmlText.gpOpen("RepresentationGroup",
		GPXmlText.gpAttr("ID", "rg_annotation"), 2))
	gpOut.append(GPXmlText.gpOpen("RepresentationTypeGroup", GPXmlText.gpAttrs([
		GPXmlText.gpAttr("ID", "rtg_annotation"),
		GPXmlText.gpAttr("Type", "Static"),
	]), 3))
	for gpPrim in gpShapes:
		gpOut.append_array(_gpPrimitiveLines(gpPrim as Dictionary, 4))
	gpOut.append(GPXmlText.gpClose("RepresentationTypeGroup", 3))
	gpOut.append(GPXmlText.gpClose("RepresentationGroup", 2))
	return gpOut


# The shape catalogue: one <Shape> per used symbol, holding its glyph primitives.
# 图元目录：每个用到的图元一个 <Shape>，内含其字形图元。
static func _gpShapeCatalogueLines(gpShapes: Array) -> Array[String]:
	if gpShapes.is_empty():
		return []
	var gpOut: Array[String] = []
	gpOut.append(GPXmlText.gpOpen("ShapeCatalogue",
		GPXmlText.gpAttr("Name", "G-PID"), 1))
	for gpShape in gpShapes:
		var gpS: Dictionary = gpShape as Dictionary
		gpOut.append(GPXmlText.gpOpen("Shape",
			GPXmlText.gpAttr("Name", str(gpS.get("id", ""))), 2))
		for gpPrim in (gpS.get("primitives", []) as Array):
			gpOut.append_array(_gpPrimitiveLines(gpPrim as Dictionary, 3))
		gpOut.append(GPXmlText.gpClose("Shape", 2))
	gpOut.append(GPXmlText.gpClose("ShapeCatalogue", 1))
	return gpOut


# One graphical primitive. Every Y goes through gpFlipY, exactly as the center lines do: the
# file frame is uniformly Y-up, so a local coordinate is no exception.
# 一个图形图元。每个 Y 都经 gpFlipY，与中心线完全一致：文件坐标系**统一**为 Y 向上，
# 局部坐标也不例外。
static func _gpPrimitiveLines(gpPrim: Dictionary, gpLevel: int) -> Array[String]:
	var gpPts: Array = gpPrim.get("points", []) as Array
	if gpPts.is_empty():
		return []
	var gpKind: int = int(gpPrim.get("kind", 0))
	var gpClosed: bool = bool(gpPrim.get("closed", false))
	var gpColor: Color = gpPrim.get("color", Color(0.0, 0.0, 0.0)) as Color
	var gpOut: Array[String] = []
	match gpKind:
		GPShape.GPKind.GP_CIRCLE:
			gpOut.append(GPXmlText.gpOpen("Ellipse", "", gpLevel))
			var gpC: Vector2 = gpPts[0] as Vector2
			gpOut.append(GPXmlText.gpSelf("Center", GPXmlText.gpAttrs([
				GPXmlText.gpAttr("X", GPXmlText.gpNum(gpC.x)),
				GPXmlText.gpAttr("Y", GPXmlText.gpNum(GPDexpiMapping.gpFlipY(gpC.y))),
			]), gpLevel + 1))
			gpOut.append(GPXmlText.gpSelf("RX",
				GPXmlText.gpAttr("Value", GPXmlText.gpNum(float(gpPrim.get("radius", 0.0)))),
				gpLevel + 1))
			gpOut.append(GPXmlText.gpSelf("RY",
				GPXmlText.gpAttr("Value", GPXmlText.gpNum(float(gpPrim.get("radius", 0.0)))),
				gpLevel + 1))
			gpOut.append_array(_gpPresentationLines(gpColor, gpLevel + 1))
			gpOut.append(GPXmlText.gpClose("Ellipse", gpLevel))
		GPShape.GPKind.GP_RECT:
			# A rectangle closes, so it is a polygon: first point repeated at the end (§4.4).
			# 矩形是闭合的，故为多边形：首点在末尾重复一次（§4.4）。
			gpOut.append_array(_gpPointElementLines("Polygon", gpPts, true, gpColor, gpLevel))
		GPShape.GPKind.GP_ARC:
			# DEXPI has no arc primitive in the set the spec lists (PolyLine/Line/Ellipse/
			# Polygon/Text), so an arc degrades to its sampled polyline. Recorded, not invented.
			# 规范列出的图元集合（PolyLine/Line/Ellipse/Polygon/Text）中没有弧线，
			# 故弧线降级为其采样折线。这是**记录**，不是臆造。
			gpOut.append_array(_gpPointElementLines("PolyLine", gpPts, false, gpColor, gpLevel))
		GPShape.GPKind.GP_LINE:
			if gpPts.size() == 2:
				gpOut.append_array(_gpPointElementLines("Line", gpPts, false, gpColor, gpLevel))
			else:
				gpOut.append_array(_gpPointElementLines("PolyLine", gpPts, gpClosed, gpColor, gpLevel))
		_:
			if gpClosed:
				gpOut.append_array(_gpPointElementLines("Polygon", gpPts, true, gpColor, gpLevel))
			else:
				gpOut.append_array(_gpPointElementLines("PolyLine", gpPts, false, gpColor, gpLevel))
	return gpOut


static func _gpPointElementLines(gpName: String, gpPts: Array, gpClosed: bool,
		gpColor: Color, gpLevel: int) -> Array[String]:
	# A closed polygon repeats its first point (§4.4), which is how the receiver knows to close
	# it rather than draw an open hairline.
	# 闭合多边形重复其首点（§4.4）—— 接收方据此知道要闭合它，而不是画一条开口的细线。
	var gpCount: int = gpPts.size() + (1 if gpClosed else 0)
	var gpOut: Array[String] = []
	gpOut.append(GPXmlText.gpOpen(gpName,
		GPXmlText.gpAttr("NumPoints", str(gpCount)), gpLevel))
	gpOut.append_array(_gpPresentationLines(gpColor, gpLevel + 1))
	var gpIndex: int = 0
	for gpP in gpPts:
		var gpV: Vector2 = gpP as Vector2
		gpOut.append(GPXmlText.gpSelf("Coordinate", GPXmlText.gpAttrs([
			GPXmlText.gpAttr("X", GPXmlText.gpNum(gpV.x)),
			GPXmlText.gpAttr("Y", GPXmlText.gpNum(GPDexpiMapping.gpFlipY(gpV.y))),
		]), gpLevel + 1))
		gpIndex += 1
	if gpClosed and not gpPts.is_empty():
		var gpFirst: Vector2 = gpPts[0] as Vector2
		gpOut.append(GPXmlText.gpSelf("Coordinate", GPXmlText.gpAttrs([
			GPXmlText.gpAttr("X", GPXmlText.gpNum(gpFirst.x)),
			GPXmlText.gpAttr("Y", GPXmlText.gpNum(GPDexpiMapping.gpFlipY(gpFirst.y))),
		]), gpLevel + 1))
	gpOut.append(GPXmlText.gpClose(gpName, gpLevel))
	return gpOut


# <Presentation> carries line weight and the NORMALISED colour (§4.4 / risk 3).
# <Presentation> 承载线宽与**归一化**颜色（§4.4 / 风险 3）。
# ASSUMPTION: GPShape stores no line weight, so a CAD thin-line default is used. Flagged.
# 假设：GPShape 不存线宽，故采用 CAD 细线默认值。已标记待确认。
static func _gpPresentationLines(gpColor: Color, gpLevel: int) -> Array[String]:
	var gpRgb: Array = GPDexpiMapping.gpNormRgb(gpColor)
	return [GPXmlText.gpSelf("Presentation", GPXmlText.gpAttrs([
		GPXmlText.gpAttr("LineType", "0"),
		GPXmlText.gpAttr("LineWeight", "0.35"),
		GPXmlText.gpAttr("R", GPXmlText.gpNum(float(gpRgb[0]))),
		GPXmlText.gpAttr("G", GPXmlText.gpNum(float(gpRgb[1]))),
		GPXmlText.gpAttr("B", GPXmlText.gpNum(float(gpRgb[2]))),
	]), gpLevel)]


# ============================ attributes ============================

# One <GenericAttribute/>. A missing value OMITS the Value attribute (§6.5 risk 2): writing
# Value="" would tell the receiver "known to be empty" instead of "unknown".
# 一个 <GenericAttribute/>。值缺失时**省略** Value 属性（§6.5 风险 2）：
# 写 Value="" 会告诉接收方「已知为空」，而不是「未知」。
static func _gpGenericAttribute(gpName: String, gpUri: String, gpValue: Variant,
		gpFormat: String, gpUnits: String, gpUnitsUri: String, gpLanguage: String,
		gpLevel: int) -> String:
	var gpText: String = _gpValueText(gpValue, gpFormat)
	return GPXmlText.gpSelf("GenericAttribute", GPXmlText.gpAttrs([
		GPXmlText.gpAttr("Name", gpName),
		GPXmlText.gpAttr("AttributeURI", gpUri),
		GPXmlText.gpAttr("Value", gpText),
		GPXmlText.gpAttr("Format", gpFormat),
		GPXmlText.gpAttr("Units", gpUnits),
		GPXmlText.gpAttr("UnitsURI", gpUnitsUri),
		GPXmlText.gpAttr("Language", gpLanguage),
	]), gpLevel)


# Project one G-PID property. Internal (layout) keys are dropped on purpose (§6.5 risk 8).
# 投影一个 G-PID 属性。internal（布局）键被**刻意**丢弃（§6.5 风险 8）。
static func _gpPropertyLines(gpKey: String, gpValue: Variant, gpLevel: int) -> Array[String]:
	if GPDexpiMapping.gpIsInternal(gpKey):
		return []
	var gpRow: Dictionary = GPDexpiMapping.gpAttributeFor(gpKey)
	return [_gpGenericAttribute(
		str(gpRow.get("name", "")),
		str(gpRow.get("uri", "")),
		gpValue,
		str(gpRow.get("format", "string")),
		str(gpRow.get("units", "")),
		str(gpRow.get("units_uri", "")),
		"",
		gpLevel)]


# Wrap attribute lines in a <GenericAttributes Set="…"> container.
# 把属性行包进 <GenericAttributes Set="…"> 容器。
# WHY THE Number ATTRIBUTE / 为何需要 Number 属性：it states how many children the container
# has. Omitting it leaves a container the receiver cannot cheaply validate.
# 它声明容器有多少子元素。省略会让接收方无法低成本校验。
# WHY NO AT ALL WHEN EMPTY / 为何为空时不写容器: an empty <GenericAttributes/> is noise, and
# two containers of the same Set under one parent is a structural violation (risk 9).
# 空的 <GenericAttributes/> 只是噪音，而同一父元素下两个同 Set 的容器属于结构违规（风险 9）。
static func _gpGenericAttributesBlock(gpLines: Array[String], gpLevel: int,
		gpSet: String) -> Array[String]:
	if gpLines.is_empty():
		return []
	var gpOut: Array[String] = []
	gpOut.append(GPXmlText.gpOpen("GenericAttributes", GPXmlText.gpAttrs([
		GPXmlText.gpAttr("Number", str(gpLines.size())),
		GPXmlText.gpAttr("Set", gpSet),
	]), gpLevel))
	for gpLine in gpLines:
		gpOut.append(gpLine)
	gpOut.append(GPXmlText.gpClose("GenericAttributes", gpLevel))
	return gpOut


# Render a Variant for XML. Empty string and null both mean "unknown" here, so both omit Value.
# 把 Variant 渲染为 XML。此处空串与 null 同义「未知」，故两者都省略 Value。
static func _gpValueText(gpValue: Variant, gpFormat: String) -> String:
	if gpValue == null:
		return ""
	if gpValue is bool:
		return "true" if bool(gpValue) else "false"
	if gpValue is int:
		return str(int(gpValue))
	if gpValue is float:
		if gpFormat == "integer":
			return str(int(gpValue))
		return GPXmlText.gpNum(float(gpValue))
	var gpText: String = str(gpValue)
	if gpText.strip_edges().is_empty():
		return ""
	return gpText


# ============================ file output ============================

# Write the intermediate structure to gpPath through the shared atomic writer.
# 经共用的原子写出器把中间结构写到 gpPath。
static func gpExportFile(gpMid: Dictionary, gpPath: String) -> GPIOResult:
	if gpPath.is_empty():
		return GPIOResult.gpFailure("io.write_failed", "status.export_fail", gpPath)
	var gpText: String = gpWriteXml(gpMid)
	if gpText.is_empty():
		return GPIOResult.gpFailure("export.nothing", "status.export_empty", gpPath)
	# Verify BEFORE writing: a document that cannot be re-parsed must never reach disk.
	# 写入**之前**校验：无法重新解析的文档绝不能落到磁盘上。
	if not gpIsWellFormed(gpText):
		return GPIOResult.gpFailure("export.serialize_failed", "status.export_fail", gpPath)
	var gpWrite: GPIOResult = GPAtomicFile.gpWriteAtomic(gpPath, gpText)
	if not gpWrite.gpIsOk():
		return GPIOResult.gpFailure("io.write_failed", "status.export_fail", gpPath)
	return GPIOResult.gpSuccess("status.exported", gpPath)


# Is gpText well-formed XML? The single place this is answered, so the exporter's pre-write
# check and the tests' acceptance check can never disagree.
# gpText 是否为良构 XML？这是该问题的**唯一**回答处，
# 使导出器的写前校验与测试的验收校验不可能给出不同结论。
# NOTE: Godot has no XMLDocument class; XMLParser is the built-in reader, and reaching
# ERR_FILE_EOF means the whole document parsed cleanly.
# 注意：Godot 没有 XMLDocument 类；XMLParser 是内置读取器，读到 ERR_FILE_EOF 即表示整篇解析干净。
static func gpIsWellFormed(gpText: String) -> bool:
	if gpText.is_empty():
		return false
	var gpParser: XMLParser = XMLParser.new()
	var gpOpened: int = gpParser.open_buffer(gpText.to_utf8_buffer())
	if gpOpened != OK:
		return false
	while true:
		var gpRead: int = gpParser.read()
		if gpRead == ERR_FILE_EOF:
			return true
		if gpRead != OK:
			return false
	return false


# Convenience pipeline: preflight -> project -> serialise -> write.
# 便利流程：预检 -> 投影 -> 序列化 -> 落盘。
# Returns GPIOResult; on refusal the gpPayload carries the GPImportReport so the UI can show
# WHY the export was refused instead of a bare failure.
# 返回 GPIOResult；被拒时 gpPayload 携带 GPImportReport，
# 使界面能显示「为何被拒」而非一个裸失败。
static func gpExportSheet(gpGraph: GPPIDGraph, gpSheet: GPSheet, gpPath: String) -> GPIOResult:
	var gpReport: GPImportReport = gpPreflight(gpGraph, gpSheet)
	if gpReport.gpHasErrors():
		return GPIOResult.gpFailure("dexpi.preflight_failed", "status.export_fail",
			gpReport.gpSummary())
	var gpMid: Dictionary = gpFromGraph(gpGraph, gpSheet)
	var gpResult: GPIOResult = gpExportFile(gpMid, gpPath)
	if gpResult.gpIsOk():
		# Payload shape matches GPProjectExport's, so the SAME status line works for every
		# format without the UI knowing which one ran: {nodes, edges, ...} plus the report.
		# 载荷形态与 GPProjectExport 的一致，
		# 故同一条状态栏逻辑对每种格式都成立，界面无需知道跑的是哪一种：
		# {nodes, edges, ...} 另加报告。
		gpResult.gpPayload = {
			"nodes": (gpMid.get(GP_KEY_EQUIPMENT, []) as Array).size(),
			"edges": (gpMid.get(GP_KEY_SEGMENTS, []) as Array).size(),
			"skipped": (gpMid.get(GP_KEY_SKIPPED, []) as Array).size(),
			"path": gpPath,
			"kind": "dexpi",
			"report": gpReport,
		}
	return gpResult
