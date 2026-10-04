class_name GPSymbolCategories
extends RefCounted

# Copyright © 2026 Jonson Wang
# Single source of truth for per-category nominal envelope sizes and standard port anchors.
# 类别标称包络尺寸与标准端口锚点的唯一事实来源。
# Why: symbols of the same family MUST render at the same size on the canvas, otherwise a
# gate valve and a globe valve placed on one line look mismatched. Sizes therefore belong to
# the CATEGORY, never to the individual glyph's original SVG dimensions.
# 原因：同族图元在画布上必须等大，否则同一管线上的闸阀与截止阀会大小不一。因此尺寸归属
# 「类别」，绝不取单个字形原始 SVG 的尺寸。
# See 符号编辑器设计说明 §5.2 / §6 / §7.
# 见《符号编辑器设计说明》§5.2 / §6 / §7。

# Category -> nominal envelope size in millimetres (world-unit == 1 mm from v0.1, see plan Phase 0).
# 类别 → 标称包络尺寸（毫米；从 v0.1 起世界单位 = 1mm，见计划 Phase 0）。
# This is ONLY a fallback for symbols that carry no explicit size (e.g. user-drawn glyphs or
# packs that omit size_mm); the built-in DEXPI pack writes each symbol's real C01 mm size
# per-symbol via the generator (see plan Phase 4), so the per-family equal-size rule yields to
# the real standard proportions there. The ISO 10628 pack hardcodes its own sizes and is
# unaffected by this table.
# 这仅是「无显式尺寸的图元」的兜底（如用户手绘图元或省略 size_mm 的包）；内置 DEXPI 包经生成器
# 逐符号写入真实 C01 毫米尺寸（见计划 Phase 4），故同族等大规则在那里让位于真实标准比例。
# ISO 10628 包自行硬编码尺寸，不受本表影响。
const GP_NOMINAL: Dictionary = {
	"valve": Vector2(12, 9),
	"pump": Vector2(15, 11),
	"tank": Vector2(14, 20),
	"instrument": Vector2(11, 11),
	"heat": Vector2(16, 12),
	"general": Vector2(12, 12),
}

# Fallback envelope for unknown categories, in millimetres.
# 未知类别的兜底包络尺寸（毫米）。
const GP_FALLBACK_SIZE: Vector2 = Vector2(12, 12)

# Category -> standard port anchors, normalized 0..1 against the nominal envelope.
# 类别 → 标准端口锚点，相对标称包络归一化到 0..1。
# (0,0) = top-left of the envelope, (1,1) = bottom-right; "dir" is the outward normal.
# (0,0) = 包络左上角，(1,1) = 右下角；"dir" 为向外法线方向。
# "type" is the port purpose and decides which line kind may attach (see GPPort.GP_*).
# "type" 是端口用途，决定可接哪类连线（见 GPPort.GP_*）。
const GP_STD_PORTS: Dictionary = {
	"valve": [
		{"name": "in", "pos": [0.0, 0.5], "dir": [-1, 0], "type": "NOZZLE"},
		{"name": "out", "pos": [1.0, 0.5], "dir": [1, 0], "type": "NOZZLE"},
	],
	"pump": [
		{"name": "in", "pos": [0.0, 0.5], "dir": [-1, 0], "type": "NOZZLE"},
		{"name": "out", "pos": [1.0, 0.5], "dir": [1, 0], "type": "NOZZLE"},
	],
	"heat": [
		{"name": "in", "pos": [0.0, 0.5], "dir": [-1, 0], "type": "NOZZLE"},
		{"name": "out", "pos": [1.0, 0.5], "dir": [1, 0], "type": "NOZZLE"},
	],
	"tank": [
		{"name": "top", "pos": [0.5, 0.0], "dir": [0, -1], "type": "NOZZLE"},
		{"name": "bottom", "pos": [0.5, 1.0], "dir": [0, 1], "type": "NOZZLE"},
	],
	# A transmitter is tapped into the process (proc, bottom) and emits a signal (sig, top).
	# 变送器从工艺侧取压/取样（proc 在下），并向上发出信号（sig 在上）。
	"instrument": [
		{"name": "proc", "pos": [0.5, 1.0], "dir": [0, 1], "type": "NOZZLE"},
		{"name": "sig", "pos": [0.5, 0.0], "dir": [0, -1], "type": "SIGNAL"},
	],
}

