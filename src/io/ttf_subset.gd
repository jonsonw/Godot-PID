class_name GPTtfSubset
extends RefCounted
# Copyright © 2026 Jonson Wang
# Minimal TrueType subsetter: rebuild a font containing ONLY the glyphs a PDF export used,
# so an embedded CJK font costs ~100 KB instead of the ~23 MB system font it came from.
# 最小 TrueType 子集化器：重建一份**只含**本次 PDF 导出用到的字形的字体，
# 使嵌入的中文字体以 ~100 KB 计，而非其来源的 ~23 MB 系统字体。
#
# WHY SUBSET / 为何子集化：
# PDF text with Identity-H is a list of glyph IDs rendered against the EMBEDDED font; without
# subsetting, every export would carry the whole system font. The subset keeps glyf/loca/hmtx/
# head/hhea/maxp (+ name/post/OS/2 verbatim when present) and drops cmap — with Identity-H the
# viewer maps CIDs straight to glyph IDs, no cmap needed.
# Identity-H 编码下的 PDF 文字是「字形 ID 列表 + 内嵌字体」；不子集化，每次导出都要背整个
# 系统字体。子集保留 glyf/loca/hmtx/head/hhea/maxp（name/post/OS/2 若在则原样带上），
# 丢弃 cmap —— Identity-H 下查看器把 CID 直接当字形 ID 用，无需 cmap。
#
# CID NUMBERING / CID 编号：
# the caller passes source glyph IDs in first-use order; the subset assigns NEW glyph IDs by
# that order with .notdef (0) pinned to 0, and returns the src->new map. Composite glyphs pull
# their components in automatically (components are re-indexed inside glyf).
# 调用方按**首次使用顺序**传源字形 ID；子集按此顺序分配**新**字形 ID（.notdef 恒为 0），
# 并返回源->新映射。复合字形自动把构件拉进子集（glyf 内的构件索引被重写）。
#
# CHECKSUMS / 校验和：all zero. Viewers embed their own rasterizer (FreeType lineage) which
# does not validate sfnt checksums; writing correct ones would cost more than it buys.
# 校验和全零。查看器内嵌自己的光栅器（FreeType 系），不校验 sfnt 校验和；
# 写正确校验和的成本高于收益。
#
# LAYER RULE / 分层约束：byte parsing only, no FileAccess here — the caller hands in the
# bytes it already read (GPAtomicFile family owns disk access).
# 只做字节解析，此处不碰 FileAccess —— 字节由调用方读入（磁盘访问归 GPAtomicFile 家族）。

