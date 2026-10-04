class_name GPExporterRegistry
extends RefCounted

# Registry of everything the user can export. Adding a format means adding ONE entry here;
# the file dialog, the status line and the dispatch all read from this table.
# 用户可导出的一切的注册表。新增一种格式只需在此**加一条**；
# 文件对话框、状态行与分发逻辑都从这张表读取。
#
# WHY A REGISTRY / 为何用注册表（§8.1）：
# before this, "which formats exist" was encoded by call sites — a new format meant touching
# the menu definition, the action router and the writer. Three places that must agree is three
# places to disagree. With one table, the menu entries can be GENERATED from it, and the
# dispatcher never learns a new format's name.
# 此前「存在哪些格式」由调用点编码 —— 新增格式要改菜单定义、动作路由与写出器三处。
# 三处必须一致，就是三处可能不一致。有了这张表，菜单项可由它**生成**，
# 而分发器永远不需要知道新格式的名字。
#
# NOTE ON THE CURRENT STEP / 关于当前这一步的说明：
# the three menu definitions (quick_toolbar x2, menu_bar) still list their rows literally,
# because they are compile-time constants. They now mirror this table and are asserted against
# it in tests, so the next format only needs a row here plus one literal row each — and the
# test fails loudly if the two ever drift.
# 三处菜单定义（quick_toolbar 两处、menu_bar 一处）仍以字面量列出各行，
# 因为它们是编译期常量。现在它们与这张表**互为镜像**并在测试中被断言，
# 故下一种格式只需在此加一行、在各菜单各加一行 —— 若两者漂移，测试会大声失败。

# Export kinds. / 导出种类。
const GP_PROJECT: String = "project"
const GP_LIBRARY: String = "library"
const GP_CONFIG: String = "config"
const GP_DEXPI: String = "dexpi"

# kind -> {label_key, extension, filter_key, needs_sheet}
# `filter_key`: the i18n key for this format's file-dialog filter label. The dialog reads it
# before EVERY popup (see file_coordinator._gpApplyDialogFilters) — a format whose filter the
# dialog never learns cannot be saved under its own extension, which is a silent feature.
# `filter_key`：该格式在文件对话框中过滤器标签的 i18n 键。对话框在**每次**弹窗前读取它
# （见 file_coordinator._gpApplyDialogFilters）—— 对话框学不到某格式的过滤器，
# 该格式就无法按自身扩展名保存，那是一个静默的功能。
# `needs_sheet`: DEXPI writes a <Drawing> extent, so it cannot work without a sheet.
# `needs_sheet`：DEXPI 要写 <Drawing> 的范围，故缺图纸则无法工作。
const GP_EXPORTERS: Dictionary = {
	GP_PROJECT: {"label_key": "menu.export_project", "extension": "pid.json",
		"filter_key": "doc.pid_filter", "needs_sheet": false},
	GP_LIBRARY: {"label_key": "menu.export_library", "extension": "pid.json",
		"filter_key": "doc.pid_filter", "needs_sheet": false},
	GP_CONFIG: {"label_key": "menu.export_config", "extension": "pid.json",
		"filter_key": "doc.pid_filter", "needs_sheet": false},
	GP_DEXPI: {"label_key": "menu.export_dexpi", "extension": "pid.xml",
		"filter_key": "doc.dexpi_filter", "needs_sheet": true},
}


# Every registered kind, in a stable order.
# 全部已注册的 kind，按稳定顺序。
static func gpAllKinds() -> Array[String]:
	var gpOut: Array[String] = []
	for gpKey in GP_EXPORTERS.keys():
		gpOut.append(str(gpKey))
	gpOut.sort()
	return gpOut


static func gpMetaOf(gpKind: String) -> Dictionary:
	var gpRow: Variant = GP_EXPORTERS.get(gpKind)
	if gpRow is Dictionary:
		return (gpRow as Dictionary).duplicate(true)
	return {}


static func gpIsKnown(gpKind: String) -> bool:
	return GP_EXPORTERS.has(gpKind)


static func gpLabelKeyOf(gpKind: String) -> String:
	return str(gpMetaOf(gpKind).get("label_key", ""))


static func gpExtensionOf(gpKind: String) -> String:
	return str(gpMetaOf(gpKind).get("extension", ""))


