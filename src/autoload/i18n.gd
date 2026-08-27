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
	"status.custom_pending":{ "zh": "自定义图元编辑器：待接入",     "en": "Custom symbol editor: TODO" },
	"status.view_reset":    { "zh": "视图已复位",        "en": "View reset" },
	"status.cleared":       { "zh": "画布已清空",        "en": "Canvas cleared" },
	"status.feature_todo":  { "zh": "功能待接入：%s",    "en": "Feature pending: %s" },

	"doc.info": { "zh": "G-PID 工程\n文档元信息（标题 / 图号 / 版本）待接入。",
				  "en": "G-PID Project\nDocument metadata (title / drawing no. / revision) pending." },

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
	"menu.tool_symbol_editor": { "zh": "符号编辑器",   "en": "Symbol Editor" },
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

	# ---- symbol editor wizard / 符号编辑器向导 ----
	"symed.title":            { "zh": "符号编辑器", "en": "Symbol Editor" },
	"symed.preview":          { "zh": "实时预览", "en": "Live Preview" },
	"symed.preview_hint":     { "zh": "左：1:1 标称尺寸 · 右：2× 放大 · 下方：同族对照（应等大）",
								 "en": "Left: 1:1 nominal size · right: 2x · bottom: same-family strip (should match sizes)" },
	"symed.cat_note":         { "zh": "同一类目的图元共享一套标称包络尺寸，因此同族图元在画布上恒为等大。",
								 "en": "A category shares one nominal envelope, so every symbol of the family renders equal-sized." },
	"symed.step1":            { "zh": "1. 选类目", "en": "1. Pick Category" },
	"symed.step2":            { "zh": "2. 画字形", "en": "2. Draw Glyph" },
	"symed.step3":            { "zh": "3. 填属性", "en": "3. Fill Attributes" },
	"symed.step4":            { "zh": "4. 填标准", "en": "4. Standard Ref" },
	"symed.step5":            { "zh": "5. 导出", "en": "5. Export" },
	"symed.cat_label":        { "zh": "类目", "en": "Category" },
	"symed.id_label":         { "zh": "图元 ID", "en": "Symbol ID" },
	"symed.name_label":       { "zh": "显示名", "en": "Display Name" },
	"symed.env_label":        { "zh": "标称包络", "en": "Nominal Envelope" },
	"symed.tool_label":       { "zh": "工具", "en": "Tool" },
	"symed.tool_polyline":    { "zh": "折线", "en": "Polyline" },
	"symed.tool_circle":      { "zh": "圆", "en": "Circle" },
	"symed.tool_rect":        { "zh": "矩形", "en": "Rectangle" },
	"symed.tool_port":        { "zh": "端口", "en": "Port" },
	"symed.btn_finish":       { "zh": "结束折线", "en": "Finish Path" },
	"symed.btn_undo":         { "zh": "撤销", "en": "Undo" },
	"symed.btn_clear":        { "zh": "清空", "en": "Clear" },
	"symed.draw_hint":        { "zh": "左键落点，右键结束/撤销，双击闭合；端口工具点参考框边线吸附法线。",
								 "en": "Left click to add points, right click to finish/undo, double click to close; the Port tool snaps to the guide edge." },
	"symed.attr_key":         { "zh": "属性键", "en": "Attribute key" },
	"symed.attr_default":     { "zh": "默认值", "en": "Default value" },
	"symed.btn_add":          { "zh": "添加", "en": "Add" },
	"symed.btn_delete":       { "zh": "删除选中", "en": "Delete Selected" },
	"symed.attr_hint":        { "zh": "属性会出现在右侧属性面板与导出的图元包 schema 中；bool 填 true/1/是。",
								 "en": "Attributes appear in the inspector and the exported pack schema; bool accepts true/1/是." },
	"symed.pack_id_label":    { "zh": "图元包 ID", "en": "Pack ID" },
	"symed.pack_name_label":  { "zh": "图元包名称", "en": "Pack Name" },
	"symed.std_label":        { "zh": "标准出处", "en": "Standard Ref" },
	"symed.version_label":    { "zh": "版本", "en": "Version" },
	"symed.author_label":     { "zh": "作者", "en": "Author" },
	"symed.export_register":  { "zh": "导出后注册到活动图元库（立即可在左侧面板放置）",
								 "en": "Register into the live library on export (placeable from the palette at once)" },
	"symed.prev":             { "zh": "上一步", "en": "Back" },
	"symed.next":             { "zh": "下一步", "en": "Next" },
	"symed.export":           { "zh": "导出图元包", "en": "Export Pack" },
	"symed.close":            { "zh": "关闭", "en": "Close" },
	"symed.summary_shapes":   { "zh": "图元原语数", "en": "Primitives" },
	"symed.summary_ports":    { "zh": "端口数", "en": "Ports" },
	"symed.summary_pack":     { "zh": "图元包", "en": "Pack" },
	"symed.summary_std":      { "zh": "标准", "en": "Standard" },
	"symed.export_saved":     { "zh": "已保存", "en": "Saved" },
	"symed.export_save_fail": { "zh": "保存失败", "en": "Save failed" },
	"symed.export_done":      { "zh": "导出完成，已注册到活动图元库。", "en": "Export done; registered into the live library." },
	"symed.hint_id_required": { "zh": "请先填写图元 ID（第 1 步）。", "en": "Fill the Symbol ID first (step 1)." },
	"symed.hint_name_required": { "zh": "请先填写显示名（第 1 步）。", "en": "Fill the Display Name first (step 1)." },
	"symed.hint_attr_key":    { "zh": "属性键不能为空。", "en": "Attribute key cannot be empty." },
	"symed.hint_attr_dup":    { "zh": "该属性键已存在。", "en": "That attribute key already exists." },
	"symed.pack_added":       { "zh": "已加入图元库：%s", "en": "Added to library: %s" },
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
