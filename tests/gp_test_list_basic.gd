extends "res://tests/gp_test.gd"
# M13 batch & lists: an equipment list must carry TAG + NAME + the effective value of every
# property, survive a CSV round-trip, and re-import only what the user actually changed.
# M13 批量与清单：设备清单必须含位号 + 名称 + 各属性有效值，能经 CSV 往返，
# 且回灌时只写入用户真正改动过的东西。


# ---- helpers / 辅助构造 ----

func _gpField(gpKeyVal: String, gpKindVal: int, gpDefault: Variant = "") -> GPPropertyDef:
	var f := GPPropertyDef.new()
	f.gpKey = gpKeyVal
	f.gpKind = gpKindVal
	f.gpDefault = gpDefault
	return f


func _gpDef(gpIdVal: String, gpCat: String, gpFields: Array[GPPropertyDef]) -> GPSymbolDef:
	var d := GPSymbolDef.new()
	d.gpId = gpIdVal
	d.gpCategory = gpCat
	# Display name doubles as the fallback for the name column, which makes it assertable.
	# 显示名兼作名称列的回落值，便于断言。
	d.gpDisplayName = gpIdVal
	var sc := GPPropertySchema.new()
	for f in gpFields:
		sc.gpFields.append(f)
	d.gpSchema = sc
	return d


func _gpNode(gpTag: String, gpSymbolId: String, gpProps: Dictionary) -> GPPIDNode:
	var n := GPPIDNode.new()
	n.gpTag = gpTag
	n.gpSymbolId = gpSymbolId
	n.gpProps = gpProps.duplicate()
	return n


# ---- 1. a row carries tag + name + effective values / 行含位号+名称+有效值 ----

func gpTestBuildListCarriesTagAndEffectiveProps() -> void:
	var gpPump := _gpDef("LPUMP001", "pump", [
		_gpField("rated_flow", GPPropertyDef.GPKind.GP_FLOAT, 80.0),
		_gpField("material", GPPropertyDef.GPKind.GP_ENUM, "CS"),
	])
	var gpNode := _gpNode("P-1001", "LPUMP001", {})
	gpNode.gpNames = {"zh_CN": "磨矿给料泵"}
	var gpGraph := GPPIDGraph.new()
	gpGraph.gpNodes.append(gpNode)
	var gpRows := GPListBasic.gpBuildList(gpGraph, "pump", [gpPump])
	gpEq(gpRows.size(), 1, "exactly one pump row")
	gpEq(str(gpRows[0]["tag"]), "P-1001", "tag column carries the tag")
	gpEq(str(gpRows[0]["name"]), "磨矿给料泵", "name column carries the localized name")
	# A field the instance never touched must export the LIBRARY DEFAULT — that is the whole
	# point of reading through GPPropertyResolver instead of gpProps.
	# 实例从未动过的字段必须导出**库默认值** —— 这正是「经 GPPropertyResolver 读取
	# 而非直接读 gpProps」的全部意义。
	gpEq(str(gpRows[0]["rated_flow"]), "80.0", "untouched float exports the library default")
	gpEq(str(gpRows[0]["material"]), "CS", "untouched enum exports the library default")


# ---- 2. name falls back to the library display name / 名称回落到库显示名 ----

func gpTestNameFallsBackToLibraryName() -> void:
	var gpPump := _gpDef("LPUMP001", "pump", [])
	var gpGraph := GPPIDGraph.new()
	gpGraph.gpNodes.append(_gpNode("P-1002", "LPUMP001", {}))
	var gpRows := GPListBasic.gpBuildList(gpGraph, "pump", [gpPump])
	gpEq(str(gpRows[0]["name"]), "LPUMP001",
		"an unnamed instance falls back to the library display name")


# ---- 3. CSV round-trip / CSV 往返 ----

