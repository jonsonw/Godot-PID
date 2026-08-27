class_name GPSymbolLibrary
extends RefCounted

# Symbol library: discovers and loads all symbol packs.
# 符号库：发现并加载所有图元包。
# Auto-discovers packs from src/core/symbol_packs/ directory.
# 自动发现 src/core/symbol_packs/ 目录下的所有图元包。
# Coding rule: every variable must declare its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Session-scoped defs registered at runtime (e.g. exported from the symbol editor).
# 运行期注册的会话级图元定义（例如由图元编辑器导出）。
# Kept in memory only.
# 仅驻留内存。
static var _gpExtraDefs: Array[GPSymbolDef] = []

# Cached default definitions to avoid reloading on every call.
# 缓存默认定义，避免每次调用都重新加载。
static var _gpCachedDefs: Array[GPSymbolDef] = []
static var _gpCacheValid: bool = false

# Directory where user-authored symbol packs are persisted across sessions.
# 用户自建图元包的跨会话持久化目录（由符号编辑器导出时写入）。
const GP_USER_PACKS_DIR: String = "user://symbol_packs"


# Return the default built-in symbol definitions.
# 返回默认内置图元定义。
static func gpDefaultDefs() -> Array[GPSymbolDef]:
	if _gpCacheValid:
		return _gpCachedDefs
	_gpCachedDefs = _gpLoadAllPacks()
	_gpCacheValid = true
	# Anything the user authored in this session comes last so it is easy to spot.
	# 用户本次会话新建的图元排在最后，便于识别。
	_gpCachedDefs.append_array(_gpExtraDefs)
	return _gpCachedDefs


# Load all symbol packs from src/core/symbol_packs/.
# 从 src/core/symbol_packs/ 加载所有图元包。
static func _gpLoadAllPacks() -> Array[GPSymbolDef]:
	var gpOut: Array[GPSymbolDef] = []
	# Load ISO 10628 pack (25 symbols).
	# 加载 ISO 10628 图元包（25 个图元）。
	var gpIsoPack: Array[GPSymbolDef] = GPSymbolPackIso_10628.gpDefs()
	gpOut.append_array(gpIsoPack)
	# Load IEC 62424 / open-pid-icons pack (6 symbols).
	# 加载 IEC 62424 / open-pid-icons 图元包（6 个图元）。
	var gpIecPack: Array[GPSymbolDef] = GPSymbolPackOpenPidIcons.gpDefs()
	gpOut.append_array(gpIecPack)
	return gpOut


# Register runtime symbol definitions (symbol editor export path).
# 注册运行期图元定义（图元编辑器导出路径）。
# Re-registering an existing id replaces it, so re-exporting the same symbol updates in place.
# 重复注册同一 id 会覆盖原有项，因此重新导出同名图元即为原地更新。
static func gpRegisterDefs(gpDefs: Array[GPSymbolDef]) -> void:
	for gpD in gpDefs:
		var gpIdx: int = _gpIndexOfId(gpD.gpId)
		if gpIdx >= 0:
			_gpExtraDefs[gpIdx] = gpD
		else:
			_gpExtraDefs.append(gpD)
	# Invalidate cache so next call reloads.
	# 使缓存失效，下次调用时重新加载。
	_gpCacheValid = false


# Drop all runtime-registered definitions (used by tests and "reset library" actions).
# 清空所有运行期注册的定义（供测试与「重置图元库」使用）。
static func gpClearRegistered() -> void:
	_gpExtraDefs.clear()
	_gpCacheValid = false


# Read every persisted user pack from GP_USER_PACKS_DIR as GPSymbolPack objects.
# 把 GP_USER_PACKS_DIR 下所有持久化的用户图元包以 GPSymbolPack 对象读出。
# No registration: this is the shared reader used by both gpLoadUserPacks (which
# then registers the symbols into the live library) and gpUserPacks (which hands
# them to the save/export path so they can be embedded into the *.pid.json file).
# 不做注册：这是被 gpLoadUserPacks（随后把图元注册进活动图元库）与 gpUserPacks
#（交给存盘/导出路径、以便嵌入 *.pid.json）共用的读取器。
static func _gpReadUserPackFiles() -> Array[GPSymbolPack]:
	var gpPacks: Array[GPSymbolPack] = []
	# Nothing to read if the directory was never created.
	# 目录从未创建过则无内容可读。
	if not DirAccess.dir_exists_absolute(GP_USER_PACKS_DIR):
		return gpPacks
	var gpDir: DirAccess = DirAccess.open(GP_USER_PACKS_DIR)
	if gpDir == null:
		return gpPacks
	gpDir.list_dir_begin()
	var gpFileName: String = gpDir.get_next()
	while gpFileName != "":
		# Only consider top-level .json files (each is one exported symbol pack).
		# 只处理顶层 .json 文件（每个文件即一个导出的图元包）。
		if not gpDir.current_is_dir() and gpFileName.ends_with(".json"):
			var gpPath: String = "%s/%s" % [GP_USER_PACKS_DIR, gpFileName]
			var gpText: String = _gpReadFile(gpPath)
			if gpText != "":
				var gpJson: Variant = JSON.parse_string(gpText)
				if gpJson is Dictionary:
					var gpPack: GPSymbolPack = GPSymbolPack.new()
					gpPack.gpFromDict(gpJson as Dictionary)
					gpPacks.append(gpPack)
		gpFileName = gpDir.get_next()
	gpDir.list_dir_end()
	return gpPacks