# Subset one font for the given source glyph IDs (order = CID order).
# 按给定源字形 ID 列表子集化一份字体（顺序即 CID 顺序）。
# Returns {"ok": bool, "bytes": PackedByteArray, "map": Dictionary, "err": String}.
# 返回 {"ok": bool, "bytes": PackedByteArray, "map": Dictionary, "err": String}。
static func gpSubset(gpFont: PackedByteArray, gpGids: PackedInt32Array) -> Dictionary:
	var gpFail: Dictionary = {"ok": false, "bytes": PackedByteArray(), "map": {}, "err": ""}
	if gpFont.size() < 12 or gpGids.is_empty():
		gpFail["err"] = "empty"
		return gpFail
	# ---- table directory / 表目录 ----
	var gpNumTables: int = _gpU16(gpFont, 4)
	var gpTables: Dictionary = {}   # tag -> {"off": int, "len": int}
	for gpI in range(gpNumTables):
		var gpRec: int = 12 + gpI * 16
		var gpTag: String = gpFont.slice(gpRec, gpRec + 4).get_string_from_ascii()
		gpTables[gpTag] = {"off": _gpU32(gpFont, gpRec + 8), "len": _gpU32(gpFont, gpRec + 12)}
	for gpTag in ["head", "hhea", "maxp", "loca", "glyf", "hmtx"]:
		if not gpTables.has(gpTag):
			gpFail["err"] = "missing table " + gpTag
			return gpFail
	# ---- head: units per em + loca format / head：每 em 单位数 + loca 格式 ----
	var gpHeadOff: int = int((gpTables["head"] as Dictionary)["off"])
	var gpUpem: int = _gpU16(gpFont, gpHeadOff + 18)
	var gpLocFmt: int = _gpU16(gpFont, gpHeadOff + 50)
	if gpUpem == 0:
		gpFail["err"] = "bad upem"
		return gpFail
	# ---- hhea: metric count / hhea：度量条目数 ----
	var gpHheaOff: int = int((gpTables["hhea"] as Dictionary)["off"])
	var gpNumH: int = _gpU16(gpFont, gpHheaOff + 34)
	if gpNumH == 0:
		gpNumH = 1
	# ---- maxp: glyph count / maxp：字形总数 ----
	var gpMaxpOff: int = int((gpTables["maxp"] as Dictionary)["off"])
	var gpNumGlyphs: int = _gpU16(gpFont, gpMaxpOff + 4)
	# ---- loca: glyph byte ranges / loca：字形的字节区间 ----
	var gpLocaOff: int = int((gpTables["loca"] as Dictionary)["off"])
	var gpLoca: PackedInt32Array = PackedInt32Array()
	for gpI in range(gpNumGlyphs + 1):
		if gpLocFmt == 0:
			gpLoca.append(_gpU16(gpFont, gpLocaOff + gpI * 2) * 2)
		else:
			gpLoca.append(_gpU32(gpFont, gpLocaOff + gpI * 4))
	# ---- expand composites, assign new ids / 展开复合字形并分配新 ID ----
	var gpMap: Dictionary = {0: 0}          # src gid -> new gid (.notdef pinned)
	var gpOrder: PackedInt32Array = PackedInt32Array([0])
	var gpQueue: PackedInt32Array = PackedInt32Array()
	for gpG in gpGids:
		if gpG > 0 and gpG < gpNumGlyphs and not gpMap.has(gpG):
			gpQueue.append(gpG)
	while not gpQueue.is_empty():
		var gpG: int = gpQueue[0]
		gpQueue.remove_at(0)
		if gpMap.has(gpG) or gpG <= 0 or gpG >= gpNumGlyphs:
			continue
		gpMap[gpG] = gpOrder.size()
		gpOrder.append(gpG)
		# A composite glyph references component gids — queue them too.
		# 复合字形引用构件字形 ID —— 一并入队。
		for gpRef in _gpComponents(gpFont, gpTables, gpLoca, gpG):
			if not gpMap.has(gpRef):
				gpQueue.append(gpRef)
	var gpN: int = gpOrder.size()
	# ---- rebuild glyf / loca / hmtx / 重建三表 ----
	# loca offsets are RELATIVE TO THE GLYF TABLE, not to the file — forgetting the base
	# reads random bytes as glyph data (the bug the Python cross-check caught).
	# loca 偏移是**相对 glyf 表**的，而非相对整个文件 —— 漏加基址就会把随机字节
	# 当字形数据读（Python 交叉核验抓住的正是这个 bug）。
	var gpGlyfOff: int = int((gpTables["glyf"] as Dictionary)["off"])
	var gpGlyf: PackedByteArray = PackedByteArray()
	var gpHmtx: PackedByteArray = PackedByteArray()
	var gpLocaNew: PackedInt32Array = PackedInt32Array()
	var gpHmtxOff: int = int((gpTables["hmtx"] as Dictionary)["off"])
	for gpI in range(gpN):
		gpLocaNew.append(gpGlyf.size())
		var gpSrc: int = gpOrder[gpI]
		var gpStart: int = gpGlyfOff + gpLoca[gpSrc]
		var gpEnd: int = gpGlyfOff + (gpLoca[gpSrc + 1] if gpSrc + 1 < gpLoca.size() else gpSrc)
		if gpEnd > gpStart and gpEnd <= gpFont.size():
			var gpData: PackedByteArray = gpFont.slice(gpStart, gpEnd)
			_gpRemapComponents(gpData, gpMap)
			gpGlyf.append_array(gpData)
			if gpGlyf.size() % 2 == 1:
				gpGlyf.append(0)
		gpHmtx.append_array(_gpMetric(gpFont, gpHmtxOff, gpNumH, gpSrc))
	gpLocaNew.append(gpGlyf.size())
	# ---- assemble the new font / 组装新字体 ----
	var gpOut: PackedByteArray = PackedByteArray()
	var gpKeep: Dictionary = {
		"glyf": gpGlyf,
		"loca": _gpLocaBytes(gpLocaNew),
		"hmtx": gpHmtx,
		"head": _gpPatchedTable(gpFont, gpTables["head"], {8: 0, 50: 1}),
		"hhea": _gpPatchedTable(gpFont, gpTables["hhea"], {34: gpN}),
		"maxp": _gpPatchedTable(gpFont, gpTables["maxp"], {4: gpN}),
	}
	for gpTag in ["name", "post", "OS/2"]:
		if gpTables.has(gpTag):
			var gpT: Dictionary = gpTables[gpTag]
			gpKeep[gpTag] = gpFont.slice(int(gpT["off"]), int(gpT["off"]) + int(gpT["len"]))
	var gpTags: Array = gpKeep.keys()
	gpTags.sort()
	var gpEs: int = 0
	while (1 << (gpEs + 1)) <= gpTags.size():
		gpEs += 1
	var gpSearch: int = (1 << gpEs) * 16
	# sfnt header: version, numTables, searchRange, entrySelector, rangeShift.
	# sfnt 头：版本、表数、searchRange、entrySelector、rangeShift。
	_gpPushU32(gpOut, _gpU32(gpFont, 0))
	_gpPushU16(gpOut, gpTags.size())
	_gpPushU16(gpOut, gpSearch)
	_gpPushU16(gpOut, gpEs)
	_gpPushU16(gpOut, gpTags.size() * 16 - gpSearch)
	for gpTag in gpTags:
		gpOut.append_array(gpTag.to_ascii_buffer())
		_gpPushU32(gpOut, 0)  # checksum: unchecked by viewers / 校验和：查看器不校验
		_gpPushU32(gpOut, 0)  # offset, back-patched below / 偏移，下方回填
		_gpPushU32(gpOut, (gpKeep[gpTag] as PackedByteArray).size())
	for gpTag in gpTags:
		var gpData: PackedByteArray = gpKeep[gpTag]
		while gpOut.size() % 4 != 0:
			gpOut.append(0)
		var gpAt: int = 12 + gpTags.find(gpTag) * 16 + 8
		gpOut[gpAt] = (gpOut.size() >> 24) & 0xFF
		gpOut[gpAt + 1] = (gpOut.size() >> 16) & 0xFF
		gpOut[gpAt + 2] = (gpOut.size() >> 8) & 0xFF
		gpOut[gpAt + 3] = gpOut.size() & 0xFF
		gpOut.append_array(gpData)
	return {"ok": true, "bytes": gpOut, "map": gpMap, "err": ""}


