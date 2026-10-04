class_name GPDexpiValidator
extends RefCounted

# L1 structural + L2 rule validation of an imported DEXPI structure, producing a
# GPImportReport (reused type — no new report class, §7.3).
# 对导入的 DEXPI 结构做 L1 结构校验 + L2 规则校验，产出 GPImportReport
# （**复用**既有类型 —— 不新建报告类，§7.3）。
#
# LEVELS / 级别（§7.3 四级分类）：
# fatal -> cannot form a usable model: abort, roll back, write nothing.
# error -> this object is unusable: skip it, keep the rest.
# warning -> usable but degraded or doubtful: import and flag it.
# info -> a note: record only.
# GPImportReport carries error/warning/info; a fatal finding is recorded as an error whose code
# starts with "fatal." so the caller can refuse on gpHasErrors() without a new vocabulary.
# GPImportReport 承载 error/warning/info；fatal 记为 code 以 "fatal." 开头的 error，
# 使调用方无需新词汇即可凭 gpHasErrors() 拒绝。
#
# ★ VALIDATION NEVER DISCARDS DATA / 校验**永不**丢弃数据（与既有导入管线同规）：
# every finding is a report entry. A questionable object is imported and FLAGGED, because
# losing a valve silently is worse than importing a slightly suspect one.
# 每条发现都是一个报告条目。有问题的对象被导入并**标记** ——
# 静默丢掉一个阀门，比导入一个略有疑问的阀门更糟。

const GP_FATAL: String = "fatal."
const GP_CODE_NO_PLANT_INFO: String = GP_FATAL + "no_plant_information"
const GP_CODE_NO_SCHEMA: String = GP_FATAL + "no_schema_version"
const GP_CODE_EXTENT_INCOMPLETE: String = "dexpi.extent_incomplete"
const GP_CODE_NO_DIAGRAM: String = "dexpi.no_diagram"
const GP_CODE_NO_COMPONENT_CLASS: String = "dexpi.no_component_class"
const GP_CODE_UNKNOWN_CLASS: String = "dexpi.unknown_component_class"
const GP_CODE_MISSING_URI: String = "dexpi.missing_uri"
const GP_CODE_DANGLING_REFERENCE: String = "dexpi.dangling_reference"
const GP_CODE_BAD_LANGUAGE: String = "dexpi.bad_language_tag"
const GP_CODE_NULL_VALUE: String = "dexpi.null_value"
const GP_CODE_OLD_VERSION: String = "dexpi.old_version"
const GP_CODE_NO_GEOMETRY: String = "dexpi.no_geometry"


static func gpValidate(gpMid: Dictionary) -> GPImportReport:
	var gpReport: GPImportReport = GPImportReport.new()
	if gpMid.is_empty():
		gpReport.gpAddError(GP_CODE_NO_PLANT_INFO, "the structure is empty")
		return gpReport
	_gpValidatePlant(gpMid, gpReport)
	_gpValidateDiagram(gpMid, gpReport)
	_gpValidateEquipment(gpMid, gpReport)
	_gpValidateSegments(gpMid, gpReport)
	return gpReport


static func _gpValidatePlant(gpMid: Dictionary, gpReport: GPImportReport) -> void:
	var gpPlant: Dictionary = gpMid.get(GPDexpiExporter.GP_KEY_PLANT, {}) as Dictionary
	if gpPlant.is_empty():
		gpReport.gpAddError(GP_CODE_NO_PLANT_INFO, "PlantInformation is mandatory (§2.1)")
		return
	var gpSchema: String = str(gpPlant.get("schema", ""))
	if gpSchema.is_empty():
		gpReport.gpAddError(GP_CODE_NO_SCHEMA, "PlantInformation.SchemaVersion is mandatory")
		return
	# Degradation ① (§7.5): an older document is imported, but its graphics must not be read
	# as DEXPI graphics.
	# 降级 ①（§7.5）：较旧的文档仍被导入，但其图形**不得**按 DEXPI 图形语义解读。
	var gpGraphics: String = GPDexpiSchema.gpGraphicsMode(gpSchema)
	if gpGraphics == "out_of_scope":
		gpReport.gpAddWarning(GP_CODE_OLD_VERSION,
			"schema " + gpSchema + ": graphics are outside the spec and are read as plain Proteus")
	elif gpGraphics == "informative":
		gpReport.gpAddWarning(GP_CODE_OLD_VERSION,
			"schema " + gpSchema + ": graphics are informative, not normative")