# Per-symbol port overrides, keyed by symbol id. A present key REPLACES the category table
# entirely, so a four-nozzle heat exchanger does not have to inherit a two-nozzle default.
# 按符号 id 的端口覆盖表。存在该键即「整体替换」类别表，故四管口换热器无需继承两管口默认值。
#
# Mirrors PORT_OVERRIDES in tools/gen_symbol_packs.py. gp_test_symbol_pack.gd asserts that a
# built-in symbol and a user symbol of the same category end up with the same ports, because
# GPSymbolNormalizer falls back to this table for user symbols with no ports of their own.
# 与 tools/gen_symbol_packs.py 的 PORT_OVERRIDES 镜像。gp_test_symbol_pack.gd 断言同类别的
# 内置图元与用户图元端口一致，因为 GPSymbolNormalizer 对用户自建的无端口图元走本表回退。
const GP_PORT_OVERRIDES: Dictionary = {
	# ---- DEXPI C01 包（v0.1 标准集）----
	# 与 assets/symbol_packs/dexpi/manifest.json 的逐符号端口互为镜像：
	# 包自带端口；本表让「按类别新建的用户图元」与内置图元行为一致，并由
	# gp_test_symbol_pack.gpTestCategoryTableMatchesGeneratedPack 断言两侧不脱节。
	# ---- DEXPI C01 pack (v0.1 standard set) ----
	# Mirrors the per-symbol ports in assets/symbol_packs/dexpi/manifest.json: the pack
	# carries its own; this table keeps user symbols created from a category behaving like
	# their built-in twins, and gp_test_symbol_pack pins the two sides together.
	"DVALVE001": [
		{"name": "in", "pos": [0.33, 1.0], "dir": [0, 1], "type": "NOZZLE"},
		{"name": "out", "pos": [1.0, 0.14], "dir": [1, 0], "type": "NOZZLE"},
	],
	# 盲板：单侧法兰端点 / blind cover: a single terminal on the flanged side
	"DGENERAL003": [
		{"name": "end", "pos": [0.5, 0.0], "dir": [0, -1], "type": "TERMINAL"},
	],
	# 控制执行机构：**仅**顶部一个信号口（规划 §14）。
	# 机械联系（杆驱动阀体）不再是一条端口到端口的边，而是**挂载**：执行机构装在阀门的
	# top_actuator 锚点上，故它自己不再需要 "stem" 执行机构端口。若两表脱节，
	# gpTestCategoryTableMatchesGeneratedPack 会立刻变红 —— 本表必须与 manifest 的 ports 一致。
	# Controlled actuator: the TOP signal terminal and NOTHING else (规划 §14). The mechanical link
	# (stem drives the body) is no longer a port-to-port EDGE but a MOUNT — the actuator sits on the
	# valve's top_actuator anchor — so it no longer needs a "stem" ACTUATOR terminal of its own.
	# If this table drifts from the manifest, gpTestCategoryTableMatchesGeneratedPack goes red:
	# the two MUST list the same ports.
	"DGENERAL004": [
		{"name": "sig", "pos": [0.5, 0.0], "dir": [0, -1], "type": "SIGNAL"},
	],
	# 换热器：壳程左右两管口 / exchanger: two shell-side nozzles
	"DHEAT001": [
		{"name": "shell_in", "pos": [0.0, 0.5], "dir": [-1, 0], "type": "NOZZLE"},
		{"name": "shell_out", "pos": [1.0, 0.5], "dir": [1, 0], "type": "NOZZLE"},
	],
	"DHEAT002": [
		{"name": "shell_in", "pos": [0.0, 0.5], "dir": [-1, 0], "type": "NOZZLE"},
		{"name": "shell_out", "pos": [1.0, 0.5], "dir": [1, 0], "type": "NOZZLE"},
	],
	# 仪表气泡：下方取自工艺、上方发出信号 / bubble: taps the process below, signals above
	"DINSTRUMENT001": [
		{"name": "proc", "pos": [0.5, 1.0], "dir": [0, 1], "type": "NOZZLE"},
		{"name": "sig", "pos": [0.5, 0.0], "dir": [0, -1], "type": "SIGNAL"},
	],
	"DINSTRUMENT002": [
		{"name": "proc", "pos": [0.5, 1.0], "dir": [0, 1], "type": "NOZZLE"},
		{"name": "sig", "pos": [0.5, 0.0], "dir": [0, -1], "type": "SIGNAL"},
	],
	# 人孔：设备壁上的进出孔 —— **不是**工艺连接，没有任何端口。
	# manhole: an access opening, NOT a process connection — it carries no port at all.
	"DGENERAL007": [],
	# 接管嘴：只有一条朝**外**的连接（内端与设备的接合面是挂载，不是端口）。
	# nozzle: ONE outward connection — the inboard end where it meets the vessel is a mount,
	# not a port.
	"DGENERAL008": [
		{"name": "pipe", "pos": [1.0, 0.5], "dir": [1, 0], "type": "NOZZLE"},
	],
	# 保温管道：穿过的管段两端 / insulated piping: the run passes straight through
	"DGENERAL009": [
		{"name": "in", "pos": [0.0, 0.5], "dir": [-1, 0], "type": "NOZZLE"},
		{"name": "out", "pos": [1.0, 0.5], "dir": [1, 0], "type": "NOZZLE"},
	],
	# 异径管 / reducer
	"DGENERAL010": [
		{"name": "in", "pos": [0.0, 0.5], "dir": [-1, 0], "type": "NOZZLE"},
		{"name": "out", "pos": [1.0, 0.5], "dir": [1, 0], "type": "NOZZLE"},
	],
	# 管道坡度 / slope
	"DGENERAL011": [
		{"name": "in", "pos": [0.0, 0.5], "dir": [-1, 0], "type": "NOZZLE"},
		{"name": "out", "pos": [1.0, 0.5], "dir": [1, 0], "type": "NOZZLE"},
	],
	# T 型三通：主管左右贯通 + 下方支管 / tee: main run left-right plus a branch downward
	"DGENERAL012": [
		{"name": "in", "pos": [0.0, 0.0], "dir": [-1, 0], "type": "NOZZLE"},
		{"name": "out", "pos": [1.0, 0.0], "dir": [1, 0], "type": "NOZZLE"},
		{"name": "branch", "pos": [0.5, 1.0], "dir": [0, 1], "type": "NOZZLE"},
	],
	# 容器：顶 / 底 / 两侧 / vessel: top, bottom and two side nozzles
	"DTANK001": [
		{"name": "top", "pos": [0.5, 0.0], "dir": [0, -1], "type": "NOZZLE"},
		{"name": "bottom", "pos": [0.5, 1.0], "dir": [0, 1], "type": "NOZZLE"},
		{"name": "left", "pos": [0.0, 0.5], "dir": [-1, 0], "type": "NOZZLE"},
		{"name": "right", "pos": [1.0, 0.5], "dir": [1, 0], "type": "NOZZLE"},
	],
}

