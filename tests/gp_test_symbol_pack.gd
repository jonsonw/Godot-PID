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


# ---- P1: built-in symbols must SHIP with ports ----
# ---- P1：内置图元必须自带端口 ----
# Before P1 every built-in symbol had an empty gpPorts because the generator's SVG scan was
# dead code (it matched namespace-prefixed tags against bare-tag SVGs). Pipes could therefore
# only be attached to a node centre — "connect this line to the shell side of the exchanger"
# was not expressible. These assertions are the guard that ports stay in the pack.
# P1 之前每个内置图元的 gpPorts 都是空的，因为生成器的 SVG 扫描是死代码（用带命名空间前缀的
# 标签去匹配裸标签 SVG）。于是管线只能连到节点中心 ——「把这条管线接到换热器壳程」无法表达。
# 以下断言就是「端口必须留在包里」的护栏。

# Legend glyphs (the three line-type samples) are artwork, not connectable symbols.
# 图例符号（三个线型样例）是美术元素，不是可连接图元。
# The three line-type samples are artwork, not connectable symbols. Ids follow the project
# rule L/C + category + 3-digit sequence (see GPSymbolNaming).
# 三个线型样例是美术元素，不是可连接图元。id 遵循项目规则 L/C + 类别 + 三位序号
#（见 GPSymbolNaming）。
const GP_LEGEND_IDS: Array[String] = [
	"LGENERAL003", "LGENERAL002", "LGENERAL001",  # ProcessLine / InstrumentLine / ElectricalLine
]


func _gpBuiltinDefs() -> Array[GPSymbolDef]:
	return GPSymbolPackIso_10628.gpDefs()


func gpTestEveryBuiltinSymbolHasPorts() -> void:
	var gpDefs: Array[GPSymbolDef] = _gpBuiltinDefs()
	gpEq(gpDefs.size(), 25, "the ISO pack still holds 25 symbols")
	for gpD in gpDefs:
		if GP_LEGEND_IDS.has(gpD.gpId):
			gpCheck(gpD.gpPorts.is_empty(), "legend glyph carries no ports: %s" % gpD.gpId)
		else:
			gpCheck(not gpD.gpPorts.is_empty(), "connectable symbol must carry ports: %s" % gpD.gpId)


func gpTestBuiltinPortNamesAreUnique() -> void:
	for gpD in _gpBuiltinDefs():
		gpCheck(gpD.gpPortNamesUnique(), "port names are unique so port_id can be a name: %s"
			% gpD.gpId)


func gpTestMultiNozzleEquipment() -> void:
	for gpD in _gpBuiltinDefs():
		match gpD.gpId:
			"LHEAT001", "LTANK001":  # 换热器 / 储罐
				gpEq(gpD.gpPorts.size(), 4, "%s exposes four nozzles" % gpD.gpId)
				gpEq(gpD.gpPortsOfType(GPPort.GP_NOZZLE).size(), 4,
					"%s nozzles are all process nozzles" % gpD.gpId)
			_:
				pass


# A control valve, an actuator and a positioner each take a signal line on their actuator
# terminal — that is what makes "wire the controller to the valve" expressible at all.
# 调节阀、执行器与定位器各有一个执行机构端子用于接信号线 —— 这正是「把控制器接到阀门上」
# 得以表达的前提。
func gpTestValveActuatorTerminals() -> void:
	for gpName in ["调节阀", "阀门执行器", "阀门定位器"]:
		var gpD: GPSymbolDef = _gpDefByDisplayName(gpName)
		gpCheck(gpD != null, "symbol exists: %s" % gpName)
		if gpD == null:
			continue
		gpEq(gpD.gpPortsOfType(GPPort.GP_ACTUATOR).size(), 1,
			"%s has exactly one actuator terminal" % gpName)
		gpEq(gpD.gpPortsOfType(GPPort.GP_NOZZLE).size(), 2,
			"%s keeps its two process nozzles" % gpName)


