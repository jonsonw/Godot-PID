class_name GPProjectExport
extends RefCounted

# Build and write the three export containers (ADR-2: one format, three `kind` values).
# 构建并写出三种导出容器（ADR-2：一种格式、三种 `kind` 取值）。
#   project -> sheets + library + config + tag_rules (the deliverable / 交付物)
#   library -> library only (symbol distribution / 图元库分发)
#   config   -> config + tag_rules (template reuse / 模板复用)
#
# EXPORT IS NOT SAVE-AS / 「导出」不是「另存为」：
# exporting never touches the in-memory graph and never reassigns gpCurrentPath. Save-as
# moves the user's working file; export produces a file FOR SOMEONE ELSE. Conflating them
# is how people end up editing an archived copy and losing the original.
# 导出从不改动内存中的图，也从不重新指定 gpCurrentPath。另存为移动用户的工作文件；
# 导出产出一个**给别人**的文件。把两者混同，正是人们最终编辑归档副本并丢失原件的原因。
# See 持久化实现方案 §8 (导出流程) / 见「持久化实现方案」§8。
# Coding rule: every variable must declare its type explicitly. / 编码规范：变量显式类型。

# Warn above this size: a fully embedded library can dwarf the drawing itself (E13).
# 超过此体积即预警：完整内嵌的图元库可能让图纸本身相形见绌（E13）。
const GP_SIZE_WARN_BYTES: int = 20 * 1024 * 1024


# Build the `project` container from a live graph.
# 从活动图构建 `project` 容器。
# The graph serialises to the v2 shape, then the SAME migration chain used on import lifts
# it to v3 — one code path, so an exported file is necessarily readable by the importer.
# 图先序列化为 v2 形态，再由与导入相同的迁移链升到 v3 —— 同一条代码路径，
# 故导出的文件必然能被导入方读取。
static func gpBuildProject(gpGraph: GPPIDGraph, gpDocId: String = "",
		gpConfig: Dictionary = {}) -> Dictionary:
	if gpGraph == null:
		return {}
	var gpOut: Dictionary = GPSchemaMigrate.gpMigrate(gpGraph.gpToDict())
	gpOut["kind"] = GPSchemaMigrate.GP_KIND_PROJECT
	if not gpDocId.is_empty():
		gpOut["doc_id"] = gpDocId
	if not gpConfig.is_empty():
		gpOut["config"] = GPSchemaMigrate._gpFillConfig(gpConfig)
	return gpOut


# Build the `library` container from user symbol packs (builtin symbols travel free:
# they are compiled into every build, so exporting them would only bloat the file).
# 从用户图元包构建 `library` 容器（内置图元无需携带：它们已编译进每个构建，
# 导出只会让文件膨胀）。
static func gpBuildLibrary(gpPacks: Array) -> Dictionary:
	var gpPacksOut: Array = []
	for gpPack in gpPacks:
		if gpPack is GPSymbolPack:
			gpPacksOut.append((gpPack as GPSymbolPack).gpToDict())
		elif gpPack is Dictionary:
			gpPacksOut.append((gpPack as Dictionary).duplicate(true))
	return {
		"format": GPSchemaMigrate.GP_FORMAT,
		"format_version": GPSchemaMigrate.GP_FORMAT_VERSION,
		"kind": GPSchemaMigrate.GP_KIND_LIBRARY,
		"generator": GPSchemaMigrate.gpGeneratorInfo(),
		"created_at": GPSchemaMigrate.gpNowIso(),
		"doc_id": GPIdGen.gpNewDocId(),
		"library": {"packs": gpPacksOut, "builtin_overrides": []},
	}


# Build the `config` container: drawing settings + numbering rules, no geometry.
# 构建 `config` 容器：图纸设置 + 编号规则，不含几何。
static func gpBuildConfig(gpConfig: Dictionary, gpTagRules: Variant = null) -> Dictionary:
	var gpOut: Dictionary = {
		"format": GPSchemaMigrate.GP_FORMAT,
		"format_version": GPSchemaMigrate.GP_FORMAT_VERSION,
		"kind": GPSchemaMigrate.GP_KIND_CONFIG,
		"generator": GPSchemaMigrate.gpGeneratorInfo(),
		"created_at": GPSchemaMigrate.gpNowIso(),
		"doc_id": GPIdGen.gpNewDocId(),
		"config": GPSchemaMigrate._gpFillConfig(gpConfig),
	}
	if gpTagRules != null and gpTagRules is GPProjectTagRules:
		gpOut["tag_rules"] = (gpTagRules as GPProjectTagRules).gpToDict()
	elif gpTagRules is Dictionary:
		gpOut["tag_rules"] = (gpTagRules as Dictionary).duplicate(true)
	return gpOut


