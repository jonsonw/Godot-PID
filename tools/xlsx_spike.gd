extends SceneTree
# P2 visual spike: build a real workbook, read it back, and write it for LibreOffice rendering.
# P2 可视化探针：构建真实工作簿、读回、并落盘供 LibreOffice 渲染。
func _initialize() -> void:
	var out := "/Users/macbook/DSH/Godot-PID/过程文件/xlsx_spike.xlsx"
	var sheets: Array = [
		{
			"name": "管线一览表",
			"rows": [
				["序号", "管线号", "介质", "长度(m)", "阀门"],
				["1", "L-1", "矿浆", 12.5, "V-301"],
				["2", "L-2", "水", 8.0, ""],
			],
			"header_rows": 1,
			"widths": [8.0, 16.0, 14.0, 12.0, 16.0],
			"freeze_rows": 1,
			"auto_filter": "A1:E3",
			"landscape": true,
		},
		{
			"name": "设备一览表",
			"rows": [
				["位号", "名称", "数量", "材质"],
				["P-101", "离心泵", 1, "碳钢"],
				["T-201", "储罐", 1, "304不锈钢"],
			],
			"header_rows": 1,
			"widths": [14.0, 18.0, 8.0, 14.0],
		},
	]
	var err := GPXlsxBuilder.gpBuildToPath(out, sheets)
	print("BUILD_ERR=", err, " SIZE=", FileAccess.get_file_as_bytes(out).size())
	var read := GPXlsxPackage.gpReadArchive(out)
	print("READ_OK=", read.get("ok", false), " ERROR=", read.get("error", ""))
	if bool(read.get("ok", false)):
		var entries: Dictionary = read["entries"] as Dictionary
		var wb := GPXlsxPackage.gpWorkbook(entries)
		print("WB=", wb)
		print("SHEETS=", GPXlsxReader.gpSheetNames(entries))
		for s in GPXlsxReader.gpSheetNames(entries):
			var d := GPXlsxReader.gpSheetByName(entries, s)
			print("SHEET ", s, " PATH=", d.get("path", ""))
			var rows := GPXlsxReader.gpReadSheet(entries, str(d.get("path", "")))
			print("  ROWS=", rows.size(), " A2=", GPXlsxReader.gpTextAt(entries, str(d.get("path", "")), "A2"))
	quit(0)
