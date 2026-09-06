class_name GPDxfExporter
extends RefCounted

# Export DXF (vector): PIDGraph -> LINE/CIRCLE/TEXT/LWPOLYLINE entities + frame.
# Plain-text R12, openable by any CAD. See Dev Guide §4.4.2 / §4.6.2.
# 导出 DXF（矢量）：PIDGraph → LINE/CIRCLE/TEXT/LWPOLYLINE 实体 + 图框。
# 纯文本 R12，任何 CAD 可打开。见开发指南 §4.4.2 / §4.6.2。

# Export a document to a DXF file; returns success.
# 将文档导出为 DXF 文件，返回是否成功。
func gpExport(gpDoc, gpPath: String) -> bool:
	return false
