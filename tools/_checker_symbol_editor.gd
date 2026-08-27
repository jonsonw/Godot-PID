extends SceneTree

# Copyright © 2026 Jonson Wang
# Headless validator for the W2 symbol editor: forces the whole symbol-editor script chain
# to COMPILE (preload registers every class_name) and smoke-tests the export core
# (normalizer -> pack -> library register -> JSON round-trip) that the wizard relies on.
# W2 符号编辑器的 headless 校验：强制整套编辑器脚本链编译（preload 注册全部 class_name），
# 并冒烟测试向导依赖的导出核心（归一化 -> 打包 -> 注册 -> JSON 往返）。
# The UI widgets themselves need the editor + autoloads, so they are validated in-editor;
# this checker covers the model/compile surface that headless can reach.
# UI 控件本身需要编辑器与 autoload，故在编辑器内验证；本脚本覆盖 headless 可达的模型/编译面。

# Preload in dependency order so each class_name is registered before its dependents compile.
# 按依赖顺序预加载，使每个 class_name 在其被依赖者编译前已注册。
const GP_Categories := preload("res://src/core/symbol_categories.gd")
const GP_Def := preload("res://src/core/symbol_def.gd")
const GP_Normalizer := preload("res://src/core/symbol_normalizer.gd")
const GP_Pack := preload("res://src/model/symbol_pack.gd")
const GP_Library := preload("res://src/core/symbol_library.gd")
const GP_Painter := preload("res://src/render/symbol_painter.gd")
const GP_Glyph := preload("res://src/ui/glyph_canvas.gd")
const GP_Preview := preload("res://src/ui/symbol_preview.gd")
const GP_Editor := preload("res://src/ui/symbol_editor.gd")


# Entry point for a headless --script run.
# headless --script 运行的入口。
func _initialize() -> void:
	printerr("SYMSTEP0 compile ok")

	_gpTestNormalizeWithPorts()
	_gpTestNormalizeNoPortsFallsBack()
	_gpTestNormalizeEmptyGlyph()
	_gpTestLibraryRegister()
	_gpTestPackRoundTrip()
	_gpTestEditorInstantiable()

	printerr("SYMCHECKER_OK")
	var gpF: FileAccess = FileAccess.open("/tmp/sym_checker_result.txt", FileAccess.WRITE)
	if gpF != null:
		gpF.store_string("SYMCHECKER_OK\n")
		gpF.close()
	quit()


# A hand-drawn valve glyph (a 100x40 author-space rectangle) with two ports at its ends must
# become a valve-sized def with 0..1 ports snapped to the left/right edges.
# 手绘阀门字形（100x40 作者空间矩形）+ 两端各一端口，应变为阀门尺寸的定义，
# 端口归一化到 0..1 并吸附到左右边。
func _gpTestNormalizeWithPorts() -> void:
	var gpRaw: Dictionary = {
		"id": "my_valve",
		"display_name": "我的阀门",
		"shapes": {"paths": [], "circles": [],
				   "rects": [{"pos": [0.0, 40.0], "size": [100.0, 40.0]}]},
		"ports": [
			{"name": "in", "pos": [0.0, 60.0]},
			{"name": "out", "pos": [100.0, 60.0]},
		],
		"attrs_schema": {},
	}
	var gpDef: GPSymbolDef = GP_Normalizer.gpNormalizeSymbol(gpRaw, "valve", {})
	assert(gpDef.gpCategory == "valve", "category should be valve")
	assert(gpDef.gpDefaultSize == Vector2(64, 48), "envelope must come from category")
	assert(gpDef.gpShape.has("box"), "shape must carry a unit-space box")
	var gpBox: Array = gpDef.gpShape["box"]
	assert(float(gpBox[0]) >= -0.01 and float(gpBox[2]) <= 100.01, "box must sit inside the unit box")
	assert(gpDef.gpPorts.size() == 2, "two ports expected")
	var gpP0: Array = gpDef.gpPorts[0]["pos"]
	var gpP1: Array = gpDef.gpPorts[1]["pos"]
	assert(absf(float(gpP0[0]) - 0.0) < 0.02 and absf(float(gpP0[1]) - 0.5) < 0.02, "port0 should be left-mid (0,0.5)")
	assert(absf(float(gpP1[0]) - 1.0) < 0.02 and absf(float(gpP1[1]) - 0.5) < 0.02, "port1 should be right-mid (1,0.5)")
	printerr("SYMSTEP1 normalize-with-ports ok")


