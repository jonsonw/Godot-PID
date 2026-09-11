extends "res://tests/gp_test.gd"
# M8 property model: type layer (schema) vs instance layer (values) + the resolver bridge.
# M8 属性模型：类型层（schema）与实例层（取值）的拆分 + 解析层桥梁。
#
# The single rule under test / 被测试的唯一规则：
#   instances store VALUES only, and every read goes through GPPropertyResolver — that is
#   what makes "edit the library, every project follows" true.
#   实例只存「值」，所有读取都经 GPPropertyResolver —— 这正是「改库即全项目同步」成立的原因。


# ---- helpers / 辅助构造 ----

func _gpSchema() -> GPPropertySchema:
	var gpSc: GPPropertySchema = GPPropertySchema.new()
	var gpFlow: GPPropertyDef = GPPropertyDef.new()
	gpFlow.gpKey = "rated_flow"
	gpFlow.gpKind = GPPropertyDef.GPKind.GP_FLOAT
	gpFlow.gpDefault = 0.0
	gpFlow.gpUnit = "m3/h"
	gpFlow.gpGroup = "工艺"
	gpFlow.gpOrder = 1
	var gpMat: GPPropertyDef = GPPropertyDef.new()
	gpMat.gpKey = "material"
	gpMat.gpKind = GPPropertyDef.GPKind.GP_ENUM
	gpMat.gpDefault = "CS"
	gpMat.gpOptions.append("CS")
	gpMat.gpOptions.append("SS316L")
	gpMat.gpGroup = "材料"
	gpMat.gpOrder = 2
	gpSc.gpFields.append(gpFlow)
	gpSc.gpFields.append(gpMat)
	return gpSc


# ---- 1. defaults & overrides / 默认值与覆盖 ----

func gpTestDefaultIsInherited() -> void:
	var gpSc: GPPropertySchema = _gpSchema()
	gpEq(GPPropertyResolver.gpEffectiveValue(gpSc, {}, "rated_flow"), 0.0,
		"untouched field follows the library default")
	gpEq(GPPropertyResolver.gpEffectiveValue(gpSc, {}, "material"), "CS",
		"enum default comes from the library")
	gpEq(GPPropertyResolver.gpIsOverridden({}, "rated_flow"), false,
		"an empty instance overrides nothing")


func gpTestOverrideWins() -> void:
	var gpSc: GPPropertySchema = _gpSchema()
	gpEq(GPPropertyResolver.gpEffectiveValue(gpSc, {"rated_flow": 80.0}, "rated_flow"), 80.0,
		"instance value beats the library default")
	gpEq(GPPropertyResolver.gpIsOverridden({"rated_flow": 80.0}, "rated_flow"), true,
		"storing a value marks the field as overridden")


# The reason `has()` and not `!= default`: an instance that stored the default explicitly must
# KEEP its own value when the library default later changes.
# 之所以用 `has()` 而非「是否等于默认值」：显式存了默认值的实例，在库默认值日后变更时
# 必须保留自己的值。
func gpTestStoringTheDefaultStillCountsAsOverridden() -> void:
	var gpSc: GPPropertySchema = _gpSchema()
	var gpProps: Dictionary = {"material": "CS"}
	gpSc.gpFieldByKey("material").gpDefault = "SS316L"
	gpEq(GPPropertyResolver.gpEffectiveValue(gpSc, gpProps, "material"), "CS",
		"an explicit default survives a later library default change")
	gpEq(GPPropertyResolver.gpEffectiveValue(gpSc, {}, "material"), "SS316L",
		"an untouched field follows the NEW library default")


# ---- 2. orphans / 孤儿值 ----

func gpTestOrphansAreKeptNotDropped() -> void:
	var gpSc: GPPropertySchema = _gpSchema()
	var gpProps: Dictionary = {"rated_flow": 80.0, "old_spec": "HG/T 20570"}
	gpEq(GPPropertyResolver.gpOrphanKeys(gpSc, gpProps), ["old_spec"],
		"a key the library no longer declares is an orphan")
	gpEq(GPPropertyResolver.gpEffectiveValue(gpSc, gpProps, "old_spec"), "HG/T 20570",
		"orphan values are returned as stored — never silently dropped")
	gpEq(GPPropertyResolver.gpEffectiveProps(gpSc, gpProps).has("old_spec"), true,
		"orphans travel with the effective set (bill of materials / export)")


