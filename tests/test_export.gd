extends GutTest
# GUT smoke tests for the REAL exporters (stage 4 S3/S4).
# 真导出器的 GUT 冒烟测试（阶段 4 S3/S4）。
#
# History / 变更说明：
#   本文件最初钉的是「导出器桩恒返回 false」的桩契约。阶段 4 出图闭环（2026-10-17）
#   把 DXF / PDF 桩转为真实现 —— API 变为 static gpExportSheet(gpGraph, gpSheet, gpPath, …)，
#   旧 gpExport 不复存在，旧断言在运行期报 Nonexistent function（GUT 5/3 的 2 个失败）。
#   本文件随之更新为真契约的**薄冒烟**：真实几何行为由 gp_test_dxf_export.gd /
#   gp_test_pdf_export.gd 以字节级断言钉死（门 2 权威），此处只钉「API 存在 + 空输入礼貌拒绝」。
#
# Contract under test / 被测契约：
#   GPDxfExporter.gpExportSheet(gpGraph, gpSheet, gpPath, …) -> bool
#   GPPdfExporter.gpExportSheet(gpGraph, gpSheet, gpPath, …) -> bool
#   GPListBasic.gpExportLists(gpDoc, gpDir) -> Dictionary
#   两者对 gpSheet == null 一律礼貌返回 false（不崩溃、不落盘）。


# The DXF exporter serves the REAL sheet API and refuses missing input gracefully.
# DXF 导出器提供**真**图纸 API，且对缺失输入礼貌拒绝。
func test_dxf_export_sheet_api() -> void:
	var gpEx: GPDxfExporter = GPDxfExporter.new()
	assert_true(gpEx.has_method("gpExportSheet"), "GPDxfExporter 应提供 gpExportSheet 真实现")
	var gpResult: GPIOResult = gpEx.gpExportSheet(null, null, "user://test_out.dxf")
	assert_true(gpResult is GPIOResult, "gpExportSheet 应返回 GPIOResult")
	assert_false(gpResult.gpIsOk(), "gpSheet 为空时应礼貌拒绝（不落盘）")


# The PDF exporter serves the REAL sheet API and refuses missing input gracefully.
# PDF 导出器提供**真**图纸 API，且对缺失输入礼貌拒绝。
func test_pdf_export_sheet_api() -> void:
	var gpEx: GPPdfExporter = GPPdfExporter.new()
	assert_true(gpEx.has_method("gpExportSheet"), "GPPdfExporter 应提供 gpExportSheet 真实现")
	var gpResult: GPIOResult = gpEx.gpExportSheet(null, null, "user://test_out.pdf")
	assert_true(gpResult is GPIOResult, "gpExportSheet 应返回 GPIOResult")
	assert_false(gpResult.gpIsOk(), "gpSheet 为空时应礼貌拒绝（不落盘）")


# ListBasic.export_lists must return a Dictionary; the stub returns an empty one.
# ListBasic.export_lists 必须返回 Dictionary；桩返回空字典。
func test_export_lists_returns_dict() -> void:
	var gpLb: GPListBasic = GPListBasic.new()
	var gpOut: Dictionary = gpLb.gpExportLists(null, "user://")
	assert_true(gpOut is Dictionary, "GPListBasic.gpExportLists 应返回 Dictionary")
	assert_eq(gpOut.size(), 0, "清单导出尚未实现，桩应返回空字典")
