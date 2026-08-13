class_name GPPIDToolbar
extends VBoxContainer

# Left toolbar: symbol buttons grouped by SymbolCategory + tools (select / connect) +
# custom-shape tool group; embeds SymbolSearch.
# 左侧工具栏：图元按钮按 SymbolCategory 折叠分组 + 工具（选择/连线）+ 自定义图元工具组；内嵌 SymbolSearch。
# See Dev Guide §4.4.
# 见开发指南 §4.4。

# Emitted when a symbol/tool is selected
# 选中图元/工具时发出
signal gpToolSelected(type: String)

# TODO: populate from SymbolLibrary.list_by_category()
# TODO：用 SymbolLibrary.list_by_category() 填充。