# ---- 3. field rename migration / 字段改名迁移 ----

func gpTestRenameMigration() -> void:
	var gpSc: GPPropertySchema = _gpSchema()
	var gpRenamed: GPPropertyDef = GPPropertyDef.new()
	gpRenamed.gpKey = "rated_flow"
	gpRenamed.gpRenameFrom = "flow"
	gpRenamed.gpKind = GPPropertyDef.GPKind.GP_FLOAT
	gpRenamed.gpDefault = 0.0
	gpSc.gpFields = [gpRenamed]
	var gpMigrated: Dictionary = GPPropertyResolver.gpMigrateProps(gpSc, {"flow": 42.0})
	gpEq(gpMigrated.has("flow"), false, "the stale old key is dropped")
	gpEq(gpMigrated.get("rated_flow", -1.0), 42.0, "the value moved onto the new key")
	# Idempotent: migrating an already-migrated dict changes nothing.
	# 幂等：对已迁移过的字典再做一次迁移，结果不变。
	var gpAgain: Dictionary = GPPropertyResolver.gpMigrateProps(gpSc, gpMigrated)
	gpEq(gpAgain.get("rated_flow", -1.0), 42.0, "migration is idempotent")
	# The new key wins when both exist (the user already re-entered it).
	# 新旧键同时存在时以新键为准（用户已重新录入）。
	var gpBoth: Dictionary = GPPropertyResolver.gpMigrateProps(gpSc, {"flow": 1.0, "rated_flow": 9.0})
	gpEq(gpBoth.get("rated_flow", -1.0), 9.0, "the new key wins over the stale old one")


# ---- 4. coercion & validation / 类型转换与校验 ----

func gpTestCoerceByKind() -> void:
	var gpF: GPPropertyDef = GPPropertyDef.new()
	gpF.gpKind = GPPropertyDef.GPKind.GP_FLOAT
	gpEq(gpF.gpCoerce("80"), 80.0, "a JSON string becomes a float")
	gpF.gpKind = GPPropertyDef.GPKind.GP_INT
	gpEq(gpF.gpCoerce(7.9), 7, "floats truncate to int")
	gpF.gpKind = GPPropertyDef.GPKind.GP_BOOL
	gpEq(gpF.gpCoerce("true"), true, "'true' parses as boolean")
	gpEq(gpF.gpCoerce("no"), false, "'no' parses as boolean false")
	gpF.gpKind = GPPropertyDef.GPKind.GP_ENUM
	gpF.gpOptions.append("CS")
	gpF.gpOptions.append("SS316L")
	gpF.gpDefault = "CS"
	gpEq(gpF.gpCoerce("SS316L"), "SS316L", "a known enum value is kept")
	gpEq(gpF.gpCoerce("Ti"), "CS", "an unknown enum value falls back to the default")


func gpTestValidateRules() -> void:
	var gpReq: GPPropertyDef = GPPropertyDef.new()
	gpReq.gpKey = "tag_no"
	gpReq.gpRequired = true
	gpEq(gpReq.gpValidate(""), false, "required rejects empty")
	gpEq(gpReq.gpValidate("P-1001"), true, "required accepts a value")

	var gpNum: GPPropertyDef = GPPropertyDef.new()
	gpNum.gpKind = GPPropertyDef.GPKind.GP_FLOAT
	gpNum.gpMin = 0.0
	gpNum.gpMax = 100.0
	gpEq(gpNum.gpValidate(50.0), true, "in-range passes")
	gpEq(gpNum.gpValidate(120.0), false, "above max fails")
	gpEq(gpNum.gpValidate(-1.0), false, "below min fails")

	var gpPat: GPPropertyDef = GPPropertyDef.new()
	gpPat.gpPattern = "^(P|V)-[0-9]{4}$"
	gpEq(gpPat.gpValidate("P-1001"), true, "pattern match passes")
	gpEq(gpPat.gpValidate("1001"), false, "pattern mismatch fails")
	# NOT asserted: an uncompilable pattern is treated as "no rule" (the code returns true), but
	# RegEx.compile prints an engine error that GUT counts as an unexpected error, and a single
	# broken pattern must never make the whole gate red.
	# 此处不做断言：坏正则被当作「无规则」（代码返回 true），但 RegEx.compile 会打印一条引擎
	# 错误，GUT 会把它计为意外错误 —— 不能因为一个坏正则就让整道门禁变红。


