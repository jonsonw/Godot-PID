class_name GPPIDNode
extends RefCounted

# One symbol instance on the canvas (not a Resource; serialized via self-managed to_dict).
# 画布上的一个图元实例（非 Resource，序列化走自管 to_dict）。
# See Dev Guide §4.5 and 从零落地架构_分步实施.md Step 1.2.
# 见开发指南 §4.5 与「从零落地架构_分步实施.md」Step 1.2。

# ---- identity: TWO numbers, two jobs ----
# ---- 标识：两个号，两种职责 ----

# Cross-document technical id, e.g. "a3f9k2m1-n17". NEVER changes once assigned: edges and
# off-page cross references point at this, so renaming a tag can never break a pipe.
# Allocated by GPIdGen.gpNextGlobal (M8 field, wired in M9/M11).
# 跨文档技术号，如 "a3f9k2m1-n17"。一旦分配**永不改变**：边与跨页互引都指向它，
# 故改位号绝不会断线。由 GPIdGen.gpNextGlobal 分配（M8 建字段，M9/M11 接线）。
var gpUid: String = ""

# Per-drawing instance id, e.g. "u-1". Kept as the in-file key; gpUid supersedes it for any
# cross-document reference.
# 单图纸内的实例 id，如 "u-1"。仍是文件内键；跨文档引用一律改用 gpUid。
var gpInstanceId: String = ""

# SymbolDef id this node instantiates
# 该节点实例化的 SymbolDef id
var gpSymbolId: String = ""

# Process tag, e.g. "P-1001". Project-scoped, user editable, unique within the project.
# Empty means "render the localized type name" (the historic fallback).
# 工艺位号，如 "P-1001"。项目级、用户可改、项目内唯一。为空时显示本地化类型名（历史回落行为）。
var gpTag: String = ""

# Multi-language instance names, e.g. {"zh_CN": "磨矿给料泵", "en_US": "Mill Feed Pump"}.
# This is the NAME that shows in the inspector — never on the canvas.
# 多语言实例名称，如 {"zh_CN": "磨矿给料泵", "en_US": "Mill Feed Pump"}。
# 这是显示在**属性面板**里的名称 —— 永不进画布。
var gpNames: Dictionary = {}

# ---- geometry / 几何 ----
# World position of the node center
# 节点中心的世界坐标
var gpPosition: Vector2 = Vector2.ZERO

# Rotation in degrees
# 旋转角度（度）
var gpRotationDeg: float = 0.0

# Mirror horizontally
# 水平翻转
var gpFlipped: bool = false

# ---- properties / 属性 ----
# User-set property VALUES, keyed by GPPropertyDef.gpKey. Only values live here — never a copy
# of the field definitions, which is what lets a library edit propagate to every project
# (see GPPropertyResolver). Orphaned keys (field deleted from the library) STAY here.
# 用户设置的属性**值**，按 GPPropertyDef.gpKey 索引。此处只存值 —— 绝不存字段定义的副本，
# 这正是「改库即全项目同步」得以成立的原因（见 GPPropertyResolver）。
# 库中已删字段留下的孤儿键**保留**在此。
var gpProps: Dictionary = {}

# ---- canvas label placement (see GPLabelAnchor) ----
# ---- 画布标签位置（见 GPLabelAnchor） ----
# Anchor: GPLabelAnchor.GP_ANCHOR_UNSET means "follow the library default".
# 锚点：GPLabelAnchor.GP_ANCHOR_UNSET 表示「跟随库默认」。
var gpLabelAnchor: int = GPPropertyResolver.GP_ANCHOR_UNSET

# Offset in NORMALISED units (1.0 = half the envelope) — never pixels, or the label drifts on
# zoom / DPI change / print. GP_OFFSET_UNSET means "follow the library default".
# 归一化单位的偏移（1.0 = 半个包络）—— 绝不用像素，否则缩放 / DPI 变化 / 打印时标签会漂移。
# GP_OFFSET_UNSET 表示「跟随库默认」。
var gpLabelOffset: Vector2 = GPLabelAnchor.GP_OFFSET_UNSET


