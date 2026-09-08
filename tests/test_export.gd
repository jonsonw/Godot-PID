extends GutTest
# GUT tests for the exporter stubs (Dev Guide §4.1 / §4.6.2).
# 导出器桩的 GUT 测试（开发指南 §4.1 / §4.6.2）。
#
# History / 变更说明：
#   本文件最初是在 GUT 尚未安装时写下的「桩的桩」——`extends Node` + 内置 assert()，
#   以便脚本可解析、可独立运行。GUT 9.6.1 安装后按其原始注释要求改造为 `extends GutTest`，
#   方法名由 gpTest* 改为 GUT 约定的 test_*，断言换用 assert_true / assert_false。
#
# Contract under test / 被测契约：
#   GPDxfExporter.gpExport(gpDoc, gpPath) -> bool
#   GPPdfExporter.gpExport(gpDoc, gpPath) -> bool
#   GPListBasic.gpExportLists(gpDoc, gpDir) -> Dictionary
#   三者当前均为未实现桩（恒返回 false / 空字典）。测试锁定「桩契约」，
#   待导出器真正落地后需同步更新断言（届时返回值不再为 false）。


# DxfExporter must return a bool; the stub returns false until implemented.
# DxfExporter 必须返回 bool；未实现前桩返回 false。
func test_dxf_export_returns_bool() -> void:
	var gpEx: GPDxfExporter = GPDxfExporter.new()
	var gpResult: bool = gpEx.gpExport(null, "res://test_out.dxf")
	assert_true(gpResult is bool, "GPDxfExporter.gpExport 应返回 bool")
	assert_false(gpResult, "DXF 导出尚未实现，桩应返回 false")


# PdfExporter must return a bool; the stub returns false until implemented.
# PdfExporter 必须返回 bool；未实现前桩返回 false。
func test_pdf_export_returns_bool() -> void:
	var gpEx: GPPdfExporter = GPPdfExporter.new()
	var gpResult: bool = gpEx.gpExport(null, "res://test_out.pdf")
	assert_true(gpResult is bool, "GPPdfExporter.gpExport 应返回 bool")
	assert_false(gpResult, "PDF 导出尚未实现，桩应返回 false")


# ListBasic.export_lists must return a Dictionary; the stub returns an empty one.
# ListBasic.export_lists 必须返回 Dictionary；桩返回空字典。
func test_export_lists_returns_dict() -> void:
	var gpLb: GPListBasic = GPListBasic.new()
	var gpOut: Dictionary = gpLb.gpExportLists(null, "user://")
	assert_true(gpOut is Dictionary, "GPListBasic.gpExportLists 应返回 Dictionary")
	assert_eq(gpOut.size(), 0, "清单导出尚未实现，桩应返回空字典")
