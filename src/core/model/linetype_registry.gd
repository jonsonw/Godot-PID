class_name GPLinetypeRegistry
extends RefCounted
# Copyright © 2026 Jonson Wang
# Standard linetype registry (AutoCAD-style): name -> dash pattern in MILLIMETRES
# (1 world unit = 1 mm), sharing GPEdgeStyle's signal-dash unit system.
# 标准线型登记表（AutoCAD 式）：名称 -> 毫米单位的划/空图案（1 世界单位 = 1 mm），
# 与 GPEdgeStyle 的信号虚线同一单位体系。
#
# WHY THIS LIVES IN core / 为何住在 core（ADR-10 修正，2026-11-06）：
# GPEdgeStyle.gpStyleFor() is a core pure function and it must answer "what does a DASHED line
# look like" without reaching up into render. The table is DATA — it used to sit in
# render/linetype_manager.gd, which made core -> render the layering leak D02 in the W12 review.
# 表格是**数据**：GPEdgeStyle.gpStyleFor() 是 core 的纯函数，它要回答「DASHED 长什么样」却必须
# 够到 render 去问 —— 这正是 W12 审查里 core→render 的 D02 渗漏。故表格下沉 core。
#
# WHAT IS NOT HERE / 这里**没有**什么：
# Any file IO. assets/linetypes/acad.ltp is parsed by GPLinetypeFile in src/io and handed back
# through gpSetOverrides(). Keeping the reader out of core is ADR-2/ADR-4 (io owns the disk).
# 这里没有任何文件读写。acad.ltp 由 src/io 的 GPLinetypeFile 解析，再经 gpSetOverrides() 交回。
# 读取器不进 core 是 ADR-2/ADR-4 的要求（磁盘归 io）。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Global linetype scale (AutoCAD LTSCALE). Multiplies every dash/space length.
# 全局线型比例（AutoCAD LTSCALE）。乘到每段划长 / 空白长。
static var gpLinetypeScale: float = 1.0

# Built-in patterns: name -> PackedFloat32Array (on/off lengths in millimetres).
# Empty array = solid (CONTINUOUS).
# 内置图案：名称 -> 划/空长度数组（毫米）。空数组 = 实线（CONTINUOUS）。
static var gpBuiltins: Dictionary = {
	"CONTINUOUS": PackedFloat32Array(),
	"HIDDEN": PackedFloat32Array([3.0, 1.5]),
	"DASHED": PackedFloat32Array([6.0, 2.0]),
	"CENTER": PackedFloat32Array([20.0, 3.0, 3.0, 3.0]),
	"PHANTOM": PackedFloat32Array([20.0, 3.0, 3.0, 3.0]),
	"DOT": PackedFloat32Array([0.0, 1.5]),
}

# Runtime override table (filled by gpSetOverrides()): per-name, layered ON TOP of the built-ins.
# 运行时覆盖表（由 gpSetOverrides() 填充）：逐名叠加在内置值**之上**。
static var gpOverrides: Dictionary = {}


# Resolve the dash pattern for a linetype name, already scaled by the global LTSCALE.
# 解析某线型名的虚线图案，已乘全局 LTSCALE。
# [return] on/off lengths in millimetres (1 world unit = 1 mm); EMPTY = solid (CONTINUOUS).
# [return] 毫米单位的划/空长度（1 世界单位 = 1 mm）；空 = 实线。
#
# LAYERED PER NAME, NOT WHOLE-TABLE REPLACEMENT / 逐名叠加，而非整表替换：
# An override table only wins for the names it actually declares; every other name keeps its
# built-in. The old implementation swapped the whole source (`overrides if not empty else
# builtins`), so loading a PARTIAL .ltp silently turned every unlisted linetype into a solid line
# — a data-driven styling system that corrupts styling when the data is incomplete. Caught by
# gpTestLinetypeOverridesReplaceBuiltins() when this table moved to core.
# 覆盖表只在它**真正声明**的名字上胜出，其余名字仍用内置值。旧实现整表换源
# （`overrides if not empty else builtins`），于是加载一份**不完整**的 .ltp 会把所有未列出的线型
# 静默变成实线 —— 一个「数据不全就破坏样式」的数据驱动样式系统。本表下沉 core 时被
# gpTestLinetypeOverridesReplaceBuiltins() 抓到。
static func gpPatternFor(gpName: String) -> PackedFloat32Array:
	var gpBase: PackedFloat32Array = PackedFloat32Array()
	if gpOverrides.has(gpName):
		gpBase = gpOverrides[gpName] as PackedFloat32Array
	elif gpBuiltins.has(gpName):
		gpBase = gpBuiltins[gpName] as PackedFloat32Array
	if gpBase.is_empty():
		return PackedFloat32Array()
	# CONTINUOUS or a leading-zero pattern (dotted) passes through as-is; the dash
	# generator treats a leading 0.0 as a zero-length "on" run (a dot).
	# CONTINUOUS 或前导 0（点线）原样返回；虚线生成器把前导 0.0 视为零长「有墨」段（点）。
	var gpOut: PackedFloat32Array = PackedFloat32Array()
	for gpV in gpBase:
		gpOut.append(maxf(gpV, 0.0) * gpLinetypeScale)
	return gpOut


# Install an override table (from GPLinetypeFile). Empty dictionary clears the overrides.
# 安装覆盖表（来自 GPLinetypeFile）。空字典等于清除覆盖。
static func gpSetOverrides(gpTableIn: Dictionary) -> void:
	gpOverrides = gpTableIn.duplicate(true)


# True when an override table is installed (i.e. a .ltp file was actually loaded).
# 是否已安装覆盖表（即真的加载过 .ltp 文件）。
static func gpHasOverrides() -> bool:
	return not gpOverrides.is_empty()


# Reset the scale to AutoCAD's default LTSCALE = 1.0. Used by tests and by "reset preferences".
# 复位比例为 AutoCAD 默认 LTSCALE = 1.0。测试与「复位偏好」使用。
static func gpResetScale() -> void:
	gpLinetypeScale = 1.0