# Serialize this node to a plain dictionary (object graph -> dict graph).
# 将本节点序列化为普通字典（对象图 → 字典图）。
# The shape matches docs/samples/pani_detox.pid.json so JSON stays forward-compatible.
# 该形状与 docs/samples/pani_detox.pid.json 一致，保证 JSON 向前兼容。
func gpToDict() -> Dictionary:
	var gpD: Dictionary = {}
	gpD["uid"] = gpUid
	gpD["instance_id"] = gpInstanceId
	gpD["symbol_id"] = gpSymbolId
	gpD["tag"] = gpTag
	gpD["names"] = gpNames.duplicate(true)
	gpD["position"] = [gpPosition.x, gpPosition.y]
	gpD["rotation_deg"] = gpRotationDeg
	gpD["flipped"] = gpFlipped
	gpD["props"] = gpProps.duplicate(true)
	gpD["label_anchor"] = gpLabelAnchor
	# Only emit the offset when it is actually set: the unset sentinel is ±INF, which is NOT
	# representable in JSON and would corrupt the archive.
	# 仅在偏移确实设置时输出：未设置的哨兵是 ±INF，它无法用 JSON 表示，会损坏存档。
	if gpLabelOffset != GPLabelAnchor.GP_OFFSET_UNSET:
		gpD["label_offset"] = [gpLabelOffset.x, gpLabelOffset.y]
	return gpD


# Restore this node from a dictionary (inverse of gpToDict).
# 从字典还原本节点（gpToDict 的逆操作）。
# Tolerant of the old dictionary-graph shape (id/type/label/pos/attrs) so legacy
# *.pid.json files still load.
# 兼容旧字典图形状（id/type/label/pos/attrs），使旧版 *.pid.json 仍可载入。
func gpFromDict(gpD: Dictionary) -> void:
	# New object-graph key first, fall back to the old dictionary-graph key.
	# 优先用对象图新键，再兜底旧字典图键。
	gpUid = gpD.get("uid", "")
	gpInstanceId = gpD.get("instance_id", gpD.get("id", ""))
	gpSymbolId = gpD.get("symbol_id", gpD.get("type", ""))
	gpTag = gpD.get("tag", gpD.get("label", ""))

	# v1 archives put the NAME in "label" (there was no separate tag field). When the label is
	# not a tag-like string, seed names.zh_CN from it so no user data is lost.
	# v1 存档把「名称」塞在 "label" 里（当时没有独立的位号字段）。当 label 不像位号时，
	# 用它初始化 names.zh_CN，避免丢失用户数据。
	var gpNamesIn: Dictionary = gpD.get("names", {})
	gpNames = gpNamesIn.duplicate(true) if gpNamesIn is Dictionary else {}
	if gpNames.is_empty() and gpTag != "" and not _gpLooksLikeTag(gpTag):
		gpNames[GPPropertyResolver.GP_FALLBACK_LOCALE] = gpTag

	var gpP: Array = gpD.get("position", gpD.get("pos", [0.0, 0.0]))
	gpPosition = Vector2(float(gpP[0]), float(gpP[1]))
	gpRotationDeg = float(gpD.get("rotation_deg", 0.0))
	gpFlipped = bool(gpD.get("flipped", false))

	# "props" is current; "attr_values" / "attrs" are the legacy names.
	# "props" 为当前键；"attr_values" / "attrs" 为历史键名。
	var gpPropsIn: Variant = gpD.get("props", gpD.get("attr_values", gpD.get("attrs", {})))
	gpProps = (gpPropsIn as Dictionary).duplicate(true) if gpPropsIn is Dictionary else {}

	gpLabelAnchor = int(gpD.get("label_anchor", GPPropertyResolver.GP_ANCHOR_UNSET))
	var gpOff: Array = gpD.get("label_offset", [])
	if gpOff.size() >= 2:
		gpLabelOffset = Vector2(float(gpOff[0]), float(gpOff[1]))
	else:
		gpLabelOffset = GPLabelAnchor.GP_OFFSET_UNSET


# Effective uid: an archive written before M8 has none, so the per-drawing id doubles as the
# reference key until it is upgraded (M12 migration backfills real uids).
# 生效的 uid：M8 之前的存档没有该字段，故在升级前用单图纸 id 兼任引用键
# （M12 迁移会回填真正的 uid）。
func gpRefId() -> String:
	if gpUid != "":
		return gpUid
	return gpInstanceId


# Heuristic for the v1 "label held the name" case: a tag is short, ASCII and usually carries a
# prefix + digits (P-1001, XV-12). Anything else is treated as a human name.
# v1「label 存的是名称」的判定启发式：位号短、纯 ASCII，且多为「前缀 + 数字」（P-1001、XV-12）。
# 其余一律视为人类可读名称。
func _gpLooksLikeTag(gpText: String) -> bool:
	if gpText.length() > 24:
		return false
	var gpLetters: int = 0
	var gpDigits: int = 0
	for gpI in range(gpText.length()):
		var gpC: String = gpText.substr(gpI, 1)
		var gpU: int = gpC.unicode_at(0)
		if gpU >= 48 and gpU <= 57:
			gpDigits += 1
		elif (gpU >= 65 and gpU <= 90) or (gpU >= 97 and gpU <= 122) or gpC == "-" or gpC == "_":
			gpLetters += 1
		else:
			return false
	return gpLetters > 0 and gpDigits > 0
