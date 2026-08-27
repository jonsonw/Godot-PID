extends SceneTree
# Lean model-layer validator for the W2 export core (no UI/library preloads, which are
# validated in-editor). Forces categories/def/normalizer/pack to compile and round-trips the
# normalize -> pack -> JSON path the wizard relies on.
# W2 导出核心的精简模型层校验（不预加载 UI/库，它们在编辑器内验证）。强制
# categories/def/normalizer/pack 编译，并往返测试向导依赖的归一化 -> 打包 -> JSON 路径。
const C := preload("res://src/core/symbol_categories.gd")
const D := preload("res://src/core/symbol_def.gd")
const N := preload("res://src/core/symbol_normalizer.gd")
const P := preload("res://src/model/symbol_pack.gd")

func _initialize() -> void:
	printerr("CORE0 compile ok")

	# valve glyph with two end ports -> valve-sized def, 0..1 ports on left/right edges
	var raw = {"id":"my_valve","display_name":"我的阀门",
		"shapes":{"paths":[],"circles":[],"rects":[{"pos":[0.0,40.0],"size":[100.0,40.0]}]},
		"ports":[{"name":"in","pos":[0.0,60.0]},{"name":"out","pos":[100.0,60.0]}],"attrs_schema":{}}
	var d: GPSymbolDef = N.gpNormalizeSymbol(raw, "valve", {})
	assert(d.gpCategory == "valve", "cat=valve")
	assert(d.gpDefaultSize == Vector2(64,48), "env from category")
	assert(d.gpShape.has("box"), "has box")
	var p0: Array = d.gpPorts[0]["pos"]; var p1: Array = d.gpPorts[1]["pos"]
	assert(absf(float(p0[0]))<0.02 and absf(float(p0[1])-0.5)<0.02, "port0 (0,0.5)")
	assert(absf(float(p1[0])-1.0)<0.02 and absf(float(p1[1])-0.5)<0.02, "port1 (1,0.5)")
	printerr("CORE1 normalize-with-ports ok")

	# no ports -> category standard anchors
	var raw2 = {"id":"my_tank","display_name":"x",
		"shapes":{"paths":[{"pts":[[10,10],[90,10],[90,90],[10,90]],"closed":true}],"circles":[],"rects":[]},
		"ports":[],"attrs_schema":{}}
	var d2: GPSymbolDef = N.gpNormalizeSymbol(raw2, "tank", {})
	assert(d2.gpPorts.size()==2 and d2.gpPorts[0]["name"]=="top", "tank standard ports")
	printerr("CORE2 no-ports fallback ok")

	# empty glyph -> empty shape + standard ports
	var d3: GPSymbolDef = N.gpNormalizeSymbol(
		{"id":"x","display_name":"x","shapes":{"paths":[],"circles":[],"rects":[]},"ports":[],"attrs_schema":{}}, "pump", {})
	assert(d3.gpShape.is_empty() and d3.gpPorts.size()==2, "empty glyph fallback")
	printerr("CORE3 empty glyph ok")

	# pack round-trip
	var pk: GPSymbolPack = GPSymbolPack.new()
	pk.gpPackId = "rt_pack"; pk.gpName = "RT Pack"; pk.gpStandardRef = "ISA-5.1-2022"; pk.gpSymbols = [d]
	var js: String = JSON.stringify(pk.gpToDict(), "", true)
	var parsed: Dictionary = JSON.parse_string(js)
	var pk2: GPSymbolPack = GPSymbolPack.new(); pk2.gpFromDict(parsed)
	assert(pk2.gpPackId=="rt_pack" and pk2.gpSymbols.size()==1 and pk2.gpSymbols[0].gpId=="my_valve", "pack round-trip")
	printerr("CORE4 pack round-trip ok")

	printerr("CORE_OK")
	var f: FileAccess = FileAccess.open("/tmp/symcore_result.txt", FileAccess.WRITE)
	if f != null: f.store_string("CORE_OK\n"); f.close()
	quit()
