class_name GPSchemaMigrate
extends RefCounted

# Archive format migration + JSON sanitizing for *.pid.json.
# *.pid.json 存档的格式迁移与 JSON 净化。
# Every transformation here happens on PLAIN DICTIONARIES, never on the model objects —
# that is what keeps the hexagon boundary intact (core owns the model, io owns the bytes).
# 这里的所有变换都发生在**普通字典**上，从不触碰模型对象 —— 这正是保持六边形边界完整的
# 原因（core 拥有模型，io 拥有字节）。
#
# Three shapes must all load, and all converge on v3:
# 三种形态都必须能载入，并统一收敛到 v3：
#   v1  {meta, nodes:[{id,type,label,pos,attr_values}], edges:[{id,from,to}]}
#   v2  {meta, nodes:[{instance_id,symbol_id,uid,props}], tag_rules, user_symbol_packs}
#   v3  {format, format_version, kind, sheets:[...], library:{...}, config:{...}}
# Plus the HISTORIC multi-document shape found in docs/samples/pani_detox.pid.json:
# 以及 docs/samples/pani_detox.pid.json 中的历史多文档形态：
#   {meta, documents:[{id,title,graph:{meta,nodes,edges}}], cross_links:[...]}
# See 持久化实现方案 §7 (版本演进与迁移链) / 见「持久化实现方案」§7。
# Coding rule: every variable must declare its type explicitly. / 编码规范：变量显式类型。

# File format marker. A file without it is a pre-v3 archive.
# 文件格式标记。缺少它的文件即为 v3 之前的存档。
const GP_FORMAT: String = "g-pid"

# Current on-disk format version. / 当前磁盘格式版本。
const GP_FORMAT_VERSION: int = 3

# Highest format_version this build can open. Anything above is refused for writing
# (E6) so a newer file is never silently downgraded by an older build.
# 本构建可打开的最高 format_version。高于它的文件拒绝写入型打开（E6），
# 使新版本文件永不被旧版本静默降级。
const GP_MAX_SUPPORTED: int = 3

# Recursion guard for deeply nested (or hand-crafted malicious) JSON.
# 深度嵌套（或手工构造的恶意）JSON 的递归保护。
const GP_MAX_DEPTH: int = 32

# Where ±Infinity is clamped. Large enough to be off-screen, small enough to stay finite
# in every downstream float operation.
# ±Infinity 的夹取目标。大到在屏幕外，小到在任何下游浮点运算中仍为有限值。
const GP_INF_CLAMP: float = 1.0e9

# Container kinds (ADR-2: one container, three kinds, not three extensions).
# 容器种类（ADR-2：单一容器、三种 kind，而非三种扩展名）。
const GP_KIND_PROJECT: String = "project"
const GP_KIND_LIBRARY: String = "library"
const GP_KIND_CONFIG: String = "config"

# Default sheet id / name for a single-sheet archive.
# 单图纸存档的默认图纸 id / 名称。
const GP_FIRST_SHEET_ID: String = "sheet-1"

# ---------------------------------------------------------------------------
# Version detection / 版本识别
# ---------------------------------------------------------------------------

# Which on-disk version gpData looks like: 1, 2 or 3.
# gpData 看起来属于哪个磁盘版本：1、2 或 3。
static func gpDetectVersion(gpData: Dictionary) -> int:
	if str(gpData.get("format", "")) == GP_FORMAT:
		return int(gpData.get("format_version", 1))
	if _gpHasV2Features(gpData):
		return 2
	return 1


# True when the dict carries at least one M8+ key, i.e. it is not a plain v1 archive.
# 当字典至少带有一个 M8+ 的键时为真，即它不是纯粹的 v1 存档。
static func _gpHasV2Features(gpData: Dictionary) -> bool:
	if gpData.has("tag_rules") or gpData.has("uid") or gpData.has("sheets"):
		return true
	if gpData.has("library") or gpData.has("config"):
		return true
	for gpSheet in _gpRawSheetList(gpData):
		for gpN in _gpArrayOfDicts((gpSheet as Dictionary).get("nodes", [])):
			if (gpN as Dictionary).has("uid") or (gpN as Dictionary).has("props"):
				return true
	return false


