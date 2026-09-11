extends "res://tests/gp_test.gd"
# M12 library drift & migration: a drawing saved against an OLDER library must detect that the
# library moved on, carry values across a field rename, and keep (never silently sweep) values
# whose field vanished from the library.
# M12 库变更与迁移：按旧库保存的图纸必须能察觉库已变、字段改名时带过取值、
# 且字段已删除的取值要保留（绝不静默清扫）。


# ---- helpers / 辅助构造 ----

func _gpField(gpKeyVal: String, gpKindVal: int, gpRename: String = "") -> GPPropertyDef:
	var f := GPPropertyDef.new()
	f.gpKey = gpKeyVal
	f.gpKind = gpKindVal
	f.gpDefault = ""
	f.gpRenameFrom = gpRename
	return f


func _gpDef(gpIdVal: String, gpFields: Array[GPPropertyDef]) -> GPSymbolDef:
	var d := GPSymbolDef.new()
	d.gpId = gpIdVal
	var sc := GPPropertySchema.new()
	for f in gpFields:
		sc.gpFields.append(f)
	d.gpSchema = sc
	return d


func _gpNode(gpSymbolIdVal: String, gpProps: Dictionary) -> GPPIDNode:
	var n := GPPIDNode.new()
	n.gpSymbolId = gpSymbolIdVal
	n.gpProps = gpProps.duplicate()
	return n


# ---- 1. fingerprints reflect the field set / 指纹随字段集合变化 ----

func gpTestFingerprintReflectsFieldSet() -> void:
	var pumpA := _gpDef("LPUMP001", [_gpField("rated_flow", GPPropertyDef.GPKind.GP_FLOAT)])
	var fps := GPPropertyResolver.gpFingerprintsFor([pumpA])
	gpCheck(fps.has("LPUMP001"), "fingerprint keyed by symbol id")
	# Adding a field to the library must change the fingerprint.
	# 给库加一个字段，指纹必须改变。
	var pumpB := _gpDef("LPUMP001", [_gpField("rated_flow", GPPropertyDef.GPKind.GP_FLOAT),
			_gpField("material", GPPropertyDef.GPKind.GP_ENUM)])
	var fps2 := GPPropertyResolver.gpFingerprintsFor([pumpB])
	gpCheck(str(fps2["LPUMP001"]) != str(fps["LPUMP001"]),
		"adding a field changes the fingerprint")


# ---- 2. drift = changed fields + vanished symbols / 变更=改字段+消失图元 ----

func gpTestDriftDetectsChangedAndVanished() -> void:
	var pumpOld := _gpDef("LPUMP001", [_gpField("rated_flow", GPPropertyDef.GPKind.GP_FLOAT)])
	var valveOld := _gpDef("LVALVE001", [_gpField("dn", GPPropertyDef.GPKind.GP_INT)])
	var gpStored := GPPropertyResolver.gpFingerprintsFor([pumpOld, valveOld])
	# New library: pump gained a field (changed), valve removed entirely (vanished).
	# 新库：pump 多了字段（变更），valve 彻底被删（消失）。
	var pumpNew := _gpDef("LPUMP001", [_gpField("rated_flow", GPPropertyDef.GPKind.GP_FLOAT),
			_gpField("material", GPPropertyDef.GPKind.GP_ENUM)])
	var gpLive := GPPropertyResolver.gpFingerprintsFor([pumpNew])
	var gpDrift := GPPropertyResolver.gpDriftedSymbols(gpLive, gpStored)
	gpEq(gpDrift.size(), 2, "pump changed + valve vanished = 2 drifted symbols")
	# Sorted ascending as plain strings: "LPUMP001" (P…) precedes "LVALVE001" (V…).
	# 按字符串升序排序：「LPUMP001」(P…) 在「LVALVE001」(V…) 之前。
	gpEq(gpDrift[0], "LPUMP001", "changed symbol reported first (alphabetical)")
	gpEq(gpDrift[1], "LVALVE001", "vanished symbol reported second (alphabetical)")


# ---- 3. migration carries the value across a rename / 迁移把取值带过改名 ----

func gpTestMigrateRenamedField() -> void:
	# Old library stored the value under "flow"; the new library renamed it to "rated_flow".
	# 旧库把值存在 "flow"，新库改名为 "rated_flow"。
	var newDef := _gpDef("LPUMP001", [_gpField("rated_flow", GPPropertyDef.GPKind.GP_FLOAT, "flow")])
	var gpNode := _gpNode("LPUMP001", {"flow": 100.0, "material": "CS"})
	var gpGraph := GPPIDGraph.new()
	gpGraph.gpNodes.append(gpNode)
	var gpChanged := GPPropertyResolver.gpMigrateGraph(gpGraph, [newDef])
	gpEq(gpChanged, 1, "exactly one instance migrated")
	gpEq(gpNode.gpProps.has("flow"), false, "old key removed after migration")
	gpEq(gpNode.gpProps.get("rated_flow", -1.0), 100.0, "value moved to the new key")
	gpEq(gpNode.gpProps.get("material"), "CS", "unrelated field left untouched")


# ---- 4. orphans are counted, then removed only on request / 孤儿先计数、再按需清除 ----

func gpTestOrphanCountAndClean() -> void:
	var gpDef := _gpDef("LPUMP001", [_gpField("rated_flow", GPPropertyDef.GPKind.GP_FLOAT)])
	var gpNode := _gpNode("LPUMP001", {"rated_flow": 80.0, "legacy_field": "x", "obsolete": 1})
	var gpGraph := GPPIDGraph.new()
	gpGraph.gpNodes.append(gpNode)
	gpEq(GPPropertyResolver.gpOrphanCount(gpGraph, [gpDef]), 2,
		"two values whose field vanished are orphans")
	# Cleaning is the ONLY way an orphan disappears — an explicit user action, never automatic.
	# 清除是孤儿值**唯一**的消失途径：明确的用户操作，绝不自动。
	var gpRemoved := GPPropertyResolver.gpCleanOrphans(gpNode, gpDef.gpSchema)
	gpEq(gpRemoved, 2, "clean removed both orphaned values")
	gpEq(gpNode.gpProps.has("legacy_field"), false, "legacy_field dropped")
	gpEq(gpNode.gpProps.has("obsolete"), false, "obsolete dropped")
	gpEq(gpNode.gpProps.has("rated_flow"), true, "live field kept")
	gpEq(GPPropertyResolver.gpOrphanCount(gpGraph, [gpDef]), 0, "no orphans remain after clean")


# ---- 5. fingerprint snapshot round-trips through save / load / 指纹随存盘往返 ----

func gpTestFingerprintRoundTrip() -> void:
	var gpGraph := GPPIDGraph.new()
	gpGraph.gpMeta = {}
	gpGraph.gpSchemaFingerprints = {"LPUMP001": "fp-abc"}
	var gpDict := gpGraph.gpToDict()
	gpCheck(gpDict["meta"].has("schema_fingerprints"),
		"fingerprint snapshot embedded inside meta (v1 readers ignore it)")
	gpEq(str(gpDict["meta"]["schema_fingerprints"].get("LPUMP001")), "fp-abc",
		"fingerprint value preserved in the dictionary")
	var gpRestored := GPPIDGraph.gpFromDict(gpDict)
	gpEq(str(gpRestored.gpSchemaFingerprints.get("LPUMP001")), "fp-abc",
		"fingerprint restored on load")
