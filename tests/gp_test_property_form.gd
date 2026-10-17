extends "res://tests/gp_test.gd"
# M10 panel LOGIC (GPPropertyForm): grouping, ordering, effective values, orphans and the
# multi-select "shared value" rules — all pure, so no widget is built here.
# M10 面板**逻辑**（GPPropertyForm）：分组、排序、有效值、孤儿与多选「共有取值」规则
# —— 全部为纯函数，故此处不构建任何控件。
#
# Why these matter / 为何重要：
#   the panel is where "the library owns the definition, the instance owns the value" becomes
#   visible to the user. If grouping or the shared-value rule drifts, a batch edit silently
#   writes one instance's value onto all the others.
#   面板是「库持有定义、实例持有取值」对用户可见的地方。分组或共有取值规则一旦走偏，
#   批量编辑就会把某个实例的值静默写到其余实例上。


func _gpField(gpKey: String, gpGroup: String, gpOrder: int, gpKind: int,
		gpDefault: Variant) -> GPPropertyDef:
	var gpF: GPPropertyDef = GPPropertyDef.new()
	gpF.gpKey = gpKey
	gpF.gpGroup = gpGroup
	gpF.gpOrder = gpOrder
	gpF.gpKind = gpKind
	gpF.gpDefault = gpDefault
	return gpF


# 工艺: rated_flow(1), head(2) | 材料: material(1)
func _gpSchema() -> GPPropertySchema:
	var gpSc: GPPropertySchema = GPPropertySchema.new()
	gpSc.gpFields.append(_gpField("rated_flow", "工艺", 1,
		GPPropertyDef.GPKind.GP_FLOAT, 0.0))
	gpSc.gpFields.append(_gpField("head", "工艺", 2,
		GPPropertyDef.GPKind.GP_FLOAT, 30.0))
	gpSc.gpFields.append(_gpField("material", "材料", 1,
		GPPropertyDef.GPKind.GP_ENUM, "CS"))
	return gpSc


# ---- 1. grouping & ordering / 分组与排序 ----

func gpTestSectionsGroupFields() -> void:
	var gpSecs: Array[Dictionary] = GPPropertyForm.gpSections(_gpSchema(), {})
	gpEq(gpSecs.size(), 2, "two groups: 工艺 and 材料")
	# Groups are sorted by name, so 工艺 (U+5DE5) precedes 材料 (U+6750).
	# 分组按名排序，故「工艺」(U+5DE5) 先于「材料」(U+6750)。
	gpEq(str(gpSecs[0]["group"]), "工艺", "first section is 工艺")
	gpEq(str(gpSecs[1]["group"]), "材料", "second section is 材料")
	gpEq((gpSecs[0]["fields"] as Array).size(), 2, "工艺 holds two fields")
	gpEq((gpSecs[1]["fields"] as Array).size(), 1, "材料 holds one field")


func gpTestFieldsKeepSchemaOrderInsideGroup() -> void:
	var gpSecs: Array[Dictionary] = GPPropertyForm.gpSections(_gpSchema(), {})
	var gpFields: Array = gpSecs[0]["fields"] as Array
	gpEq(str(gpFields[0]["key"]), "rated_flow", "gpOrder 1 comes first")
	gpEq(str(gpFields[1]["key"]), "head", "gpOrder 2 comes second")


func gpTestUngroupedFieldsGetTheirOwnSection() -> void:
	var gpSc: GPPropertySchema = GPPropertySchema.new()
	gpSc.gpFields.append(_gpField("note", "", 0, GPPropertyDef.GPKind.GP_STRING, ""))
	var gpSecs: Array[Dictionary] = GPPropertyForm.gpSections(gpSc, {})
	gpEq(gpSecs.size(), 1, "one section")
	gpEq(str(gpSecs[0]["group"]), GPPropertyForm.GP_UNGROUPED, "group is the ungrouped bucket")


# ---- 2. effective values & the override flag / 有效值与覆盖标志 ----

func gpTestRowCarriesEffectiveValue() -> void:
	var gpSecs: Array[Dictionary] = GPPropertyForm.gpSections(_gpSchema(), {"head": 55.0})
	var gpFields: Array = gpSecs[0]["fields"] as Array
	var gpHead: Dictionary = gpFields[1]
	gpEq(float(gpHead["value"]), 55.0, "the instance value is what the panel shows")
	gpEq(bool(gpHead["overridden"]), true, "and it is marked as overridden")
	var gpFlow: Dictionary = gpFields[0]
	gpEq(float(gpFlow["value"]), 0.0, "an untouched field shows the library default")
	gpEq(bool(gpFlow["overridden"]), false, "and is NOT marked as overridden")


# ---- 3. orphans / 孤儿字段 ----

func gpTestOrphanRowsKeepTheValue() -> void:
	var gpRows: Array[Dictionary] = GPPropertyForm.gpOrphanRows(_gpSchema(), {"legacy_kw": 7.5})
	gpEq(gpRows.size(), 1, "the unknown key is surfaced, not dropped")
	gpEq(str(gpRows[0]["key"]), "legacy_kw", "orphan key")
	gpEq(float(gpRows[0]["value"]), 7.5, "orphan value is preserved verbatim")


func gpTestNoOrphansWhenSchemaMatches() -> void:
	gpEq(GPPropertyForm.gpOrphanRows(_gpSchema(), {"head": 1.0}).size(), 0, "declared keys are not orphans")


# ---- 4. multi-select: shared value / 多选：共有取值 ----

func gpTestSharedValueWhenAllAgree() -> void:
	var gpList: Array = [{"head": 40.0}, {"head": 40.0}, {"head": 40.0}]
	var gpOut: Dictionary = GPPropertyForm.gpSharedValue(_gpSchema(), gpList, "head")
	gpEq(bool(gpOut["same"]), true, "identical values are reported as shared")
	gpEq(float(gpOut["value"]), 40.0, "and the shared value is returned")