# True when gpData is a G-PID archive (any version). Used to reject foreign JSON (E7).
# gpData 是否为 G-PID 存档（任意版本）。用于拒绝外来 JSON（E7）。
static func gpIsGPidArchive(gpData: Dictionary) -> bool:
	if str(gpData.get("format", "")) == GP_FORMAT:
		return true
	if gpData.has("nodes") or gpData.has("edges") or gpData.has("sheets"):
		return true
	if gpData.has("documents") or gpData.has("user_symbol_packs"):
		return true
	if gpData.has("meta") and (gpData.get("meta") is Dictionary):
		return true
	return false


# ---------------------------------------------------------------------------
# Sanitize / 净化
# ---------------------------------------------------------------------------

# Make gpValue safe for JSON.stringify. JSON has no NaN / Infinity: Godot writes those as
# bare literals and the resulting file cannot be parsed back — the whole archive is lost.
# This is the LAST line of defence; the model already skips the ±INF offset sentinel.
# 使 gpValue 对 JSON.stringify 安全。JSON 没有 NaN / Infinity：Godot 会把它们写成裸字面量，
# 生成的文件无法再解析回来 —— 整个存档就此丢失。这是最后一道防线；模型层已跳过 ±INF 偏移哨兵。
# Returns a NEW value; the input is never mutated. / 返回新值；入参从不修改。
static func gpSanitizeJson(gpValue: Variant, gpDepth: int = 0) -> Variant:
	if gpDepth > GP_MAX_DEPTH:
		return null
	var gpT: int = typeof(gpValue)
	if gpT == TYPE_FLOAT:
		return _gpFiniteFloat(float(gpValue))
	if gpT == TYPE_INT or gpT == TYPE_BOOL or gpT == TYPE_STRING:
		return gpValue
	if gpT == TYPE_VECTOR2:
		var gpV: Vector2 = gpValue as Vector2
		return [_gpFiniteFloat(gpV.x), _gpFiniteFloat(gpV.y)]
	if gpT == TYPE_ARRAY:
		var gpOut: Array = []
		for gpItem in (gpValue as Array):
			gpOut.append(gpSanitizeJson(gpItem, gpDepth + 1))
		return gpOut
	if gpT == TYPE_DICTIONARY:
		var gpD: Dictionary = gpValue as Dictionary
		var gpOutD: Dictionary = {}
		for gpKey in gpD.keys():
			# JSON object keys must be strings. / JSON 对象键必须是字符串。
			gpOutD[str(gpKey)] = gpSanitizeJson(gpD[gpKey], gpDepth + 1)
		return gpOutD
	# Anything else (Object, Callable, RID, ...) has no JSON representation.
	# 其他任何类型（Object、Callable、RID 等）都没有 JSON 表示。
	return null


# Clamp a float into the JSON-representable range. / 把浮点夹取进 JSON 可表示范围。
static func _gpFiniteFloat(gpV: float) -> float:
	if is_nan(gpV):
		return 0.0
	if is_inf(gpV):
		return GP_INF_CLAMP if gpV > 0.0 else -GP_INF_CLAMP
	return gpV


# ---------------------------------------------------------------------------
# Migration / 迁移
# ---------------------------------------------------------------------------

