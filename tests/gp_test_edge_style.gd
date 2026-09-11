extends "res://tests/gp_test.gd"
# Headless tests for GPEdgeStyle (P1 of the connection feature).
# 连线功能 P1 —— GPEdgeStyle 的 headless 测试。
#
# Drafting rule under test (see docs/adr/ADR-UI-02-线型语义.md):
#   - PROCESS stays a SOLID CONTINUOUS line; line weight is its only visual distinction.
#   - UTILITY adopts the AutoCAD DASHED convention so utility mains read as dashed.
# The style sheet is a pure function so that restyling is a one-line edit instead of a
# migration over every saved archive.
# 被测的制图规则（见 docs/adr/ADR-UI-02-线型语义.md）：
#   - PROCESS 仍用实线 CONTINUOUS，线宽是其唯一可见区分手段。
#   - UTILITY 采用 AutoCAD DASHED 惯例，使公用工程主线呈虚线。
# 样式表是纯函数，改样式即一行编辑，不必遍历每个存档做迁移。


func gpTestMainProcessIsThickerThanUtility() -> void:
	var gpMain: Dictionary = GPEdgeStyle.gpStyleFor(GPPIDEdge.GP_PROCESS, "", 1.0)
	var gpUtil: Dictionary = GPEdgeStyle.gpStyleFor(GPPIDEdge.GP_UTILITY, "", 1.0)
	gpApprox(float(gpMain["width"]), 3.0, 0.0001, "main process line is 3.0 world units wide")
	gpApprox(float(gpUtil["width"]), 1.6, 0.0001, "utility line is 1.6 world units wide")
	gpCheck(float(gpMain["width"]) > float(gpUtil["width"]),
		"the main line must be visibly thicker than the utility line")


# Per ADR-UI-02: PROCESS is solid (CONTINUOUS), UTILITY is dashed (DASHED).
# 按 ADR-UI-02：PROCESS 实线（CONTINUOUS），UTILITY 虚线（DASHED）。
func gpTestProcessSolidAndUtilityDashed() -> void:
	var gpMain: PackedFloat32Array = GPEdgeStyle.gpStyleFor(GPPIDEdge.GP_PROCESS, "", 1.0)["pattern"]
	var gpUtil: PackedFloat32Array = GPEdgeStyle.gpStyleFor(GPPIDEdge.GP_UTILITY, "", 1.0)["pattern"]
	gpCheck((gpMain as PackedFloat32Array).is_empty(),
		"process lines stay solid (CONTINUOUS)")
	gpCheck(not (gpUtil as PackedFloat32Array).is_empty(),
		"utility lines are dashed (DASHED, per ADR-UI-02)")


func gpTestSignalLineTypes() -> void:
	gpEq(GPEdgeStyle.gpStyleFor(GPPIDEdge.GP_SIGNAL, "ELECTRIC", 1.0)["pattern"],
		PackedFloat32Array([10.0, 3.0, 2.0, 3.0]), "electric is dash-dot")
	gpEq(GPEdgeStyle.gpStyleFor(GPPIDEdge.GP_SIGNAL, "PNEUMATIC", 1.0)["pattern"],
		PackedFloat32Array([6.0, 4.0]), "pneumatic is a short dash")
	gpEq(GPEdgeStyle.gpStyleFor(GPPIDEdge.GP_SIGNAL, "HYDRAULIC", 1.0)["pattern"],
		PackedFloat32Array([10.0, 3.0, 2.0, 3.0, 2.0, 3.0]), "hydraulic is dash-dot-dot")
	gpEq(GPEdgeStyle.gpStyleFor(GPPIDEdge.GP_SIGNAL, "DATA", 1.0)["pattern"],
		PackedFloat32Array([2.0, 4.0]), "DCS data link is a dense dot")
	gpEq(GPEdgeStyle.gpStyleFor(GPPIDEdge.GP_SIGNAL, "CAPILLARY", 1.0)["pattern"],
		PackedFloat32Array([12.0, 4.0]), "capillary is a long dash")


