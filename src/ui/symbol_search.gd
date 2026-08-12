class_name SymbolSearch
extends Control

# Symbol search: fuzzy match SymbolLibrary by name / category / tag; pick or drag to canvas.
# 图元搜索：按名称/类目/标签模糊检索 SymbolLibrary，点选或拖入画布。
# See Dev Guide §4.4 / §4.4.1.
# 见开发指南 §4.4 / §4.4.1。

signal query_changed(q: String)    # Search text changed / 搜索文本变化
signal symbol_picked(type: String)  # A symbol was picked / 选中某图元

# TODO: call SymbolLibrary.search(q) on query_changed.
# TODO：在 query_changed 时调用 SymbolLibrary.search(q)。