# Bring any archive dict up to the v3 canonical container. IDEMPOTENT by construction:
# migrate(migrate(d)) == migrate(d), because every step only fills what is missing or
# normalises a legacy key into its modern name (and the legacy key is then gone).
# 把任意存档字典升格为 v3 规范容器。构造上**幂等**：migrate(migrate(d)) == migrate(d)，
# 因为每一步只填补缺失项，或把旧键归一为现代键名（旧键随后即消失）。
static func gpMigrate(gpData: Dictionary) -> Dictionary:
	var gpOut: Dictionary = (gpData as Dictionary).duplicate(true)
	var gpVersion: int = gpDetectVersion(gpOut)
	# The document id must exist before uid back-fill, and must be stable across runs so
	# two migrations of the same file land on the same uid set.
	# 文档 id 必须在 uid 回填之前存在，且必须跨运行稳定，使同一文件的两次迁移落在一组相同 uid 上。
	var gpDocId: String = str(gpOut.get("doc_id", ""))
	if gpDocId.is_empty():
		gpDocId = str((_gpMetaOf(gpOut)).get("doc_id", ""))
	if gpDocId.is_empty():
		gpDocId = GPIdGen.gpNewDocId()
	gpOut["doc_id"] = gpDocId

	# Tracks uids ALREADY ASSIGNED during this pass, so back-fill never collides. It must
	# start EMPTY: pre-seeding it with the archive's own uids makes every pre-existing uid
	# look like a collision, so all of them get re-assigned — rewriting the user's
	# identities AND breaking idempotence (migrate(migrate(d)) != migrate(d)).
	# 记录本次遍历中**已分配**的 uid，使回填永不冲突。它必须以**空**开始：
	# 若用存档自身的 uid 预填，会让每个既有 uid 都看似冲突而被全部重新分配 ——
	# 既改写用户标识，又破坏幂等（migrate(migrate(d)) != migrate(d)）。
	var gpUsedUids: Dictionary = {}

	# --- v1 -> v2: key-name normalisation + uid back-fill -------------------
	# --- v1 -> v2：键名归一 + uid 回填 --------------------------------------
	var gpSheets: Array = _gpRawSheetList(gpOut)
	var gpSheetsOut: Array = []
	var gpIdx: int = 0
	for gpSheetRaw in gpSheets:
		var gpSheet: Dictionary = (gpSheetRaw as Dictionary).duplicate(true)
		var gpNodesIn: Array = _gpArrayOfDicts(gpSheet.get("nodes", []))
		var gpNodesOut: Array = []
		for gpN in gpNodesIn:
			gpNodesOut.append(_gpNormalizeNode(gpN as Dictionary, gpDocId, gpUsedUids))
		var gpEdgesIn: Array = _gpArrayOfDicts(gpSheet.get("edges", []))
		var gpEdgesOut: Array = []
		for gpE in gpEdgesIn:
			gpEdgesOut.append(_gpNormalizeEdge(gpE as Dictionary))
		var gpShapesIn: Array = _gpArrayOfDicts(gpSheet.get("shapes", []))
		gpSheet["id"] = str(gpSheet.get("id", _gpSheetIdFor(gpIdx)))
		if not gpSheet.has("name") or str(gpSheet.get("name", "")).is_empty():
			gpSheet["name"] = _gpSheetNameFor(gpIdx, gpOut)
		gpSheet["index"] = gpIdx
		gpSheet["nodes"] = gpNodesOut
		gpSheet["edges"] = gpEdgesOut
		gpSheet["shapes"] = gpShapesIn
		gpSheetsOut.append(gpSheet)
		gpIdx += 1
	if gpSheetsOut.is_empty():
		gpSheetsOut.append(_gpEmptySheet(gpOut))

	# --- v2 -> v3: sheets[] + library + config ------------------------------
	# --- v2 -> v3：sheets[] + library + config ------------------------------
	gpOut["sheets"] = gpSheetsOut
	# Drop the legacy carry-overs so the v3 container has exactly one place for data.
	# 丢弃旧版遗留键，使 v3 容器只有一处存放数据。
	gpOut.erase("nodes")
	gpOut.erase("edges")
	gpOut.erase("shapes")
	gpOut.erase("documents")

	var gpPacksOut: Array = []
	var gpOldPacks: Array = _gpArrayOfDicts(gpOut.get("user_symbol_packs", []))
	for gpP in gpOldPacks:
		gpPacksOut.append((gpP as Dictionary).duplicate(true))
	var gpLibrary: Dictionary = {}
	if gpOut.get("library") is Dictionary:
		gpLibrary = (gpOut.get("library") as Dictionary).duplicate(true)
	var gpExistingPacks: Array = _gpArrayOfDicts(gpLibrary.get("packs", []))
	if gpPacksOut.is_empty():
		gpPacksOut = gpExistingPacks
	if not gpLibrary.has("builtin_overrides"):
		gpLibrary["builtin_overrides"] = []
	gpLibrary["packs"] = gpPacksOut
	gpOut["library"] = gpLibrary
	gpOut.erase("user_symbol_packs")

	if not (gpOut.get("config") is Dictionary):
		gpOut["config"] = gpDefaultConfig()
	else:
		gpOut["config"] = _gpFillConfig((gpOut.get("config") as Dictionary))

	# --- v3 header -----------------------------------------------------------
	var gpMeta: Dictionary = _gpMetaOf(gpOut).duplicate(true)
	gpMeta["version"] = str(gpMeta.get("version", "1.1"))
	if not gpMeta.has("sheets"):
		gpMeta["sheets"] = gpSheetsOut.size()
	else:
		gpMeta["sheets"] = gpSheetsOut.size()
	gpOut["meta"] = gpMeta
	gpOut["format"] = GP_FORMAT
	gpOut["format_version"] = GP_FORMAT_VERSION
	gpOut["kind"] = str(gpOut.get("kind", GP_KIND_PROJECT))
	if not (gpOut.get("generator") is Dictionary):
		gpOut["generator"] = gpGeneratorInfo()
	if str(gpOut.get("created_at", "")).is_empty():
		gpOut["created_at"] = gpNowIso()
	return gpOut


