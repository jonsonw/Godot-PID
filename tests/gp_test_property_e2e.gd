extends "res://tests/gp_test.gd"
# 阶段 3 验收项：属性系统「端到端」用例。
# Stage-3 acceptance: property-system end-to-end.
#   放置 → 改属性（命令层）→ 保存 → 重开 → 值仍在（经 GPPropertyResolver 取回）。
#   place → change attribute (command layer) → save → reopen → value still present
#   (resolved through GPPropertyResolver).
#
# 既有测试只覆盖半程：gp_test_attr_commands.gd 在内存里测了命令层改/撤属性，
# 但从未经过「保存→重开」持久化；gp_test_persist_roundtrip.gd 测了裸 gpProps 字典往返，
# 但只直接 poke 字典、不经过属性系统（schema / 命令 / 解析器）。
# 本文件把两段缝起来：用真实 EditService 改属性、落盘、重开、再用解析器证明
# 实例覆盖值存活且库默认值对未改字段仍生效。
# Existing tests only cover half the path: gp_test_attr_commands.gd exercises the command
# layer in memory (never persisted); gp_test_persist_roundtrip.gd checks the raw gpProps dict
# round-trips but bypasses the property system (no schema / command / resolver). This file
# stitches the two: edit via the real service, persist, reopen, then prove through the resolver
# that the instance override survives and the library default still applies to untouched fields.

const GP_TMP: String = "user://gp_test_property_e2e.pid.json"


# A typed property schema (TYPE LAYER) — what a symbol library would declare for the symbol
# we place below. Kept in memory across the reload so the resolver can re-apply it, exactly as
# the real app re-applies the library after reopening a drawing.
# 一份类型化属性 schema（类型层）—— 即下方所放图元在图元库里会声明的内容。
# 跨重开保留在内存中，以便解析器在重开后重新套用，正如真实 app 在重开图纸后重新套用库。
func _gpSchema() -> GPPropertySchema:
	var gpS: GPPropertySchema = GPPropertySchema.new()
	var gpRating: GPPropertyDef = GPPropertyDef.new()
	gpRating.gpKey = "rating"
	gpRating.gpKind = GPPropertyDef.GPKind.GP_ENUM
	gpRating.gpOptions = ["SIL-1", "SIL-2", "SIL-3"]
	gpRating.gpDefault = "SIL-1"
	var gpFlow: GPPropertyDef = GPPropertyDef.new()
	gpFlow.gpKey = "rated_flow"
	gpFlow.gpKind = GPPropertyDef.GPKind.GP_FLOAT
	gpFlow.gpDefault = 120.0
	gpFlow.gpUnit = "m3/h"
	var gpMaker: GPPropertyDef = GPPropertyDef.new()
	gpMaker.gpKey = "manufacturer"
	gpMaker.gpKind = GPPropertyDef.GPKind.GP_STRING
	gpMaker.gpDefault = "TBD"
	gpS.gpFields = [gpRating, gpFlow, gpMaker]
	return gpS


func _gpCleanup() -> void:
	var gpAbs: String = ProjectSettings.globalize_path(GP_TMP)
	if FileAccess.file_exists(gpAbs):
		DirAccess.remove_absolute(gpAbs)


