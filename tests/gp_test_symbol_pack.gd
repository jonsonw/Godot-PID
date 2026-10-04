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

# Annotation glyphs that sit ON a line (arrows, flow-direction marks) are artwork, not
# connectable symbols: they are drawn, never wired.
# 标注类图元（箭头、流向标记）是画在线上的美术元素，不是可连接图元：只绘制，不接线。
# Ids follow the project rule L/C/D + category + 3-digit sequence (see GPSymbolNaming).
# id 遵循项目规则 L/C/D + 类别 + 三位序号（见 GPSymbolNaming）。
const GP_LEGEND_IDS: Array[String] = [
	"DGENERAL001", "DGENERAL002",  # 关键介质进/出口箭头 / essential-substance inlet/outlet arrows
	"DGENERAL005", "DGENERAL006",  # 流向（主/支管段）/ direction-of-flow marks
]

# Mountable parts that connect NOTHING. A manhole is an access opening in the wall — a person
# goes through it, a pipe never does — so it must carry no port at all, and its identity is the
# auto-numbered manhole_id ("M1", "M2", ...) instead (the user's real-usage correction: a stray
# port dot plus a bare i18n key where "M1" belongs).
# 可挂载但不连接任何东西的部件。人孔是壁上的进出孔 —— 过人不过管 —— 故**一个端口都不能有**，
# 其标识改用自动编号的 manhole_id（「M1」「M2」……）（用户实测纠正：多出的端口圆点 +
# 本应是「M1」处裸显 i18n 键）。
const GP_PORTLESS_PART_IDS: Array[String] = [
	"DGENERAL007",  # 人孔 / manhole
]


func _gpBuiltinDefs() -> Array[GPSymbolDef]:
	return GPSymbolPackDexpi.gpDefs()


func gpTestEveryBuiltinSymbolHasPorts() -> void:
	var gpDefs: Array[GPSymbolDef] = _gpBuiltinDefs()
	gpEq(gpDefs.size(), 24, "the DEXPI C01 pack holds 24 symbols")
	for gpD in gpDefs:
		if GP_LEGEND_IDS.has(gpD.gpId):
			gpCheck(gpD.gpPorts.is_empty(), "legend glyph carries no ports: %s" % gpD.gpId)
		elif GP_PORTLESS_PART_IDS.has(gpD.gpId):
			gpCheck(gpD.gpPorts.is_empty(),
				"an access opening connects no pipe, so it carries no port: %s" % gpD.gpId)
		else:
			gpCheck(not gpD.gpPorts.is_empty(), "connectable symbol must carry ports: %s" % gpD.gpId)


# The user's third-round corrections, pinned at the PACK level: a nozzle faces OUTWARD with exactly
# one connection; a manhole shows an auto-numbered "M1", not its i18n key.
# 用户第三轮纠正，在 **pack 层**钉死：管嘴只朝**外**一个连接点；人孔显示自动编号「M1」
# 而非其 i18n 键。
func gpTestNozzleFacesOutwardAndAManholeIsNumberedNotKeyed() -> void:
	var gpNoz: GPSymbolDef = _gpDefById("DGENERAL008")
	if gpNoz == null:
		return
	gpEq(gpNoz.gpPorts.size(), 1, "a nozzle carries exactly ONE connection")
	if gpNoz.gpPorts.size() == 1:
		gpEq(gpNoz.gpPorts[0].gpName, "pipe", "the nozzle's only port is the OUTBOARD pipe end")
		gpCheck(gpNoz.gpPorts[0].gpPos.x > 0.5,
			"the only port sits on the outboard half, away from the vessel")
	gpEq(gpNoz.gpPartTagKey, "nozzle_id", "the nozzle numbers itself through nozzle_id")
	gpEq(gpNoz.gpPartTagPrefix, "N", "the nozzle's series letter is N")
	# The DN slot must read "DN80", not a bare number and never a bare "DN" when unset.
	# DN 槽必须读作「DN80」，既不是光秃秃的数字，未填时也绝不能剩一个光秃秃的「DN」。
	var gpDnSlot: GPLabelSlot = null
	for gpS in gpNoz.gpLabelSlots:
		if gpS.gpKey == "dn":
			gpDnSlot = gpS
	gpCheck(gpDnSlot != null, "the nozzle carries a dn label slot")
	if gpDnSlot != null:
		gpEq(gpDnSlot.gpFormat, "DN{prop:nominal_size}",
			"the DN slot prefixes the value with DN")
	var gpMh: GPSymbolDef = _gpDefById("DGENERAL007")
	if gpMh == null:
		return
	gpEq(gpMh.gpPorts.size(), 0, "a manhole carries no port at all")
	gpEq(gpMh.gpPartTagKey, "manhole_id", "the manhole numbers itself through manhole_id")
	gpEq(gpMh.gpPartTagPrefix, "M", "the manhole's series letter is M")
	gpCheck(not gpMh.gpLabelSlots.is_empty(),
		"the manhole shows its number through a label slot, never a bare i18n key")


