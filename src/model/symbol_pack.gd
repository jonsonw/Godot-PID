class_name GPSymbolPack
extends Resource

# A symbol pack — a distributable unit of symbols (one folder: manifest + SymbolDef .tres).
# 图元包 —— 可分发单元（一个文件夹：manifest + 若干 SymbolDef .tres）。
# See Dev Guide §4.2.2.
# 见开发指南 §4.2.2。

# Pack id
# 图元包 id
var gpPackId: String = ""

# Display name
# 显示名
var gpName: String = ""

# Standard ref, e.g. "ISA-5.1-2020"
# 标准出处，如 "ISA-5.1-2020"
var gpStandardRef: String = ""

# Pack version
# 图元包版本
var gpVersion: String = "1.0"

# Author
# 作者
var gpAuthor: String = ""

# Categories covered
# 覆盖的类目
var gpCategories: Array[GPSymbolDef.GPSymbolCategory] = []

# Symbols in this pack
# 本包内图元
var gpSymbols: Array[GPSymbolDef] = []

# Optional per-category nominal envelope overrides, e.g. {"valve": Vector2(70, 52)}.
# 可选的类别标称包络尺寸覆盖表，如 {"valve": Vector2(70, 52)}。
# Lets a design institute ship its own house proportions without forking the core table.
# 让某设计院可自带内部比例，而无需分叉核心尺寸表。
# Query via GPSymbolCategories.gpSizeFor(gpCat, gpCategorySizes).
# 查询方式：GPSymbolCategories.gpSizeFor(gpCat, gpCategorySizes)。
var gpCategorySizes: Dictionary = {}


# Instantiate all symbols as SymbolDef resources.
# 将包内全部图元实例化为 SymbolDef 资源。
func gpInstantiateSymbols() -> Array[GPSymbolDef]:
	return gpSymbols.duplicate()


# Resolve the nominal envelope size for a category inside this pack.
# 解析本包内某类别的标称包络尺寸。
func gpSizeFor(gpCat: String) -> Vector2:
	return GPSymbolCategories.gpSizeFor(gpCat, gpCategorySizes)


# Serialize pack metadata (symbols are serialized by the caller via GPSymbolDef.gpToDict).
# 序列化图元包元数据（图元本身由调用方通过 GPSymbolDef.gpToDict 序列化）。
func gpToDict() -> Dictionary:
	var gpSizes: Dictionary = {}
	for gpK in gpCategorySizes.keys():
		var gpV: Vector2 = gpCategorySizes[gpK]
		gpSizes[str(gpK)] = [gpV.x, gpV.y]
	var gpSyms: Array = []
	for gpS in gpSymbols:
		gpSyms.append(gpS.gpToDict())
	return {
		"pack_id": gpPackId,
		"name": gpName,
		"standard_ref": gpStandardRef,
		"version": gpVersion,
		"author": gpAuthor,
		"category_sizes": gpSizes,
		"symbols": gpSyms,
	}


# Rebuild pack metadata and symbols from a dictionary (inverse of gpToDict).
# 从字典重建图元包元数据与图元（gpToDict 的逆操作）。
func gpFromDict(gpD: Dictionary) -> void:
	gpPackId = gpD.get("pack_id", "")
	gpName = gpD.get("name", "")
	gpStandardRef = gpD.get("standard_ref", "")
	gpVersion = gpD.get("version", "1.0")
	gpAuthor = gpD.get("author", "")
	gpCategorySizes = {}
	var gpSizes: Dictionary = gpD.get("category_sizes", {})
	for gpK in gpSizes.keys():
		var gpArr: Array = gpSizes[gpK]
		gpCategorySizes[str(gpK)] = Vector2(float(gpArr[0]), float(gpArr[1]))
	gpSymbols = []
	var gpSyms: Array = gpD.get("symbols", [])
	for gpItem in gpSyms:
		var gpDef: GPSymbolDef = GPSymbolDef.new()
		gpDef.gpFromDict(gpItem as Dictionary)
		gpSymbols.append(gpDef)
