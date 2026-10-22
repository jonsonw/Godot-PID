extends "res://tests/gp_test.gd"
# P5 acceptance: export-dialog helper logic and preference persistence. The real dialog is
# visually accepted through tools/export_dialog_preview.tscn; these are the deterministic
# pieces that must not depend on a window server.
# P5 验收：导出对话框的辅助逻辑与偏好持久化。真实对话框由 tools/export_dialog_preview.tscn
# 做可视化验收；这里只钉不依赖窗口服务器的确定部分。

func _gpTempCfg() -> String:
	return "user://gp_test_export_prefs_%d.cfg" % Time.get_ticks_usec()


func gpTestDefaultListIds() -> void:
	var gpIds: Array[String] = GPExportListsDialog.gpDefaultListIds()
	gpEq(gpIds.size(), 4, "four lists")
	gpEq(gpIds, ["line", "equipment", "instrument", "valve"], "list order")
	gpEq(GPDeliverableFields.gpListIds(), gpIds, "dialog order follows the field catalogue")


func gpTestCheckedListIds() -> void:
	var gpOut: Array[String] = GPExportListsDialog.gpCheckedListIds({
		"line": true, "equipment": false, "instrument": true, "valve": false,
	})
	gpEq(gpOut, ["line", "instrument"], "only checked lists survive, in catalogue order")
	gpEq(GPExportListsDialog.gpCheckedListIds({}).size(), 0, "empty map -> no lists")


func gpTestCountSummary() -> void:
	gpEq(GPExportListsDialog.gpCountSummary({"line": 2, "equipment": 3}),
		"line=2 equipment=3 instrument=0 valve=0", "count summary fills missing lists with 0")


func gpTestPrefsRoundTrip() -> void:
	var gpPath: String = _gpTempCfg()
	var gpTpl: Dictionary = {"line": "/tmp/my line.xlsx", "valve": "/tmp/v.xlsx"}
	gpEq(GPDeliverablePrefs.gpSaveTo(gpPath, "/tmp/out", "W6", gpTpl), OK,
		"prefs save")
	var gpLoaded: Dictionary = GPDeliverablePrefs.gpLoadFrom(gpPath)
	gpEq(str(gpLoaded.get("output_dir", "")), "/tmp/out", "output dir round-trip")
	gpEq(str(gpLoaded.get("name_prefix", "")), "W6", "prefix round-trip")
	var gpLoadedTpl: Dictionary = gpLoaded.get("templates", {}) as Dictionary
	gpEq(str(gpLoadedTpl.get("line", "")), "/tmp/my line.xlsx", "template round-trip")
	gpEq(str(gpLoadedTpl.get("valve", "")), "/tmp/v.xlsx", "second template round-trip")
	if FileAccess.file_exists(gpPath):
		DirAccess.remove_absolute(gpPath)


func gpTestPrefsDefaultsOnMissingFile() -> void:
	var gpLoaded: Dictionary = GPDeliverablePrefs.gpLoadFrom(_gpTempCfg())
	gpCheck(str(gpLoaded.get("output_dir", "")) != "", "default output dir is non-empty")
	gpEq(str(gpLoaded.get("name_prefix", "")), "G-PID", "default prefix")
	gpCheck((gpLoaded.get("templates", {}) as Dictionary).is_empty(), "no templates by default")


func gpTestDialogClassAndMenuKeys() -> void:
	var gpDlg: GPExportListsDialog = GPExportListsDialog.new()
	gpCheck(gpDlg != null, "dialog class constructs")
	gpDlg.free()
	gpCheck(I18n.GP_STRINGS.has("menu.export_lists_xlsx"), "Excel menu key exists")
	gpCheck(I18n.GP_STRINGS.has("menu.project_export_list"), "CSV menu key still exists")
	gpCheck(I18n.GP_STRINGS.has("xlsx.dialog_title"), "dialog title key exists")
	gpCheck(I18n.gpTr("menu.project_export_list").find("CSV") >= 0,
		"old list action is relabelled CSV")


func gpTestMenuStructureMovesCsvUnderExport() -> void:
	var gpFileItems: Array = GPPIDMenuBar.GP_MENUS["menu.file"] as Array
	var gpExportItems: Array = []
	for gpItemRaw in gpFileItems:
		if not (gpItemRaw is Dictionary):
			continue
		var gpItem: Dictionary = gpItemRaw as Dictionary
		if str(gpItem.get("title", "")) == "menu.export":
			gpExportItems = gpItem.get("items", []) as Array
			break
	gpCheck(not gpExportItems.is_empty(), "file menu has the export submenu")
	var gpHasExcel: bool = false
	var gpHasCsv: bool = false
	for gpItemRaw in gpExportItems:
		if gpItemRaw is Array:
			var gpEntry: Array = gpItemRaw as Array
			if gpEntry.size() >= 2 and str(gpEntry[1]) == "export_lists_xlsx":
				gpHasExcel = true
			if gpEntry.size() >= 2 and str(gpEntry[1]) == "project_export_list":
				gpHasCsv = true
	gpCheck(gpHasExcel, "Excel list action lives under Export")
	gpCheck(gpHasCsv, "old CSV action lives under Export")
	var gpProjectItems: Array = GPPIDMenuBar.GP_MENUS["menu.project"] as Array
	for gpItemRaw in gpProjectItems:
		if gpItemRaw is Array:
			var gpEntry: Array = gpItemRaw as Array
			gpCheck(gpEntry.size() < 2 or str(gpEntry[1]) != "project_export_list",
				"CSV action is no longer in the Project menu")