func gpTestBuiltinPortNamesAreUnique() -> void:
	for gpD in _gpBuiltinDefs():
		gpCheck(gpD.gpPortNamesUnique(), "port names are unique so port_id can be a name: %s"
			% gpD.gpId)


# Every built-in display name must be an i18n key that actually resolves in both languages —
# a raw English string slipped into the pack would show up untranslated in a Chinese drawing.
# 每个内置显示名都必须是能同时解析出中英两种语言的 i18n 键；若包里混进裸英文串，
# 中文图纸上就会出现未翻译的图元名。
func gpTestBuiltinDisplayNamesResolveBilingually() -> void:
	for gpD in _gpBuiltinDefs():
		gpCheck(gpD.gpDisplayName.begins_with("dexpi."),
			"display name is an i18n key: %s" % gpD.gpDisplayName)
		var gpZh: String = I18n.gpTrIn(gpD.gpDisplayName, "zh", gpD.gpDisplayName)
		var gpEn: String = I18n.gpTrIn(gpD.gpDisplayName, "en", gpD.gpDisplayName)
		gpCheck(gpZh != gpD.gpDisplayName, "chinese name resolves: %s" % gpD.gpDisplayName)
		gpCheck(gpEn != gpD.gpDisplayName, "english name resolves: %s" % gpD.gpDisplayName)
		var gpById: GPSymbolDef = _gpDefByDisplayName(gpZh)
		gpCheck(gpById != null and gpById.gpId == gpD.gpId,
			"lookup by chinese name returns the same symbol: %s" % gpD.gpId)


# The vessel is the one multi-nozzle equipment glyph in C01: top, bottom and two side
# nozzles, all process nozzles — that is what lets you land four different lines on it.
# 容器是 C01 中唯一的多管口设备图元：顶 / 底 / 两侧共四个管口，全为工艺管口 ——
# 这正是「在容器上接四条不同管线」得以表达的前提。
func gpTestMultiNozzleEquipment() -> void:
	for gpD in _gpBuiltinDefs():
		match gpD.gpId:
			"DTANK001":  # 碟形封头容器 / vessel with dished heads
				gpEq(gpD.gpPorts.size(), 4, "%s exposes four nozzles" % gpD.gpId)
				gpEq(gpD.gpPortsOfType(GPPort.GP_NOZZLE).size(), 4,
					"%s nozzles are all process nozzles" % gpD.gpId)
			_:
				pass


