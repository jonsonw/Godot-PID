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