func gpTestCsvRoundTrip() -> void:
	var gpPump := _gpDef("LPUMP001", "pump", [
		_gpField("rated_flow", GPPropertyDef.GPKind.GP_FLOAT, 80.0),
	])
	var gpGraph := GPPIDGraph.new()
	gpGraph.gpNodes.append(_gpNode("P-1001", "LPUMP001", {}))
	gpGraph.gpNodes.append(_gpNode("P-1002", "LPUMP001", {"rated_flow": 120.0}))
	var gpCsv := GPListBasic.gpListToCsv(GPListBasic.gpBuildList(gpGraph, "pump", [gpPump]))
	gpCheck(gpCsv.begins_with("tag,name,rated_flow\n"), "header is tag,name then the schema keys")
	var gpBack := GPListBasic.gpCsvToList(gpCsv)
	gpEq(gpBack.size(), 2, "both rows parsed back")
	gpEq(str(gpBack[0]["tag"]), "P-1001", "first tag survives")
	gpEq(str(gpBack[0]["rated_flow"]), "80.0", "inherited default survives as text")
	gpEq(str(gpBack[1]["tag"]), "P-1002", "second tag survives")
	gpEq(str(gpBack[1]["rated_flow"]), "120.0", "instance override survives as text")


# ---- 4. commas and quotes are escaped symmetrically / 逗号与引号对称转义 ----

func gpTestCsvQuotesCommasAndQuotes() -> void:
	var gpPump := _gpDef("LPUMP001", "pump", [_gpField("note", GPPropertyDef.GPKind.GP_STRING, "")])
	var gpGraph := GPPIDGraph.new()
	gpGraph.gpNodes.append(_gpNode("P-1001", "LPUMP001", {"note": "a,b \"c\""}))
	var gpCsv := GPListBasic.gpListToCsv(GPListBasic.gpBuildList(gpGraph, "pump", [gpPump]))
	gpCheck(gpCsv.find("\"a,b \"\"c\"\"\"") >= 0, "a comma and quotes force a quoted cell")
	var gpBack := GPListBasic.gpCsvToList(gpCsv)
	gpEq(str(gpBack[0]["note"]), "a,b \"c\"", "escaped cell round-trips byte for byte")


# ---- 5. header is the union across one category's schemas / 表头取同类别 schema 并集 ----

func gpTestColumnsUnionAcrossSchemas() -> void:
	# Two symbols in the SAME category declaring DIFFERENT fields — the realistic case.
	# 同一类别下两个图元声明了不同字段 —— 这才是真实情况。
	var gpA := _gpDef("LVALVE001", "valve", [_gpField("dn", GPPropertyDef.GPKind.GP_INT, 50)])
	var gpB := _gpDef("LVALVE002", "valve", [_gpField("actuator", GPPropertyDef.GPKind.GP_STRING, "")])
	var gpGraph := GPPIDGraph.new()
	gpGraph.gpNodes.append(_gpNode("V-1", "LVALVE001", {}))
	gpGraph.gpNodes.append(_gpNode("V-2", "LVALVE002", {}))
	var gpRows := GPListBasic.gpBuildList(gpGraph, "valve", [gpA, gpB])
	var gpCols := GPListBasic.gpColumns(gpRows)
	gpEq(gpCols.size(), 4, "tag + name + the union of both schemas")
	gpEq(gpCols[0], "tag", "tag is always the first column")
	gpEq(gpCols[1], "name", "name is always the second column")
	gpCheck(gpCols.has("dn") and gpCols.has("actuator"), "both schemas contribute a column")
	# A row missing a column exports BLANK rather than shifting the remaining cells left —
	# a shifted row would silently write valve A's value into valve B.
	# 缺失列的行导出为**空白**而非把后面的单元格左移 —— 左移会把 A 阀的值静默写进 B 阀。
	var gpBack := GPListBasic.gpCsvToList(GPListBasic.gpListToCsv(gpRows))
	gpEq(str(gpBack[0].get("dn", "<missing>")), "50", "valve A keeps its dn")
	gpEq(str(gpBack[0].get("actuator", "<missing>")), "", "valve A's absent column is blank")
	gpEq(str(gpBack[1].get("actuator", "<missing>")), "", "valve B keeps its own column")


# ---- 6. re-import writes what changed / 回灌写入改动 ----