# Read the head/hhea numbers a PDF FontDescriptor needs (font units).
# 读取 PDF FontDescriptor 所需的 head/hhea 数值（字体单位）。
# Returns {"upem": int, "bbox": [xMin,yMin,xMax,yMax], "ascent": int, "descent": int},
# or {} when the bytes are not a readable TrueType font.
# 返回 {"upem": int, "bbox": [xMin,yMin,xMax,yMax], "ascent": int, "descent": int}；
# 字节不是可读的 TrueType 字体时返回 {}。
static func gpHeadInfo(gpFont: PackedByteArray) -> Dictionary:
	if gpFont.size() < 12:
		return {}
	var gpNumTables: int = _gpU16(gpFont, 4)
	var gpHead: int = -1
	var gpHhea: int = -1
	for gpI in range(gpNumTables):
		var gpRec: int = 12 + gpI * 16
		var gpTag: String = gpFont.slice(gpRec, gpRec + 4).get_string_from_ascii()
		if gpTag == "head":
			gpHead = _gpU32(gpFont, gpRec + 8)
		elif gpTag == "hhea":
			gpHhea = _gpU32(gpFont, gpRec + 8)
	if gpHead < 0 or gpHhea < 0 or gpHead + 52 > gpFont.size() or gpHhea + 36 > gpFont.size():
		return {}
	return {
		"upem": _gpU16(gpFont, gpHead + 18),
		"bbox": [_gpI16(gpFont, gpHead + 36), _gpI16(gpFont, gpHead + 38),
			_gpI16(gpFont, gpHead + 40), _gpI16(gpFont, gpHead + 42)],
		"ascent": _gpI16(gpFont, gpHhea + 4),
		"descent": _gpI16(gpFont, gpHhea + 6),
	}


