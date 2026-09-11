class_name GPSetLabelAnchorCommand
extends GPCommand
# Copyright © 2026 Jonson Wang
# Set the coarse label anchor of one instance (M11). Fine positioning is M10b's canvas grip.
# 设置单个实例标签的粗粒度锚点（M11）。精细定位由 M10b 的画布抓取点负责。
#
# GPPropertyResolver.GP_ANCHOR_UNSET (-1) means "follow the library default" and is a LEGAL
# stored value, so "unset" is never confused with "GP_AUTO" (0). That distinction is why the
# model uses a sentinel instead of zero.
# GPPropertyResolver.GP_ANCHOR_UNSET（-1）意为「跟随库默认」，是**合法**的存储值，
# 故「未设置」绝不会与 GP_AUTO（0）混淆。模型用哨兵而非零，正是为了保住这个区别。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

var _gpId: String = ""
var _gpNewAnchor: int = GPPropertyResolver.GP_ANCHOR_UNSET
var _gpOldAnchor: int = GPPropertyResolver.GP_ANCHOR_UNSET


func _init(gpInId: String, gpInAnchor: int) -> void:
	_gpId = gpInId
	_gpNewAnchor = gpInAnchor
	gpLabel = "设置标签位置"


func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or gpCtx.gpGraph == null:
		return false
	var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(_gpId)
	if gpN == null:
		return false
	_gpOldAnchor = gpN.gpLabelAnchor
	if _gpOldAnchor == _gpNewAnchor:
		return false
	gpN.gpLabelAnchor = _gpNewAnchor
	gpCtx.gpGraph.gpGraphChanged.emit()
	return true


func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(_gpId)
	if gpN == null:
		return
	gpN.gpLabelAnchor = _gpOldAnchor
	gpCtx.gpGraph.gpGraphChanged.emit()


func gpRedo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	var gpN: GPPIDNode = gpCtx.gpGraph.gpGetNode(_gpId)
	if gpN == null:
		return
	gpN.gpLabelAnchor = _gpNewAnchor
	gpCtx.gpGraph.gpGraphChanged.emit()
