class_name GPSymbolNamingTest
extends GPGTest
# Copyright © 2026 Jonson Wang
# Guards the project-wide symbol id rule (L/C + category + 3-digit sequence).
# 守护项目级图元 id 规则（L/C + 类别 + 三位序号）。
#
# Two things are defended here / 这里守住两件事：
#   1. the rule itself — parse / validate / allocate behave as documented
#      规则本身 —— 解析 / 校验 / 分配的行为与文档一致
#   2. the DATA still follows the rule — every built-in def must carry a canonical id, and
#      the legacy alias table must match the map the generator wrote to disk
#      数据仍符合规则 —— 每个内置图元都须持有规范 id，且旧 id 别名表须与生成器落盘的映射一致


func gpTestCanonicalIdsValidate() -> void:
	for gpId in ["LVALVE001", "CPUMP003", "LINSTRUMENT009", "LGENERAL001", "LTANK001"]:
		gpCheck(GPSymbolNaming.gpIsValid(gpId), "canonical id accepted: %s" % gpId)


func gpTestMalformedIdsRejected() -> void:
	# Wrong source code, short sequence, lower case, empty, trailing junk.
	# 来源码错误、序号位数不足、小写、空串、尾部多余字符。
	for gpId in ["XVALVE001", "LVALVE01", "lvalve001", "", "LVALVE0011", "LVALVE00A",
			"L_VALVE001", "P_CentrifugalPump_001"]:
		gpCheck(not GPSymbolNaming.gpIsValid(gpId), "malformed id rejected: %s" % gpId)


func gpTestParseSplitsTheThreeParts() -> void:
	var gpP: Dictionary = GPSymbolNaming.gpParse("LINSTRUMENT009")
	gpEq(gpP.get("source", ""), "L", "source code parsed")
	gpEq(gpP.get("category", ""), "INSTRUMENT", "category code parsed")
	gpEq(gpP.get("seq", -1), 9, "sequence parsed as a number")
	gpEq(GPSymbolNaming.gpParse("nonsense"), {}, "unparseable id yields an empty dict")


func gpTestCategoryCode() -> void:
	gpEq(GPSymbolNaming.gpCategoryCode("valve"), "VALVE", "plain category upper-cased")
	gpEq(GPSymbolNaming.gpCategoryCode("instrument"), "INSTRUMENT", "long category kept whole")
	gpEq(GPSymbolNaming.gpCategoryCode("instrument_signal"), "INSTRUMENTSIGNAL",
		"underscore dropped so the code stays one token")
	gpEq(GPSymbolNaming.gpCategoryCode(""), "GENERAL", "empty category falls back")
	gpEq(GPSymbolNaming.gpCategoryCode("离心泵"), "GENERAL",
		"CJK-only category falls back (no ASCII letters)")


func gpTestPrefix() -> void:
	gpEq(GPSymbolNaming.gpPrefix("L", "valve"), "LVALVE", "library valve prefix")
	gpEq(GPSymbolNaming.gpPrefix("C", "tank"), "CTANK", "custom tank prefix")


func gpTestAllocateStartsAt001() -> void:
	var gpTaken: Array[String] = []
	gpEq(GPSymbolNaming.gpAllocate("C", "valve", gpTaken), "CVALVE001",
		"an empty family starts at 001")


func gpTestAllocateContinuesAfterTheHighest() -> void:
	var gpTaken: Array[String] = ["LVALVE001", "LVALVE002", "LVALVE008"]
	gpEq(GPSymbolNaming.gpAllocate("L", "valve", gpTaken), "LVALVE009",
		"allocation continues after the HIGHEST sequence, not after the count")


func gpTestAllocateNeverReusesARetiredNumber() -> void:
	# LVALVE001 was deleted. Reusing its number would make an old *.pid.json resolve to a
	# DIFFERENT symbol that now occupies 001 — the whole reason the sequence is monotonic.
	# LVALVE001 已被删除。复用其号码会让旧 *.pid.json 解析到「现在占用 001」的另一个图元
	# —— 这正是序号必须单调递增的理由。
	var gpTaken: Array[String] = ["LVALVE002", "LVALVE003"]
	gpEq(GPSymbolNaming.gpAllocate("L", "valve", gpTaken), "LVALVE004",
		"the gap at 001 is NOT reused")


func gpTestAllocateRefusesUnknownSourceAndExhaustedFamily() -> void:
	var gpTaken: Array[String] = []
	gpEq(GPSymbolNaming.gpAllocate("X", "valve", gpTaken), "", "unknown source code refused")
	var gpFull: Array[String] = ["CVALVE999"]
	gpEq(GPSymbolNaming.gpAllocate("C", "valve", gpFull), "",
		"a family that used all 999 slots refuses rather than overflowing into 4 digits")


