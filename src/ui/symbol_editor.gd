class_name GPSymbolEditor
extends Control

# Foolproof symbol editor: wizard generates a SymbolPack (pick category -> draw glyph ->
# fill attr schema -> fill standard ref -> export) without touching code.
# 傻瓜式图元编辑器：向导生成 SymbolPack（选类目→画字形→填属性 schema→填标准出处→导出），不动代码。
# See Dev Guide §4.2.2.
# 见开发指南 §4.2.2。

# A SymbolPack was exported
# 图元包导出完成
signal gpPackExported(pack)

# TODO: 5-step wizard -> export SymbolPack to user://symbol_packs/
# TODO：五步向导 → 导出 SymbolPack 到 user://symbol_packs/