# Return the user-authored symbol packs currently persisted in GP_USER_PACKS_DIR.
# 返回当前持久化在 GP_USER_PACKS_DIR 的用户自建图元包。
# The save/export path calls this to embed custom symbols into the *.pid.json so the
# file is self-contained and re-openable on any machine without the separate
# user://symbol_packs/ files (data sovereignty).
# 存盘/导出路径调用它把自定义图元嵌入 *.pid.json，使文件自包含、可在任意机器
# 重新打开而无需单独的 user://symbol_packs/ 文件（数据主权）。
static func gpUserPacks() -> Array[GPSymbolPack]:
	return _gpReadUserPackFiles()


# Load every persisted user pack from GP_USER_PACKS_DIR back into the live library.
# 把 GP_USER_PACKS_DIR 下所有持久化的用户图元包读回活动图元库。
# Called once at startup (see main_window._ready) so symbols authored in a previous
# session re-appear in the left palette and on the canvas after a restart.
# 启动时调用一次（见 main_window._ready），使上一会话中自建的图元在重启后
# 重新出现在左侧图元库与画布中。
# Returns the number of symbol definitions restored.
# 返回恢复出的图元定义数量。
static func gpLoadUserPacks() -> int:
	var gpPacks: Array[GPSymbolPack] = _gpReadUserPackFiles()
	var gpRestoredDefs: Array[GPSymbolDef] = []
	for gpPack in gpPacks:
		for gpSym in gpPack.gpSymbols:
			gpRestoredDefs.append(gpSym)
	# Register in one batch so the cache is invalidated only once.
	# 一次性批量注册，使缓存仅失效一次。
	if gpRestoredDefs.size() > 0:
		gpRegisterDefs(gpRestoredDefs)
	return gpRestoredDefs.size()


# Read a UTF-8 text file fully; returns "" on any failure (missing / unreadable).
# 完整读取一个 UTF-8 文本文件；任何失败（缺失/不可读）均返回空串。
static func _gpReadFile(gpPath: String) -> String:
	var gpF: FileAccess = FileAccess.open(gpPath, FileAccess.READ)
	if gpF == null:
		return ""
	var gpText: String = gpF.get_as_text()
	gpF.close()
	return gpText


# Look up one definition by id across built-ins, packs and runtime registrations.
# 跨内置图元、图元包与运行期注册按 id 查找单个定义。
static func gpFindById(gpId: String) -> GPSymbolDef:
	for gpD in gpDefaultDefs():
		if gpD.gpId == gpId:
			return gpD
	return null


# Internal: index of a runtime-registered def by id, or -1.
# 内部：按 id 查找运行期注册定义的下标，找不到返回 -1。
static func _gpIndexOfId(gpId: String) -> int:
	for gpI in range(_gpExtraDefs.size()):
		if _gpExtraDefs[gpI].gpId == gpId:
			return gpI
	return -1


# Group the default defs by category. The left palette injects one collapsible
# section per category from this map.
# 按类目分组默认图元。左栏据此为每个类目注入一个可折叠分组。
static func list_by_category() -> Dictionary:
	var gpOut: Dictionary = {}
	for gpD in gpDefaultDefs():
		if not gpOut.has(gpD.gpCategory):
			gpOut[gpD.gpCategory] = []
		gpOut[gpD.gpCategory].append(gpD)
	return gpOut


# Fuzzy match by display name / id / category (case-insensitive substring).
# 按显示名 / id / 类目做不区分大小写的子串匹配。
static func search(gpQ: String) -> Array[GPSymbolDef]:
	var gpOut: Array[GPSymbolDef] = []
	var gpNeedle: String = gpQ.strip_edges().to_lower()
	if gpNeedle == "":
		return gpDefaultDefs()
	for gpD in gpDefaultDefs():
		var gpHay: String = "%s %s %s" % [gpD.gpDisplayName, gpD.gpId, gpD.gpCategory]
		if gpHay.to_lower().contains(gpNeedle):
			gpOut.append(gpD)
	return gpOut
