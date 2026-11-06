extends Node
# Copyright © 2026 Jonson Wang
#
# Minimal headless CLI (ADR-39 E06/E07): `check` runs the SAME DRC engine as the GUI and exits
# with a machine-readable status. This is the first slice — export/bench can follow the same
# scene-launch pattern.
# 最小 headless CLI（ADR-39 E06/E07）：`check` 跑与 GUI **同一套** DRC 引擎，并以机器可读状态退出。
# 这是第一刀 —— export/bench 可沿用同一 scene 启动方式。
#
# Run / 运行：
#   Godot --headless --path . res://tools/gp_cli.tscn -- check \
#     --project path/to/file.pid.json [--report /tmp/drc.json]
#
# Exit codes / 退出码：
#   0 = no un-waived errors; 1 = blocked by errors; 2 = usage / load failure.
#   0 = 无未豁免 error；1 = 被 error 阻断；2 = 用法 / 载入失败。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。


func _ready() -> void:
	# Install symbol persistence before anything reads user packs: `check`/`export` embed them in
	# the emitted file, and GPSymbolLibrary (core) reaches the disk only through this seam.
	# 在任何读取用户图元包之前装入持久化：`check`/`export` 会把它们嵌入输出文件，而
	# GPSymbolLibrary（core）只经本缝触达磁盘。
	GPSymbolPackStore.gpInstall()
	var gpArgs: PackedStringArray = OS.get_cmdline_user_args()
	if gpArgs.is_empty():
		_gpUsage()
		get_tree().quit(2)
		return
	var gpCmd: String = str(gpArgs[0])
	match gpCmd:
		"check":
			_gpCheck(gpArgs)
		"export":
			_gpExport(gpArgs)
		"bench":
			_gpBench(gpArgs)
		"smoke":
			print("gpid-cli smoke: ok")
			get_tree().quit(0)
		"--help", "-h", "help":
			_gpUsage()
			get_tree().quit(0)
		_:
			printerr("unknown command: " + gpCmd)
			_gpUsage()
			get_tree().quit(2)


func _gpUsage() -> void:
	print("gpid-cli — G-PID headless checks")
	print("  check  --project <file.pid.json> [--report <out.json>]")
	print("  export --project <file.pid.json> --format <pdf|dxf|dexpi|project> --out <file|dir>")
	print("  bench  --project <file.pid.json> [--iterations N]")
	print("  smoke")
	print("exit: 0 ok / 1 DRC errors / 2 usage or load failure")


# One named option from the user args, or a fallback.
# 从用户参数中取一个具名选项，或回退值。
func _gpOpt(gpArgs: PackedStringArray, gpName: String, gpDefault: String = "") -> String:
	for gpI in range(gpArgs.size() - 1):
		if str(gpArgs[gpI]) == gpName:
			return str(gpArgs[gpI + 1])
	return gpDefault


func _gpCheck(gpArgs: PackedStringArray) -> void:
	var gpPath: String = _gpOpt(gpArgs, "--project", "")
	if gpPath == "":
		printerr("check: --project is required")
		_gpUsage()
		get_tree().quit(2)
		return
	var gpRead: GPIOResult = GPProjectIO.gpReadSheets(gpPath)
	if not gpRead.gpIsOk():
		printerr("check: cannot read project: " + str(gpRead.gpDetail))
		get_tree().quit(2)
		return
	var gpSheets: Array = gpRead.gpPayload as Array
	if gpSheets.is_empty():
		printerr("check: project has no sheets")
		get_tree().quit(2)
		return
	var gpDefs: Array[GPSymbolDef] = _gpDefsFor(gpSheets)
	var gpStd: GPProjectStandard = _gpStdOf(gpSheets)
	var gpFindings: Array[GPFinding] = GPDrcEngine.gpRunProject(gpSheets, gpDefs, gpStd)
	var gpMeta: Dictionary = {
		"mode": "project",
		"doc_hash": GPExportGate.gpDocHash(gpSheets),
		"rules_hash": GPExportGate.gpRulesHash(gpStd),
	}
	var gpJson: String = GPDRCReport.gpToJson(gpFindings, gpMeta)
	var gpReport: String = _gpOpt(gpArgs, "--report", "")
	if gpReport != "":
		var gpDir: String = gpReport.get_base_dir()
		var gpBase: String = gpReport.get_file().get_basename()
		var gpWritten: String = GPDRCReportFile.gpWriteJson(gpFindings, gpDir, gpBase, gpMeta)
		if gpWritten == "":
			printerr("check: cannot write report: " + gpReport)
			get_tree().quit(2)
			return
	# JSON to stdout regardless, so a caller can pipe it even without --report.
	# 无论是否 --report 都向 stdout 输出 JSON，方便调用方直接管道。
	print(gpJson)
	if GPDrcEngine.gpHasBlocking(gpFindings):
		printerr("check: blocked by un-waived DRC errors")
		get_tree().quit(1)
	else:
		get_tree().quit(0)


# Built-ins + every embedded user pack, so the CLI sees the same symbols the GUI shows.
# 内置图元 + 每个内嵌用户包，使 CLI 与 GUI 看到同一套符号。
func _gpDefsFor(gpSheets: Array) -> Array[GPSymbolDef]:
	var gpDefs: Array[GPSymbolDef] = GPSymbolLibrary.gpDefaultDefs()
	var gpSeen: Dictionary = {}
	for gpD in gpDefs:
		if gpD != null:
			gpSeen[gpD.gpId] = true
	for gpSheetRaw in gpSheets:
		var gpSheet: GPSheet = gpSheetRaw as GPSheet
		if gpSheet == null or gpSheet.gpGraph == null:
			continue
		for gpPack in gpSheet.gpGraph.gpUserSymbolPacks:
			if gpPack == null:
				continue
			for gpD in gpPack.gpSymbols:
				if gpD != null and not gpSeen.has(gpD.gpId):
					gpDefs.append(gpD)
					gpSeen[gpD.gpId] = true
	return gpDefs