static func _gpValidateDiagram(gpMid: Dictionary, gpReport: GPImportReport) -> void:
	var gpDiagram: Dictionary = gpMid.get(GPDexpiExporter.GP_KEY_DIAGRAM, {}) as Dictionary
	# Degradation ②: a document with NO <Drawing> is legal — it simply carries no graphics.
	# 降级 ②：没有 <Drawing> 的文档是**合法**的 —— 它只是不含图形。
	if gpDiagram.is_empty():
		gpReport.gpAddInfo(GP_CODE_NO_DIAGRAM, "no Diagram: concept only, which is legal (§5.2)")
		return
	for gpKey in ["min_x", "min_y", "max_x", "max_y"]:
		if not (gpDiagram.get(gpKey) is float) and not (gpDiagram.get(gpKey) is int):
			gpReport.gpAddError(GP_CODE_EXTENT_INCOMPLETE, "Diagram." + gpKey + " is missing")
	if str(gpDiagram.get("name", "")).strip_edges().is_empty():
		gpReport.gpAddError(GP_CODE_EXTENT_INCOMPLETE, "Diagram.Name is mandatory")


static func _gpValidateEquipment(gpMid: Dictionary, gpReport: GPImportReport) -> void:
	var gpEquipment: Array = gpMid.get(GPDexpiExporter.GP_KEY_EQUIPMENT, []) as Array
	gpReport.gpStats["nodes"] = gpEquipment.size()
	for gpEq in gpEquipment:
		var gpE: Dictionary = gpEq as Dictionary
		var gpId: String = str(gpE.get("id", ""))
		var gpClass: String = str(gpE.get("class", ""))
		if gpClass.is_empty():
			gpReport.gpAddError(GP_CODE_NO_COMPONENT_CLASS, gpId + ": ComponentClass is mandatory")
		elif GPDexpiMapping.gpSymbolIdFor(gpClass).is_empty():
			# Degradation ③: unknown class -> a Custom counterpart, keeping the original URI.
			# Not an error: the object still exists, it just has no local glyph.
			# 降级 ③：未知类 -> 落到 Custom 对应物，保留原始 URI。
			# 这不是 error：对象仍然存在，只是没有本地字形。
			gpReport.gpAddWarning(GP_CODE_UNKNOWN_CLASS,
				gpId + ": " + gpClass + " has no local symbol; it imports as a placeholder")
		# Degradation ④: a missing URI is flagged, never invented.
		# 降级 ④：缺失的 URI 被标记，绝不臆造。
		if str(gpE.get("uri", "")).is_empty() and not gpClass.is_empty():
			gpReport.gpAddWarning(GP_CODE_MISSING_URI, gpId + ": no ComponentClassURI")
		for gpLang in (gpE.get("names", {}) as Dictionary).keys():
			var gpTag: String = str(gpLang)
			if gpTag != GPXmlText.gpLang2(gpTag):
				gpReport.gpAddWarning(GP_CODE_BAD_LANGUAGE,
					gpId + ": language tag " + gpTag + " is not two letters")
		for gpKey in (gpE.get("props", {}) as Dictionary).keys():
			if (gpE.get("props", {}) as Dictionary).get(gpKey) == null:
				# Degradation: a null is "unknown", never an empty string.
				# 降级：null 表示「未知」，绝不当成空串。
				gpReport.gpAddInfo(GP_CODE_NULL_VALUE, gpId + "." + str(gpKey) + " is null")


static func _gpValidateSegments(gpMid: Dictionary, gpReport: GPImportReport) -> void:
	var gpSegments: Array = gpMid.get(GPDexpiExporter.GP_KEY_SEGMENTS, []) as Array
	gpReport.gpStats["edges"] = gpSegments.size()
	var gpIds: Dictionary = {}
	for gpEq in (gpMid.get(GPDexpiExporter.GP_KEY_EQUIPMENT, []) as Array):
		gpIds[str((gpEq as Dictionary).get("id", ""))] = true
	for gpSeg in gpSegments:
		var gpS: Dictionary = gpSeg as Dictionary
		var gpId: String = str(gpS.get("id", ""))
		for gpSide in ["from_uid", "to_uid"]:
			var gpRef: String = str(gpS.get(gpSide, ""))
			if gpRef.is_empty():
				continue
			if not gpIds.has(gpRef):
				gpReport.gpAddError(GP_CODE_DANGLING_REFERENCE,
					gpId + ": " + gpSide + " points at " + gpRef + ", which is not in this document")
		# Degradation: geometry missing -> the pipe keeps its topology but has no route.
		# 降级：几何缺失 -> 管线保留拓扑但没有走向。
		if (gpS.get("points", []) as Array).size() < 2:
			gpReport.gpAddWarning(GP_CODE_NO_GEOMETRY,
				gpId + ": fewer than two points; topology kept, route empty")