# ---- 5. fingerprint / 指纹 ----

func gpTestFingerprintDetectsLibraryChange() -> void:
	var gpSc: GPPropertySchema = _gpSchema()
	var gpBefore: String = gpSc.gpFingerprint()
	gpSc.gpFieldByKey("rated_flow").gpUnit = "L/s"
	gpEq(gpSc.gpFingerprint(), gpBefore, "a unit change does not change the fingerprint")
	var gpExtra: GPPropertyDef = GPPropertyDef.new()
	gpExtra.gpKey = "duty"
	gpExtra.gpKind = GPPropertyDef.GPKind.GP_STRING
	gpSc.gpFields.append(gpExtra)
	gpCheck(gpSc.gpFingerprint() != gpBefore, "adding a field changes the fingerprint")


# ---- 6. names & canvas label / 名称与画布标签 ----

func gpTestNameLocaleFallback() -> void:
	var gpNames: Dictionary = {"zh_CN": "磨矿给料泵", "en_US": "Mill Feed Pump"}
	gpEq(GPPropertyResolver.gpDisplayName(gpNames, "离心泵", "en_US"), "Mill Feed Pump",
		"exact locale wins")
	gpEq(GPPropertyResolver.gpDisplayName(gpNames, "离心泵", "de_DE"), "磨矿给料泵",
		"unknown locale falls back to the project primary language")
	gpEq(GPPropertyResolver.gpDisplayName({}, "离心泵", "de_DE"), "离心泵",
		"no names at all falls back to the library display name")
	gpEq(GPPropertyResolver.gpDisplayName({}, "", "de_DE", "P-1001"), "P-1001",
		"last resort is the tag, so a label is never blank")


# The canvas shows the TAG; the symbol's library name lives in the inspector.
# 画布显示位号；图元的库名称住在属性面板里。
func gpTestLabelTemplateShowsTagByDefault() -> void:
	gpEq(GPPropertyResolver.GP_DEFAULT_LABEL_FORMAT, "{tag}", "default template is tag-only")
	gpEq(GPPropertyResolver.gpLabelText("{tag}", "P-1001", "磨矿给料泵"), "P-1001",
		"default template renders the tag alone")
	gpEq(GPPropertyResolver.gpLabelText("{tag}\n{name}", "P-1001", "磨矿给料泵"), "P-1001\n磨矿给料泵",
		"opt-in two-line template still works")
	gpEq(GPPropertyResolver.gpLabelText("", "P-1001", ""), "P-1001",
		"an empty template falls back to the default, not to a blank label")


# ---- 7. label placement / 标签位置 ----

func gpTestLabelOffsetIsClamped() -> void:
	var gpClamped: Vector2 = GPLabelAnchor.gpClamp(GPLabelAnchor.GPAnchor.GP_BELOW, Vector2(9.0, -9.0))
	gpEq(gpClamped, Vector2(GPLabelAnchor.GP_RANGE, -GPLabelAnchor.GP_RANGE),
		"offset is clamped to the ±1.5 half-envelope range")
	var gpInside: Vector2 = GPLabelAnchor.gpClamp(GPLabelAnchor.GPAnchor.GP_INSIDE, Vector2(1.2, 0.0))
	gpEq(gpInside, Vector2(GPLabelAnchor.GP_INSIDE_RANGE, 0.0),
		"INSIDE is clamped tighter so text stays within the glyph")


func gpTestLabelOffsetWorld() -> void:
	var gpSize: Vector2 = Vector2(100.0, 60.0)
	var gpBelow: Vector2 = GPLabelAnchor.gpOffsetWorld(GPLabelAnchor.GPAnchor.GP_BELOW, Vector2.ZERO, gpSize, 4.0)
	gpEq(gpBelow, Vector2(0.0, 34.0), "BELOW sits half the height plus the gap under the centre")
	var gpAbove: Vector2 = GPLabelAnchor.gpOffsetWorld(GPLabelAnchor.GPAnchor.GP_ABOVE, Vector2.ZERO, gpSize, 4.0)
	gpEq(gpAbove, Vector2(0.0, -34.0), "ABOVE mirrors BELOW")
	# Normalised: 1.0 means half the envelope, so x=1.0 shifts by 50 px on a 100 px wide symbol.
	# 归一化：1.0 表示半个包络，故 x=1.0 在 100px 宽的图元上平移 50px。
	var gpShifted: Vector2 = GPLabelAnchor.gpOffsetWorld(GPLabelAnchor.GPAnchor.GP_BELOW, Vector2(1.0, 0.0), gpSize, 4.0)
	gpEq(gpShifted, Vector2(50.0, 34.0), "offset scales with the envelope, not with pixels")


