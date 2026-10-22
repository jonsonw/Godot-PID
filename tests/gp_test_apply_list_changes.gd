extends "res://tests/gp_test.gd"
# P6 acceptance: command-level guarantees of the list import — one command per sheet,
# exact undo, edge attrs, and the GPEditService public execution seam.
# P6 验收：清单导入的命令级保证 —— 每图一条命令、精确撤销、边属性、GPEditService 公共执行缝。

func _gpNode(gpId: String, gpTag: String) -> GPPIDNode:
	var gpN: GPPIDNode = GPPIDNode.new()
	gpN.gpInstanceId = gpId
	gpN.gpSymbolId = "DPUMP001"
	gpN.gpTag = gpTag
	gpN.gpNames["zh"] = "泵"
	gpN.gpProps["material"] = "碳钢"
	return gpN


func _gpEdge(gpId: String, gpTag: String) -> GPPIDEdge:
	var gpE: GPPIDEdge = GPPIDEdge.new()
	gpE.gpInstanceId = gpId
	gpE.gpTag = gpTag
	gpE.gpKind = GPPIDEdge.GP_PROCESS
	gpE.gpAttrs["dn"] = "DN80"
	gpE.gpAttrs["medium"] = "水"
	return gpE


func _gpChange(gpKind: String, gpId: String, gpKey: String, gpNew: Variant,
		gpClear: bool = false, gpLocale: String = "zh") -> Dictionary:
	return {"kind": gpKind, "target_id": gpId, "key": gpKey, "locale": gpLocale,
		"new": gpNew, "clear": gpClear}


func gpTestOneCommandUndoesNameAndProperty() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpN: GPPIDNode = _gpNode("p1", "P-101")
	gpG.gpAddNode(gpN)
	var gpCmd: GPApplyListChangesCommand = GPApplyListChangesCommand.new([
		_gpChange("node_name", "p1", "name", "泵 A"),
		_gpChange("node_prop", "p1", "material", "316L"),
	])
	var gpCtx: GPCommandContext = GPCommandContext.new(gpG)
	gpCheck(gpCmd.gpExecute(gpCtx), "command executes")
	gpEq(str(gpN.gpNames.get("zh", "")), "泵 A", "name changed")
	gpEq(str(gpN.gpProps.get("material", "")), "316L", "property changed")
	gpCmd.gpUndo(gpCtx)
	gpEq(str(gpN.gpNames.get("zh", "")), "泵", "undo restores name")
	gpEq(str(gpN.gpProps.get("material", "")), "碳钢", "undo restores property")
	gpCmd.gpRedo(gpCtx)
	gpEq(str(gpN.gpProps.get("material", "")), "316L", "redo re-applies")


func gpTestEdgeAttrClearAndUndo() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpE: GPPIDEdge = _gpEdge("e1", "L-1")
	gpG.gpAddEdge(gpE)
	var gpCmd: GPApplyListChangesCommand = GPApplyListChangesCommand.new([
		_gpChange("edge_attr", "e1", "dn", null, true),
		_gpChange("edge_attr", "e1", "medium", "矿浆"),
	])
	var gpCtx: GPCommandContext = GPCommandContext.new(gpG)
	gpCheck(gpCmd.gpExecute(gpCtx), "edge command executes")
	gpCheck(not gpE.gpAttrs.has("dn"), "blank clears edge attr")
	gpEq(str(gpE.gpAttrs.get("medium", "")), "矿浆", "edge attr changed")
	gpCmd.gpUndo(gpCtx)
	gpEq(str(gpE.gpAttrs.get("dn", "")), "DN80", "undo restores edge attr")
	gpEq(str(gpE.gpAttrs.get("medium", "")), "水", "undo restores second edge attr")


func gpTestPerSheetCommandsAreIndependent() -> void:
	var gpG1: GPPIDGraph = GPPIDGraph.new()
	var gpG2: GPPIDGraph = GPPIDGraph.new()
	var gpN1: GPPIDNode = _gpNode("p1", "P-101")
	var gpN2: GPPIDNode = _gpNode("p2", "P-201")
	gpG1.gpAddNode(gpN1)
	gpG2.gpAddNode(gpN2)
	var gpC1: GPApplyListChangesCommand = GPApplyListChangesCommand.new(
		[_gpChange("node_prop", "p1", "material", "316L")])
	var gpC2: GPApplyListChangesCommand = GPApplyListChangesCommand.new(
		[_gpChange("node_prop", "p2", "material", "304")])
	var gpCtx1: GPCommandContext = GPCommandContext.new(gpG1)
	var gpCtx2: GPCommandContext = GPCommandContext.new(gpG2)
	gpCheck(gpC1.gpExecute(gpCtx1), "sheet 1 command")
	gpCheck(gpC2.gpExecute(gpCtx2), "sheet 2 command")
	gpC1.gpUndo(gpCtx1)
	gpEq(str(gpN1.gpProps.get("material", "")), "碳钢", "sheet 1 undone")
	gpEq(str(gpN2.gpProps.get("material", "")), "304", "sheet 2 untouched")


func gpTestStalePreviewIsSkipped() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpN: GPPIDNode = _gpNode("p1", "P-101")
	gpG.gpAddNode(gpN)
	gpN.gpProps["material"] = "不锈钢"
	var gpCmd: GPApplyListChangesCommand = GPApplyListChangesCommand.new([{
		"kind": "node_prop", "target_id": "p1", "key": "material", "locale": "zh",
		"old": "碳钢", "new": "316L", "clear": false,
	}])
	var gpCtx: GPCommandContext = GPCommandContext.new(gpG)
	gpCheck(not gpCmd.gpExecute(gpCtx), "stale change does not create an undo step")
	gpEq(gpCmd.gpStale.size(), 1, "stale change is reported")
	gpEq(str(gpN.gpProps.get("material", "")), "不锈钢", "stale change does not overwrite")


func gpTestEditServiceExecutesCommand() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpN: GPPIDNode = _gpNode("p1", "P-101")
	gpG.gpAddNode(gpN)
	var gpSvc: GPEditService = GPEditService.new()
	gpSvc.gpBindGraph(gpG, GPIdGen.new())
	var gpCmd: GPApplyListChangesCommand = GPApplyListChangesCommand.new(
		[_gpChange("node_prop", "p1", "material", "316L")])
	gpCheck(gpSvc.gpExecuteCommand(gpCmd), "service executes the command")
	gpEq(str(gpN.gpProps.get("material", "")), "316L", "service applied")
	gpCheck(gpSvc.gpUndo(), "service undo")
	gpEq(str(gpN.gpProps.get("material", "")), "碳钢", "service undo restored")
	gpCheck(not gpSvc.gpExecuteCommand(null), "null command refused")