# A controlled actuator takes a signal line on its TOP signal terminal and drives the valve stem
# by being MOUNTED onto it (规划 §14 / §10 M1). It touches the process itself, so it must NOT
# expose a nozzle.
# 控制执行机构在**顶部**信号端子上接信号线，并通过**挂载**在阀门上驱动阀杆（规划 §14 / §10 M1）。
# 它不直接接触工艺，故不得暴露管口。
#
# WHAT CHANGED AND WHY THE "stem" PORT IS GONE / 变化了什么、以及为何去掉 "stem" 端口：
# the mechanical link used to be a port-to-port EDGE (a "stem" ACTUATOR terminal facing the valve).
# §10 M1 re-expresses it as a MOUNT, because a mount is the relation that actually carries a
# transform: an actuator must ROTATE and MOVE with its valve, and an edge carries no transform at
# all. Once the link is an anchor, an ACTUATOR terminal has nothing left to attach to — and an
# unreachable port is worse than no port, because every signal line drawn to it would be legal
# while nothing in the model would mean anything.
# 机械联系此前是端口到端口的**边**（朝阀门的 "stem" 执行机构端子）。§10 M1 把它改为**挂载**，
# 因为只有挂载才传递变换：执行机构必须随阀门旋转与移动，而边完全不传递变换。一旦联系变成锚点，
# ACTUATOR 端子就再无可接之处 —— 而一个接不通的端口比没有端口更糟，因为连到它的每条信号线都合法，
# 但模型里什么含义都没有。
func gpTestValveActuatorTerminals() -> void:
	var gpD: GPSymbolDef = _gpDefById("DGENERAL004")
	gpCheck(gpD != null, "controlled actuator exists")
	if gpD == null:
		return
	# P3 / §14: the stem edge became a MOUNT, so the ACTUATOR terminal is GONE (assertion inverted
	# from 1 to 0 on purpose — see the doc comment above for the argument).
	# P3 / §14：阀杆边变成了**挂载**，故 ACTUATOR 端子消失（断言刻意由 1 反转为 0 —— 论证见上方注释）。
	gpEq(gpD.gpPortsOfType(GPPort.GP_ACTUATOR).size(), 0,
		"%s no longer exposes an actuator terminal (the stem link is a mount now)" % gpD.gpId)
	gpEq(gpD.gpPortsOfType(GPPort.GP_SIGNAL).size(), 1,
		"%s has exactly one signal terminal" % gpD.gpId)
	gpEq(gpD.gpPortsOfType(GPPort.GP_NOZZLE).size(), 0,
		"%s is not plumbed into the process" % gpD.gpId)
	# "Signal in AND NOTHING ELSE" only means something if the one terminal really is the only way
	# in — so pin the total, not just the per-type counts. A future extra NOZZLE/TERMINAL port would
	# otherwise pass every check above while quietly turning the part into a junction.
	# 「只有信号口」这句话只有在那个口确实是唯一入口时才有意义 —— 故钉住**总数**，而不只是分类型计数。
	# 否则将来多加一个 NOZZLE / TERMINAL 端口会通过以上全部检查，同时悄悄把这个部件变成一个三通。
	gpEq(gpD.gpPorts.size(), 1, "%s exposes exactly one port in total" % gpD.gpId)
	if gpD.gpPorts.size() == 1:
		gpEq(gpD.gpPorts[0].gpName, "sig", "%s sole port is the signal terminal" % gpD.gpId)
		# 顶部 = 包络的上边。执行机构顶端的信号口正是「信号线只能从上面走进来」这一版面约定的
		# 几何表达；落到别的边上，画出来的信号线就会从侧面穿入。
		# Top = the envelope's upper edge. The actuator's top-mounted signal terminal is the
		# geometric form of "a signal line can only come in from above"; on another edge the drawn
		# signal line would enter from the side.
		gpCheck(gpD.gpPorts[0].gpPos.y <= 0.001, "%s signal terminal sits on the TOP edge, got y=%f"
			% [gpD.gpId, gpD.gpPorts[0].gpPos.y])
		gpEq(gpD.gpPorts[0].gpDir, Vector2(0.0, -1.0),
			"%s signal terminal points OUTWARD (up)" % gpD.gpId)
	# And the part side of §14: it must be MOUNTABLE (ACTUATOR) and carry the canonical mount angle
	# that makes its upright glyph land correctly on the valve's top anchor (§14.2).
	# §14 的子件侧：它必须**可挂载**（ACTUATOR），并携带规范的安装角，
	# 使其直立字形能正确落在阀门的顶部锚点上（§14.2）。
	gpEq(gpD.gpMountKind, "ACTUATOR", "%s is mountable as an actuator" % gpD.gpId)
	gpCheck(not is_zero_approx(gpD.gpBaseMountRot),
		"%s carries a non-zero canonical mount angle (its glyph must be turned to land)"
			% gpD.gpId)
	# The FC/FO short labels of §14.3; a missing slot means the reference drawing's "F.C." never
	# appears, which is the whole visible point of the annotation.
	# §14.3 的 FC/FO 短标签；槽缺失则参照图上的 "F.C." 永不出现，而那正是这枚标注可见的全部意义。
	var gpSlot: GPLabelSlot = gpD.gpLabelSlotByKey("fail_action")
	gpCheck(gpSlot != null, "%s carries the fail-action label slot" % gpD.gpId)
	if gpSlot != null:
		gpEq(str(gpSlot.gpShortMap.get("FC 故障关", "")), "F.C.",
			"%s renders FC as the F.C. abbreviation" % gpD.gpId)
		gpEq(str(gpSlot.gpShortMap.get("FO 故障开", "")), "F.O.",
			"%s renders FO as the F.O. abbreviation" % gpD.gpId)