func gpTestInstanceLabelFollowsLibraryUntilSet() -> void:
	gpEq(GPPropertyResolver.gpActiveAnchor(GPLabelAnchor.GPAnchor.GP_ABOVE, GPPropertyResolver.GP_ANCHOR_UNSET),
		GPLabelAnchor.GPAnchor.GP_ABOVE, "an unset instance anchor follows the library")
	gpEq(GPPropertyResolver.gpActiveAnchor(GPLabelAnchor.GPAnchor.GP_ABOVE, GPLabelAnchor.GPAnchor.GP_BELOW),
		GPLabelAnchor.GPAnchor.GP_BELOW, "a set instance anchor wins")
	gpEq(GPPropertyResolver.gpActiveOffset(Vector2(0.0, 0.5), GPLabelAnchor.GP_OFFSET_UNSET),
		Vector2(0.0, 0.5), "an unset instance offset follows the library")
	# ZERO is a legitimate value ("exactly on the anchor"), so it must not read as "unset".
	# 零是合法取值（正好落在锚点上），故不能被当成「未设置」。
	gpEq(GPPropertyResolver.gpActiveOffset(Vector2(0.0, 0.5), Vector2.ZERO), Vector2.ZERO,
		"an explicit zero offset wins over the library default")


# ---- 8. serialization round trips / 序列化往返 ----

func gpTestNodeRoundTripV2() -> void:
	var gpN: GPPIDNode = GPPIDNode.new()
	gpN.gpUid = "a3f9k2m1-n17"
	gpN.gpInstanceId = "u-1"
	gpN.gpSymbolId = "LPUMP003"
	gpN.gpTag = "P-1001"
	gpN.gpNames = {"zh_CN": "磨矿给料泵", "en_US": "Mill Feed Pump"}
	gpN.gpProps = {"rated_flow": 80.0}
	gpN.gpLabelAnchor = GPLabelAnchor.GPAnchor.GP_ABOVE
	gpN.gpLabelOffset = Vector2(0.25, -0.5)
	gpN.gpPosition = Vector2(120.0, 340.0)
	var gpBack: GPPIDNode = GPPIDNode.new()
	gpBack.gpFromDict(gpN.gpToDict())
	gpEq(gpBack.gpUid, "a3f9k2m1-n17", "uid survives a round trip")
	gpEq(gpBack.gpTag, "P-1001", "tag survives a round trip")
	gpEq(gpBack.gpNames.get("en_US", ""), "Mill Feed Pump", "multi-language names survive")
	gpEq(gpBack.gpProps.get("rated_flow", -1.0), 80.0, "props survive")
	gpEq(gpBack.gpLabelAnchor, GPLabelAnchor.GPAnchor.GP_ABOVE, "label anchor survives")
	gpEq(gpBack.gpLabelOffset, Vector2(0.25, -0.5), "label offset survives")
	gpEq(gpBack.gpPosition, Vector2(120.0, 340.0), "position survives")


# v1 archives: no uid, "label" carried either a tag or a human name, "attrs" held properties.
# v1 存档：无 uid，"label" 里可能是位号也可能是名称，"attrs" 存属性。
func gpTestNodeLegacyV1Loads() -> void:
	var gpTagged: GPPIDNode = GPPIDNode.new()
	gpTagged.gpFromDict({"id": "u-1", "type": "LPUMP003", "label": "P-1001",
		"pos": [10.0, 20.0], "attrs": {"k": "v"}})
	gpEq(gpTagged.gpTag, "P-1001", "a tag-shaped legacy label becomes the tag")
	gpEq(gpTagged.gpNames.has("zh_CN"), false, "a tag-shaped label does not seed the name")
	gpEq(gpTagged.gpProps.get("k", ""), "v", "legacy attrs load into props")
	gpEq(gpTagged.gpRefId(), "u-1", "a pre-M8 archive references by instance id")

	var gpNamed: GPPIDNode = GPPIDNode.new()
	gpNamed.gpFromDict({"id": "u-2", "type": "LPUMP003", "label": "磨矿给料泵"})
	gpEq(gpNamed.gpNames.get("zh_CN", ""), "磨矿给料泵",
		"a name-shaped legacy label seeds names.zh_CN instead of the tag")


