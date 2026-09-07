extends "res://tests/gp_test.gd"
# Headless regression tests for GPSymbolPack round-trip and GPSymbolNormalizer port
# normalization (migrated from the legacy tools/_checker_symcore.gd).
# GPSymbolPack 往返与 GPSymbolNormalizer 端口归一化的 headless 回归测试
# （自遗留 tools/_checker_symcore.gd 迁移而来）。
# These assertions were previously unreachable: no gp_test_* suite referenced
# GPSymbolPack at all, so pack serialization was an untested blind spot.
# 这些断言此前无法触达：全部 gp_test_* 套件均未涉及 GPSymbolPack，
# 符号包序列化属于未被测试的盲区。
# NOTE: gpShapes/gpPorts are typed Arrays (Array[GPShape] / Array[GPPort]), not
# dictionaries — read them through gpName / gpPos, never via string keys.
# 注意：gpShapes/gpPorts 为强类型数组（Array[GPShape] / Array[GPPort]），
# 须通过 gpName / gpPos 读取，不可用字符串键索引。


# Build a raw valve glyph with two end ports (author coords 0..100).
# 构造一个带两个端部端口的原始阀门图形（作者坐标 0..100）。
func _gpRawValve() -> Dictionary:
	return {
		"id": "my_valve", "display_name": "我的阀门",
		"shapes": {
			"paths": [], "circles": [],
			"rects": [{"pos": [0.0, 40.0], "size": [100.0, 40.0]}]
		},
		"ports": [
			{"name": "in", "pos": [0.0, 60.0]},
			{"name": "out", "pos": [100.0, 60.0]}
		],
		"attrs_schema": {}
	}


# Normalizing a glyph with two end ports keeps the category envelope and
# re-anchors the ports onto the normalized 0..1 unit square.
# 归一化带两个端部端口的图形：保留类别默认尺寸，并把端口重锚到 0..1 单位方。
func gpTestNormalizeWithPorts() -> void:
	var gpD: GPSymbolDef = GPSymbolNormalizer.gpNormalizeSymbol(_gpRawValve(), "valve", {})
	gpCheck(gpD.gpCategory == "valve", "normalized category should be valve")
	gpCheck(gpD.gpDefaultSize.x > 0.0 and gpD.gpDefaultSize.y > 0.0,
		"default size should be a positive category envelope")
	gpCheck(not gpD.gpShapes.is_empty(), "a glyph with a rect should normalize to shapes")
	gpCheck(gpD.gpPorts.size() == 2, "two ports should be preserved")
	if gpD.gpPorts.size() == 2:
		var gpP0: GPPort = gpD.gpPorts[0]
		var gpP1: GPPort = gpD.gpPorts[1]
		gpCheck(absf(gpP0.gpPos.x - 0.0) < 0.02 and absf(gpP0.gpPos.y - 0.5) < 0.02,
			"first port should normalize to (0, 0.5)")
		gpCheck(absf(gpP1.gpPos.x - 1.0) < 0.02 and absf(gpP1.gpPos.y - 0.5) < 0.02,
			"second port should normalize to (1, 0.5)")


# A glyph with no explicit ports falls back to the category standard anchors.
# 未显式声明端口的图形应回退到类别标准锚点。
func gpTestNormalizeWithoutPorts() -> void:
	var gpRaw: Dictionary = {
		"id": "my_tank", "display_name": "x",
		"shapes": {
			"paths": [{"pts": [[10, 10], [90, 10], [90, 90], [10, 90]], "closed": true}],
			"circles": [], "rects": []
		},
		"ports": [], "attrs_schema": {}
	}
	var gpD: GPSymbolDef = GPSymbolNormalizer.gpNormalizeSymbol(gpRaw, "tank", {})
	gpCheck(gpD.gpPorts.size() == 2, "tank should fall back to standard ports")
	if gpD.gpPorts.size() > 0:
		gpCheck(gpD.gpPorts[0].gpName == "top", "first standard port should be named top")


# An empty glyph still yields a valid def with standard ports.
# 空图形仍应产出带标准端口的有效定义。
func gpTestNormalizeEmptyGlyph() -> void:
	var gpD: GPSymbolDef = GPSymbolNormalizer.gpNormalizeSymbol(
		{"id": "x", "display_name": "x",
		 "shapes": {"paths": [], "circles": [], "rects": []},
		 "ports": [], "attrs_schema": {}}, "pump", {})
	gpCheck(gpD.gpShapes.is_empty(), "empty glyph should normalize to no shapes")
	gpCheck(gpD.gpPorts.size() == 2, "empty glyph should still carry standard ports")


# A pack survives JSON stringify -> parse -> from_dict with its symbols intact.
# 符号包经 JSON 序列化 -> 解析 -> from_dict 后应保持符号完整。
func gpTestPackRoundTrip() -> void:
	var gpDef: GPSymbolDef = GPSymbolNormalizer.gpNormalizeSymbol(_gpRawValve(), "valve", {})

	var gpPack: GPSymbolPack = GPSymbolPack.new()
	gpPack.gpPackId = "rt_pack"
	gpPack.gpName = "RT Pack"
	gpPack.gpStandardRef = "ISA-5.1-2022"
	gpPack.gpSymbols = [gpDef]

	var gpJson: String = JSON.stringify(gpPack.gpToDict(), "", true)
	var gpParsed: Variant = JSON.parse_string(gpJson)
	gpCheck(typeof(gpParsed) == TYPE_DICTIONARY, "pack JSON should parse back into a dictionary")
	if typeof(gpParsed) != TYPE_DICTIONARY:
		return

	var gpPack2: GPSymbolPack = GPSymbolPack.new()
	gpPack2.gpFromDict(gpParsed)
	gpCheck(gpPack2.gpPackId == "rt_pack", "pack id should survive the round-trip")
	gpCheck(gpPack2.gpSymbols.size() == 1, "one symbol should survive the round-trip")
	if gpPack2.gpSymbols.size() == 1:
		gpCheck(gpPack2.gpSymbols[0].gpId == "my_valve", "symbol id should survive the round-trip")