# An instrumentation bubble taps the process from below (proc) and emits a signal (sig).
# C01 ships both the central-room and the field variant, and both must behave the same.
# 仪表气泡从下方取工艺信号（proc）并向外发出信号（sig）。C01 同时提供中控室与现场两种变体，
# 两者行为必须一致。
func gpTestInstrumentBubblesHaveProcessAndSignalPorts() -> void:
	for gpId in ["DINSTRUMENT001", "DINSTRUMENT002"]:
		var gpD: GPSymbolDef = _gpDefById(gpId)
		gpCheck(gpD != null, "symbol exists: %s" % gpId)
		if gpD == null:
			continue
		gpEq(gpD.gpPortsOfType(GPPort.GP_NOZZLE).size(), 1,
			"%s taps the process through one nozzle" % gpId)
		gpEq(gpD.gpPortsOfType(GPPort.GP_SIGNAL).size(), 1,
			"%s emits one signal" % gpId)


# A tee is pierced by the main run and branches off it, so it gets three nozzles.
# 三通被主管贯穿并向分支引出，故为三个管口。
func gpTestTeeHasThreeNozzles() -> void:
	var gpD: GPSymbolDef = _gpDefById("DGENERAL012")
	gpCheck(gpD != null, "t-type connection exists")
	if gpD == null:
		return
	gpEq(gpD.gpPorts.size(), 3, "a tee exposes three nozzles")
	gpEq(gpD.gpPortsOfType(GPPort.GP_NOZZLE).size(), 3, "all three tee ports are nozzles")
	gpCheck(gpD.gpPortNamesUnique(), "tee port names are unique so port_id can be a name")


# A blind cover terminates a flanged branch: it is a TERMINAL, not a nozzle, so no process
# line can be routed through it by accident.
# 盲板用于封堵法兰支管：它是 TERMINAL 而非管口，因此不会被误接工艺管线。
func gpTestBlindCoverIsTerminalOnly() -> void:
	var gpD: GPSymbolDef = _gpDefById("DGENERAL003")
	gpCheck(gpD != null, "blind cover exists")
	if gpD == null:
		return
	gpEq(gpD.gpPortsOfType(GPPort.GP_TERMINAL).size(), 1, "a blind cover has one terminal")
	gpEq(gpD.gpPortsOfType(GPPort.GP_NOZZLE).size(), 0, "a blind cover has no nozzle")