# Glyph fit margin inside the 100x100 unit box during normalization.
# 归一化时字形塞入 100x100 单位框的留边系数。
# 1.0 means "touch the unit box" so that edge ports coincide with the drawn endpoints;
# lower it only if a category needs visual padding.
# 1.0 表示「贴合单位框」，使边缘端口与绘制端点重合；仅在某类别需要视觉留白时才调低。
const GP_FIT_MARGIN: float = 1.0


# ---- Mounting: standard attach anchors per category (P3) ----
# ---- 挂载：各类别的标准安装锚点（P3）----
# A mount is the SECOND relationship beside a port: an edge means "flow from here to there", a
# mount means "this part is fitted ONTO that part" (see 图元层级架构规划 §2). This table is its
# host side, and it is the exact structural twin of GP_STD_PORTS — including the fallback rule,
# so a USER symbol created from a category ends up with the same anchoring sockets as its
# built-in twin.
# 挂载是与端口并列的**第二种**关系：边表示「从这里流到那里」，挂载表示「这个部件**装**在那个
# 部件上」（见规划 §2）。本表是它的宿主侧，与 GP_STD_PORTS 结构完全同构 —— 连同回退规则，
# 使按类别新建的用户图元拥有与内置同族图元相同的锚点插座。
#
# Anchor keys mirror GPAttachPoint: name / pos / dir / accepts / default_child / required /
# default_props. See tools/gen_symbol_packs.py::STD_ATTACH, which is the mirrored source.
# 锚点键镜像 GPAttachPoint：name / pos / dir / accepts / default_child / required / default_props。
# 镜像源见 tools/gen_symbol_packs.py::STD_ATTACH。
const GP_STD_ATTACH: Dictionary = {
	# 阀门：顶部一个执行机构锚点（规划 §14.2）。刻意不默认实例化执行机构 —— 普通阀门不需要，
	# 由用户在右键菜单按需添加（§16.6「不自动生成多余件」）。
	# valve: one actuator anchor on top (§14.2), deliberately with NO default child.
	"valve": [
		{"name": "top_actuator", "pos": [0.5, 0.0], "dir": [0, -1], "accepts": ["ACTUATOR"]},
	],
	# 泵（A 类，§16.3）：吸入 + 排出两支内置管口，位置由泵型决定故不可卸下。
	# pump (class A, §16.3): suction + discharge, both built in and non-removable.
	"pump": [
		{"name": "pump_suction", "pos": [0.0, 0.5], "dir": [-1, 0], "accepts": ["NOZZLE"],
			"default_child": "DGENERAL008", "required": true,
			"default_props": {"nozzle_id": "N1"}},
		{"name": "pump_discharge", "pos": [0.5, 0.0], "dir": [0, -1], "accepts": ["NOZZLE"],
			"default_child": "DGENERAL008", "required": true,
			"default_props": {"nozzle_id": "N2"}},
	],
	# 换热器（A 类，§16.3）：N1..N4 四个内置管口，编号按参照图。
	# heat exchanger (class A, §16.3): four built-in nozzles N1..N4.
	"heat": [
		{"name": "hx_n3", "pos": [0.0, 0.25], "dir": [-1, 0], "accepts": ["NOZZLE"],
			"default_child": "DGENERAL008", "required": true,
			"default_props": {"nozzle_id": "N3"}},
		{"name": "hx_n2", "pos": [1.0, 0.25], "dir": [1, 0], "accepts": ["NOZZLE"],
			"default_child": "DGENERAL008", "required": true,
			"default_props": {"nozzle_id": "N2"}},
		{"name": "hx_n1", "pos": [0.0, 0.75], "dir": [-1, 0], "accepts": ["NOZZLE"],
			"default_child": "DGENERAL008", "required": true,
			"default_props": {"nozzle_id": "N1"}},
		{"name": "hx_n4", "pos": [1.0, 0.75], "dir": [1, 0], "accepts": ["NOZZLE"],
			"default_child": "DGENERAL008", "required": true,
			"default_props": {"nozzle_id": "N4"}},
	],
	# 塔 / 罐 / 反应器（B 类，§16.4）：默认 4 管口 + 1 人孔，中间预留搅拌位。全部可增删
	#（B 类管口数量随工艺而变），故 required 一律 false。
	# column / tank / reactor (class B, §16.4): 4 nozzles + 1 manhole, stirrer socket RESERVED.
	"tank": [
		{"name": "ves_bottom_nozzle", "pos": [0.5, 1.0], "dir": [0, 1],
			"accepts": ["NOZZLE"], "default_child": "DGENERAL008",
			"default_props": {"nozzle_id": "N1"}},
		{"name": "ves_left_manhole", "pos": [0.0, 0.5], "dir": [-1, 0],
			"accepts": ["MANHOLE"], "default_child": "DGENERAL007",
			"default_props": {"manhole_id": "M1"}},
		{"name": "ves_right_nozzle", "pos": [1.0, 0.5], "dir": [1, 0],
			"accepts": ["NOZZLE"], "default_child": "DGENERAL008",
			"default_props": {"nozzle_id": "N2"}},
		{"name": "ves_top_left_nozzle", "pos": [0.3, 0.0], "dir": [0, -1],
			"accepts": ["NOZZLE"], "default_child": "DGENERAL008",
			"default_props": {"nozzle_id": "N3"}},
		{"name": "ves_top_right_nozzle", "pos": [0.7, 0.0], "dir": [0, -1],
			"accepts": ["NOZZLE"], "default_child": "DGENERAL008",
			"default_props": {"nozzle_id": "N4"}},
		# "中间"取顶部正中：搅拌电机在顶、轴居中下伸，与上左/上右两管口天然不冲突。
		# The middle is the TOP CENTRE, which cannot collide with the two top corner nozzles.
		{"name": "ves_stirrer", "pos": [0.5, 0.0], "dir": [0, -1],
			"accepts": ["AGITATOR"], "default_child": ""},
	],
	"instrument": [],
	"general": [],
}

