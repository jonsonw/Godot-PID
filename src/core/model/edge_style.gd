class_name GPEdgeStyle
extends RefCounted
# Copyright © 2026 Jonson Wang
# Style sheet: (kind, signal type, zoom) -> {width, color, pattern}. A PURE FUNCTION, on purpose.
# 样式表：(类型, 信号类型, 缩放) -> {宽度, 颜色, 图案}。刻意做成纯函数。
#
# Why not per-edge width / color fields / 为何不在每条边上存宽度与颜色：
#   a drawing whose line weights live on 400 individual edges cannot be restyled — changing
#   "utility lines are 1.6 wide" would need a migration pass over every archive. Keeping the
#   mapping in one pure function means restyling is a one-line edit and old files pick it up
#   automatically. Per-edge overrides, if ever needed, belong in gpAttrs, not in the model core.
#   把线重存在 400 条边上的图纸无法重新配色 —— 把「公用工程线宽 1.6」改掉需要遍历每个存档迁移。
#   映射收在一个纯函数里，改样式就是一行编辑，旧文件自动跟上。真需要逐边覆盖时应放 gpAttrs，
#   而不是模型内核。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Selection halo (drawn UNDER the ink so the line keeps its true weight).
# 选中光晕（画在墨线之下，使线条保持其真实线重）。
# Brightened from 0.35 -> 0.5 alpha so a selected pipe reads at a glance, not just via its grips.
# alpha 由 0.35 提至 0.5，使选中管线一眼可辨，而不只靠抓取点三角。
const GP_SEL_HALO: Color = Color(0.235, 0.549, 1.0, 0.5)

# Halo for the edge CURRENTLY BEING EDITED (a grip is being dragged). Distinct orange so the
# user can tell "selected" from "actively editing" at a glance.
# 正在编辑中的边光晕（某抓取点正被拖拽）。用橙色与「选中」区分，一眼可辨。
const GP_EDIT_HALO: Color = Color(1.0, 0.60, 0.20, 0.55)

# Bright core stroke drawn ON TOP of the ink for a selected / editing edge, so the whole path
# lights up (not only the halo underneath). A thin, high-alpha line keeps the original colour
# visible while making the selection obvious.
# 选中 / 编辑边在墨线之上叠的一道亮色细描边，使整条路径发亮（而非仅底部光晕）。
# 细而高不透明的线在保留原色的同时令选中状态明显。
const GP_SEL_OUTLINE: Color = Color(0.45, 0.72, 1.0, 0.95)

# Hover halo. / 悬停光晕。
const GP_HOVER_HALO: Color = Color(1.0, 1.0, 1.0, 0.18)

# Marker for a free (dangling) end. / 悬空端标记色。
const GP_DANGLING: Color = Color(1.0, 0.604, 0.235)

# Minimum on-screen line width in PIXELS. World-unit widths shrink with zoom; at 25% a 3.0 world
# unit main line would be 0.75px and read as a hairline identical to a utility line — which is
# the one distinction the drafting requirement calls for. This floor protects that distinction.
# 屏幕最小线宽（像素）。世界单位线宽随缩放变细；25% 缩放时 3.0 世界单位的主管线只有 0.75px，
# 与公用工程线看起来完全一样 —— 而那正是制图要求要区分的那一项。本下限保护该区分。
const GP_MIN_PX: float = 1.2

# Minimum on-screen length of one dash run in PIXELS. Without it a dash-dot line turns into a
# solid smear once a single dash falls below one pixel.
# 单段划长的屏幕最小长度（像素）。没有它，单个划长不足一像素时点划线会糊成实线。
const GP_MIN_DASH_PX: float = 2.0