# ---------------------------------------------------------------------------
# internals / 内部
# ---------------------------------------------------------------------------

# Component glyph ids of one glyph (empty for a simple glyph or an empty slot).
# 单个字形的构件字形 ID（简单字形或空槽位返回空表）。
static func _gpComponents(gpFont: PackedByteArray, gpTables: Dictionary, gpLoca: PackedInt32Array,
		gpGid: int) -> PackedInt32Array:
	var gpOut: PackedInt32Array = PackedInt32Array()
	var gpGlyfOff: int = int((gpTables["glyf"] as Dictionary)["off"])
	var gpStart: int = gpGlyfOff + gpLoca[gpGid]
	var gpEnd: int = gpGlyfOff + (gpLoca[gpGid + 1] if gpGid + 1 < gpLoca.size() else gpLoca[gpGid])
	if gpEnd <= gpStart or gpEnd > gpFont.size():
		return gpOut
	# numberOfContours >= 0 = simple glyph; -1 = composite.
	# numberOfContours >= 0 = 简单字形；-1 = 复合字形。
	if _gpI16(gpFont, gpStart) >= 0:
		return gpOut
	var gpP: int = gpStart + 4
	while gpP + 4 <= gpEnd:
		var gpFlags: int = _gpU16(gpFont, gpP)
		gpOut.append(_gpU16(gpFont, gpP + 2))
		gpP += 4
		# args / 参数
		gpP += 4 if (gpFlags & 0x0001) != 0 else 2
		# scale variants / 缩放变体
		if gpFlags & 0x0008:
			gpP += 2
		elif gpFlags & 0x0040:
			gpP += 4
		elif gpFlags & 0x0080:
			gpP += 8
		if gpFlags & 0x0020 == 0:
			break
	return gpOut


# Rewrite the component glyph indices inside a (copied) glyph data slice.
# 重写（已复制的）字形数据切片内的构件字形索引。
static func _gpRemapComponents(gpData: PackedByteArray, gpMap: Dictionary) -> void:
	if gpData.size() < 4 or _gpI16(gpData, 0) >= 0:
		return
	var gpP: int = 4
	while gpP + 4 <= gpData.size():
		var gpFlags: int = _gpU16(gpData, gpP)
		var gpSrc: int = _gpU16(gpData, gpP + 2)
		var gpNew: int = int(gpMap.get(gpSrc, 0))
		gpData[gpP + 2] = (gpNew >> 8) & 0xFF
		gpData[gpP + 3] = gpNew & 0xFF
		gpP += 4
		gpP += 4 if (gpFlags & 0x0001) != 0 else 2
		if gpFlags & 0x0008:
			gpP += 2
		elif gpFlags & 0x0040:
			gpP += 4
		elif gpFlags & 0x0080:
			gpP += 8
		if gpFlags & 0x0020 == 0:
			break


