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

# Category -> nominal envelope size in canvas pixels. Shared by the whole family.
# 类别 → 标称包络尺寸（画布像素）。同族共享。
const GP_NOMINAL: Dictionary = {
	"valve": Vector2(64, 48),
	"pump": Vector2(80, 56),
	"tank": Vector2(72, 96),
	"instrument": Vector2(56, 56),
	"heat": Vector2(84, 64),
	"general": Vector2(64, 64),
}

# Fallback envelope for unknown categories.
# 未知类别的兜底包络尺寸。
const GP_FALLBACK_SIZE: Vector2 = Vector2(64, 64)

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
	# 换热器：壳程两个 + 管程两个 / shell side x2 + tube side x2
	"LHEAT001": [
		{"name": "shell_in", "pos": [0.0, 0.5], "dir": [-1, 0], "type": "NOZZLE"},
		{"name": "shell_out", "pos": [1.0, 0.5], "dir": [1, 0], "type": "NOZZLE"},
		{"name": "tube_in", "pos": [0.5, 0.0], "dir": [0, -1], "type": "NOZZLE"},
		{"name": "tube_out", "pos": [0.5, 1.0], "dir": [0, 1], "type": "NOZZLE"},
	],
	# 储罐：顶 / 底 / 两侧 / tank: top, bottom and two side nozzles
	"LTANK001": [
		{"name": "top", "pos": [0.5, 0.0], "dir": [0, -1], "type": "NOZZLE"},
		{"name": "bottom", "pos": [0.5, 1.0], "dir": [0, 1], "type": "NOZZLE"},
		{"name": "left", "pos": [0.0, 0.25], "dir": [-1, 0], "type": "NOZZLE"},
		{"name": "right", "pos": [1.0, 0.75], "dir": [1, 0], "type": "NOZZLE"},
	],
	# 调节阀 / 执行器 / 定位器：两个管口 + 顶部执行机构接点（接信号线）
	# control valve / actuator / positioner: two nozzles + a top actuator terminal
	"LVALVE003": [
		{"name": "in", "pos": [0.0, 0.5], "dir": [-1, 0], "type": "NOZZLE"},
		{"name": "out", "pos": [1.0, 0.5], "dir": [1, 0], "type": "NOZZLE"},
		{"name": "act", "pos": [0.5, 0.0], "dir": [0, -1], "type": "ACTUATOR"},
	],
	"LVALVE008": [
		{"name": "in", "pos": [0.0, 0.5], "dir": [-1, 0], "type": "NOZZLE"},
		{"name": "out", "pos": [1.0, 0.5], "dir": [1, 0], "type": "NOZZLE"},
		{"name": "act", "pos": [0.5, 0.0], "dir": [0, -1], "type": "ACTUATOR"},
	],
	"LVALVE007": [
		{"name": "in", "pos": [0.0, 0.5], "dir": [-1, 0], "type": "NOZZLE"},
		{"name": "out", "pos": [1.0, 0.5], "dir": [1, 0], "type": "NOZZLE"},
		{"name": "act", "pos": [0.5, 0.0], "dir": [0, -1], "type": "ACTUATOR"},
	],
	# 就地指示表（FI/PI/TI/LI）：图形左右被管线贯穿，故是两个管口 + 顶部信号端子
	# in-line indicators: the glyph is pierced left-to-right by the pipe, plus a signal terminal
	"LINSTRUMENT002": [
		{"name": "in", "pos": [0.0, 0.5], "dir": [-1, 0], "type": "NOZZLE"},
		{"name": "out", "pos": [1.0, 0.5], "dir": [1, 0], "type": "NOZZLE"},
		{"name": "sig", "pos": [0.5, 0.0], "dir": [0, -1], "type": "SIGNAL"},
	],
	"LINSTRUMENT006": [
		{"name": "in", "pos": [0.0, 0.5], "dir": [-1, 0], "type": "NOZZLE"},
		{"name": "out", "pos": [1.0, 0.5], "dir": [1, 0], "type": "NOZZLE"},
		{"name": "sig", "pos": [0.5, 0.0], "dir": [0, -1], "type": "SIGNAL"},
	],
	"LINSTRUMENT008": [
		{"name": "in", "pos": [0.0, 0.5], "dir": [-1, 0], "type": "NOZZLE"},
		{"name": "out", "pos": [1.0, 0.5], "dir": [1, 0], "type": "NOZZLE"},
		{"name": "sig", "pos": [0.5, 0.0], "dir": [0, -1], "type": "SIGNAL"},
	],
	"LINSTRUMENT004": [
		{"name": "in", "pos": [0.0, 0.5], "dir": [-1, 0], "type": "NOZZLE"},
		{"name": "out", "pos": [1.0, 0.5], "dir": [1, 0], "type": "NOZZLE"},
		{"name": "sig", "pos": [0.5, 0.0], "dir": [0, -1], "type": "SIGNAL"},
	],
	# 现场接线箱：两个信号端子，无工艺管口 / field enclosure: two signal terminals only
	"LINSTRUMENT001": [
		{"name": "sig_in", "pos": [0.0, 0.5], "dir": [-1, 0], "type": "SIGNAL"},
		{"name": "sig_out", "pos": [1.0, 0.5], "dir": [1, 0], "type": "SIGNAL"},
	],
	# 线型图例符号：它们是图例美术，不是可连接图元 / legend glyphs, deliberately not connectable
	"LGENERAL003": [],
	"LGENERAL002": [],
	"LGENERAL001": [],
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
