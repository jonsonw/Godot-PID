extends SceneTree
# Generate the two DRC CI fixtures (good / bad) as real *.pid.json archives.
# 生成 DRC CI 的两个夹具（好 / 坏）为真实 *.pid.json 存档。
#
# Usage / 用法:
#   Godot --headless --path . --script res://tools/make_drc_fixtures.gd
#
# The good fixture must pass every default-enabled rule: sheet number, title-block identity,
# frame on, no nodes/lines. The bad one adds a node whose symbol does not exist → an error.
# 好夹具必须通过所有默认启用的规则：图号、图签身份、图框开启、无图元/连线。坏夹具加一个
# 符号不存在的节点 → error。


func _initialize() -> void:
	var gpGood: GPSheet = _gpSheet("drc-good", "PID-9001", "DRC-GOOD")
	gpGood.gpGraph = GPPIDGraph.new()
	_write(gpGood, "res://tests/fixtures/drc_good.pid.json")
	var gpBad: GPSheet = _gpSheet("drc-bad", "PID-9002", "DRC-BAD")
	gpBad.gpGraph = GPPIDGraph.new()
	var gpN: GPPIDNode = gpBad.gpGraph.gpNewNode("n1", "MISSING_SYMBOL", "X-1",
		Vector2(100.0, 100.0))
	gpBad.gpGraph.gpAddNode(gpN)
	_write(gpBad, "res://tests/fixtures/drc_bad.pid.json")
	quit(0)


func _gpSheet(gpId: String, gpNo: String, gpTitle: String) -> GPSheet:
	var gpS: GPSheet = GPSheet.gpNew(gpId, gpNo, 0)
	gpS.gpWidthMM = 420.0
	gpS.gpHeightMM = 297.0
	gpS.gpFrameOn = true
	gpS.gpNumber = gpNo
	gpS.gpName = gpNo
	gpS.gpTitleBlock = GPSheet.gpDefaultTitleBlock()
	gpS._gpSetTitleField("drawing_no", gpNo)
	gpS._gpSetTitleField("drawing_title", gpTitle)
	gpS._gpSetTitleField("project", "DRC CI")
	gpS._gpSetTitleField("designed", "CI")
	gpS._gpSetTitleField("checked", "CI")
	gpS._gpSetTitleField("approved", "CI")
	return gpS


func _write(gpSheet: GPSheet, gpPath: String) -> void:
	var gpErr: int = GPProjectIO.gpWriteSheets([gpSheet], gpPath)
	if gpErr != OK:
		printerr("write failed: ", gpPath)
	else:
		print("WROTE: ", gpPath)
