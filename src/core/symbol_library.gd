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

# Number of built-in defs currently in _gpCachedDefs; everything at or after this
# index is a runtime-registered extra that gpRegisterDefs / gpClearRegistered patch
# in place (no pack reload).
# 当前 _gpCachedDefs 中内置图元的数量；此下标及之后均为运行期注册的额外项，
# 由 gpRegisterDefs / gpClearRegistered 原地修补（无需重载图元包）。
static var _gpBuiltinCount: int = 0

# Directory where user-authored symbol packs are persisted across sessions.
# 用户自建图元包的跨会话持久化目录（由符号编辑器导出时写入）。
const GP_USER_PACKS_DIR: String = "user://symbol_packs"


# Return the default built-in symbol definitions.
# 返回默认内置图元定义。
# IMPORTANT: the returned array has a STABLE IDENTITY — it is refreshed in place
# (clear + re-append) instead of being replaced by a brand-new array. Every caller
# that captured an earlier reference (main window, left palette, graph binder)
# therefore transparently observes later registrations.
# 重要：返回数组的身份是「稳定的」——它以原地方式刷新（清空 + 重新追加）而非整体替换。
# 因此任何持有早期引用的调用方（主窗口、左图元库、图绑定器）都能透明地看到后续注册。
# Returning a fresh array here would silently freeze those holders on stale
# GPSymbolDef objects, and no amount of downstream re-binding could recover them.
# 若此处改为返回新数组，那些持有者会静默地停留在过期的 GPSymbolDef 对象上，
# 下游无论如何重绑都无法挽回。
static func gpDefaultDefs() -> Array[GPSymbolDef]:
	if not _gpCacheValid:
		_gpRebuildCache()
	return _gpCachedDefs


# Rebuild the cached defs array in place, preserving its identity.
# 原地重建缓存定义数组，保持其身份不变。
# Built-ins first, then user-authored defs, so custom symbols are easy to spot.
# 先内置图元，再用户自建图元，便于识别自定义图元。
# _gpBuiltinCount records where the extra segment begins so later in-place updates
# (gpRegisterDefs / gpClearRegistered) can patch the SAME array instead of reloading
# every pack — that reload froze headless validation and is an O(n^2) regression in the
# editor when several symbols are exported in a row.
# _gpBuiltinCount 记录额外段起点，使后续原地更新（gpRegisterDefs / gpClearRegistered）
# 能就地修补同一数组而非重载所有包——该重载会冻结 headless 校验，也是编辑器里连续
# 导出多个图元时的 O(n^2) 性能回归。
static func _gpRebuildCache() -> void:
	var gpBuiltin: Array[GPSymbolDef] = _gpLoadAllPacks()
	_gpCachedDefs.clear()
	_gpCachedDefs.append_array(gpBuiltin)
	_gpBuiltinCount = _gpCachedDefs.size()
	_gpCachedDefs.append_array(_gpExtraDefs)
	_gpCacheValid = true


# Load all symbol packs from src/core/symbol_packs/.
# 从 src/core/symbol_packs/ 加载所有图元包。
static func _gpLoadAllPacks() -> Array[GPSymbolDef]:
	var gpOut: Array[GPSymbolDef] = []
	# Load ISO 10628 pack (25 symbols).
	# 加载 ISO 10628 图元包（25 个图元）。
	var gpIsoPack: Array[GPSymbolDef] = GPSymbolPackIso_10628.gpDefs()
	# Decision D3: ISO library symbols are built-in (read-only). The in-place editor derives a
	# custom_<id> copy instead of overwriting them, so flag them here at load time.
	# 决策 D3：ISO 库图元为内置（只读）。就地编辑器派生 custom_<id> 副本而非覆盖，
	# 故在加载时标记。
	for gpD in gpIsoPack:
		gpD.gpBuiltin = true
	gpOut.append_array(gpIsoPack)
	return gpOut


