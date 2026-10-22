class_name GPDeliverablePrefs
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# Persist the last classified-export choices (output folder, filename prefix, per-list custom
# templates) in user://deliverable_export.cfg. UI calls this class; UI never touches FileAccess.
# 持久化上次分类导出选择（输出目录、文件名前缀、每类自定义模板）到
# user://deliverable_export.cfg。UI 调本类；UI 不直接碰 FileAccess。
#
# Why separate from settings.cfg / 为何独立于 settings.cfg：
# the export dialog owns this state; mixing it into the global settings file would make every
# unrelated settings write rewrite export paths, and would couple the dialog to Settings' load
# order. A tiny ConfigFile is simpler and can be deleted by the user.
# 导出对话框拥有此状态；混进全局 settings.cfg 会让每次无关设置写入都重写导出路径，并把对话框
# 耦合到 Settings 的加载顺序。一个独立小 ConfigFile 更简单，用户也可直接删除。
#
# Coding rule: every variable declares its type explicitly; every function is static.
# 编码规范：所有变量显式声明类型；函数全部静态。

const GP_CONFIG_PATH: String = "user://deliverable_export.cfg"
const GP_SECTION: String = "export"


# Load choices. Defaults are safe on first run.
# 读取选择；首次运行使用安全默认值。
static func gpLoad() -> Dictionary:
	return gpLoadFrom(GP_CONFIG_PATH)


# Load from an explicit path (tests use a temp file; the app uses gpLoad()).
# 从显式路径读取（测试用临时文件；应用用 gpLoad()）。
static func gpLoadFrom(gpPath: String) -> Dictionary:
	var gpOut: Dictionary = {
		"output_dir": gpDefaultOutputDir(),
		"name_prefix": "G-PID",
		"templates": {},
	}
	var gpCfg: ConfigFile = ConfigFile.new()
	if gpCfg.load(gpPath) != OK:
		return gpOut
	gpOut["output_dir"] = str(gpCfg.get_value(GP_SECTION, "output_dir",
		gpOut["output_dir"]))
	gpOut["name_prefix"] = str(gpCfg.get_value(GP_SECTION, "name_prefix",
		gpOut["name_prefix"]))
	var gpTpl: Variant = gpCfg.get_value(GP_SECTION, "templates", {})
	if gpTpl is Dictionary:
		gpOut["templates"] = (gpTpl as Dictionary).duplicate(true)
	return gpOut


# Save choices; returns OK or a ConfigFile error. / 保存选择。
static func gpSave(gpOutputDir: String, gpNamePrefix: String, gpTemplates: Dictionary) -> int:
	return gpSaveTo(GP_CONFIG_PATH, gpOutputDir, gpNamePrefix, gpTemplates)


# Save to an explicit path. / 保存到显式路径。
static func gpSaveTo(gpPath: String, gpOutputDir: String, gpNamePrefix: String,
		gpTemplates: Dictionary) -> int:
	var gpCfg: ConfigFile = ConfigFile.new()
	gpCfg.set_value(GP_SECTION, "output_dir", gpOutputDir)
	gpCfg.set_value(GP_SECTION, "name_prefix", gpNamePrefix)
	gpCfg.set_value(GP_SECTION, "templates", gpTemplates.duplicate(true))
	return gpCfg.save(gpPath)


# Default output folder under the user's Documents; user://exports is the fallback.
# 用户「文档」下的默认输出目录；回退到 user://exports。
static func gpDefaultOutputDir() -> String:
	var gpDocs: String = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if gpDocs.strip_edges() == "":
		return "user://exports"
	return gpDocs.path_join("G-PID 导出")


# Clear persisted choices (used by tests or a future "reset" button).
# 清除持久化选择（测试或未来「重置」按钮用）。
static func gpClear() -> void:
	if FileAccess.file_exists(GP_CONFIG_PATH):
		DirAccess.remove_absolute(GP_CONFIG_PATH)
