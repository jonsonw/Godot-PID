class_name GPPdfExporter
extends RefCounted

# Export PDF / print: rasterize the canvas at sheet size + compose frame/title block -> one-page PDF.
# 导出 PDF / 打印：画布按幅面高分辨率栅格化 + 图框标题栏合成 → 单页 PDF。
# See Dev Guide §4.4.2 / §4.6.2.
# 见开发指南 §4.4.2 / §4.6.2。

# Export a document to a PDF file; returns success.
# 将文档导出为 PDF 文件，返回是否成功。
func gpExport(gpDoc, gpPath: String) -> bool:
	return false


# Open the system print dialog (Ctrl+P).
# 调系统打印对话框（Ctrl+P）。
func gpPrint(gpDoc) -> void:
	pass