# The file-dialog wildcard for a kind ("*.pid.xml"). Empty for an unknown kind, so the caller
# can fall back instead of adding a meaningless "*." filter.
# 某格式对应的文件对话框通配符（"*.pid.xml"）。未知格式返回空串，
# 调用方可据此回退，而不是加一个无意义的 "*." 过滤器。
static func gpFilterPatternOf(gpKind: String) -> String:
	var gpExt: String = gpExtensionOf(gpKind)
	return "" if gpExt.is_empty() else "*." + gpExt


# The i18n key naming this format's file-dialog filter label.
# 该格式在文件对话框中过滤器标签的 i18n 键。
static func gpFilterKeyOf(gpKind: String) -> String:
	return str(gpMetaOf(gpKind).get("filter_key", ""))


# Finish a user-typed or pre-filled export file name so the registry's extension lands on
# disk EXACTLY ONCE. Two real defects are closed here, both observed on disk as
# "W6.pid.pid.xml":
#   1. a bare typed name ("W6") got the extension appended — still correct;
#   2. a name already ending in ".pid" ("W6.pid", whether typed or produced by taking the
#      basename of "W6.pid.json") used to get ".pid.xml" appended whole -> the DOUBLE
#      extension. A trailing ".pid" is an incomplete container name, so it is FINISHED
#      (".xml" is added), not doubled.
# 把用户手打或预填的导出文件名补全，使注册表扩展名**恰好出现一次**。这里关闭两个真实缺陷，
# 二者都曾在磁盘上以「W6.pid.pid.xml」的形态出现：
#   1. 手打裸名（「W6」）补全扩展名 —— 仍然正确；
#   2. 已以「.pid」结尾的名字（「W6.pid」，无论手打还是取「W6.pid.json」的 basename 得来）
#      此前会整段追加「.pid.xml」→ 双扩展名。结尾的「.pid」是**未写完**的容器名，
#      应补完（加「.xml」），而非翻倍。
# Examples / 示例：
#   gpFinishName("/a/W6", "pid.xml")      -> "/a/W6.pid.xml"
#   gpFinishName("/a/W6.pid", "pid.xml")  -> "/a/W6.pid.xml"   (was "W6.pid.pid.xml")
#   gpFinishName("/a/W6.pid.xml", "pid.xml") -> unchanged       (already complete)
#   gpFinishName("/a/W6", "png")          -> "/a/W6.png"
static func gpFinishName(gpPath: String, gpExt: String) -> String:
	if gpExt.is_empty() or gpPath.is_empty():
		return gpPath
	var gpName: String = gpPath.get_file()
	if gpName.ends_with(".pid") and gpExt.begins_with("pid."):
		return gpPath + gpExt.trim_prefix("pid")
	if not gpName.contains("."):
		return gpPath + "." + gpExt
	return gpPath


static func gpNeedsSheet(gpKind: String) -> bool:
	return bool(gpMetaOf(gpKind).get("needs_sheet", false))


# Dispatch one export. The UI calls this and never learns which writer ran.
# 分发一次导出。界面调用它，且永远不需要知道跑的是哪个写出器。
static func gpExport(gpKind: String, gpPath: String, gpGraph: GPPIDGraph,
		gpPacks: Array, gpSheet: GPSheet = null) -> GPIOResult:
	if not gpIsKnown(gpKind):
		return GPIOResult.gpFailure("export.unknown_kind", "status.export_fail", gpKind)
	if gpPath.is_empty():
		return GPIOResult.gpFailure("io.write_failed", "status.export_fail", gpPath)
	if gpKind == GP_DEXPI:
		# DEXPI needs the sheet for the Diagram extent, and it runs its own pre-flight: a
		# refused export is reported with the reasons, not as a bare failure.
		# DEXPI 需要图纸以给出 Diagram 范围，且它跑自己的预检：
		# 被拒的导出会附带原因报告，而非一个裸失败。
		if gpSheet == null:
			return GPIOResult.gpFailure("dexpi.no_sheet", "status.export_fail", gpPath)
		return GPDexpiExporter.gpExportSheet(gpGraph, gpSheet, gpPath)
	return GPProjectExport.gpExportToFile(gpKind, gpPath, gpGraph, gpPacks)