# Per-symbol attach-anchor overrides, keyed by symbol id. A present key REPLACES the category
# table entirely. An explicit [] states "this symbol is not a carrier" — the same convention
# GP_PORT_OVERRIDES already uses for the legend glyphs.
# 按符号 id 的锚点覆盖表。存在该键即「整体替换」类别表。显式的 [] 声明「本图元不是载体」
# —— 与 GP_PORT_OVERRIDES 对图例图元所用约定一致。
# Mirrors ATTACH_OVERRIDES in tools/gen_symbol_packs.py.
# 与 tools/gen_symbol_packs.py 的 ATTACH_OVERRIDES 互为镜像。
const GP_ATTACH_OVERRIDES: Dictionary = {
	"DGENERAL003": [],   # 盲板 / blind cover
	"DGENERAL004": [],   # 执行机构 / controlled actuator
	"DGENERAL007": [],   # 人孔 / manhole
	"DGENERAL008": [],   # 接管嘴（管口）/ nozzle
	"DGENERAL009": [],   # 保温管道 / insulated piping
	# 止回阀无执行机构：启闭由介质流向决定。
	# A check valve takes no actuator — its disc is driven by flow, not by a fail action.
	"DVALVE005": [],
}


# Resolve the nominal envelope size for a category, honouring a pack-level override map.
# 解析某类别的标称包络尺寸，并允许图元包级覆盖表生效。
# [param gpCat] Category key, e.g. "valve".
# [param gpCat] 类别键，如 "valve"。
# [param gpOverride] Optional {category: Vector2} override supplied by a GPSymbolPack.
# [param gpOverride] 可选的 {类别: Vector2} 覆盖表，由 GPSymbolPack 提供。
static func gpSizeFor(gpCat: String, gpOverride: Dictionary = {}) -> Vector2:
	if gpOverride.has(gpCat):
		return gpOverride[gpCat]
	if GP_NOMINAL.has(gpCat):
		return GP_NOMINAL[gpCat]
	return GP_FALLBACK_SIZE