func gpTestApplyListWritesChangedProps() -> void:
	var gpPump := _gpDef("LPUMP001", "pump", [
		_gpField("rated_flow", GPPropertyDef.GPKind.GP_FLOAT, 80.0),
	])
	var gpNode := _gpNode("P-1001", "LPUMP001", {})
	var gpGraph := GPPIDGraph.new()
	gpGraph.gpNodes.append(gpNode)
	var gpRows: Array[Dictionary] = [{"tag": "P-1001", "name": "磨矿给料泵", "rated_flow": "120.5"}]
	gpEq(GPListBasic.gpApplyList(gpGraph, gpRows, [gpPump]), 1, "exactly one node changed")
	gpEq(float(gpNode.gpProps.get("rated_flow", -1.0)), 120.5, "edited float written back")
	gpEq(str(gpNode.gpNames.get("zh_CN", "")), "磨矿给料泵", "name written to the fallback locale")


# ---- 7. THE round-trip invariant: an untouched export must change nothing ----
# ---- 7. 往返不变式：未改动的导出必须不产生任何变化 ----

func gpTestReimportOfUntouchedExportWritesNothing() -> void:
	var gpPump := _gpDef("LPUMP001", "pump", [
		_gpField("rated_flow", GPPropertyDef.GPKind.GP_FLOAT, 80.0),
	])
	var gpNode := _gpNode("P-1001", "LPUMP001", {})
	var gpGraph := GPPIDGraph.new()
	gpGraph.gpNodes.append(gpNode)
	var gpRows := GPListBasic.gpBuildList(gpGraph, "pump", [gpPump])
	var gpBack := GPListBasic.gpCsvToList(GPListBasic.gpListToCsv(gpRows))
	gpEq(GPListBasic.gpApplyList(gpGraph, gpBack, [gpPump]), 0,
		"re-importing an untouched export changes nothing")
	# gpProps.has(key) is the ONLY record of "never touched" (M8). If a naive re-import wrote
	# every column, this distinction would be gone forever.
	# gpProps.has(key) 是「从未动过」的**唯一**记录（M8）。若朴素回灌把每列都写回去，
	# 该区分就永久丢失了。
	gpEq(gpNode.gpProps.size(), 0, "gpProps stays empty — 'never touched' preserved")


# ---- 8. a blank cell means "follow the library default again" / 空单元格=重新跟随默认 ----

func gpTestBlankCellRestoresLibraryDefault() -> void:
	var gpPump := _gpDef("LPUMP001", "pump", [
		_gpField("rated_flow", GPPropertyDef.GPKind.GP_FLOAT, 80.0),
	])
	var gpNode := _gpNode("P-1001", "LPUMP001", {"rated_flow": 120.0})
	var gpGraph := GPPIDGraph.new()
	gpGraph.gpNodes.append(gpNode)
	var gpRows: Array[Dictionary] = [{"tag": "P-1001", "name": "x", "rated_flow": ""}]
	gpEq(GPListBasic.gpApplyList(gpGraph, gpRows, [gpPump]), 1, "clearing a cell counts as a change")
	gpEq(gpNode.gpProps.has("rated_flow"), false, "the override is erased, not set to zero")
	gpEq(float(GPPropertyResolver.gpEffectiveValue(gpPump.gpSchema, gpNode.gpProps, "rated_flow")),
		80.0, "the effective value falls back to the library default")


# ---- 9. safety: unknown tags and stray columns / 安全：未知位号与多余列 ----

func gpTestUnmatchedTagsAreReported() -> void:
	var gpPump := _gpDef("LPUMP001", "pump", [
		_gpField("rated_flow", GPPropertyDef.GPKind.GP_FLOAT, 80.0),
	])
	var gpGraph := GPPIDGraph.new()
	gpGraph.gpNodes.append(_gpNode("P-1001", "LPUMP001", {}))
	var gpRows: Array[Dictionary] = [{"tag": "P-9999", "name": "ghost", "rated_flow": "1"}]
	gpEq(GPListBasic.gpApplyList(gpGraph, gpRows, [gpPump]), 0,
		"a row whose tag matches nothing changes nothing")
	var gpUn := GPListBasic.gpUnmatchedTags(gpGraph, gpRows)
	gpEq(gpUn.size(), 1, "the unknown tag is reported")
	gpEq(gpUn[0], "P-9999", "the offending tag is named, not silently dropped")


