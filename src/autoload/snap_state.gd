extends Node
# Copyright © 2026 Jonson Wang
# Global snap / ortho state, surfaced as CAD-conventional toggles in the status bar.
# 全局捕捉 / 正交状态，作为状态栏中的 CAD 常规开关暴露。
#
# Tools adopt this state in a follow-up pass; for now it is the SINGLE SOURCE OF TRUTH
# the status bar binds to, so enabling the UI cannot regress any existing tool behaviour.
# 工具在后续接入本状态；当前它是状态栏绑定的唯一事实来源，故启用该 UI 不会回归任何
# 既有工具行为。
# 编码规范：所有变量均显式声明类型。

# Snap point kinds (mirrors the CAD convention). / 捕捉点类型（对应 CAD 惯例）。
enum GP_SNAP_TYPE { ENDPOINT, MIDPOINT, INTERSECTION, PERPENDICULAR }

# Whether endpoint/feature snapping is active. / 端点/特征捕捉是否启用。
var gpSnapEnabled: bool = true

# Whether orthogonal (90°) routing is forced for new connections. / 新连线是否强制正交（90°）。
var gpOrthoEnabled: bool = true

# Active snap point kind. / 当前捕捉点类型。
var gpSnapType: int = GP_SNAP_TYPE.ENDPOINT

# Snap pick radius in world units. / 捕捉拾取半径（世界单位）。
var gpSnapSize: float = 2.5


signal gpSnapChanged(gpOn: bool)
signal gpOrthoChanged(gpOn: bool)
signal gpSnapTypeChanged(gpType: int)


func gpSetSnap(gpOn: bool) -> void:
	gpSnapEnabled = gpOn
	gpSnapChanged.emit(gpOn)


func gpSetOrtho(gpOn: bool) -> void:
	gpOrthoEnabled = gpOn
	gpOrthoChanged.emit(gpOn)


func gpSetSnapType(gpType: int) -> void:
	gpSnapType = gpType
	gpSnapTypeChanged.emit(gpType)
