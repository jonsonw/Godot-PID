class_name SymbolPack
extends Resource

# A symbol pack — a distributable unit of symbols (one folder: manifest + SymbolDef .tres).
# 图元包 —— 可分发单元（一个文件夹：manifest + 若干 SymbolDef .tres）。
# See Dev Guide §4.2.2.
# 见开发指南 §4.2.2。

var pack_id: String = ""                                # Pack id / 图元包 id
var name: String = ""                                   # Display name / 显示名
var standard_ref: String = ""                           # Standard ref, e.g. "ISA-5.1-2020" / 标准出处，如 "ISA-5.1-2020"
var version: String = "1.0"                             # Pack version / 图元包版本
var author: String = ""                                 # Author / 作者
var categories: Array[SymbolDef.SymbolCategory] = []    # Categories covered / 覆盖的类目
var symbols: Array[SymbolDef] = []                      # Symbols in this pack / 本包内图元

# Instantiate all symbols as SymbolDef resources.
# 将包内全部图元实例化为 SymbolDef 资源。
func instantiate_symbols() -> Array[SymbolDef]:
	return symbols.duplicate()