# Flatten a v3 container into the shape GPPIDGraph.gpFromDict() understands.
# 把 v3 容器展平为 GPPIDGraph.gpFromDict() 能理解的形状。
# The full `sheets` array is kept in the output so multi-sheet work (P2) can consume it
# without re-reading the file; gpFromDict() ignores unknown keys.
# 输出中保留完整 `sheets` 数组，使多图纸工作（P2）无需重读文件即可消费；
# gpFromDict() 会忽略未知键。
static func gpToGraphDict(gpData: Dictionary, gpSheetIndex: int = 0) -> Dictionary:
	var gpV3: Dictionary = gpMigrate(gpData)
	var gpSheets: Array = _gpArrayOfDicts(gpV3.get("sheets", []))
	var gpPick: Dictionary = {}
	if gpSheets.size() > 0:
		var gpClamped: int = clampi(gpSheetIndex, 0, gpSheets.size() - 1)
		gpPick = (gpSheets[gpClamped] as Dictionary).duplicate(true)
	var gpOut: Dictionary = {
		"meta": (gpV3.get("meta") as Dictionary).duplicate(true),
		"nodes": _gpArrayOfDicts(gpPick.get("nodes", [])).duplicate(true),
		"edges": _gpArrayOfDicts(gpPick.get("edges", [])).duplicate(true),
		"shapes": _gpArrayOfDicts(gpPick.get("shapes", [])).duplicate(true),
		"user_symbol_packs": _gpArrayOfDicts(
			(gpV3.get("library") as Dictionary).get("packs", [])).duplicate(true),
		# Carried through for P2; harmless to gpFromDict(). / 为 P2 透传；对 gpFromDict() 无害。
		"sheets": gpSheets,
		"doc_id": str(gpV3.get("doc_id", "")),
		"config": (gpV3.get("config") as Dictionary).duplicate(true),
	}
	if gpV3.has("tag_rules"):
		gpOut["tag_rules"] = (gpV3.get("tag_rules") as Dictionary).duplicate(true)
	if gpV3.has("cross_links"):
		gpOut["cross_links"] = _gpArrayOfDicts(gpV3.get("cross_links", [])).duplicate(true)
	return gpOut


# How many sheets a (possibly legacy) archive holds. / 一个（可能是旧版的）存档含多少图纸。
static func gpSheetCount(gpData: Dictionary) -> int:
	var gpV3: Dictionary = gpMigrate(gpData)
	return _gpArrayOfDicts(gpV3.get("sheets", [])).size()


# ---------------------------------------------------------------------------
# Field normalisation / 字段归一
# ---------------------------------------------------------------------------