func gpTestShapeNewFieldsRoundTrip() -> void:
	var gpS: GPShape = GPShape.gpLine(Vector2(0.0, 0.0), Vector2(10.0, 10.0))
	gpS.gpUid = "a3f9k2m1-s3"
	gpS.gpName = "界区线"
	gpS.gpLayer = "BORDER"
	gpS.gpProps = {"note": "battery limits"}
	var gpBack: GPShape = GPShape.new()
	gpBack.gpFromDict(gpS.gpToDict())
	gpEq(gpBack.gpUid, "a3f9k2m1-s3", "shape uid survives")
	gpEq(gpBack.gpName, "界区线", "shape name survives")
	gpEq(gpBack.gpLayer, "BORDER", "shape layer survives")
	gpEq(gpBack.gpProps.get("note", ""), "battery limits", "shape props survive")
	# Legacy shape: none of the new keys — must load with defaults.
	# 历史图形：没有任何新键 —— 必须按默认值载入。
	var gpOld: GPShape = GPShape.new()
	gpOld.gpFromDict({"kind": GPShape.GPKind.GP_LINE, "pts": [[0.0, 0.0], [1.0, 1.0]]})
	gpEq(gpOld.gpLayer, "ANNOTATION", "a legacy shape gets the default layer")
	gpEq(gpOld.gpUid, "", "a legacy shape has no uid until migrated")


func gpTestSymbolDefSchemaRoundTrip() -> void:
	var gpDef: GPSymbolDef = GPSymbolDef.new()
	gpDef.gpId = "LPUMP003"
	gpDef.gpDisplayName = "离心泵"
	gpDef.gpSchema = _gpSchema()
	gpDef.gpTagPrefix = "P"
	gpDef.gpLabelFormat = "{tag}"
	gpDef.gpLabelAnchor = GPLabelAnchor.GPAnchor.GP_ABOVE
	gpDef.gpLabelOffset = Vector2(0.0, 0.5)
	var gpBack: GPSymbolDef = GPSymbolDef.new()
	gpBack.gpFromDict(gpDef.gpToDict())
	gpCheck(gpBack.gpSchema != null, "typed schema survives a round trip")
	gpEq(gpBack.gpSchema.gpKeys(), ["rated_flow", "material"], "schema fields survive in order")
	gpEq(gpBack.gpSchema.gpFieldByKey("rated_flow").gpUnit, "m3/h", "field metadata survives")
	gpEq(gpBack.gpTagPrefix, "P", "tag prefix survives")
	gpEq(gpBack.gpLabelFormat, "{tag}", "label format survives")
	gpEq(gpBack.gpLabelAnchor, GPLabelAnchor.GPAnchor.GP_ABOVE, "label anchor survives")
	# A pre-M8 pack: no schema, no label keys — everything must fall back to the defaults.
	# M8 之前的图元包：无 schema、无标签键 —— 一切必须回落到默认值。
	var gpOld: GPSymbolDef = GPSymbolDef.new()
	gpOld.gpFromDict({"id": "legacy_pump", "display_name": "泵"})
	gpEq(gpOld.gpSchema, null, "a legacy pack has no typed schema")
	gpEq(gpOld.gpLabelFormat, "{tag}", "label format defaults to tag-only")
	gpEq(gpOld.gpLabelAnchor, GPLabelAnchor.GPAnchor.GP_BELOW, "label anchor defaults to BELOW (historic look)")


# ---- 9. uid allocation / uid 分配 ----