func gpTestMaxSeqIgnoresOtherFamilies() -> void:
	var gpTaken: Array[String] = ["LVALVE007", "CPUMP002", "LINSTRUMENT009", "LGENERAL001"]
	gpEq(GPSymbolNaming.gpMaxSeq("LVALVE", gpTaken), 7, "valve family max")
	gpEq(GPSymbolNaming.gpMaxSeq("CPUMP", gpTaken), 2, "custom pump family max")
	gpEq(GPSymbolNaming.gpMaxSeq("CTANK", gpTaken), 0, "unknown family reports zero")


func gpTestLegacyIdsMigrate() -> void:
	gpEq(GPSymbolNaming.gpMigrate("P_CentrifugalPump_001"), "LPUMP003",
		"the centrifugal pump kept its identity across the rule change")
	gpEq(GPSymbolNaming.gpMigrate("TK_Tank_001"), "LTANK001", "tank migrated")
	gpCheck(GPSymbolNaming.gpIsLegacy("GV_GateValve_001"), "known legacy id recognised")


func gpTestUnknownIdsPassThroughUnchanged() -> void:
	# User symbols authored before the rule have no alias; silently renumbering them would
	# break that user's saved files.
	# 规则变更前用户自建的图元没有别名条目；静默重新编号会破坏该用户的存档。
	gpEq(GPSymbolNaming.gpMigrate("my_valve"), "my_valve", "user symbol left alone")
	gpEq(GPSymbolNaming.gpMigrate("离心泵"), "离心泵", "CJK user symbol left alone")
	gpCheck(not GPSymbolNaming.gpIsLegacy("my_valve"), "user symbol is not flagged legacy")


func gpTestLegacyLookupFindsTheRenamedSymbol() -> void:
	# The whole point of the alias table: an old *.pid.json must still open.
	# 别名表的全部意义：旧 *.pid.json 必须仍能打开。
	var gpD: GPSymbolDef = GPSymbolLibrary.gpFindById("P_CentrifugalPump_001")
	gpCheck(gpD != null, "a pre-rule id still resolves through the library")
	if gpD != null:
		gpEq(gpD.gpId, "LPUMP003", "and resolves to the renamed definition")


func gpTestEveryBuiltinDefFollowsTheRule() -> void:
	var gpDefs: Array[GPSymbolDef] = GPSymbolPackIso_10628.gpDefs()
	gpCheck(gpDefs.size() > 0, "the ISO pack is not empty")
	for gpD in gpDefs:
		gpCheck(GPSymbolNaming.gpIsValid(gpD.gpId), "built-in id follows the rule: %s" % gpD.gpId)
		gpEq(GPSymbolNaming.gpParse(gpD.gpId).get("source", ""), "L",
			"library symbols are flagged L: %s" % gpD.gpId)


func gpTestBuiltinIdsAreUnique() -> void:
	var gpSeen: Array[String] = []
	for gpD in GPSymbolPackIso_10628.gpDefs():
		gpCheck(not gpSeen.has(gpD.gpId), "no duplicate id in the pack: %s" % gpD.gpId)
		gpSeen.append(gpD.gpId)


func gpTestAliasTableMatchesTheGeneratedMap() -> void:
	# The generator writes assets/symbol_packs/iso_10628/legacy_id_map.json on every run.
	# If that map and the compiled-in table drifted, an old file would resolve differently
	# in a fresh build than in the generator's own output.
	# 生成器每次运行都会写出 assets/symbol_packs/iso_10628/legacy_id_map.json。
	# 若该映射与编译进代码的常量表脱节，旧文件在新构建中的解析结果就会与生成器输出不一致。
	var gpPath: String = "res://assets/symbol_packs/iso_10628/legacy_id_map.json"
	if not FileAccess.file_exists(gpPath):
		gpCheck(false, "legacy id map is missing: %s" % gpPath)
		return
	var gpF: FileAccess = FileAccess.open(gpPath, FileAccess.READ)
	if gpF == null:
		gpCheck(false, "legacy id map cannot be read")
		return
	var gpText: String = gpF.get_as_text()
	gpF.close()
	var gpParsed: Variant = JSON.parse_string(gpText)
	if not (gpParsed is Dictionary):
		gpCheck(false, "legacy id map is not a JSON object")
		return
	var gpMap: Dictionary = gpParsed as Dictionary
	gpEq(gpMap.size(), GPSymbolNaming.GP_LEGACY_ALIASES.size(),
		"the map and the compiled table hold the same number of aliases")
	for gpOld in gpMap.keys():
		gpEq(GPSymbolNaming.gpMigrate(gpOld), String(gpMap[gpOld]),
			"alias agrees for %s" % gpOld)