# Return a mutable copy of the standard port anchors for a category.
# 返回某类别标准端口锚点的可变副本。
# Constants are read-only in Godot 4, so callers get a deep copy they may edit freely.
# Godot 4 中常量为只读，因此调用方拿到的是可自由修改的深拷贝。
static func gpStandardPorts(gpCat: String) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	if not GP_STD_PORTS.has(gpCat):
		return gpOut
	var gpSrc: Array = GP_STD_PORTS[gpCat]
	for gpP in gpSrc:
		gpOut.append((gpP as Dictionary).duplicate(true))
	return gpOut


# Ports for a symbol: the per-id override table wins, then the per-category standard table.
# 某图元的端口：按 id 覆盖表优先，其次按类别标准表。
# Mirrors tools/gen_symbol_packs.py::_ports_for so a built-in symbol and a user symbol of the
# same category get identical ports. gp_test_symbol_pack.gd asserts the two stay in step.
# 与 tools/gen_symbol_packs.py::_ports_for 镜像，使同类别的内置图元与用户图元端口完全一致。
# gp_test_symbol_pack.gd 断言两侧不脱节。
static func gpPortsForSymbol(gpSymbolId: String, gpCat: String) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	if GP_PORT_OVERRIDES.has(gpSymbolId):
		for gpP in (GP_PORT_OVERRIDES[gpSymbolId] as Array):
			gpOut.append((gpP as Dictionary).duplicate(true))
		return gpOut
	return gpStandardPorts(gpCat)


