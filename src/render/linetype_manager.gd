class_name GPLinetypeManager
extends RefCounted
# Copyright © 2026 Jonson Wang
# Standard linetype registry (AutoCAD-style). Pattern values are in WORLD units, matching
# GPEdgeStyle's signal dashes so all line styling shares one unit system.
# 标准线型登记表（AutoCAD 式）。图案数值以世界单位计，与 GPEdgeStyle 的信号虚线同一单位
# 体系，使全部线型共用一套尺度。
#
# Why built-in defaults AND a file / 为何内置默认值又提供文件：
#   The render path (GPEdgeStyle.gpStyleFor) must never fail or block on a file read, so the
#   SAME patterns live here as constants. assets/linetypes/acad.ltp is the user-editable
#   mirror — gpLoadFile() overrides the built-ins when present.
#   渲染路径（GPEdgeStyle.gpStyleFor）绝不能为读文件而失败或阻塞，故同一份图案作为常量内置。
#   assets/linetypes/acad.ltp 是可编辑镜像——存在时 gpLoadFile() 覆盖内置值。
# 编码规范：所有变量均显式声明类型。

# Global linetype scale (AutoCAD LTSCALE). Multiplies every dash/space length.
# 全局线型比例（AutoCAD LTSCALE）。乘到每段划长 / 空白长。
static var gpLinetypeScale: float = 1.0

# Built-in patterns: name -> PackedFloat32Array (on/off lengths in world units).
# Empty array = solid (CONTINUOUS). 内置图案：名称 -> 划/空长度数组（世界单位）。空数组 = 实线。
static var gpBuiltins: Dictionary = {
	"CONTINUOUS": PackedFloat32Array(),
	"HIDDEN": PackedFloat32Array([12.0, 6.0]),
	"DASHED": PackedFloat32Array([18.0, 6.0]),
	"CENTER": PackedFloat32Array([28.0, 6.0, 3.0, 6.0, 3.0, 6.0]),
	"PHANTOM": PackedFloat32Array([32.0, 6.0, 3.0, 6.0, 3.0, 6.0]),
	"DOT": PackedFloat32Array([0.0, 4.0]),
}

# Runtime override table (filled by gpLoadFile). Empty = use built-ins.
# 运行时覆盖表（由 gpLoadFile 填充）。为空则使用内置值。
static var gpOverrides: Dictionary = {}


# Resolve the dash pattern for a linetype name, already scaled by the global LTSCALE.
# 解析某线型名的虚线图案，已乘全局 LTSCALE。
# [return] on/off lengths in world units; EMPTY = solid (CONTINUOUS).
# [return] 世界单位的划/空长度；空 = 实线。
static func gpPatternFor(gpName: String) -> PackedFloat32Array:
	var gpSrc: Dictionary = gpOverrides if not gpOverrides.is_empty() else gpBuiltins
	if not gpSrc.has(gpName):
		return PackedFloat32Array()
	var gpBase: PackedFloat32Array = gpSrc[gpName] as PackedFloat32Array
	if gpBase.is_empty():
		return PackedFloat32Array()
	# CONTINUOUS or a leading-zero pattern (dotted) passes through as-is; the dash
	# generator treats a leading 0.0 as a zero-length "on" run (a dot).
	# CONTINUOUS 或前导 0（点线）原样返回；虚线生成器把前导 0.0 视为零长「有墨」段（点）。
	var gpOut: PackedFloat32Array = PackedFloat32Array()
	for gpV in gpBase:
		gpOut.append(maxf(gpV, 0.0) * gpLinetypeScale)
	return gpOut


# Load an acad.ltp-style file, overriding the built-ins. Safe: a bad line is skipped and the
# rest keeps resolving. Returns the number of linetypes loaded (0 if the file is missing).
# 加载 acad.ltp 式文件，覆盖内置值。安全：解析错误跳过该行，其余继续解析。返回加载的线型数
#（文件缺失时为 0）。
static func gpLoadFile(gpPath: String) -> int:
	if not FileAccess.file_exists(gpPath):
		return 0
	var gpF: FileAccess = FileAccess.open(gpPath, FileAccess.READ)
	if gpF == null:
		return 0
	gpOverrides = {}
	var gpName: String = ""
	while not gpF.eof_reached():
		var gpLine: String = gpF.get_line().strip_edges()
		if gpLine == "" or gpLine.begins_with("#"):
			continue
		if gpLine.begins_with("A,"):
			var gpBody: String = gpLine.substr(2).strip_edges()
			var gpParts: PackedStringArray = gpBody.split(",")
			var gpArr: PackedFloat32Array = PackedFloat32Array()
			for gpP in gpParts:
				gpArr.append(float(gpP.strip_edges()))
			if gpName != "" and not gpArr.is_empty():
				gpOverrides[gpName] = gpArr
			gpName = ""
		elif gpLine.contains("="):
			gpName = gpLine.substr(0, gpLine.find("=")).strip_edges().to_upper()
		else:
			gpName = ""
	gpF.close()
	return gpOverrides.size()
