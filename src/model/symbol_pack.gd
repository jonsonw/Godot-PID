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


# Instantiate all symbols as SymbolDef resources.
# 将包内全部图元实例化为 SymbolDef 资源。
func gpInstantiateSymbols() -> Array[GPSymbolDef]:
	return gpSymbols.duplicate()