# One node dict -> modern key names, with a uid guaranteed to be non-empty and unique.
# 单个节点字典 -> 现代键名，并保证 uid 非空且唯一。
static func _gpNormalizeNode(gpN: Dictionary, gpDocId: String, gpUsedUids: Dictionary) -> Dictionary:
	var gpOut: Dictionary = (gpN as Dictionary).duplicate(true)
	var gpInstanceId: String = str(gpOut.get("instance_id", gpOut.get("id", "")))
	if gpInstanceId.is_empty():
		gpInstanceId = "n" + str(gpUsedUids.size() + 1)
	var gpTag: String = str(gpOut.get("tag", gpOut.get("label", "")))
	# M-v1b: a v1 "label" that is NOT tag-shaped was really a NAME (there was no separate
	# field back then), so seed names.zh_CN from it instead of dropping the text.
	# M-v1b：v1 里不像位号的 "label" 其实是**名称**（当时没有独立字段），
	# 故用它初始化 names.zh_CN，而不是把文本丢掉。
	var gpNames: Dictionary = {}
	if gpOut.get("names") is Dictionary:
		gpNames = (gpOut.get("names") as Dictionary).duplicate(true)
	if gpNames.is_empty() and not gpTag.is_empty() and not gpLooksLikeTag(gpTag) \
			and not gpOut.has("tag"):
		gpNames["zh_CN"] = gpTag
	# M-v1c: uid back-fill keeps every edge reference resolvable.
	# M-v1c：uid 回填使每条边的引用都可解析。
	var gpUid: String = str(gpOut.get("uid", ""))
	if gpUid.is_empty() or gpUsedUids.has(gpUid):
		gpUid = gpDocId + "-" + gpInstanceId
		var gpSuffix: int = 2
		while gpUsedUids.has(gpUid):
			gpUid = gpDocId + "-" + gpInstanceId + "-" + str(gpSuffix)
			gpSuffix += 1
	gpUsedUids[gpUid] = true
	var gpPos: Array = gpOut.get("position", gpOut.get("pos", [0.0, 0.0]))
	if not (gpPos is Array) or (gpPos as Array).size() < 2:
		gpPos = [0.0, 0.0]
	var gpProps: Variant = gpOut.get("props",
		gpOut.get("attr_values", gpOut.get("attrs", {})))
	# Read the offset BEFORE gpOut is reassigned below — the new dict simply has no such
	# key yet, so reading it afterwards would silently drop every custom offset.
	# 在下面重赋值 gpOut **之前**读取偏移 —— 新字典此时还没有这个键，
	# 事后读取会静默丢掉全部自定义偏移。
	var gpOffRaw: Variant = gpOut.get("label_offset", [])
	gpOut = {
		"uid": gpUid,
		"instance_id": gpInstanceId,
		"symbol_id": str(gpOut.get("symbol_id", gpOut.get("type", ""))),
		"tag": gpTag,
		"names": gpNames,
		"position": [float((gpPos as Array)[0]), float((gpPos as Array)[1])],
		"rotation_deg": float(gpOut.get("rotation_deg", 0.0)),
		"flipped": bool(gpOut.get("flipped", false)),
		"props": (gpProps as Dictionary).duplicate(true) if gpProps is Dictionary else {},
		"label_anchor": int(gpOut.get("label_anchor", -1)),
	}
	# The unset-offset sentinel (±INF) is not JSON-representable, so it is simply not
	# emitted — matching GPPIDNode.gpToDict().
	# 未设置偏移的哨兵（±INF）无法用 JSON 表示，故干脆不输出 —— 与 GPPIDNode.gpToDict() 一致。
	if gpOffRaw is Array and (gpOffRaw as Array).size() >= 2:
		gpOut["label_offset"] = [float((gpOffRaw as Array)[0]), float((gpOffRaw as Array)[1])]
	else:
		gpOut.erase("label_offset")
	return gpOut


# One edge dict -> modern key names, with node-to-node "from"/"to" lifted to refs.
# 单个边字典 -> 现代键名，并把节点到节点的 "from"/"to" 提升为引用。
static func _gpNormalizeEdge(gpE: Dictionary) -> Dictionary:
	var gpIn: Dictionary = gpE as Dictionary
	var gpFrom: Dictionary = {}
	if gpIn.get("from_ref") is Dictionary:
		gpFrom = (gpIn.get("from_ref") as Dictionary).duplicate(true)
	else:
		gpFrom = {"node_id": str(gpIn.get("from", "")), "port_id": ""}
	var gpTo: Dictionary = {}
	if gpIn.get("to_ref") is Dictionary:
		gpTo = (gpIn.get("to_ref") as Dictionary).duplicate(true)
	else:
		gpTo = {"node_id": str(gpIn.get("to", "")), "port_id": ""}
	var gpAttrs: Dictionary = {}
	if gpIn.get("attrs") is Dictionary:
		gpAttrs = (gpIn.get("attrs") as Dictionary).duplicate(true)
	var gpRouting: Array = []
	for gpP in _gpArrayOfDicts(gpIn.get("routing", [])):
		gpRouting.append(gpP)
	if not (gpIn.get("routing") is Array):
		gpRouting = []
	return {
		"instance_id": str(gpIn.get("instance_id", gpIn.get("id", ""))),
		"from_ref": gpFrom,
		"to_ref": gpTo,
		"kind": str(gpIn.get("kind", "PROCESS")),
		"signal_type": str(gpIn.get("signal_type", "")),
		"ortho": bool(gpIn.get("ortho", true)),
		"routing": gpRouting,
		"tag": str(gpIn.get("tag", "")),
		"attrs": gpAttrs,
	}