func gpTestTransmittersHaveProcessAndSignalPorts() -> void:
	for gpName in ["流量变送器", "压力变送器", "液位变送器", "温度变送器"]:
		var gpD: GPSymbolDef = _gpDefByDisplayName(gpName)
		gpCheck(gpD != null, "symbol exists: %s" % gpName)
		if gpD == null:
			continue
		gpEq(gpD.gpPortsOfType(GPPort.GP_NOZZLE).size(), 1,
			"%s taps the process through one nozzle" % gpName)
		gpEq(gpD.gpPortsOfType(GPPort.GP_SIGNAL).size(), 1,
			"%s emits one signal" % gpName)


# In-line indicators are pierced by the pipe, so they get two nozzles plus a signal terminal.
# 就地指示表被管线贯穿，故两个管口 + 一个信号端子。
func gpTestInLineIndicators() -> void:
	for gpName in ["流量指示器", "压力指示器", "温度指示器", "液位指示器"]:
		var gpD: GPSymbolDef = _gpDefByDisplayName(gpName)
		gpCheck(gpD != null, "symbol exists: %s" % gpName)
		if gpD == null:
			continue
		gpEq(gpD.gpPortsOfType(GPPort.GP_NOZZLE).size(), 2, "%s has two nozzles" % gpName)
		gpEq(gpD.gpPortsOfType(GPPort.GP_SIGNAL).size(), 1,
			"%s has one signal terminal" % gpName)


func gpTestFieldEnclosureIsSignalOnly() -> void:
	var gpD: GPSymbolDef = _gpDefByDisplayName("现场接线箱")
	gpCheck(gpD != null, "field enclosure exists")
	if gpD != null:
		gpEq(gpD.gpPortsOfType(GPPort.GP_SIGNAL).size(), 2, "a field enclosure has two terminals")
		gpEq(gpD.gpPortsOfType(GPPort.GP_NOZZLE).size(), 0, "a field enclosure has no nozzle")


# The GDScript table and the generator's Python table must agree: a user symbol created from
# a category gets its ports from GPSymbolCategories, so if the two drifted, a built-in valve
# and a user valve would not behave the same when you try to connect a pipe.
# GDScript 表与生成器的 Python 表必须一致：按类别创建的用户图元从 GPSymbolCategories 取端口，
# 若两者脱节，内置阀门与用户阀门在连线时行为就会不同。
func gpTestCategoryTableMatchesGeneratedPack() -> void:
	for gpD in _gpBuiltinDefs():
		var gpFromTable: Array[Dictionary] = GPSymbolCategories.gpPortsForSymbol(
			gpD.gpId, gpD.gpCategory)
		gpEq(gpFromTable.size(), gpD.gpPorts.size(),
			"table and pack agree on the port count: %s" % gpD.gpId)
		for gpI in range(mini(gpFromTable.size(), gpD.gpPorts.size())):
			gpEq(str(gpFromTable[gpI].get("name", "")), gpD.gpPorts[gpI].gpName,
				"table and pack agree on port %d of %s" % [gpI, gpD.gpId])
			gpEq(str(gpFromTable[gpI].get("type", "")), gpD.gpPorts[gpI].gpType,
				"table and pack agree on the purpose of port %d of %s" % [gpI, gpD.gpId])


func _gpDefById(gpId: String) -> GPSymbolDef:
	for gpD in _gpBuiltinDefs():
		if gpD.gpId == gpId:
			return gpD
	return null


# Look-up by display name. Since the L/C naming rule an id is ALLOCATED from the category,
# so the sequence part shifts whenever a symbol is inserted before another one; tests that
# name ids would break on every such insertion. The display name is the stable handle.
# 按显示名查找。自 L/C 命名规则起，id 由类别「分配」而来，一旦在某个图元之前插入新图元，
# 其后的序号就会平移；写死 id 的测试会在每次插入时失效。显示名才是稳定句柄。
func _gpDefByDisplayName(gpName: String) -> GPSymbolDef:
	for gpD in _gpBuiltinDefs():
		if gpD.gpDisplayName == gpName:
			return gpD
	return null


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
