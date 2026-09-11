class_name GPPropertySchema
extends Resource
# Copyright © 2026 Jonson Wang
# The ordered set of property fields a symbol family declares — TYPE LAYER metadata.
# 一个图元族声明的有序属性字段集合 —— 类型层元数据。
#
# Instances never store a copy of this: they store values keyed by gpKey, and GPPropertyResolver
# merges the two. That single rule is what makes "edit the library, every project follows" work.
# 实例绝不保存它的副本：实例只按 gpKey 存值，由 GPPropertyResolver 合并两层。
# 这条唯一规则正是「改图元库，全项目同步」得以成立的原因。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Bumped whenever the field set changes in a way that needs migration.
# 字段集合发生需迁移的变化时递增。
@export var gpVersion: int = 1

@export var gpFields: Array[GPPropertyDef] = []


# Look up a field by its technical key. Returns null when the library no longer has it (the
# instance value then becomes an ORPHAN — never deleted silently, see GPPropertyResolver).
# 按技术键查找字段；库中已无该字段时返回 null（此时实例值成为「孤儿」—— 绝不静默删除，
# 见 GPPropertyResolver）。
func gpFieldByKey(gpKey: String) -> GPPropertyDef:
	for gpF in gpFields:
		if gpF.gpKey == gpKey:
			return gpF
	return null


# Every declared key, in schema order. / 全部声明键，按 schema 顺序。
func gpKeys() -> Array[String]:
	var gpOut: Array[String] = []
	for gpF in gpFields:
		gpOut.append(gpF.gpKey)
	return gpOut


# Keys in panel order: grouped by gpGroup, then by gpOrder, then by declaration order.
# Stable sorting matters — a reordered library must not reshuffle the panel on every open.
# 面板顺序的键：先按 gpGroup，再按 gpOrder，最后按声明顺序。
# 稳定排序很重要 —— 库字段重排不应每次打开都让面板洗牌。
func gpOrderedKeys() -> Array[String]:
	var gpRows: Array[Dictionary] = []
	for gpI in range(gpFields.size()):
		var gpF: GPPropertyDef = gpFields[gpI]
		var gpRow: Dictionary = {}
		gpRow["group"] = gpF.gpGroup
		gpRow["order"] = gpF.gpOrder
		gpRow["index"] = gpI
		gpRow["key"] = gpF.gpKey
		gpRows.append(gpRow)
	gpRows.sort_custom(func(gpA: Dictionary, gpB: Dictionary) -> bool:
		if gpA["group"] != gpB["group"]:
			return str(gpA["group"]) < str(gpB["group"])
		if int(gpA["order"]) != int(gpB["order"]):
			return int(gpA["order"]) < int(gpB["order"])
		return int(gpA["index"]) < int(gpB["index"]))
	var gpOut: Array[String] = []
	for gpR in gpRows:
		gpOut.append(str(gpR["key"]))
	return gpOut


# Fingerprint of the field set (key + kind + type-sensitive defaults), used to detect
# "the library changed since this drawing was saved" at open time.
# 字段集合指纹（键 + 类型 + 类型敏感默认值），用于打开图纸时检测「库自上次保存后已变更」。
func gpFingerprint() -> String:
	# Built by concatenation: neither Array[String] nor PackedStringArray offers join() in
	# Godot 4.7, and a hand-rolled join avoids depending on either.
	# 手工拼接：Godot 4.7 中 Array[String] 与 PackedStringArray 都没有 join()，
	# 手工拼接可避免依赖任何一方。
	var gpJoined: String = ""
	var gpKeysSorted: Array[String] = gpKeys()
	gpKeysSorted.sort()
	for gpK in gpKeysSorted:
		var gpF: GPPropertyDef = gpFieldByKey(gpK)
		if gpF == null:
			continue
		if gpF != null and gpJoined != "":
			gpJoined += "|"
		gpJoined += "%s:%d:%s" % [gpK, gpF.gpKind, str(gpF.gpDefault)]
	return str(gpJoined.hash())


# Old key -> new key map for fields that were renamed in the library (gpRenameFrom).
# 库中改名过的字段映射：旧键 -> 新键（取自 gpRenameFrom）。
func gpRenameMap() -> Dictionary:
	var gpOut: Dictionary = {}
	for gpF in gpFields:
		if gpF.gpRenameFrom != "":
			gpOut[gpF.gpRenameFrom] = gpF.gpKey
	return gpOut


func gpToDict() -> Dictionary:
	var gpArr: Array = []
	for gpF in gpFields:
		gpArr.append(gpF.gpToDict())
	var gpD: Dictionary = {}
	gpD["version"] = gpVersion
	gpD["fields"] = gpArr
	return gpD


# Restore in place (inverse of gpToDict). gpFields is CLEARED first so the declared typed-array
# type survives (re-assigning a new Array would be fine too, but clearing is the safe idiom).
# 就地还原（gpToDict 的逆操作）。先清空 gpFields，以保留已声明的类型化数组类型
# （重新赋值新 Array 也可，但清空是更安全的写法）。
func gpFromDict(gpD: Dictionary) -> void:
	gpVersion = int(gpD.get("version", 1))
	gpFields.clear()
	var gpArr: Array = gpD.get("fields", [])
	for gpItem in gpArr:
		if not (gpItem is Dictionary):
			continue
		var gpF: GPPropertyDef = GPPropertyDef.new()
		gpF.gpFromDict(gpItem as Dictionary)
		gpFields.append(gpF)