# Heuristic: does gpText look like a P&ID tag (P-1001, FV-101, PL-201) rather than a name?
# 启发式：gpText 看起来像位号（P-1001、FV-101、PL-201）而不是名称吗？
# Deliberately ASCII-only: any CJK character immediately means "this is a name".
# 刻意只认 ASCII：任何 CJK 字符立刻意味着「这是名称」。
static func gpLooksLikeTag(gpText: String) -> bool:
	var gpS: String = gpText.strip_edges()
	if gpS.is_empty() or gpS.length() > 24:
		return false
	var gpFirst: String = gpS.substr(0, 1)
	if gpFirst < "A" or gpFirst > "Z":
		return false
	var gpHasDigit: bool = false
	for gpCh in gpS:
		var gpC: String = gpCh
		if gpC >= "0" and gpC <= "9":
			gpHasDigit = true
			continue
		if (gpC >= "A" and gpC <= "Z") or gpC == "-" or gpC == "_" or gpC == "." or gpC == "/":
			continue
		return false
	return gpHasDigit


# ---------------------------------------------------------------------------
# Sheet helpers / 图纸辅助
# ---------------------------------------------------------------------------

# Raw sheet-ish list from ANY shape: v3 sheets[], historic documents[].graph, or the
# single-sheet top level. Always returns at least one entry.
# 从任意形态取出原始图纸列表：v3 的 sheets[]、历史的 documents[].graph，或单图纸的顶层。
# 恒返回至少一个条目。
static func _gpRawSheetList(gpData: Dictionary) -> Array:
	var gpOut: Array = []
	var gpSheets: Variant = gpData.get("sheets", null)
	if gpSheets is Array and (gpSheets as Array).size() > 0:
		for gpS in (gpSheets as Array):
			gpOut.append((gpS as Dictionary).duplicate(true))
		return gpOut
	# Historic multi-document shape: each document wraps its own graph one level deeper.
	# 历史多文档形态：每个 document 把自己的 graph 多包了一层。
	var gpDocs: Variant = gpData.get("documents", null)
	if gpDocs is Array and (gpDocs as Array).size() > 0:
		var gpI: int = 0
		for gpD in (gpDocs as Array):
			var gpDoc: Dictionary = gpD as Dictionary
			var gpGraph: Dictionary = gpDoc.get("graph", {}) if gpDoc.get("graph") is Dictionary else {}
			var gpSheet: Dictionary = {
				"id": str(gpDoc.get("id", _gpSheetIdFor(gpI))),
				"name": str(gpDoc.get("title", "")),
				"index": gpI,
				"nodes": gpGraph.get("nodes", []),
				"edges": gpGraph.get("edges", []),
				"shapes": gpGraph.get("shapes", []),
			}
			gpOut.append(gpSheet)
			gpI += 1
		return gpOut
	if gpData.has("nodes") or gpData.has("edges") or gpData.has("shapes"):
		gpOut.append({
			"id": GP_FIRST_SHEET_ID,
			"name": str((_gpMetaOf(gpData)).get("title", "")),
			"index": 0,
			"nodes": gpData.get("nodes", []),
			"edges": gpData.get("edges", []),
			"shapes": gpData.get("shapes", []),
		})
	return gpOut


# The meta dictionary, or {} when the container has none at all. A `config` or `library`
# export carries no meta, and `null as Dictionary` would crash on the next .get().
# meta 字典，容器根本没有时返回 {}。`config` / `library` 导出不含 meta，
# 而 `null as Dictionary` 会在紧接着的 .get() 上崩溃。
static func _gpMetaOf(gpData: Dictionary) -> Dictionary:
	if gpData.get("meta") is Dictionary:
		return gpData.get("meta") as Dictionary
	return {}


# A brand-new empty sheet, used when the archive carried no sheet data at all.
# 全新的空图纸，用于存档完全不含图纸数据的情形。
static func _gpEmptySheet(gpData: Dictionary) -> Dictionary:
	return {
		"id": GP_FIRST_SHEET_ID,
		"name": str((_gpMetaOf(gpData)).get("title", "")),
		"index": 0,
		"nodes": [],
		"edges": [],
		"shapes": [],
	}


static func _gpSheetIdFor(gpIndex: int) -> String:
	return "sheet-" + str(gpIndex + 1)


