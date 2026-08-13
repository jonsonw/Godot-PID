class_name GPPIDMenuBar
extends HBoxContainer

# Top CAD-style menu bar: File / Edit / View / Insert / Format / Tools / Help.
# File has Print / Export→PDF / Export→DXF; Insert has Frame; Format has Frame Style.
# 顶部 CAD 风格菜单栏：文件/编辑/视图/插入/格式/工具/帮助。
# 文件含打印/导出→PDF/导出→DXF；插入含图框；格式含图框样式。
# Menu actions map to existing singletons/exporters (no new logic layer).
# 菜单动作映射到既有单例/导出器（不引入新逻辑层）。
# See Dev Guide §4.4 / §4.4.1.
# 见开发指南 §4.4 / §4.4.1。

# Emitted when a menu action fires
# 菜单动作触发时发出
signal gpActionTriggered(gpId: String)

# TODO: build menus, wire to AppState / Persistence / FrameEditor / DxfExporter / PdfExporter.
# TODO：构建菜单，接到 AppState / Persistence / FrameEditor / DxfExporter / PdfExporter。