# Pick a builder by kind. Unknown kind -> empty dict (the caller reports it).
# 按 kind 选择构建器。未知 kind -> 空字典（由调用方报告）。
static func gpBuild(gpKind: String, gpGraph: GPPIDGraph, gpPacks: Array,
		gpConfig: Dictionary = {}, gpDocId: String = "") -> Dictionary:
	match gpKind:
		GPSchemaMigrate.GP_KIND_LIBRARY:
			return gpBuildLibrary(gpPacks)
		GPSchemaMigrate.GP_KIND_CONFIG:
			return gpBuildConfig(gpConfig,
				gpGraph.gpTagRules if gpGraph != null else null)
		_:
			return gpBuildProject(gpGraph, gpDocId, gpConfig)


# What is inside a container: node/edge/shape/pack counts and the serialised byte size.
# 容器里有什么：节点/边/图形/包计数与序列化后的字节数。
# Size is measured on the REAL text (not an estimate) because the size warning is only
# useful if it matches what lands on disk.
# 体积在**真实文本**上度量（而非估算），因为体积预警只有在与落盘结果一致时才有意义。
static func gpStatsOf(gpContainer: Dictionary) -> Dictionary:
	var gpSheets: Array = []
	if gpContainer.get("sheets") is Array:
		gpSheets = gpContainer.get("sheets") as Array
	var gpNodes: int = 0
	var gpEdges: int = 0
	var gpShapes: int = 0
	for gpS in gpSheets:
		var gpSheet: Dictionary = gpS as Dictionary
		gpNodes += (gpSheet.get("nodes", []) as Array).size()
		gpEdges += (gpSheet.get("edges", []) as Array).size()
		gpShapes += (gpSheet.get("shapes", []) as Array).size()
	var gpPacks: int = 0
	if gpContainer.get("library") is Dictionary:
		gpPacks = ((gpContainer.get("library") as Dictionary).get("packs", []) as Array).size()
	return {
		"nodes": gpNodes,
		"edges": gpEdges,
		"shapes": gpShapes,
		"packs": gpPacks,
		"sheets": gpSheets.size(),
		"bytes": gpTextOf(gpContainer).to_utf8_buffer().size(),
	}


# Serialize -> sanitize -> stringify. Sanitizing is mandatory: JSON has no NaN/Infinity,
# and one stray NaN would make the whole exported archive unparseable (E14).
# 序列化 -> 净化 -> stringify。净化是强制的：JSON 没有 NaN/Infinity，
# 一个游离的 NaN 就会让整个导出存档无法解析（E14）。
static func gpTextOf(gpContainer: Dictionary) -> String:
	var gpSafe: Variant = GPSchemaMigrate.gpSanitizeJson(gpContainer)
	if gpSafe is Dictionary:
		return JSON.stringify(gpSafe as Dictionary, "", true)
	return JSON.stringify(gpContainer, "", true)


# Full export pipeline: build -> sanitize -> serialize -> verify -> atomic write.
# 完整导出流程：组包 -> 净化 -> 序列化 -> 校验 -> 原子写。
# Returns GPIOResult whose gpPayload is the stats dict on success.
# 返回 GPIOResult，成功时 gpPayload 为统计字典。
static func gpExportToFile(gpKind: String, gpPath: String, gpGraph: GPPIDGraph,
		gpPacks: Array, gpConfig: Dictionary = {}, gpDocId: String = "") -> GPIOResult:
	if gpPath.is_empty():
		return GPIOResult.gpFailure("io.write_failed", "status.save_fail", gpPath)
	var gpContainer: Dictionary = gpBuild(gpKind, gpGraph, gpPacks, gpConfig, gpDocId)
	if gpContainer.is_empty():
		return GPIOResult.gpFailure("export.nothing", "status.export_empty", gpPath)
	var gpText: String = gpTextOf(gpContainer)
	# Verify BEFORE writing: a payload that cannot be parsed back must never reach disk.
	# 写入**之前**校验：无法解析回来的载荷绝不能落到磁盘上。
	var gpCheck: Variant = JSON.parse_string(gpText)
	if gpCheck == null or not (gpCheck is Dictionary):
		return GPIOResult.gpFailure("export.serialize_failed", "status.export_fail", gpPath)
	var gpWrite: GPIOResult = GPAtomicFile.gpWriteAtomic(gpPath, gpText)
	if not gpWrite.gpIsOk():
		return GPIOResult.gpFailure("io.write_failed", "status.export_fail", gpPath)
	var gpStats: Dictionary = gpStatsOf(gpContainer)
	gpStats["path"] = gpPath
	gpStats["kind"] = gpKind
	gpStats["oversized"] = int(gpStats.get("bytes", 0)) > GP_SIZE_WARN_BYTES
	return GPIOResult.gpSuccessWith(gpStats, "status.exported", gpPath)