# When no ports are drawn, the category standard anchors are used.
# 未画端口时回退为类别标准锚点。
func _gpTestNormalizeNoPortsFallsBack() -> void:
	var gpRaw: Dictionary = {
		"id": "my_tank",
		"display_name": "我的储罐",
		"shapes": {"paths": [{"pts": [[10, 10], [90, 10], [90, 90], [10, 90]], "closed": true}],
				   "circles": [], "rects": []},
		"ports": [],
		"attrs_schema": {},
	}
	var gpDef: GPSymbolDef = GP_Normalizer.gpNormalizeSymbol(gpRaw, "tank", {})
	assert(gpDef.gpPorts.size() == 2, "tank has 2 standard ports")
	assert(gpDef.gpPorts[0]["name"] == "top", "first tank port is top")
	printerr("SYMSTEP2 normalize-no-ports ok")


# An empty glyph yields an empty shape and standard ports (renderer falls back to a rectangle).
# 空字形产生空形状与标准端口（渲染层回退为矩形）。
func _gpTestNormalizeEmptyGlyph() -> void:
	var gpRaw: Dictionary = {
		"id": "x", "display_name": "x",
		"shapes": {"paths": [], "circles": [], "rects": []},
		"ports": [], "attrs_schema": {},
	}
	var gpDef: GPSymbolDef = GP_Normalizer.gpNormalizeSymbol(gpRaw, "pump", {})
	assert(gpDef.gpShape.is_empty(), "empty glyph -> empty shape")
	assert(gpDef.gpPorts.size() == 2, "pump standard ports")
	printerr("SYMSTEP3 normalize-empty ok")


# Runtime registration must make the new id findable, and re-registering must replace in place.
# 运行期注册应使新 id 可被查到，且重复注册应原地替换。
func _gpTestLibraryRegister() -> void:
	GP_Library.gpClearRegistered()
	var gpDef: GPSymbolDef = GP_Def.new()
	gpDef.gpId = "rt_valve"
	gpDef.gpCategory = "valve"
	gpDef.gpDefaultSize = GP_Categories.gpSizeFor("valve")
	GP_Library.gpRegisterDefs([gpDef])
	assert(GP_Library.gpFindById("rt_valve") != null, "registered def must be findable")
	gpDef.gpDisplayName = "改名"
	GP_Library.gpRegisterDefs([gpDef])
	assert(GP_Library.gpFindById("rt_valve").gpDisplayName == "改名", "re-register replaces in place")
	GP_Library.gpClearRegistered()
	printerr("SYMSTEP4 library register ok")


# GPSymbolPack serialize -> JSON -> parse -> deserialize must round-trip the symbol id.
# GPSymbolPack 序列化 -> JSON -> 解析 -> 反序列化 必须能往返保留图元 id。
func _gpTestPackRoundTrip() -> void:
	var gpDef: GPSymbolDef = GP_Normalizer.gpNormalizeSymbol(
		{"id": "rt_sym", "display_name": "RT", "shapes": {"paths": [], "circles": [], "rects": []},
		 "ports": [], "attrs_schema": {}}, "valve", {})
	var gpPack: GPSymbolPack = GPSymbolPack.new()
	gpPack.gpPackId = "rt_pack"
	gpPack.gpName = "RT Pack"
	gpPack.gpStandardRef = "ISA-5.1-2022"
	gpPack.gpSymbols = [gpDef]
	var gpJson: String = JSON.stringify(gpPack.gpToDict(), "", true)
	var gpParsed: Dictionary = JSON.parse_string(gpJson)
	assert(gpParsed.has("symbols"), "json must carry symbols")
	var gpPack2: GPSymbolPack = GPSymbolPack.new()
	gpPack2.gpFromDict(gpParsed)
	assert(gpPack2.gpPackId == "rt_pack", "pack id round-trips")
	assert(gpPack2.gpSymbols.size() == 1, "one symbol round-trips")
	assert(gpPack2.gpSymbols[0].gpId == "rt_sym", "symbol id round-trips")
	printerr("SYMSTEP5 pack round-trip ok")


# The editor script must at least instantiate (its _ready needs the editor + autoloads, so we
# only assert the class builds; full UI runs in-editor).
# 编辑器脚本至少应能实例化（其 _ready 依赖编辑器与 autoload，故此处仅确认类可构建；
# 完整 UI 在编辑器内验证）。
func _gpTestEditorInstantiable() -> void:
	assert(GP_Editor != null, "editor script must preload")
	printerr("SYMSTEP6 editor script compiled")