# Unknown input must still produce something drawable, and never an empty dictionary.
# 未知输入必须仍能产出可绘制的样式，且绝不返回空字典。
func gpTestUnknownKindFallsBack() -> void:
	var gpS: Dictionary = GPEdgeStyle.gpStyleFor("WHATEVER", "", 1.0)
	gpCheck(gpS.has("width") and gpS.has("color") and gpS.has("pattern"),
		"the fallback style still carries all three keys")
	gpCheck(float(gpS["width"]) > 0.0, "the fallback width is positive")
	gpCheck((gpS["pattern"] as PackedFloat32Array).is_empty(), "the fallback is a solid line")
	var gpS2: Dictionary = GPEdgeStyle.gpStyleFor(GPPIDEdge.GP_SIGNAL, "UNKNOWN_MEDIUM", 1.0)
	gpCheck(float(gpS2["width"]) > 0.0, "an unknown signal type still draws")
	gpCheck(not (gpS2["pattern"] as PackedFloat32Array).is_empty(),
		"an unknown signal type keeps a pattern so it reads as a signal line")


# World-unit widths shrink with zoom; without a floor a 3.0 main line would be 0.75px at
# 25% and indistinguishable from a utility line.
# 世界单位线宽随缩放变细；没有下限，3.0 的主管线在 25% 时只有 0.75px，与公用工程线无法区分。
func gpTestScreenFloorAppliesWhenZoomedOut() -> void:
	var gpS: Dictionary = GPEdgeStyle.gpStyleFor(GPPIDEdge.GP_UTILITY, "", 0.25)
	gpCheck(float(gpS["width"]) * 0.25 >= GPEdgeStyle.GP_MIN_PX - 0.0001,
		"the on-screen width never drops below the floor")
	var gpS2: Dictionary = GPEdgeStyle.gpStyleFor(GPPIDEdge.GP_SIGNAL, "ELECTRIC", 0.1)
	for gpV in (gpS2["pattern"] as PackedFloat32Array):
		gpCheck(gpV * 0.1 >= GPEdgeStyle.GP_MIN_DASH_PX - 0.0001,
			"a single dash never drops below the pixel floor")


func gpTestFloorDoesNotInflateAtNormalZoom() -> void:
	var gpS: Dictionary = GPEdgeStyle.gpStyleFor(GPPIDEdge.GP_SIGNAL, "ELECTRIC", 1.0)
	gpEq(gpS["pattern"], PackedFloat32Array([10.0, 3.0, 2.0, 3.0]),
		"at 100% the declared dash lengths are used verbatim")


func gpTestPortColorsAreDistinct() -> void:
	gpCheck(GPEdgeStyle.gpPortColor(GPPort.GP_NOZZLE) != GPEdgeStyle.gpPortColor(GPPort.GP_SIGNAL),
		"a process nozzle and a signal terminal must not share a colour")
	gpCheck(GPEdgeStyle.gpPortColor(GPPort.GP_ACTUATOR) != GPEdgeStyle.gpPortColor(GPPort.GP_SIGNAL),
		"an actuator and a signal terminal must not share a colour")
	gpCheck(GPEdgeStyle.gpPortColor("NONSENSE") == GPEdgeStyle.gpPortColor(GPPort.GP_TERMINAL),
		"an unknown purpose falls back to the generic terminal colour")


func gpTestLineTypeKeys() -> void:
	gpEq(GPEdgeStyle.gpLineTypeKey(GPPIDEdge.GP_PROCESS, ""), "line_type_process",
		"process lines have their own i18n key")
	gpEq(GPEdgeStyle.gpLineTypeKey(GPPIDEdge.GP_SIGNAL, "PNEUMATIC"), "line_type_pneumatic",
		"pneumatic signal lines have their own i18n key")