# A manhole is an ACCESS opening in the vessel wall — a person goes through it, a pipe never does
# — so it carries no port of ANY kind, and its identity is the auto-numbered manhole_id
# ("M1", "M2", ...), not a connection (the user's real-usage correction).
# 人孔是设备壁上的**进出**孔 —— 过人不过管 —— 故任何类型的端口都没有，其标识是自动编号的
# manhole_id（「M1」「M2」……）而非连接点（用户实测纠正）。
func gpTestManholeIsTerminalOnly() -> void:
	var gpD: GPSymbolDef = _gpDefById("DGENERAL007")
	gpCheck(gpD != null, "manhole exists")
	if gpD == null:
		return
	gpEq(gpD.gpPorts.size(), 0, "a manhole connects nothing: no terminal, no nozzle, no port")
	gpEq(gpD.gpPortsOfType(GPPort.GP_TERMINAL).size(), 0, "a manhole has no terminal")
	gpEq(gpD.gpPortsOfType(GPPort.GP_NOZZLE).size(), 0, "a manhole has no nozzle")


# Every C01 glyph carries the real millimetre size measured off the reference drawing
# (1 world unit == 1 mm): a vessel is 30x51 mm while a valve is 4x2 mm. Pinning the extreme
# pair catches a generator regression that would silently flatten the whole pack to one size.
# 每个 C01 图元都带有从标准图实测的毫米尺寸（1 世界单位 = 1 mm）：容器 30x51 mm，
# 而阀门仅 4x2 mm。钉住这一极端组合，可捕获「生成器把整包压成同一尺寸」的回归。
func gpTestRealMillimetreSizesFromC01() -> void:
	var gpTank: GPSymbolDef = _gpDefById("DTANK001")
	var gpValve: GPSymbolDef = _gpDefById("DVALVE002")
	gpCheck(gpTank != null and gpValve != null, "vessel and ball valve exist")
	if gpTank != null:
		gpCheck(absf(gpTank.gpDefaultSize.x - 30.0) < 0.5 and absf(gpTank.gpDefaultSize.y - 51.0) < 0.5,
			"vessel keeps its real C01 size 30x51 mm, got %s" % gpTank.gpDefaultSize)
	if gpValve != null:
		gpCheck(absf(gpValve.gpDefaultSize.x - 4.0) < 0.5 and absf(gpValve.gpDefaultSize.y - 2.0) < 0.5,
			"ball valve keeps its real C01 size 4x2 mm, got %s" % gpValve.gpDefaultSize)
	if gpTank != null and gpValve != null:
		gpCheck(gpTank.gpDefaultSize.y > gpValve.gpDefaultSize.y * 5.0,
			"canvas proportions follow C01: the vessel dwarfs the valve")


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


# Look-up by display name. Since the L/C/D naming rule an id is ALLOCATED from the category,
# so the sequence part shifts whenever a symbol is inserted before another one; tests that
# name ids would break on every such insertion. The display name is the stable handle.
# A display name may now be an i18n key ("dexpi.xxx"), so it is compared against BOTH the
# Chinese and the English rendering (never merely the current UI locale) — that keeps these
# tests readable in Chinese while the pack stores keys, and keeps them stable when another
# suite flips gpLocale.
# 按显示名查找。自 L/C/D 命名规则起，id 由类别「分配」而来，一旦在某个图元之前插入新图元，
# 其后的序号就会平移；写死 id 的测试会在每次插入时失效。显示名才是稳定句柄。
# 显示名如今可能是 i18n 键（"dexpi.xxx"），故同时与「中文」「英文」两种渲染比较
#（而非仅当前界面语言）—— 这样符号包存键，测试仍可用中文名书写，且在他处切换 gpLocale 时稳定。
func _gpDefByDisplayName(gpName: String) -> GPSymbolDef:
	for gpD in _gpBuiltinDefs():
		if gpD.gpDisplayName == gpName:
			return gpD
		var gpZh: String = I18n.gpTrIn(gpD.gpDisplayName, "zh", gpD.gpDisplayName)
		var gpEn: String = I18n.gpTrIn(gpD.gpDisplayName, "en", gpD.gpDisplayName)
		if gpZh == gpName or gpEn == gpName:
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
