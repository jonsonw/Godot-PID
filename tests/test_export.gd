# GUT test stub for exporters (Dev Guide §4.1 / §4.6.2).
# 导出器的 GUT 测试桩（开发指南 §4.1 / §4.6.2）。
# Intended runner is GUT. Until it is installed, this uses the built-in assert() so the
# script parses and can be run standalone. Once GUT is added, change `extends Node` back to
# `extends GutTest` and swap assert() for assert_eq()/assert_true().
# 预期测试运行器为 GUT。在 GUT 安装前，本脚本用内置 assert() 以便解析并能独立运行。
# 待 GUT 接入后，将 `extends Node` 改回 `extends GutTest`，并把 assert() 换回 assert_eq()/assert_true()。
extends Node

# Ensure DxfExporter returns a boolean (stub contract).
# 验证 DxfExporter 返回布尔值（桩契约）。
func gpTestDxfExportReturnsBool() -> void:
	var gpEx: GPDxfExporter = GPDxfExporter.new()
	var gpResult: bool = gpEx.gpExport(null, "res://test_out.dxf")
	assert(gpResult is bool, "DxfExporter.export should return bool")


# Ensure PdfExporter returns a boolean (stub contract).
# 验证 PdfExporter 返回布尔值（桩契约）。
func gpTestPdfExportReturnsBool() -> void:
	var gpEx: GPPdfExporter = GPPdfExporter.new()
	var gpResult: bool = gpEx.gpExport(null, "res://test_out.pdf")
	assert(gpResult is bool, "PdfExporter.export should return bool")


# Ensure ListBasic.export_lists returns a Dictionary (stub contract).
# 验证 ListBasic.export_lists 返回字典（桩契约）。
func gpTestExportListsReturnsDict() -> void:
	var gpLb: GPListBasic = GPListBasic.new()
	var gpOut: Dictionary = gpLb.gpExportLists(null, "user://")
	assert(gpOut is Dictionary, "ListBasic.export_lists should return Dictionary")