static func _gpSheetNameFor(gpIndex: int, gpData: Dictionary) -> String:
	if gpIndex == 0:
		var gpTitle: String = str((_gpMetaOf(gpData)).get("title", ""))
		if not gpTitle.is_empty():
			return gpTitle
	return "Sheet " + str(gpIndex + 1)


# Coerce an arbitrary Variant into an Array (of anything). Guards against a hand-edited
# JSON where "nodes" is an object or a scalar.
# 把任意 Variant 强制成 Array。防御手改 JSON 里 "nodes" 是对象或标量的情形。
static func _gpArrayOfDicts(gpValue: Variant) -> Array:
	if gpValue is Array:
		return (gpValue as Array).duplicate(true)
	return []


# ---------------------------------------------------------------------------
# Defaults / 默认值
# ---------------------------------------------------------------------------

# Factory default `config` section (M-v2c: filled in memory only, never written for an
# untouched file, so old archives stay byte-stable).
# 出厂默认 `config` 段（M-v2c：仅在内存中填充，未改动的文件不写盘，故旧存档保持字节稳定）。
static func gpDefaultConfig() -> Dictionary:
	return {
		"schema": 1,
		"sheet": {
			"size": "A1",
			"orientation": "landscape",
			"margin_mm": 10,
			"grid_mm": 5,
			"frame_visible": true,
		},
		"display": {"locale": "zh_CN", "ui_font_size": 14, "symbol_font_size": 12},
		"defaults": {"edge_kind": "PROCESS", "ortho": true, "snap_mm": 2.5},
	}


# Fill missing config sub-keys without disturbing what the user already set.
# 填补缺失的 config 子键，不动用户已设置的内容。
static func _gpFillConfig(gpIn: Dictionary) -> Dictionary:
	var gpDef: Dictionary = gpDefaultConfig()
	var gpOut: Dictionary = (gpIn as Dictionary).duplicate(true)
	for gpKey in gpDef.keys():
		if not gpOut.has(gpKey):
			# Not every default is a Dictionary ("schema" is an int). `int as Dictionary`
			# yields null, and null.duplicate() raises a runtime error that GDScript
			# SWALLOWS — the function then returns an empty dict and the config silently
			# vanishes. Copy by value kind instead.
			# 并非每个默认值都是字典（"schema" 是 int）。`int as Dictionary` 得到 null，
			# 而 null.duplicate() 会抛出**被 GDScript 静默吞掉**的运行时错误 ——
			# 函数随后返回空字典，config 就无声无息地消失了。故按值的类型复制。
			var gpVal: Variant = gpDef[gpKey]
			gpOut[gpKey] = (gpVal as Dictionary).duplicate(true) if gpVal is Dictionary else gpVal
			continue
		if gpOut[gpKey] is Dictionary and gpDef[gpKey] is Dictionary:
			var gpSub: Dictionary = (gpOut[gpKey] as Dictionary).duplicate(true)
			for gpSubKey in (gpDef[gpKey] as Dictionary).keys():
				if not gpSub.has(gpSubKey):
					gpSub[gpSubKey] = (gpDef[gpKey] as Dictionary)[gpSubKey]
			gpOut[gpKey] = gpSub
	return gpOut


# Who wrote this file. Lets a future build warn "made by a newer version" even when the
# format_version happens to still be supported.
# 本文件由谁写出。使将来的构建即便 format_version 仍被支持，也能警告「由更新版本生成」。
static func gpGeneratorInfo() -> Dictionary:
	# Read as Variant: the setting may be a String, an int, or absent entirely, and forcing
	# one type here is what makes the whole script fail to parse.
	# 以 Variant 读取：该设置可能是 String、int 或根本不存在，在此强指定类型正是
	# 整个脚本解析失败的原因。
	var gpRaw: Variant = ProjectSettings.get_setting("application/config/version", "")
	var gpVersion: String = "0.1.0"
	if gpRaw is String and str(gpRaw) != "":
		gpVersion = str(gpRaw)
	return {
		"app": "G-PID",
		"version": gpVersion,
		"platform": OS.get_name(),
	}


# Current UTC time as ISO-8601 with a Z suffix (E28: one timezone on disk, always).
# 当前 UTC 时间，ISO-8601 带 Z 后缀（E28：磁盘上永远只有一种时区）。
static func gpNowIso() -> String:
	return Time.get_datetime_string_from_system(true)