# Register runtime symbol definitions (symbol editor export path).
# 注册运行期图元定义（图元编辑器导出路径）。
# Re-registering an existing id replaces it, so re-exporting the same symbol updates in place.
# 重复注册同一 id 会覆盖原有项，因此重新导出同名图元即为原地更新。
static func gpRegisterDefs(gpDefs: Array[GPSymbolDef]) -> void:
	# Ensure the cache exists before patching it in place.
	# 原地修补前确保缓存已存在。
	if not _gpCacheValid:
		_gpRebuildCache()
	for gpD in gpDefs:
		var gpIdx: int = _gpIndexOfId(gpD.gpId)
		if gpIdx >= 0:
			# Replace in BOTH the extra slot and the cached array (same identity), so
			# every holder of the array reference transparently observes the new object.
			# 同时替换额外槽与缓存数组（同一身份），使持有该数组引用的调用方都能
			# 透明看到新对象。
			_gpExtraDefs[gpIdx] = gpD
			_gpCachedDefs[_gpBuiltinCount + gpIdx] = gpD
		else:
			# Append to BOTH so every holder of the array identity sees it immediately.
			# 同时追加到两处，使持有该数组身份的调用方立即看到。
			_gpExtraDefs.append(gpD)
			_gpCachedDefs.append(gpD)
	# The cached array is already fresh — no full pack reload needed.
	# 缓存数组已是最新，无需全量重载图元包。
	_gpCacheValid = true


# Drop all runtime-registered definitions (used by tests and "reset library" actions).
# 清空所有运行期注册的定义（供测试与「重置图元库」使用）。
static func gpClearRegistered() -> void:
	_gpExtraDefs.clear()
	# Keep only the built-in segment of the cached array (same identity), so holders
	# observe the reset without a full pack reload.
	# 仅保留缓存数组中的内置段（同一身份），使持有者无需全量重载即可看到重置。
	_gpCachedDefs.resize(_gpBuiltinCount)
	_gpCacheValid = true


# Delete a user-authored symbol from the library entirely: drop it from the runtime
# registrations AND delete its persisted pack file so it does not re-appear on restart.
# 彻底删除一个用户自建图元：从运行期注册移除，并删除其持久化包文件，使其重启后不再出现。
# Returns true only when a user symbol was actually removed; returns false if the id is
# unknown or belongs to a built-in (read-only) symbol, which must never be deleted.
# 仅当确有用户图元被移除时返回 true；若 id 未知或属于内置（只读）图元则返回 false（内置永不可删）。
static func gpDeleteDef(gpId: String) -> bool:
	if not _gpCacheValid:
		_gpRebuildCache()
	# Only user-authored defs are deletable. Built-ins (ISO 10628) are read-only per
	# decision D3, and they have no persisted user pack file to remove anyway.
	# 仅用户自建图元可删。内置（ISO 10628）按决策 D3 只读，且本无持久化用户包文件。
	var gpExtraIdx: int = _gpIndexOfId(gpId)
	if gpExtraIdx < 0:
		return false
	var gpDef: GPSymbolDef = _gpExtraDefs[gpExtraIdx]
	if gpDef.gpBuiltin:
		return false
	# Remove in place from BOTH arrays, preserving their shared identity so every holder
	# (main window, left palette, graph binder) transparently observes the removal — this
	# is exactly the gpRegisterDefs surgery performed in reverse. Because gpDefaultDefs()
	# hands out the SAME array identity, the toolbar's gpDefs list shrinks too.
	# 同时原地移除两数组中的元素，保持共享身份不变，使所有持有者（主窗口、左图元库、
	# 图绑定器）都能透明看到本次删除 —— 正是 gpRegisterDefs 的逆操作。由于 gpDefaultDefs()
	# 始终交出同一数组身份，工具栏的 gpDefs 列表也随之缩减。
	_gpExtraDefs.remove_at(gpExtraIdx)
	_gpCachedDefs.remove_at(_gpBuiltinCount + gpExtraIdx)
	_gpCacheValid = true
	# Delete the persisted user pack file (user://symbol_packs/<id>.json). A single symbol
	# is stored as one pack file, written by GPMakeSymbolDialog._gpPersist.
	# 删除持久化的用户包文件（user://symbol_packs/<id>.json）。单个图元存为一个包文件，
	# 由 GPMakeSymbolDialog._gpPersist 写入。
	var gpPath: String = "%s/%s.json" % [GP_USER_PACKS_DIR, gpId]
	if FileAccess.file_exists(gpPath):
		var gpErr: Error = DirAccess.remove_absolute(gpPath)
		if gpErr != OK:
			push_warning("GPSymbolLibrary: failed to delete user pack %s (err %d)" % [gpPath, gpErr])
			return false
	return true


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