func _gpStdOf(gpSheets: Array) -> GPProjectStandard:
	if gpSheets.is_empty():
		return null
	var gpFirst: GPSheet = gpSheets[0] as GPSheet
	if gpFirst != null and gpFirst.gpGraph != null:
		return gpFirst.gpGraph.gpStandard
	return null


func _gpLoad(gpPath: String) -> Array:
	var gpRead: GPIOResult = GPProjectIO.gpReadSheets(gpPath)
	if not gpRead.gpIsOk():
		printerr("cannot read project: " + str(gpRead.gpDetail))
		return []
	var gpSheets: Array = gpRead.gpPayload as Array
	if gpSheets.is_empty():
		printerr("project has no sheets")
	return gpSheets


func _gpExport(gpArgs: PackedStringArray) -> void:
	var gpPath: String = _gpOpt(gpArgs, "--project", "")
	var gpFormat: String = _gpOpt(gpArgs, "--format", "pdf")
	var gpOut: String = _gpOpt(gpArgs, "--out", "")
	if gpPath == "" or gpOut == "":
		printerr("export: --project and --out are required")
		get_tree().quit(2)
		return
	if not GPExporterRegistry.gpIsKnown(gpFormat):
		printerr("export: unknown format: " + gpFormat)
		get_tree().quit(2)
		return
	var gpSheets: Array = _gpLoad(gpPath)
	if gpSheets.is_empty():
		get_tree().quit(2)
		return
	var gpDefs: Array[GPSymbolDef] = _gpDefsFor(gpSheets)
	var gpStd: GPProjectStandard = _gpStdOf(gpSheets)
	# PDF / DXF / DEXPI are delivery artefacts: same DRC gate as the GUI.
	# PDF / DXF / DEXPI 是交付物：与 GUI 同一 DRC 闸门。
	if gpFormat in [GPExporterRegistry.GP_PDF, GPExporterRegistry.GP_DXF,
			GPExporterRegistry.GP_DEXPI]:
		var gpGate: Dictionary = GPExportGate.gpCheck(gpSheets, gpDefs, gpStd)
		if bool(gpGate.get("blocked", false)):
			var gpJson: String = GPDRCReport.gpToJson(gpGate.get("findings", []) as Array[GPFinding],
				{"mode": "project", "doc_hash": str(gpGate.get("doc_hash", "")),
				"rules_hash": str(gpGate.get("rules_hash", ""))})
			print(gpJson)
			printerr("export: blocked by un-waived DRC errors")
			get_tree().quit(1)
			return
	var gpExt: String = GPExporterRegistry.gpExtensionOf(gpFormat)
	var gpOK: int = 0
	var gpFail: int = 0
	var gpFiles: Array[String] = []
	var gpMulti: bool = gpSheets.size() > 1
	if gpMulti:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(gpOut))
	for gpI in range(gpSheets.size()):
		var gpSheet: GPSheet = gpSheets[gpI] as GPSheet
		var gpTarget: String = GPExporterRegistry.gpFinishName(gpOut, gpExt)
		if gpMulti:
			var gpBase: String = gpPath.get_file().get_basename()
			gpTarget = gpOut.path_join("%s-sheet-%d.%s" % [gpBase, gpI + 1, gpExt])
		var gpRes: GPIOResult = GPExporterRegistry.gpExport(gpFormat, gpTarget,
			gpSheet.gpGraph if gpSheet != null else null, GPSymbolLibrary.gpUserPacks(), gpSheet)
		if gpRes.gpIsOk():
			gpOK += 1
			gpFiles.append(gpTarget)
		else:
			gpFail += 1
			printerr("export failed: " + gpTarget + " (" + str(gpRes.gpDetail) + ")")
	print(JSON.stringify({"ok": gpOK, "failed": gpFail, "files": gpFiles}, "\t"))
	get_tree().quit(0 if gpFail == 0 else 1)


func _gpBench(gpArgs: PackedStringArray) -> void:
	var gpPath: String = _gpOpt(gpArgs, "--project", "")
	if gpPath == "":
		printerr("bench: --project is required")
		get_tree().quit(2)
		return
	var gpSheets: Array = _gpLoad(gpPath)
	if gpSheets.is_empty():
		get_tree().quit(2)
		return
	var gpDefs: Array[GPSymbolDef] = _gpDefsFor(gpSheets)
	var gpStd: GPProjectStandard = _gpStdOf(gpSheets)
	var gpIter: int = maxi(1, int(_gpOpt(gpArgs, "--iterations", "5")))
	var gpTimes: Array[int] = []
	var gpLast: Array[GPFinding] = []
	for _i in range(gpIter):
		var gpT0: int = Time.get_ticks_usec()
		gpLast = GPDrcEngine.gpRunProject(gpSheets, gpDefs, gpStd)
		gpTimes.append(Time.get_ticks_usec() - gpT0)
	gpTimes.sort()
	var gpSum: int = 0
	for gpT in gpTimes:
		gpSum += gpT
	print(JSON.stringify({
		"iterations": gpIter,
		"min_us": gpTimes[0],
		"max_us": gpTimes[gpTimes.size() - 1],
		"avg_us": int(gpSum / gpTimes.size()),
		"findings": gpLast.size(),
	}, "\t"))
	get_tree().quit(0)
