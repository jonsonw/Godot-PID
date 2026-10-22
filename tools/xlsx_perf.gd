extends SceneTree
# P7 performance probe: build N equipment rows and export through the shipped template.
# P7 性能探针：构建 N 行设备并走随包模板导出。
const OUT := "/Users/macbook/DSH/Godot-PID/过程文件/xlsx_p7/perf"
func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	for n in [5000]:
		var s := GPSheet.new()
		s.gpId = "s%d" % n
		s.gpName = "Perf %d" % n
		s.gpIndex = 0
		s.gpLabelMode = GPSheet.GP_LABEL_ZH
		s.gpTitleBlock = GPSheet.gpDefaultTitleBlock()
		s.gpTitleBlock["project"]["value"] = {"zh": "PERF", "en": "PERF"}
		s.gpTitleBlock["company"]["value"] = {"zh": "G-PID", "en": "G-PID"}
		s.gpGraph = GPPIDGraph.new()
		for i in range(n):
			var node := GPPIDNode.new()
			node.gpInstanceId = "p%d" % i
			node.gpSymbolId = "DPUMP001"
			node.gpTag = "P-%d" % (i + 1)
			node.gpPosition = Vector2(100 + (i % 100) * 10, 100 + (i / 100) * 10)
			s.gpGraph.gpAddNode(node)
		var t0 := Time.get_ticks_msec()
		var res: GPIOResult = GPXlsxExport.gpExportLists([s], GPSymbolLibrary.gpDefaultDefs(), {
			"lists": ["equipment"], "output_dir": OUT, "name_prefix": "PERF%d" % n,
			"locale": "zh", "include_empty": true,
			"type_labels": {"DPUMP001": "离心泵"},
		})
		var ms := Time.get_ticks_msec() - t0
		print("PERF n=", n, " ok=", res.gpIsOk(), " ms=", ms,
			" files=", ((res.gpPayload as Dictionary).get("files", []) as Array).size())
	quit(0)