# MAIN: the full property-system round-trip.
# 主用例：属性系统完整往返。
func gpTestPropertyE2ESaveReopenPreservesValues() -> void:
	_gpCleanup()
	var gpSchema: GPPropertySchema = _gpSchema()

	# 放置 (place): a symbol instance on the canvas (data-model placement).
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpN: GPPIDNode = gpG.gpNewNode("N1", "LPUMP003", "P-1001", Vector2(10, 20))
	gpG.gpAddNode(gpN)

	# 改属性 (change attribute): through the REAL edit-service command stack (the UI entry point).
	var gpSvc: GPEditService = GPEditService.new()
	gpSvc.gpBindGraph(gpG, GPIdGen.new(), GPTagRegistry.new())
	gpCheck(gpSvc.gpSetProperty("N1", "rating", "SIL-3"), "rating override is accepted")
	gpCheck(gpSvc.gpSetProperty("N1", "rated_flow", 250.0), "rated_flow override is accepted")

	# 保存 (save).
	var gpW: GPIOResult = GPProjectIO.gpWriteProjectResult(gpG, GP_TMP)
	gpCheck(gpW.gpIsOk(), "write should succeed: " + gpW.gpToString())
	if not gpW.gpIsOk():
		_gpCleanup()
		return

	# 重开 (reopen).
	var gpR: GPIOResult = GPProjectIO.gpReadProjectResult(GP_TMP)
	gpCheck(gpR.gpIsOk(), "read should succeed: " + gpR.gpToString())
	if not gpR.gpIsOk():
		_gpCleanup()
		return
	var gpG2: GPPIDGraph = gpR.gpPayload as GPPIDGraph
	var gpN2: GPPIDNode = gpG2.gpGetNode("N1")
	gpCheck(gpN2 != null, "the node survived the round-trip")
	if gpN2 == null:
		_gpCleanup()
		return

	# 值仍在 (value still there) — verified at the SYSTEM level via GPPropertyResolver.
	# The raw override is on disk...
	gpEq(str(gpN2.gpProps.get("rating", null)), "SIL-3", "raw override value persisted to disk")
	# ...and the resolver merges it over the library default (SIL-1).
	gpEq(GPPropertyResolver.gpEffectiveValue(gpSchema, gpN2.gpProps, "rating"), "SIL-3",
		"resolver returns the override, not the SIL-1 library default")
	gpCheck(GPPropertyResolver.gpIsOverridden(gpN2.gpProps, "rating"), "rating is flagged as overridden")
	# Type coercion on the way back: the float override survives as a float.
	gpEq(GPPropertyResolver.gpEffectiveValue(gpSchema, gpN2.gpProps, "rated_flow"), 250.0,
		"float override survives the round-trip and is type-coerced by the resolver")
	gpCheck(GPPropertyResolver.gpIsOverridden(gpN2.gpProps, "rated_flow"), "rated_flow is flagged as overridden")
	# A field never set must follow the library default — the type layer is the source of truth.
	gpEq(GPPropertyResolver.gpEffectiveValue(gpSchema, gpN2.gpProps, "manufacturer"), "TBD",
		"an untouched field falls back to the library default")
	gpCheck(not GPPropertyResolver.gpIsOverridden(gpN2.gpProps, "manufacturer"),
		"manufacturer is NOT overridden")
	gpEq(GPPropertyResolver.gpEffectiveProps(gpSchema, gpN2.gpProps).size(), 3,
		"the resolver exposes every effective value (overrides + defaults)")
	_gpCleanup()


# BONUS: the edit is undoable — undoing a property edit returns the instance to the library
# default. This proves the SYSTEM semantics (override-vs-default), not just raw storage.
# 附：该编辑可撤销 —— 撤销使实例回到库默认值，证明系统的「覆盖/默认」语义，而非一串裸存储。
func gpTestPropertySetIsUndoableToDefault() -> void:
	var gpSchema: GPPropertySchema = _gpSchema()
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("N1", "LPUMP003", "P-1001", Vector2(0, 0)))
	var gpSvc: GPEditService = GPEditService.new()
	gpSvc.gpBindGraph(gpG, GPIdGen.new(), GPTagRegistry.new())

	gpSvc.gpSetProperty("N1", "rating", "SIL-2")
	gpEq(GPPropertyResolver.gpEffectiveValue(gpSchema, gpG.gpGetNode("N1").gpProps, "rating"), "SIL-2",
		"after set, the effective value is the override")
	gpSvc.gpUndo()
	gpEq(GPPropertyResolver.gpEffectiveValue(gpSchema, gpG.gpGetNode("N1").gpProps, "rating"), "SIL-1",
		"after undo, the effective value returns to the library default")
	gpCheck(not GPPropertyResolver.gpIsOverridden(gpG.gpGetNode("N1").gpProps, "rating"),
		"after undo the override key is gone")
	gpSvc.gpRedo()
	gpEq(GPPropertyResolver.gpEffectiveValue(gpSchema, gpG.gpGetNode("N1").gpProps, "rating"), "SIL-2",
		"redo re-applies the override")