func gpTestIdGenDocIdAndGlobalUid() -> void:
	var gpG: GPIdGen = GPIdGen.new()
	gpEq(gpG.gpDocId.length(), GPIdGen.GP_DOC_ID_LEN, "doc id is 8 characters")
	gpCheck(gpG.gpDocId != GPIdGen.gpNewDocId(), "two doc ids differ (random, not fixed)")
	var gpUid: String = gpG.gpNextGlobal("n")
	gpEq(gpUid, "%s-n1" % gpG.gpDocId, "global uid is docId-prefix + short id")
	gpEq(gpG.gpNextGlobal("e"), "%s-e2" % gpG.gpDocId, "node and edge uids share one counter")
	gpEq(gpG.gpNext("n"), "n3", "the plain local id still works unchanged")


# ---- 10. the schema is WIRED UP for factory symbols (阶段 1A：通电) ----
# 出厂图元的 schema 已通电
#
# Before this, GPSymbolDef.gpSchema existed and the resolver / list exporter consumed it, but
# NOTHING in production ever assigned it — so the inspector had no fields to show for factory
# symbols and "edit the library, every project follows" only held inside the tests.
# 在此之前，GPSymbolDef.gpSchema 已存在、解析器与清单导出也在消费它，但生产侧**从未赋值** ——
# 出厂图元在属性面板里无字段可显示，「改库即全项目同步」只在测试里成立。


func gpTestFactorySymbolsCarryTypedSchema() -> void:
	var gpDefs: Array[GPSymbolDef] = GPSymbolPackIso_10628.gpDefs()
	gpCheck(gpDefs.size() > 0, "the ISO pack produced definitions")
	var gpNulls: int = 0
	for gpD in gpDefs:
		if gpD.gpSchema == null:
			gpNulls += 1
	gpEq(gpNulls, 0, "every factory symbol carries a typed gpSchema (was: built but never assigned)")


func gpTestEquipmentSchemasHaveEnoughFields() -> void:
	var gpDefs: Array[GPSymbolDef] = GPSymbolPackIso_10628.gpDefs()
	var gpThin: int = 0
	for gpD in gpDefs:
		# "general" holds line-type symbols (process line, instrument line); one field is
		# correct for them. Real equipment must offer a usable panel.
		# general 类别是线型符号（工艺线、仪表线），一个字段即合理；真实设备须给出可用面板。
		if gpD.gpCategory == "general":
			continue
		if gpD.gpSchema == null or gpD.gpSchema.gpFields.size() < 3:
			gpThin += 1
	gpEq(gpThin, 0, "every equipment category exposes at least 3 property fields")


func _gpFirstOfCategory(gpCat: String) -> GPSymbolDef:
	for gpD in GPSymbolPackIso_10628.gpDefs():
		if gpD.gpCategory == gpCat:
			return gpD
	return null


func gpTestPumpSchemaDrivesTheResolver() -> void:
	var gpPump: GPSymbolDef = _gpFirstOfCategory("pump")
	gpCheck(gpPump != null, "the pack contains a pump")
	if gpPump == null:
		return
	var gpEff: Dictionary = GPPropertyResolver.gpEffectiveProps(gpPump.gpSchema, {})
	gpCheck(gpEff.size() >= 3, "the resolver renders >=3 fields for a pump with no overrides")
	gpCheck(gpEff.has("rated_flow"), "the pump schema exposes rated_flow to the panel")


func gpTestSchemaFingerprintIsStable() -> void:
	var gpValve: GPSymbolDef = _gpFirstOfCategory("valve")
	gpCheck(gpValve != null, "the pack contains a valve")
	if gpValve == null:
		return
	gpEq(gpValve.gpSchema.gpFingerprint(), gpValve.gpSchema.gpFingerprint(),
		"the fingerprint is stable across recomputation (the panel must not reshuffle)")


func gpTestNormalizerRoundTripsTypedSchema() -> void:
	var gpPump: GPSymbolDef = _gpFirstOfCategory("pump")
	if gpPump == null:
		return
	var gpDraft: Dictionary = GPSymbolNormalizer.gpDenormalizeSymbol(gpPump)
	gpCheck((gpDraft.get("schema", []) as Array).size() >= 3,
		"denormalize emits the typed schema back into the author draft")
	var gpBack: GPSymbolDef = GPSymbolNormalizer.gpNormalizeSymbol(gpDraft, "pump")
	gpCheck(gpBack.gpSchema != null, "re-normalizing the draft restores gpSchema")
	if gpBack.gpSchema != null:
		gpEq(gpBack.gpSchema.gpKeys().size(), gpPump.gpSchema.gpKeys().size(),
			"the schema survives the round-trip with the same field count")