# Return a mutable copy of the standard attach anchors for a category.
# 返回某类别标准安装锚点的可变副本。
# Constants are read-only in Godot 4, so callers get a deep copy they may edit freely.
# Godot 4 中常量为只读，因此调用方拿到的是可自由修改的深拷贝。
static func gpStandardAttach(gpCat: String) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	if not GP_STD_ATTACH.has(gpCat):
		return gpOut
	for gpA in (GP_STD_ATTACH[gpCat] as Array):
		gpOut.append((gpA as Dictionary).duplicate(true))
	return gpOut


# Attach anchors for a symbol: the per-id override table wins (a present key REPLACES the
# category table, even when its list is empty), then the per-category standard table.
# 某图元的安装锚点：按 id 覆盖表优先（存在该键即「整体替换」类别表，即便其列表为空），
# 其次按类别标准表。
# Mirrors _attach_for() in tools/gen_symbol_packs.py so a built-in symbol and a user symbol of
# the same category get identical anchoring sockets.
# 与 tools/gen_symbol_packs.py 的 _attach_for() 镜像，使同类别的内置图元与用户图元锚点完全一致。
static func gpAttachForSymbol(gpSymbolId: String, gpCat: String) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	if GP_ATTACH_OVERRIDES.has(gpSymbolId):
		for gpA in (GP_ATTACH_OVERRIDES[gpSymbolId] as Array):
			gpOut.append((gpA as Dictionary).duplicate(true))
		return gpOut
	return gpStandardAttach(gpCat)


# Same as gpAttachForSymbol(), converted into the typed model object the definition carries.
# 与 gpAttachForSymbol() 相同，但转换为定义所携带的类型化模型对象。
# This is the single conversion point, so the dictionary table and the typed anchors can never
# drift in how they are interpreted (GPSymbolNormalizer uses it).
# 这里是唯一的转换点，故字典表与类型化锚点对「如何解读」永不脱节（GPSymbolNormalizer 用它）。
static func gpAttachPointsForSymbol(gpSymbolId: String, gpCat: String) -> Array[GPAttachPoint]:
	return GPAttachPoint.gpFromDicts(gpAttachForSymbol(gpSymbolId, gpCat))


# List all known category keys (stable order for UI dropdowns).
# 列出所有已知类别键（供 UI 下拉框使用的稳定顺序）。
static func gpCategoryList() -> Array[String]:
	var gpOut: Array[String] = []
	for gpK in GP_NOMINAL.keys():
		gpOut.append(str(gpK))
	return gpOut


# Whether a category key is known to the nominal size table.
# 某类别键是否存在于标称尺寸表中。
static func gpHasCategory(gpCat: String) -> bool:
	return GP_NOMINAL.has(gpCat)
