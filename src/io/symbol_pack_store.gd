class_name GPSymbolPackStore
extends RefCounted
# Copyright © 2026 Jonson Wang
# Persistence for user-authored symbol packs (user://symbol_packs/<id>.json).
# 用户自建图元包的持久化（user://symbol_packs/<id>.json）。
#
# WHY THIS IS NOT IN GPSymbolLibrary / 为何不在 GPSymbolLibrary 里：
# The library is core: it decides WHICH symbols exist and hands them to every consumer. Opening
# user:// from there was an io-boundary leak (D05 in the W12 review) — core has no business
# knowing that a symbol happens to be stored as a JSON file on disk. Listing, reading and deleting
# files moved here; the library keeps the in-memory registry and asks this class for data. Core
# cannot name this class, so the composition root installs it through the GPSymbolLibrary seam.
# 图元库属 core：它决定**有哪些**图元、并把它们交给每个消费方。在 core 里开 user:// 是 io 边界渗漏
#（W12 审查 D05）—— core 没有理由知道"图元恰好以磁盘 JSON 文件形式存放"。列目录、读文件、删文件
# 搬到本类；图元库保留内存登记表，向本类要数据。core 不可命名本类，故由组合根经 GPSymbolLibrary
# 的缝装入。
#
# FORMAT CONTRACT / 格式契约：
# One .json file per symbol, written by the symbol editor. A malformed file is SKIPPED, not fatal:
# one bad pack must not hide the other twenty from the palette.
# 一个图元一个 .json 文件，由符号编辑器写入。坏文件**跳过**而非致命：一个坏包不该让其余二十个
# 从图元库里消失。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Directory where user-authored symbol packs live.
# 用户自建图元包的存放目录。
const GP_DIR: String = "user://symbol_packs"


# Install this store as the library's persistence seam. Called ONCE by each composition root
# (ui/shell/main_window.gd `_gpLoadSymbolLibrary`, tools/gp_cli.gd `_ready`) BEFORE the first
# gpLoadUserPacks / gpUserPacks.
# 把本存储装为图元库的持久化缝。由各组合根（ui/shell/main_window.gd 的 `_gpLoadSymbolLibrary`、
# tools/gp_cli.gd 的 `_ready`）在首次 gpLoadUserPacks / gpUserPacks **之前**调用一次。
# Wrapped in a function for one reason: a forgotten install would silently disable symbol
# persistence (the exact failure mode the W12 review found in the old zero-caller gpLoadFile).
# Making it a single named call means the guard test can assert it exists at each root.
# 包成函数只为一个原因：漏装会**静默**关掉图元持久化（正是 W12 审查在旧的无调用方 gpLoadFile
# 上发现的那种失效）。做成一个具名调用后，守卫测试即可断言每个组合根都有它。
static func gpInstall() -> void:
	GPSymbolLibrary.gpSetPackStore(gpReadAll, gpDelete)


# Read every persisted pack. Order is unspecified; the library registers them by id anyway.
# 读出全部持久化包。顺序不保证；图元库本来也按 id 登记。
static func gpReadAll() -> Array[GPSymbolPack]:
	var gpPacks: Array[GPSymbolPack] = []
	for gpName in GPFileGateway.gpListFiles(GP_DIR, ".json"):
		var gpText: String = GPFileGateway.gpReadText("%s/%s" % [GP_DIR, gpName])
		if gpText == "":
			continue
		var gpJson: Variant = JSON.parse_string(gpText)
		if not (gpJson is Dictionary):
			continue
		var gpPack: GPSymbolPack = GPSymbolPack.new()
		gpPack.gpFromDict(gpJson as Dictionary)
		gpPacks.append(gpPack)
	return gpPacks


# Delete the persisted pack for one symbol id. True when no file remains.
# 删除某个图元 id 的持久化包。文件不再存在即返回 true。
# Uses gpDeleteArchive (not gpDeleteFile) because the atomic writer keeps a .bak next to the
# pack: deleting only the .json would leave the user's "deleted" symbol on disk.
# 用 gpDeleteArchive 而非 gpDeleteFile：原子写会在包旁留一份 .bak，只删 .json 会让用户
# "已删除"的图元仍留在磁盘上。
static func gpDelete(gpId: String) -> bool:
	if gpId == "":
		return true
	return GPFileGateway.gpDeleteArchive("%s/%s.json" % [GP_DIR, gpId])