func gpTestStrayColumnNeverInventsProperty() -> void:
	var gpPump := _gpDef("LPUMP001", "pump", [
		_gpField("rated_flow", GPPropertyDef.GPKind.GP_FLOAT, 80.0),
	])
	var gpNode := _gpNode("P-1001", "LPUMP001", {})
	var gpGraph := GPPIDGraph.new()
	gpGraph.gpNodes.append(gpNode)
	var gpRows: Array[Dictionary] = [{"tag": "P-1001", "name": "x", "bogus_column": "42"}]
	GPListBasic.gpApplyList(gpGraph, gpRows, [gpPump])
	gpEq(gpNode.gpProps.has("bogus_column"), false,
		"a column the schema does not declare is ignored, never invented")


# ---- 10. categories + real file export / 类别与真实落盘 ----

func gpTestCategoriesSortedAndExportWritesFiles() -> void:
	var gpPump := _gpDef("LPUMP001", "pump", [])
	var gpValve := _gpDef("LVALVE001", "valve", [])
	var gpGraph := GPPIDGraph.new()
	gpGraph.gpNodes.append(_gpNode("P-1", "LPUMP001", {}))
	gpGraph.gpNodes.append(_gpNode("V-1", "LVALVE001", {}))
	var gpCats := GPListBasic.gpCategories(gpGraph, [gpPump, gpValve])
	gpEq(gpCats.size(), 2, "both categories present")
	gpEq(gpCats[0], "pump", "categories sorted ascending")
	gpEq(gpCats[1], "valve", "pump precedes valve")

	var gpDir := "user://gp_test_list_basic"
	DirAccess.make_dir_recursive_absolute(gpDir)
	var gpPaths := GPListBasic.gpExportLists(gpGraph, gpDir, [gpPump, gpValve])
	gpEq(gpPaths.size(), 2, "one file per category written")
	gpCheck(gpPaths.has("pump") and gpPaths.has("valve"), "both paths returned")
	if gpPaths.has("valve"):
		var gpText := FileAccess.get_file_as_string(str(gpPaths["valve"]))
		gpCheck(gpText.begins_with("tag,name"), "written CSV starts with the tag/name header")
		gpCheck(gpText.find("V-1") >= 0, "written CSV carries the valve's tag")
	# Best-effort cleanup: the runner must not leave junk in the user directory.
	# 尽力清理：运行器不该在用户目录留下垃圾。
	var gpDa := DirAccess.open(gpDir)
	if gpDa != null:
		for gpF in gpDa.get_files():
			gpDa.remove(gpF)


# ---- 11. portable rule template .gptagrule.json / 可移植规则模板 ----

func gpTestRuleTemplateRoundTrip() -> void:
	var gpRules := GPProjectTagRules.gpDefaultRules()
	gpRules.gpSetMark("P", 1007)
	var gpText := GPTagRuleService.gpRulesToJson(gpRules)
	gpCheck(gpText.find("seq_marks") >= 0, "the template carries the high-water marks")
	var gpBack := GPTagRuleService.gpRulesFromJson(gpText)
	gpCheck(gpBack != null, "the template parses back")
	if gpBack != null:
		gpEq(int(gpBack.gpSeqMarks.get("P", 0)), 1007, "the high-water mark survives")
	# A template that is valid JSON but NOT an object must read as UNREADABLE, never as
	# factory defaults — silently falling back would make a company standard look applied
	# when it was not. (Invalid JSON takes the same guard via a null parse result; it is not
	# exercised here because JSON.parse_string logs an engine error, which GUT counts as a
	# failure — see GP_EXPECTED_ERRORS in tests/gut/test_gp_suites.gd.)
	# 能解析但**不是对象**的模板必须读作「读不了」，绝不能退化成出厂规则 ——
	# 静默回落会让一份公司标准看起来已生效，实则根本没有。（非法 JSON 走同一个判空分支；
	# 此处不实测是因为 JSON.parse_string 会打印引擎错误，而 GUT 会对未处理的错误判失败
	# —— 见 tests/gut/test_gp_suites.gd 的 GP_EXPECTED_ERRORS。）
	gpCheck(GPTagRuleService.gpRulesFromJson("[]") == null,
		"a non-object template yields null instead of factory rules")