# Resolve the render style for an edge. Never fails: unknown kinds fall back to a thin solid.
# 解析一条边的渲染样式。绝不失败：未知类型回退为细实线。
# [return] {"width": float, "color": Color, "pattern": PackedFloat32Array}
#          pattern alternates on/off lengths in WORLD units; empty means solid.
#          pattern 以世界单位交替表示「有墨/空白」长度；为空表示实线。
static func gpStyleFor(gpKind: String, gpSignalType: String, gpZoom: float = 1.0) -> Dictionary:
	var gpW: float = 1.6
	var gpCol: Color = Color("#9AA6BE")
	var gpPat: PackedFloat32Array = PackedFloat32Array()
	match gpKind:
		GPPIDEdge.GP_PROCESS:
			gpW = 3.0
			gpCol = Color("#DCE3F0")
			# CONTINUOUS — solid; AutoCAD linetype overlay (ADR-UI-02) keeps the
			# semantic process colour while adopting the standard solid line.
			# CONTINUOUS —— 实线；AutoCAD 线型叠加（ADR-UI-02）在保留语义工艺色的同时
			# 采用标准实线。
			gpPat = GPLinetypeManager.gpPatternFor("CONTINUOUS")
		GPPIDEdge.GP_UTILITY:
			gpW = 1.6
			gpCol = Color("#9AA6BE")
			# DASHED — AutoCAD utility convention, scaled by the global LTSCALE.
			# DASHED —— AutoCAD 公用工程线惯例，受全局 LTSCALE 缩放。
			gpPat = GPLinetypeManager.gpPatternFor("DASHED")
		GPPIDEdge.GP_SIGNAL:
			match gpSignalType:
				"ELECTRIC":
					gpW = 1.4
					gpCol = Color("#F2C14E")
					gpPat = PackedFloat32Array([10.0, 3.0, 2.0, 3.0])
				"PNEUMATIC":
					gpW = 1.4
					gpCol = Color("#7FD1E8")
					gpPat = PackedFloat32Array([6.0, 4.0])
				"HYDRAULIC":
					gpW = 1.4
					gpCol = Color("#B98BE8")
					gpPat = PackedFloat32Array([10.0, 3.0, 2.0, 3.0, 2.0, 3.0])
				"DATA":
					gpW = 1.2
					gpCol = Color("#77C7A8")
					gpPat = PackedFloat32Array([2.0, 4.0])
				"CAPILLARY":
					gpW = 1.4
					gpCol = Color("#E88B8B")
					gpPat = PackedFloat32Array([12.0, 4.0])
				_:
					gpW = 1.4
					gpCol = Color("#F2C14E")
					gpPat = PackedFloat32Array([10.0, 3.0, 2.0, 3.0])
	# Screen-space floors, expressed back in world units (the view is scaled by gpZoom).
	# 屏幕空间下限，换算回世界单位（视图被 gpZoom 缩放）。
	var gpZ: float = maxf(gpZoom, 0.01)
	gpW = maxf(gpW, GP_MIN_PX / gpZ)
	if not gpPat.is_empty():
		var gpScaled: PackedFloat32Array = PackedFloat32Array()
		var gpMinDash: float = GP_MIN_DASH_PX / gpZ
		for gpV in gpPat:
			gpScaled.append(maxf(gpV, gpMinDash))
		gpPat = gpScaled
	return {"width": gpW, "color": gpCol, "pattern": gpPat}


# Port dot colour by purpose (shared by GPSymbolView and the snap highlight).
# 按用途取端口圆点颜色（GPSymbolView 与吸附高亮共用）。
static func gpPortColor(gpType: String) -> Color:
	match gpType:
		GPPort.GP_NOZZLE:
			return Color("#8FD6A8")
		GPPort.GP_ACTUATOR:
			return Color("#F2C14E")
		GPPort.GP_SIGNAL:
			return Color("#7FD1E8")
		_:
			return Color("#C0C6D4")


# Human-readable line-type name key (for the inspector and the legend sheet).
# 人类可读的线型名称键（供属性面板与图例页使用）。
static func gpLineTypeKey(gpKind: String, gpSignalType: String) -> String:
	if gpKind == GPPIDEdge.GP_PROCESS:
		return "line_type_process"
	if gpKind == GPPIDEdge.GP_UTILITY:
		return "line_type_utility"
	match gpSignalType:
		"ELECTRIC":
			return "line_type_electric"
		"PNEUMATIC":
			return "line_type_pneumatic"
		"HYDRAULIC":
			return "line_type_hydraulic"
		"DATA":
			return "line_type_data"
		"CAPILLARY":
			return "line_type_capillary"
		_:
			return "line_type_unknown"
