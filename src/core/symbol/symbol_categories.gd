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
	# 控制执行机构：信号入 + 阀杆出 / actuator: signal in, stem out
	"DGENERAL004": [
		{"name": "sig", "pos": [0.0, 0.5], "dir": [-1, 0], "type": "SIGNAL"},
		{"name": "stem", "pos": [1.0, 0.5], "dir": [1, 0], "type": "ACTUATOR"},
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
	# 人孔：设备壁上的一个接口 / manhole: one opening on the vessel wall
	"DGENERAL007": [
		{"name": "open", "pos": [0.0, 0.5], "dir": [-1, 0], "type": "TERMINAL"},
	],
	# 接管嘴：设备侧 + 管道侧 / nozzle: equipment side and piping side
	"DGENERAL008": [
		{"name": "equip", "pos": [0.0, 0.5], "dir": [-1, 0], "type": "NOZZLE"},
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
