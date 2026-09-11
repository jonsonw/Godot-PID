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
	"symbol_lib.tool_pipe":    { "zh": "管道",             "en": "Pipe" },
	"symbol_lib.tool_signal":  { "zh": "信号线",           "en": "Signal" },
	"ribbon.tab_home":         { "zh": "常用",   "en": "Home" },
	"ribbon.tab_view":         { "zh": "视图",   "en": "View" },
	"ribbon.tab_edit":         { "zh": "编辑",   "en": "Edit" },
	"ribbon.grp_pointer":      { "zh": "指针",   "en": "Pointer" },
	"ribbon.grp_draw":         { "zh": "绘制",   "en": "Draw" },
	"ribbon.grp_line":         { "zh": "管线",   "en": "Piping" },
	"ribbon.grp_view":         { "zh": "视图",   "en": "View" },
	"ribbon.grp_edit":         { "zh": "编辑",   "en": "Edit" },
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

	# ---- inspector (M10): identity, symbol swap, typed property fields ----
	# ---- 属性面板（M10）：标识、更换图元、类型化属性字段 ----
	"inspector.identity":      { "zh": "标识",     "en": "Identity" },
	"inspector.properties":    { "zh": "工艺属性", "en": "Process Properties" },
	"inspector.label":         { "zh": "标签",     "en": "Label" },
	"inspector.symbol_id":     { "zh": "图元标识", "en": "Symbol ID" },
	"inspector.swap":          { "zh": "更换图元", "en": "Change Symbol" },
	"inspector.tag":           { "zh": "位号",     "en": "Tag" },
	"inspector.name_zh":       { "zh": "名称（中文）", "en": "Name (Chinese)" },
	"inspector.name_en":       { "zh": "名称（英文）", "en": "Name (English)" },
	"inspector.anchor":        { "zh": "标签位置", "en": "Label Position" },
	"inspector.anchor_follow": { "zh": "跟随图元库默认", "en": "Follow library default" },
	"inspector.orphan":        { "zh": "库中已删除的字段（值保留）", "en": "Removed from library (values kept)" },
	"inspector.default":       { "zh": "默认",     "en": "default" },
	"inspector.required":      { "zh": "必填",     "en": "required" },
	"inspector.no_props":      { "zh": "（该图元暂无可配置属性）", "en": "(no configurable properties)" },
	"inspector.batch":         { "zh": "批量编辑：已选中 %d 个同类图元，修改将同时生效",
								 "en": "Batch edit: %d instances selected — edits apply to all" },
	"inspector.clean_orphans":  { "zh": "清理这 %d 项孤儿值", "en": "Discard these %d orphaned values" },
	"inspector.group_general": { "zh": "通用",     "en": "General" },

	# ---- label anchors (GPLabelAnchor) ----
	"anchor.auto":   { "zh": "自动", "en": "Auto" },
	"anchor.below":  { "zh": "下方", "en": "Below" },
	"anchor.above":  { "zh": "上方", "en": "Above" },
	"anchor.inside": { "zh": "内部", "en": "Inside" },
	"anchor.left":   { "zh": "左侧", "en": "Left" },
	"anchor.right":  { "zh": "右侧", "en": "Right" },

	"info.id":       { "zh": "ID",     "en": "ID" },
	"info.type":     { "zh": "类型",   "en": "Type" },
	"info.category": { "zh": "类目",   "en": "Category" },
	"info.size":     { "zh": "尺寸",   "en": "Size" },

	# ---- edge / connection refusals (P3) ----
	"edge.port_type_mismatch":   { "zh": "端口类型不符：管道只能连管口，信号线只能连信号 / 执行机构端。", "en": "Port type mismatch: pipes connect nozzles only; signal lines connect signal / actuator ends only." },
	"edge.pipe_needs_one_bound": { "zh": "管道至少需连接一端。", "en": "A pipe needs at least one bound end." },
	"edge.edge_self_loop":       { "zh": "不能连到同一端口。", "en": "Cannot connect to the same port." },
	"edge.port_missing":         { "zh": "端点无法解析（图元或端口缺失）。", "en": "Endpoint could not be resolved (symbol or port missing)." },
	"edge.edge_duplicate":       { "zh": "该连线已存在。", "en": "This connection already exists." },

	# ---- connectivity tool status (P3) ----
	"status.mode_pipe":   { "zh": "管道模式", "en": "Pipe mode" },
	"status.mode_signal": { "zh": "信号线模式", "en": "Signal mode" },

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

	# ---- CAD snap / ortho toggles (status bar, P1) ----
	# ---- CAD 捕捉 / 正交开关（状态栏，P1）----
	"status.snap":        { "zh": "捕捉",   "en": "Snap" },
	"status.ortho":       { "zh": "正交",   "en": "Ortho" },
	"status.snap_type":   { "zh": "捕捉点", "en": "Snap to" },
	"snap.endpoint":       { "zh": "端点", "en": "Endpoint" },
	"snap.midpoint":       { "zh": "中点", "en": "Midpoint" },
	"snap.intersection":   { "zh": "交点", "en": "Intersection" },
	"snap.perpendicular":  { "zh": "垂足", "en": "Perpendicular" },
	"settings.screen_constant_width": { "zh": "出图线宽（屏幕恒定）", "en": "Plot lineweight (screen-constant)" },
	"status.view_reset":    { "zh": "视图已复位",        "en": "View reset" },
	"status.symbol_saved":     { "zh": "图元已更新：%s（画布实例已同步）", "en": "Symbol updated: %s (canvas instances synced)" },
	"status.symbol_deleted":   { "zh": "图元已删除：%s", "en": "Symbol deleted: %s" },
	"status.cleared":          { "zh": "画布已清空",        "en": "Canvas cleared" },
	"status.undone":           { "zh": "已撤销",            "en": "Undone" },
	"status.redone":           { "zh": "已重做",            "en": "Redone" },
	"status.nothing_to_undo":  { "zh": "没有可撤销的操作",  "en": "Nothing to undo" },
	"status.nothing_to_redo":  { "zh": "没有可重做的操作",  "en": "Nothing to redo" },
	"status.feature_todo":  { "zh": "功能待接入：%s",    "en": "Feature pending: %s" },
	"status.saved_with_packs": { "zh": "已保存：%s（含 %d 个用户图元包）", "en": "Saved: %s (%d user packs embedded)" },
	"swap.warn_ports":         { "zh": "更换图元：%d 条连线因端口缺失已降级到图元中心（连接未断）",
								 "en": "Symbol changed: %d connection(s) lost their port and now attach to the symbol centre (still connected)" },
	"swap.done":               { "zh": "已更换图元：%s（位号与连线保持不变）",
								 "en": "Symbol changed to %s (tag and connections unchanged)" },
	"swap.no_such_symbol":     { "zh": "更换失败：找不到图元 %s", "en": "Swap failed: symbol %s not found" },
	"lib.drift":               { "zh": "图元库已变更：%d 个图元字段与存盘时不同（已迁移 %d 个实例，孤儿值 %d 项已保留）",
								 "en": "Library changed: %d symbol(s) differ from when this file was saved (%d instance(s) migrated, %d orphaned value(s) kept)" },
	"lib.orphans_cleaned":     { "zh": "已清理 %d 项孤儿值", "en": "Discarded %d orphaned value(s)" },
	"status.save_fail":        { "zh": "保存失败：%s",    "en": "Save failed: %s" },
	"status.loaded_with_packs":{ "zh": "已打开：%s（含 %d 个用户图元包）", "en": "Opened: %s (%d user packs embedded)" },
	"status.load_fail":        { "zh": "打开失败：%s",    "en": "Open failed: %s" },
	"status.exported":         { "zh": "已导出：%s（节点 %d / 连线 %d）",
								 "en": "Exported: %s (%d nodes / %d edges)" },
	"status.export_fail":      { "zh": "导出失败：%s",    "en": "Export failed: %s" },
	"status.export_empty":     { "zh": "没有可导出的内容", "en": "Nothing to export" },
	"status.imported":         { "zh": "已导入：%s（错误 %d / 警告 %d）",
								 "en": "Imported: %s (%d error(s) / %d warning(s))" },
	"status.import_fail":      { "zh": "导入失败：%s",    "en": "Import failed: %s" },
	"status.import_unknown":   { "zh": "不是 G-PID 文件：%s", "en": "Not a G-PID file: %s" },
	"status.import_future":    { "zh": "文件由更新版本创建：%s", "en": "File was created by a newer version: %s" },

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
	"settings.pipe_tag_rotate":   { "zh": "竖管位号旋转", "en": "Rotate vertical line numbers" },
	"settings.pipe_tag_font_size": { "zh": "位号字号（0=图元字号）", "en": "Line number size (0=symbol size)" },
	"settings.ok":         { "zh": "确定",          "en": "OK" },
	"settings.lang_zh":    { "zh": "中文",          "en": "Chinese" },
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
	"menu.file_import":        { "zh": "导入…",        "en": "Import…" },
	"menu.file_quit":          { "zh": "退出",         "en": "Quit" },
	"menu.export":             { "zh": "导出",         "en": "Export" },
	"menu.export_project":     { "zh": "工程…",        "en": "Project…" },
	"menu.export_library":     { "zh": "图元库…",      "en": "Symbol Library…" },
	"menu.export_config":      { "zh": "项目配置…",    "en": "Project Config…" },
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
	"make_symbol.name":        { "zh": "名称", "en": "Name" },
	"make_symbol.display_name": { "zh": "显示名称", "en": "Display Name" },
	"make_symbol.mode":        { "zh": "模式（由标识 id 自动决定）", "en": "Mode (auto-set by id)" },
	"make_symbol.new":         { "zh": "新建图元", "en": "Create New" },
	"make_symbol.overwrite":   { "zh": "覆盖已有图元", "en": "Overwrite Existing" },
	"make_symbol.id_exists":   { "zh": "已存在同名图元（%s），确认后将覆盖此图元。", "en": "A symbol with this name already exists (%s); confirming will overwrite it." },
	"make_symbol.builtin_protected": { "zh": "该名称与内置图元冲突（内置只读），请更换名称。", "en": "This name clashes with a read-only built-in symbol; choose another name." },
	"make_symbol.name_empty":  { "zh": "请输入图元名称", "en": "Please enter a symbol name" },
	"make_symbol.category_full": { "zh": "类别 %s 的编号已用满（999），请更换类别。", "en": "Category %s has no free id left (999 used); choose another category." },
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

	# ---- edge / connection inspector (P4) ----
	"prop.edge":            { "zh": "连线", "en": "Connection" },
	"edge.kind":            { "zh": "类型", "en": "Kind" },
	"edge.signal_type":     { "zh": "信号类型", "en": "Signal Type" },
	"edge.tag":             { "zh": "管线号", "en": "Line Number" },
	"edge.dn":              { "zh": "公称直径", "en": "Nominal Ø (DN)" },
	"edge.medium":          { "zh": "介质", "en": "Medium" },
	"edge.spec":            { "zh": "管道等级", "en": "Pipe Spec" },
	"edge.insulation":      { "zh": "保温", "en": "Insulation" },
	"edge.show_arrow":      { "zh": "流向箭头", "en": "Flow Arrow" },
	"edge.show_tag":        { "zh": "显示编号", "en": "Show Number" },
	"edge.kind_process":    { "zh": "主工艺管线", "en": "Process Line" },
	"edge.kind_utility":    { "zh": "公用工程管线", "en": "Utility Line" },
	"edge.kind_signal":     { "zh": "信号线", "en": "Signal Line" },
	"edge.type_electric":   { "zh": "电气", "en": "Electric" },
	"edge.type_pneumatic":  { "zh": "气动", "en": "Pneumatic" },
	"edge.type_hydraulic":  { "zh": "液压", "en": "Hydraulic" },
	"edge.type_data":       { "zh": "数据 (DCS)", "en": "Data (DCS)" },
	"edge.type_capillary":  { "zh": "毛细管", "en": "Capillary" },

	# ---- line-type names (inspector header + legend) ----
	"line_type_process":    { "zh": "主工艺管线", "en": "Process Line" },
	"line_type_utility":    { "zh": "公用工程管线", "en": "Utility Line" },
	"line_type_electric":   { "zh": "电气信号", "en": "Electric Signal" },
	"line_type_pneumatic":  { "zh": "气动信号", "en": "Pneumatic Signal" },
	"line_type_hydraulic":  { "zh": "液压信号", "en": "Hydraulic Signal" },
	"line_type_data":       { "zh": "数据信号", "en": "Data Signal" },
	"line_type_capillary":  { "zh": "毛细管信号", "en": "Capillary Signal" },
	"line_type_unknown":    { "zh": "未知线型", "en": "Unknown Line Type" },

	# ---- edge context menu (P4) ----
	"canvas.ctx_delete_edge":    { "zh": "删除连线", "en": "Delete Connection" },
	"canvas.ctx_set_process":    { "zh": "改为主工艺管线", "en": "Set as Process Line" },
	"canvas.ctx_set_utility":    { "zh": "改为公用工程管线", "en": "Set as Utility Line" },
	"canvas.ctx_set_signal":     { "zh": "改为信号线", "en": "Set as Signal Line" },
	"canvas.ctx_resnap_ends":    { "zh": "重新吸附端点", "en": "Re-snap Ends" },
	"canvas.ctx_clear_vertices": { "zh": "清除拐点", "en": "Clear Vertices" },
	"canvas.ctx_renumber":       { "zh": "重新编号", "en": "Renumber" },
	"canvas.ctx_auto_connect":   { "zh": "自动连线", "en": "Auto-Connect" },

	# ---- edge status messages (P4) ----
	"status.edge_tag_manual": { "zh": "位号已手工指定（重新编号将跳过）", "en": "Line number set manually (renumber will skip it)" },
	"status.renumbered":      { "zh": "已重新编号 %d 条管线", "en": "Renumbered %d lines" },
	"status.resnapped":       { "zh": "已重新吸附端点", "en": "Ends re-snapped" },

	# ---- generic dialog buttons ----
	"dialog.ok":              { "zh": "确定", "en": "OK" },
	"dialog.cancel":          { "zh": "取消", "en": "Cancel" },
	"dialog.unsaved_title":   { "zh": "未保存的更改", "en": "Unsaved Changes" },
	"dialog.unsaved_text":    { "zh": "当前图纸有未保存的更改。关闭前要保存吗？",
								"en": "This drawing has unsaved changes. Save before closing?" },
	"dialog.unsaved_save":    { "zh": "保存", "en": "Save" },
	"dialog.unsaved_discard": { "zh": "不保存", "en": "Don't Save" },
	"status.tmp_cleaned":     { "zh": "已清理上次未完成的写入残留：%s",
								"en": "Cleaned up a leftover partial write: %s" },

	# ---- project menu (M9b) ----
	"menu.project":               { "zh": "项目", "en": "Project" },
	"menu.project_tag_rules":     { "zh": "位号编号规则…", "en": "Tag Numbering Rules…" },
	"menu.project_export_list":   { "zh": "导出设备清单…", "en": "Export Equipment List…" },

	# ---- tag numbering rules dialog (M9b) ----
	"tag_rule.title":         { "zh": "位号编号规则", "en": "Tag Numbering Rules" },
	"tag_rule.template":      { "zh": "模板（须含 {seq}）", "en": "Template (must contain {seq})" },
	"tag_rule.numbers":       { "zh": "序号", "en": "Sequence" },
	"tag_rule.start":         { "zh": "起始", "en": "Start" },
	"tag_rule.step":          { "zh": "步长", "en": "Step" },
	"tag_rule.digits":        { "zh": "位数", "en": "Digits" },
	"tag_rule.source":        { "zh": "前缀来源", "en": "Prefix Source" },
	"tag_rule.by_category":   { "zh": "按类别", "en": "By Category" },
	"tag_rule.by_symbol":     { "zh": "按图元", "en": "By Symbol" },
	"tag_rule.fixed":         { "zh": "固定前缀", "en": "Fixed Prefix" },
	"tag_rule.fixed_prefix":  { "zh": "固定前缀值", "en": "Fixed Prefix Value" },
	"tag_rule.prefix_table":  { "zh": "类别前缀表", "en": "Category Prefix Table" },
	"tag_rule.preview":       { "zh": "预览", "en": "Preview" },
	"tag_rule.renumber_now":  { "zh": "同时全量重编号现有图元（%d 个）", "en": "Also renumber all existing instances (%d)" },
	"tag_rule.renumber_none": { "zh": "同时全量重编号现有图元", "en": "Also renumber all existing instances" },
	"tag_rule.err_no_seq":    { "zh": "模板必须包含 {seq}", "en": "The template must contain {seq}" },
	"tag_rule.err_bad_start": { "zh": "起始值不能为负", "en": "Start must not be negative" },
	"tag_rule.err_bad_step":  { "zh": "步长至少为 1", "en": "Step must be at least 1" },
	"tag_rule.err_bad_digits": { "zh": "位数须在 0 – 8 之间", "en": "Digits must be between 0 and 8" },
	"tag_rule.err_bad_fixed": { "zh": "固定前缀不能为空", "en": "Fixed prefix must not be empty" },
	"tag_rule.applied":       { "zh": "编号规则已更新", "en": "Numbering rules updated" },
	"tag_rule.renumbered":    { "zh": "已重排 %d 个位号", "en": "Renumbered %d tags" },
	"tag_rule.renumber_confirm": { "zh": "将重排 %d 个位号。位号会进入 DCS 点表与现场标牌，确定继续？",
								  "en": "This will renumber %d tags. Tags feed the DCS point list and physical nameplates — continue?" },
	"tag_rule.confirm_title": { "zh": "确认重排位号", "en": "Confirm Renumbering" },

	# ---- tag uniqueness (M9) ----
	"tag.err_duplicate":      { "zh": "位号已被占用", "en": "Tag already in use" },
	"tag.err_no_uid":         { "zh": "缺少实例标识", "en": "Missing instance id" },
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