# One hmtx entry (advanceWidth u16 + leftSideBearing i16) for a source gid.
# 一个源字形 ID 的 hmtx 条目（advanceWidth u16 + leftSideBearing i16）。
static func _gpMetric(gpFont: PackedByteArray, gpOff: int, gpNumH: int, gpGid: int) -> PackedByteArray:
	var gpOut: PackedByteArray = PackedByteArray()
	var gpAw: int = 0
	var gpLsb: int = 0
	if gpGid < gpNumH:
		gpAw = _gpU16(gpFont, gpOff + gpGid * 4)
		gpLsb = _gpI16(gpFont, gpOff + gpGid * 4 + 2)
	else:
		# Monotone tail: the last advance repeats, only lsb entries continue.
		# 单调尾部：最后一个 advance 重复，其后只有 lsb 条目。
		gpAw = _gpU16(gpFont, gpOff + (gpNumH - 1) * 4)
		gpLsb = _gpI16(gpFont, gpOff + gpNumH * 4 + (gpGid - gpNumH) * 2)
	gpAw = clampi(gpAw, 0, 65535)
	gpLsb = clampi(gpLsb, -32768, 32767)
	_gpPushU16(gpOut, gpAw)
	_gpPushI16(gpOut, gpLsb)
	return gpOut


# loca table in LONG (32-bit) format. / 长格式（32 位）的 loca 表。
static func _gpLocaBytes(gpLoca: PackedInt32Array) -> PackedByteArray:
	var gpOut: PackedByteArray = PackedByteArray()
	for gpV in gpLoca:
		_gpPushU32(gpOut, gpV)
	return gpOut


# Copy a table and patch u16 fields at the given offsets.
# 复制一张表并在给定偏移处修补 u16 字段。
static func _gpPatchedTable(gpFont: PackedByteArray, gpT: Dictionary, gpPatches: Dictionary) -> PackedByteArray:
	var gpOut: PackedByteArray = gpFont.slice(int(gpT["off"]), int(gpT["off"]) + int(gpT["len"]))
	for gpAt: int in gpPatches:
		var gpV: int = gpPatches[gpAt]
		if gpAt + 1 < gpOut.size():
			gpOut[gpAt] = (gpV >> 8) & 0xFF
			gpOut[gpAt + 1] = gpV & 0xFF
	return gpOut


static func _gpU16(gpB: PackedByteArray, gpAt: int) -> int:
	return (int(gpB[gpAt]) << 8) | int(gpB[gpAt + 1])


static func _gpI16(gpB: PackedByteArray, gpAt: int) -> int:
	var gpV: int = _gpU16(gpB, gpAt)
	return gpV - 65536 if gpV >= 32768 else gpV


static func _gpU32(gpB: PackedByteArray, gpAt: int) -> int:
	return (int(gpB[gpAt]) << 24) | (int(gpB[gpAt + 1]) << 16) \
		| (int(gpB[gpAt + 2]) << 8) | int(gpB[gpAt + 3])


static func _gpPushU16(gpB: PackedByteArray, gpV: int) -> void:
	gpB.append((gpV >> 8) & 0xFF)
	gpB.append(gpV & 0xFF)


static func _gpPushI16(gpB: PackedByteArray, gpV: int) -> void:
	var gpU: int = gpV & 0xFFFF
	gpB.append((gpU >> 8) & 0xFF)
	gpB.append(gpU & 0xFF)


static func _gpPushU32(gpB: PackedByteArray, gpV: int) -> void:
	gpB.append((gpV >> 24) & 0xFF)
	gpB.append((gpV >> 16) & 0xFF)
	gpB.append((gpV >> 8) & 0xFF)
	gpB.append(gpV & 0xFF)
