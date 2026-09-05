extends Node

# Global localization singleton. Holds the translation table for UI chrome,
# menu items, built-in symbol names and categories. Emits gpLocaleChanged when
# the active language is switched so widgets can refresh their text.
# 全局本地化单例。存放界面文案、菜单项、内置图元名称与类目的翻译表。
# 切换活动语言时 emit gpLocaleChanged，供各控件刷新文本。
# Coding rule: every variable must declare its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Emitted when the active locale changes, carrying the new locale code.
# 活动语言变化时发出，携带新的语言代码。
signal gpLocaleChanged(locale: String)

# Current active locale code.
# 当前活动语言代码。
var gpLocale: String = "zh"

# Translation table: key -> { "zh": ..., "en": ... }.
# 翻译表：键 -> { "zh": ..., "en": ... }。
const GP_STRINGS: Dictionary = {
	# ---- app chrome ----
	"symbol_lib.title":        { "zh": "图元库",           "en": "Symbol Library" },
	"symbol_lib.search":       { "zh": "搜索图元名称 / 类目…", "en": "Search symbols / categories…" },
	"symbol_lib.tool_select":  { "zh": "选择",             "en": "Select" },
	"symbol_lib.tool_connect": { "zh": "连线",             "en": "Connect" },
	"symbol_lib.tool_custom":  { "zh": "自定义图元",        "en": "Custom Symbol" },
	"symbol_lib.ctx_delete":  { "zh": "删除",             "en": "Delete" },
	"symbol_lib.delete_title": { "zh": "删除图元",       "en": "Delete Symbol" },
	"symbol_lib.delete_used_confirm": { "zh": "该图元已在画布 %d 处使用，删除将一并移除这些实例及其连线。确认删除？", "en": "This symbol is used in %d place(s) on the canvas. Deleting it will also remove those instances and their connections. Confirm deletion?" },
	"symbol_lib.no_selection": { "zh": "（未选中对象）",     "en": "(no selection)" },
	"symbol_lib.empty_attrs":  { "zh": "（该图元暂无可配置属性）", "en": "(no configurable attributes)" },
	"symbol_lib.select_hint":  { "zh": "未选中对象。\n在画布中点选一个图元以编辑其属性。",
								  "en": "No object selected.\nClick a symbol on the canvas to edit its properties." },

	"prop.label":   { "zh": "标签",   "en": "Label" },
	"prop.title":   { "zh": "属性",   "en": "Properties" },
	"prop.info":    { "zh": "选型",   "en": "Spec" },
	"prop.doc":     { "zh": "文档",   "en": "Document" },

	"info.id":       { "zh": "ID",     "en": "ID" },
	"info.type":     { "zh": "类型",   "en": "Type" },
	"info.category": { "zh": "类目",   "en": "Category" },
	"info.size":     { "zh": "尺寸",   "en": "Size" },

	"status.ready":         { "zh": "就绪",             "en": "Ready" },
	"status.none":          { "zh": "—",               "en": "—" },
	"status.selected":      { "zh": "选中：%s",         "en": "Selected: %s" },
	"status.coord":         { "zh": "X: %d  Y: %d",     "en": "X: %d  Y: %d" },
	"status.zoom":          { "zh": "缩放：%d%%",        "en": "Zoom: %d%%" },
	"status.symbol_picked": { "zh": "已选图元：%s（点画布放置）", "en": "Symbol selected: %s (click canvas to place)" },
	"status.mode_select":   { "zh": "模式：选择",        "en": "Mode: Select" },
	"status.mode_connect":  { "zh": "模式：连线（依次点两个图元）", "en": "Mode: Connect (click two symbols)" },
	"status.mode_line":     { "zh": "绘图：直线（在画布上拖拽）", "en": "Draw: Line (drag on canvas)" },
	"status.mode_circle":   { "zh": "绘图：圆（在画布上拖拽）", "en": "Draw: Circle (drag on canvas)" },
	"status.mode_rect":     { "zh": "绘图：矩形（在画布上拖拽）", "en": "Draw: Rectangle (drag on canvas)" },
	"status.mode_polyline": { "zh": "绘图：折线（逐点单击，双击结束）", "en": "Draw: Polyline (click points, double-click to finish)" },
	"status.custom_pending":{ "zh": "自定义图元编辑器：待接入",     "en": "Custom symbol editor: TODO" },
	"status.view_reset":    { "zh": "视图已复位",        "en": "View reset" },
	"status.symbol_saved":     { "zh": "图元已更新：%s（画布实例已同步）", "en": "Symbol updated: %s (canvas instances synced)" },
	"status.symbol_deleted":   { "zh": "图元已删除：%s", "en": "Symbol deleted: %s" },
	"status.cleared":          { "zh": "画布已清空",        "en": "Canvas cleared" },
	"status.feature_todo":  { "zh": "功能待接入：%s",    "en": "Feature pending: %s" },
	"status.saved_with_packs": { "zh": "已保存：%s（含 %d 个用户图元包）", "en": "Saved: %s (%d user packs embedded)" },
	"status.save_fail":        { "zh": "保存失败：%s",    "en": "Save failed: %s" },
	"status.loaded_with_packs":{ "zh": "已打开：%s（含 %d 个用户图元包）", "en": "Opened: %s (%d user packs embedded)" },
	"status.load_fail":        { "zh": "打开失败：%s",    "en": "Open failed: %s" },

	"doc.info": { "zh": "G-PID 工程\n文档元信息（标题 / 图号 / 版本）待接入。",
				  "en": "G-PID Project\nDocument metadata (title / drawing no. / revision) pending." },
	"doc.pid_filter": { "zh": "G-PID 工程 (*.pid.json)", "en": "G-PID Project (*.pid.json)" },

	"settings.title":      { "zh": "设置",          "en": "Settings" },
	"settings.font_size":  { "zh": "界面字体大小",   "en": "UI Font Size" },
	"settings.ui_font":    { "zh": "界面字体",       "en": "UI Font" },
	"settings.symbol_font_size": { "zh": "图元字体大小", "en": "Symbol Font Size" },
	"settings.symbol_font":{ "zh": "图元字体",       "en": "Symbol Font" },
	"settings.language":   { "zh": "语言",          "en": "Language" },
	"settings.auto_scale": { "zh": "界面随窗口自适应缩放", "en": "Auto-fit UI to window" },
	"settings.ok":         { "zh": "确定",          "en": "OK" },
	"settings.lang_zh":    { "zh": "中文",          "en": "中文" },
	"settings.lang_en":    { "zh": "English",       "en": "English" },

	# ---- menus ----
	"menu.file":               { "zh": "文件",         "en": "File" },
	"menu.edit":               { "zh": "编辑",         "en": "Edit" },
	"menu.view":               { "zh": "视图",         "en": "View" },
	"menu.insert":             { "zh": "插入",         "en": "Insert" },
	"menu.format":             { "zh": "格式",         "en": "Format" },
	"menu.tools":              { "zh": "工具",         "en": "Tools" },
	"menu.help":               { "zh": "帮助",         "en": "Help" },
	"menu.file_new":           { "zh": "新建",         "en": "New" },
	"menu.file_open":          { "zh": "打开…",        "en": "Open…" },
	"menu.file_save":          { "zh": "保存",         "en": "Save" },
	"menu.file_save_as":       { "zh": "另存为…",      "en": "Save As…" },
	"menu.file_print":         { "zh": "打印…",        "en": "Print…" },
	"menu.export_pdf":         { "zh": "导出 PDF…",    "en": "Export PDF…" },
	"menu.export_dxf":         { "zh": "导出 DXF…",    "en": "Export DXF…" },
	"menu.edit_undo":          { "zh": "撤销",         "en": "Undo" },
	"menu.edit_redo":          { "zh": "重做",         "en": "Redo" },
	"menu.edit_delete":        { "zh": "删除选中",     "en": "Delete Selected" },
	"menu.edit_clear":         { "zh": "清空画布",     "en": "Clear Canvas" },
	"menu.view_fit":           { "zh": "适应窗口",     "en": "Fit Window" },
	"menu.view_zoom_in":       { "zh": "放大",         "en": "Zoom In" },
	"menu.view_zoom_out":      { "zh": "缩小",         "en": "Zoom Out" },
	"menu.view_grid":          { "zh": "显示网格",     "en": "Show Grid" },
	"menu.insert_frame":       { "zh": "图框",         "en": "Frame" },
	"menu.insert_frame_style": { "zh": "图框样式…",    "en": "Frame Style…" },
	"menu.format_bg":          { "zh": "画布背景色…",  "en": "Canvas Background…" },
	# "New Symbol" now routes to drawing guidance on the main canvas: draw annotation shapes,
	# select them, then right-click "生成图元" to open the Make Symbol dialog.
	"menu.tool_ai_unitop":     { "zh": "AI 生成单元操作", "en": "AI Generate Unit Op" },
	"menu.tool_settings":      { "zh": "设置",         "en": "Settings" },
	"menu.help_about":         { "zh": "关于 G-PID",   "en": "About G-PID" },

	# ---- built-in symbol display names ----
	"泵":       { "zh": "泵",       "en": "Pump" },
	"储罐":     { "zh": "储罐",     "en": "Tank" },
	"阀门":     { "zh": "阀门",     "en": "Valve" },
	"仪表":     { "zh": "仪表",     "en": "Instrument" },
	"换热器":   { "zh": "换热器",   "en": "Heat Exchanger" },

	# ---- open-pid-icons vector symbol display names ----
	"闸阀":       { "zh": "闸阀",       "en": "Gate valve" },
	"手动闸阀":   { "zh": "手动闸阀",   "en": "Hand operated gate valve" },
	"手动截止阀": { "zh": "手动截止阀", "en": "Hand operated globe valve" },
	"旋转阀":     { "zh": "旋转阀",     "en": "Rotary valve" },
	"止回阀":     { "zh": "止回阀",     "en": "Check valve" },

	# ---- built-in categories ----
	"pump":       { "zh": "泵",       "en": "Pump" },
	"tank":       { "zh": "储罐",     "en": "Tank" },
	"valve":      { "zh": "阀门",     "en": "Valve" },
	"instrument": { "zh": "仪表",     "en": "Instrument" },
	"heat":       { "zh": "换热器",   "en": "Heat Exchanger" },

	# ---- main canvas interaction / 主画布交互 ----
	"canvas.ctx_edit_symbol":  { "zh": "修改图元…", "en": "Modify Symbol…" },
	"canvas.ctx_duplicate":    { "zh": "复制", "en": "Duplicate" },
	"canvas.ctx_delete":       { "zh": "删除", "en": "Delete" },
	"canvas.ctx_select_all":   { "zh": "全选", "en": "Select All" },
	"canvas.ctx_deselect":     { "zh": "取消选择", "en": "Deselect" },
	"canvas.ctx_connect_mode": { "zh": "连线模式", "en": "Connect Mode" },
	"canvas.ctx_make_symbol":  { "zh": "生成图元…", "en": "Make Symbol…" },
	# Annotation-polyline vertex editing (Bézier handles). Same labels as the symbol editor.
	# 注释折线的顶点编辑（贝塞尔手柄）。文案与符号编辑器一致。
	"canvas.ctx_smooth_vertex":  { "zh": "顶点转为平滑（拉出手柄）", "en": "Smooth Vertex (pull handles)" },
	"canvas.ctx_corner_vertex":  { "zh": "顶点转为拐角（收起手柄）", "en": "Corner Vertex (collapse handles)" },
	"canvas.ctx_delete_vertex":  { "zh": "删除此顶点", "en": "Delete This Vertex" },

	# ---- Main-canvas annotation draw tools / 主画布注释绘图工具 ----
	"canvas.tool_polyline":   { "zh": "折线", "en": "Polyline" },
	"canvas.tool_circle":     { "zh": "圆", "en": "Circle" },
	"canvas.tool_rect":       { "zh": "矩形", "en": "Rectangle" },
	"canvas.tool_line":       { "zh": "直线", "en": "Line" },

	# ---- Make-Symbol dialog (replaces the old glyph isolation editor) / 生成图元对话框 ----
	"make_symbol.title":       { "zh": "生成图元", "en": "Make Symbol" },
	"make_symbol.category":    { "zh": "图元类", "en": "Category" },
	"make_symbol.name":        { "zh": "名称（标识 id）", "en": "Name (id)" },
	"make_symbol.display_name": { "zh": "显示名称", "en": "Display Name" },
	"make_symbol.mode":        { "zh": "模式（由标识 id 自动决定）", "en": "Mode (auto-set by id)" },
	"make_symbol.new":         { "zh": "新建图元", "en": "Create New" },
	"make_symbol.overwrite":   { "zh": "覆盖已有图元", "en": "Overwrite Existing" },
	"make_symbol.id_exists":   { "zh": "已存在该标识 id（%s），确认后将覆盖此图元。", "en": "This id already exists (%s); confirming will overwrite it." },
	"make_symbol.builtin_protected": { "zh": "该标识 id 与内置图元冲突（内置只读），请更换标识。", "en": "This id clashes with a read-only built-in symbol; choose another id." },
	"make_symbol.name_empty":  { "zh": "请输入标识 id", "en": "Please enter an id" },
	"make_symbol.ok":          { "zh": "确定", "en": "OK" },
	"make_symbol.cancel":      { "zh": "取消", "en": "Cancel" },
	# Editor toolbar / 编辑器工具条
	"make_symbol.tool_select": { "zh": "选择", "en": "Select" },
	"make_symbol.tool_port":   { "zh": "加端点", "en": "Add Port" },
	"make_symbol.tool_line":   { "zh": "直线", "en": "Line" },
	"make_symbol.tool_rect":   { "zh": "矩形", "en": "Rectangle" },
	"make_symbol.tool_circle": { "zh": "圆", "en": "Circle" },
	"make_symbol.tool_poly":   { "zh": "折线", "en": "Polyline" },
	"make_symbol.editor_tip":  { "zh": "选择/加端点：左键点击编辑、拖拽移动。直线·矩形·圆：拖拽绘制。折线：逐点点击、回车结束、Esc 取消。Delete 删除选中。", "en": "Select/Add Port: click to edit, drag to move. Line/Rect/Circle: drag to draw. Polyline: click points, Enter to finish, Esc to cancel. Delete removes selection." },
	# Port (connection point) panel / 连接点面板
	"make_symbol.ports":        { "zh": "连接端点", "en": "Connection Ports" },
	"make_symbol.port_name":    { "zh": "端点名称", "en": "Port Name" },
	"make_symbol.port_dir":     { "zh": "朝向", "en": "Direction" },
	"make_symbol.port_dir_none": { "zh": "无", "en": "None" },
	"make_symbol.port_dir_left": { "zh": "左", "en": "Left" },
	"make_symbol.port_dir_right": { "zh": "右", "en": "Right" },
	"make_symbol.port_dir_up":  { "zh": "上", "en": "Up" },
	"make_symbol.port_dir_down": { "zh": "下", "en": "Down" },
	"make_symbol.delete_port":  { "zh": "删除端点", "en": "Delete Port" },
	"make_symbol.port_selected": { "zh": "已选中端点，可改名/改朝向/删除。", "en": "Port selected: rename, change direction or delete." },
	"make_symbol.no_port_selected": { "zh": "未选中端点。用「加端点」工具在画面点击添加。", "en": "No port selected. Use Add-Port tool and click on the canvas." },
	# Shape (geometry) panel / 图元几何面板
	"make_symbol.shapes":          { "zh": "图元几何", "en": "Glyph Geometry" },
	"make_symbol.delete_shape":    { "zh": "删除图形", "en": "Delete Shape" },
	"make_symbol.shape_selected":  { "zh": "已选中第 %d 个图形。", "en": "Shape #%d selected." },
	"make_symbol.no_shape_selected": { "zh": "共 %d 个图形。用上方工具添加，或选中后拖拽/删除。", "en": "%d shapes. Use a tool to add, or select to move/delete." },
	"center.sheet":           { "zh": "图纸", "en": "Sheet" },
	"center.add_tab":         { "zh": "新建图纸", "en": "New sheet" },
	"center.fullscreen":      { "zh": "全屏", "en": "Fullscreen" },
	"center.fullscreen_exit": { "zh": "退出全屏", "en": "Exit fullscreen" },
	"center.fullscreen_tip":  { "zh": "隐藏左右面板，绘图区占满窗口", "en": "Hide side panels, expand the canvas" },
}


# Translate a key into the current locale. Falls back to the key itself.
# 把键翻译成当前语言。无翻译时回退为键本身。
func gpTr(gpKey: String, gpFallback: String = "") -> String:
	var gpMap = GP_STRINGS.get(gpKey)
	if gpMap == null:
		return gpFallback if gpFallback != "" else gpKey
	var gpVal = gpMap.get(gpLocale)
	if gpVal == null or gpVal == "":
		return gpFallback if gpFallback != "" else gpKey
	return gpVal


# Switch locale and notify listeners.
# 切换语言并通知所有监听者。
func gpSetLocale(gpLocaleCode: String) -> void:
	if gpLocaleCode == gpLocale:
		return
	gpLocale = gpLocaleCode
	gpLocaleChanged.emit(gpLocale)
