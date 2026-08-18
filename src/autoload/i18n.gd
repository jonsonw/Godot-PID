extends Node

# Global localization singleton. Holds the translation table for UI chrome,
# menu items, built-in symbol names and categories. Emits gpLocaleChanged when
# the active language is switched so widgets can refresh their text.
# 全局本地化单例。存放界面文案、菜单项、内置图元名称与类目的翻译表。
# 切换活动语言时 emit gpLocaleChanged，供各控件刷新文本。
# Coding rule: every variable must declare its type explicitly.
# 编码规范：所有变量均显式声明类型。

signal gpLocaleChanged(locale: String)

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

	# ---- built-in categories ----
	"pump":       { "zh": "泵",       "en": "Pump" },
	"tank":       { "zh": "储罐",     "en": "Tank" },
	"valve":      { "zh": "阀门",     "en": "Valve" },
	"instrument": { "zh": "仪表",     "en": "Instrument" },
	"heat":       { "zh": "换热器",   "en": "Heat Exchanger" },
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