# The whole point of "same == false": the panel must NOT prefill a value that would
# overwrite three different ones on the first keystroke.
# 「same == false」的全部意义：面板**不得**预填一个会在第一次录入时就覆盖三个不同值的值。
func gpTestSharedValueWhenTheyDisagree() -> void:
	var gpList: Array = [{"head": 40.0}, {"head": 55.0}]
	var gpOut: Dictionary = GPPropertyForm.gpSharedValue(_gpSchema(), gpList, "head")
	gpEq(bool(gpOut["same"]), false, "disagreeing values are reported as NOT shared")


func gpTestSharedValueFollowsLibraryDefault() -> void:
	var gpList: Array = [{}, {}]
	var gpOut: Dictionary = GPPropertyForm.gpSharedValue(_gpSchema(), gpList, "material")
	gpEq(gpOut["value"], "CS", "instances with no value still agree on the library default")


func gpTestAllOverriddenNeedsEveryInstance() -> void:
	var gpAll: Array = [{"head": 1.0}, {"head": 2.0}]
	gpEq(GPPropertyForm.gpAllOverridden(gpAll, "head"), true, "every instance overrides")
	var gpPartial: Array = [{"head": 1.0}, {}]
	gpEq(GPPropertyForm.gpAllOverridden(gpPartial, "head"), false, "one missing override is enough to say no")
	gpEq(GPPropertyForm.gpAllOverridden([], "head"), false, "an empty selection overrides nothing")


# ---- 5. labels & titles / 显示名与标题 ----

func gpTestLabelFallsBackFromLabelToKey() -> void:
	var gpF: GPPropertyDef = GPPropertyDef.new()
	gpF.gpKey = "rated_flow"
	gpF.gpLabel = "额定流量"
	gpEq(GPPropertyForm.gpFieldLabel(gpF), "额定流量", "literal label is used when there is no i18n key")
	gpF.gpLabel = ""
	gpEq(GPPropertyForm.gpFieldLabel(gpF), "rated_flow", "and the raw key is the last resort")


func gpTestSectionTitleShowsGroupAndCount() -> void:
	var gpTitle: String = GPPropertyForm.gpSectionTitle("工艺", 2)
	gpCheck(gpTitle.contains("工艺"), "the title names the group")
	gpCheck(gpTitle.contains("2"), "the title shows the field count")
	var gpGeneral: String = GPPropertyForm.gpSectionTitle(GPPropertyForm.GP_UNGROUPED, 1)
	gpCheck(gpGeneral.contains("通用") or gpGeneral.contains("General"),
		"ungrouped fields are titled with the general bucket")


# ---- 6. custom entries & search (Rev.3 stage 1.5, R2) / 自定义条目与检索 ----

# The custom section and the orphan section read the SAME storage with two intents, so their
# row sets must agree — otherwise the panel would show one set and edit another.
# 自定义段与孤儿段读同一份存储、只是意图不同，故两者行集必须一致 —— 否则面板会显示一套、
# 编辑另一套。
func gpTestAdhocRowsAreTheOrphanSet() -> void:
	var gpProps: Dictionary = {"legacy_kw": 7.5, "head": 1.0}
	var gpA: Array[Dictionary] = GPPropertyForm.gpAdhocRows(_gpSchema(), gpProps)
	var gpO: Array[Dictionary] = GPPropertyForm.gpOrphanRows(_gpSchema(), gpProps)
	gpEq(gpA.size(), 1, "only the schema-foreign key is a custom entry")
	gpEq(gpA.size(), gpO.size(), "custom rows and orphan rows are the same size")
	gpEq(str(gpA[0]["key"]), str(gpO[0]["key"]), "and the same key")
	gpEq(float(gpA[0]["value"]), 7.5, "the value rides along verbatim")


# An empty query returns EVERY declared row flattened; a query matches label, key or value,
# case-insensitively. The search must never fabricate a row the sections would not show.
# 空查询返回全部声明行（摊平）；查询按标签 / 键 / 取值匹配、不区分大小写。
# 检索绝不可捏造分组视图不会显示的行。
func gpTestSearchEmptyQueryReturnsEverything() -> void:
	gpEq(GPPropertyForm.gpSearch(_gpSchema(), {}, "").size(), 3,
		"an empty query returns every declared row")
	gpEq(GPPropertyForm.gpSearch(_gpSchema(), {}, "   ").size(), 3,
		"a blank query behaves like an empty one")


func gpTestSearchMatchesKeyAndValue() -> void:
	gpEq(GPPropertyForm.gpSearch(_gpSchema(), {}, "head").size(), 1, "matching by key")
	gpEq(GPPropertyForm.gpSearch(_gpSchema(), {}, "30").size(), 1, "matching by (default) value")
	gpEq(GPPropertyForm.gpSearch(_gpSchema(), {"head": 55.0}, "55").size(), 1,
		"matching by the instance's override value")
	gpEq(GPPropertyForm.gpSearch(_gpSchema(), {}, "no_such_field").size(), 0,
		"a miss returns nothing")


func gpTestSearchMatchesLabelCaseInsensitively() -> void:
	var gpSc: GPPropertySchema = GPPropertySchema.new()
	var gpF: GPPropertyDef = _gpField("power", "", 1, GPPropertyDef.GPKind.GP_STRING, "")
	gpF.gpLabel = "Power Rating"
	gpSc.gpFields.append(gpF)
	gpEq(GPPropertyForm.gpSearch(gpSc, {}, "power RATING").size(), 1,
		"label match is case-insensitive")
