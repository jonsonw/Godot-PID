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
	# ---- 图元显示名（pack_dexpi）----
	# 键内嵌「分配后」的 id，由生成器落盘 assets/symbol_packs/dexpi/display_names.json
	# 生成；重跑生成器若改变序号分配，须同步重建本块。
	# ---- Symbol display names (pack_dexpi) ----
	# Keys embed the ALLOCATED id; regenerate from assets/symbol_packs/dexpi/display_names.json
	# whenever the generator's numbering changes.
	"dexpi.dgeneral001":	{ "zh": "关键介质进口箭头", "en": "Arrow — Inlet of Essential Substances" },
	"dexpi.dgeneral002":	{ "zh": "关键介质出口箭头", "en": "Arrow — Outlet of Essential Substances" },
	"dexpi.dgeneral003":	{ "zh": "盲板", "en": "Blind Cover" },
	"dexpi.dgeneral004":	{ "zh": "控制执行机构", "en": "Controlled Actuator" },
	"dexpi.dgeneral005":	{ "zh": "流向（主管段）", "en": "Direction of Flow (Primary Segment)" },
	"dexpi.dgeneral006":	{ "zh": "流向（支管段）", "en": "Direction of Flow (Secondary Segment)" },
	"dexpi.dgeneral007":	{ "zh": "人孔", "en": "Manhole" },
	"dexpi.dgeneral008":	{ "zh": "接管嘴", "en": "Nozzle" },
	"dexpi.dgeneral009":	{ "zh": "保温管道", "en": "Insulated Piping" },
	"dexpi.dgeneral010":	{ "zh": "异径管", "en": "Reducer (General)" },
	"dexpi.dgeneral011":	{ "zh": "管道坡度", "en": "Slope" },
	"dexpi.dgeneral012":	{ "zh": "T 型三通", "en": "T-Type Connection" },
	"dexpi.dheat001":	{ "zh": "浮头式管束换热器", "en": "Floating-Head Tube-Bundle Heat Exchanger" },
	"dexpi.dheat002":	{ "zh": "板式换热器", "en": "Plate-Type Heat Exchanger" },
	"dexpi.dinstrument001":	{ "zh": "仪表气泡（中控室）", "en": "Instrumentation Bubble (Central)" },
	"dexpi.dinstrument002":	{ "zh": "仪表气泡（现场）", "en": "Instrumentation Bubble (Field)" },
	"dexpi.dpump001":	{ "zh": "离心泵", "en": "Centrifugal Pump" },
	"dexpi.dpump002":	{ "zh": "往复泵", "en": "Reciprocating Pump" },
	"dexpi.dtank001":	{ "zh": "碟形封头容器", "en": "Vessel with Dished Heads" },
	"dexpi.dvalve001":	{ "zh": "角式弹簧安全阀", "en": "Angle Spring-Loaded Safety Valve" },
	"dexpi.dvalve002":	{ "zh": "球阀", "en": "Ball Valve" },
	"dexpi.dvalve003":	{ "zh": "蝶阀", "en": "Butterfly Valve" },
	"dexpi.dvalve004":	{ "zh": "截止阀", "en": "Globe Valve" },
	"dexpi.dvalve005":	{ "zh": "旋启式止回阀", "en": "Swing Check Valve" },
	# ---- annotation templates (GPSymbolAnnotationTemplates, Rev.3 stage 2) ----
	# ---- 注释类模板（GPSymbolAnnotationTemplates，Rev.3 阶段 2）----
	"sym.text_multiline":	{ "zh": "多行文本", "en": "Multi-line Text" },
	"sym.table_device_param":	{ "zh": "设备参数表", "en": "Equipment Data Table" },
	"canvas.ctx_table_ins_row":	{ "zh": "插入行", "en": "Insert Row" },
	"canvas.ctx_table_del_row":	{ "zh": "删除行", "en": "Delete Row" },
	"canvas.ctx_table_ins_col":	{ "zh": "插入列", "en": "Insert Column" },
	"canvas.ctx_table_del_col":	{ "zh": "删除列", "en": "Delete Column" },
	"table.err_structure":	{ "zh": "表格结构无法变更（已到最少行列或数量上限）",
		"en": "Table structure refused (at the min or max row/column limit)" },
	# ---- app chrome ----
	"symbol_lib.title":        { "zh": "图元库",           "en": "Symbol Library" },
	"symbol_lib.search":       { "zh": "搜索图元名称 / 类目…", "en": "Search symbols / categories…" },
	# Header of the tool block that holds the drawing tools. It used to live under the
	# removed Ribbon ("ribbon.grp_draw"); the id now follows the symbol_lib.* domain it
	# actually belongs to — gpTr() falls back to RAW KEY TEXT when a key is missing, so a
	# stale id silently shows "ribbon.grp_draw" on screen instead of failing.
	# 承载绘图工具的「绘制」工具块标题。它原先挂在已移除的 Ribbon 下（"ribbon.grp_draw"）；
	# 现改回其真正所属的 symbol_lib.* 命名域 —— 因为 gpTr() 在键缺失时会**回退为裸键名**，
	# 一个过时的 id 不会报错，只会把 "ribbon.grp_draw" 直接显示到界面上。
	"symbol_lib.grp_draw":    { "zh": "绘制",             "en": "Draw" },
	"symbol_lib.tool_select":  { "zh": "选择",             "en": "Select" },
	"symbol_lib.tool_connect": { "zh": "连线",             "en": "Connect" },
	"symbol_lib.tool_pipe":    { "zh": "管道",             "en": "Pipe" },
	"symbol_lib.tool_signal":  { "zh": "信号线",           "en": "Signal" },
	"symbol_lib.show_all":     { "zh": "全部显示",         "en": "Show All" },
	"symbol_lib.gear_tip":     { "zh": "勾选要显示的图元", "en": "Choose visible symbols" },
	# 左栏的两个顶层分组（P3）。它们按「与别的图元的关系」划分，而非按类目：阀门与管口同属
	# 「通用」类目，但一个是宿主、另一个是部件。键同时充当折叠状态的键（与「绘制」块同一约定）。
	# The left dock's two TOP-LEVEL groups (P3). They split by RELATION to another symbol, not by
	# category: a valve and a nozzle both live in "general", yet one hosts and the other is hosted.
	# The key doubles as the collapse-state key, exactly like the Draw block above.
	"symbol_lib.grp_primary":  { "zh": "主图元",           "en": "Primary Symbols" },
	"symbol_lib.grp_attach":   { "zh": "次级图元",         "en": "Attachments" },
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

	"canvas.ctx_align_left":    { "zh": "左对齐",     "en": "Align left" },
	"canvas.ctx_align_hcenter": { "zh": "水平居中",   "en": "Align horizontal centres" },
	"canvas.ctx_align_right":   { "zh": "右对齐",     "en": "Align right" },
	"canvas.ctx_align_top":     { "zh": "上对齐",     "en": "Align top" },
	"canvas.ctx_align_vcenter": { "zh": "垂直居中",   "en": "Align vertical centres" },
	"canvas.ctx_align_bottom":  { "zh": "下对齐",     "en": "Align bottom" },
	"canvas.ctx_dist_h":        { "zh": "水平等间距", "en": "Distribute horizontally" },
	"canvas.ctx_dist_v":        { "zh": "垂直等间距", "en": "Distribute vertically" },
	"drc.panel_title":             { "zh": "图面体检", "en": "Drawing check" },
	"drc.run":                     { "zh": "一键体检", "en": "Check drawing" },
	"drc.export_txt":              { "zh": "导出文本", "en": "Export text" },
	"drc.export_csv":              { "zh": "导出 CSV", "en": "Export CSV" },
	"drc.never_run":               { "zh": "尚未体检。点「一键体检」检查七项。", "en": "Not checked yet. Press \"Check drawing\" to run all seven rules." },
	"drc.no_canvas":               { "zh": "没有打开的图纸", "en": "No drawing is open" },
	"drc.all_clear":               { "zh": "七项全部通过", "en": "All seven rules passed" },
	"drc.summary":                 { "zh": "%d 错误 · %d 警告 · %d 提示", "en": "%d errors · %d warnings · %d infos" },
	"drc.report_title":            { "zh": "G-PID 图面体检报告", "en": "G-PID drawing check report" },
	"menu.tool_drc":               { "zh": "图面体检（DRC）", "en": "Drawing check (DRC)" },
	"status.drc_done":             { "zh": "体检完成：%d 错误 · %d 警告 · %d 提示", "en": "Check done: %d errors · %d warnings · %d infos" },
	"drc.end_note_missing":        { "zh": "开口端缺少注记：%s（%s 端）", "en": "Open end has no note: %s (%s end)" },
	"drc.end_note_missing_object": { "zh": "开口端注记对象已被删除：%s（%s 端）", "en": "The note object is gone: %s (%s end)" },
	"drc.end_note_empty_text":     { "zh": "开口端注记是空的：%s（%s 端）", "en": "The open-end note is empty: %s (%s end)" },
	"drc.port_unconnected":        { "zh": "必需端口未接线：%s / %s", "en": "Required port is not wired: %s / %s" },
	"drc.tag_missing":             { "zh": "缺少位号：%s", "en": "Missing tag: %s" },
	"drc.tag_duplicate":           { "zh": "位号重复：%s（%s 与 %s）", "en": "Duplicate tag: %s (%s and %s)" },
	"drc.edge_tag_missing":        { "zh": "管线缺少线号：%s", "en": "Line has no number: %s" },
	"drc.required_prop_missing":   { "zh": "必填属性为空：%s / %s", "en": "Required property is empty: %s / %s" },
	"drc.symbols_overlap":         { "zh": "图元重叠：%s 与 %s", "en": "Symbols overlap: %s and %s" },
	"drc.symbol_off_sheet":        { "zh": "图元越出图框：%s", "en": "Symbol is outside the frame: %s" },
	"drc.edge_crosses_symbol":     { "zh": "连线穿越图元：%s 穿过 %s", "en": "Line crosses a symbol: %s through %s" },
	"drc.signal_type_missing":     { "zh": "信号线缺少信号类型：%s", "en": "Signal line has no signal type: %s" },
	"drc.edge_attrs_missing":      { "zh": "连线属性缺失：%s（缺 %s）", "en": "Line attributes missing: %s (missing %s)" },
	"drc.sheet_sparse":            { "zh": "图面偏空：已用面积约 %d%%", "en": "Sheet looks sparse: about %d%% used" },
	"drc.sheet_crowded":           { "zh": "图面偏挤：已用面积约 %d%%", "en": "Sheet looks crowded: about %d%% used" },
	"canvas.ctx_cancel_line":           { "zh": "取消这条线", "en": "Drop this line" },
	"open_end.dwell_attach":            { "zh": "接到注记：%s", "en": "Connect to note: %s" },
	"open_end.menu":                    { "zh": "开口端注记…", "en": "Open-end note…" },
	"open_end.title":                   { "zh": "开口端注记", "en": "Open-end note" },
	"open_end.pick":                    { "zh": "标准注记", "en": "Standard notes" },
	"open_end.placeholder":             { "zh": "或自行输入（如 TO ATM、CONT. ON DWG W-102）", "en": "Or type your own (e.g. TO ATM, CONT. ON DWG W-102)" },
	"open_end.hint":                    { "zh": "说明这个开口端是什么；不写注记的开口端会在体检里报错。清空文字＝取消注记。", "en": "Say what this open end is; an unnoted open end fails the health check. Clearing the text detaches the note." },
	"open_end.apply":                   { "zh": "确定", "en": "Apply" },
	"open_end.cancel":                  { "zh": "取消", "en": "Cancel" },
	"bag.title":                    { "zh": "图元背包", "en": "Symbols" },
	"bag.search":                   { "zh": "搜索图元（名称 / 类目 / id）", "en": "Search symbols (name / category / id)" },
	"bag.empty":                    { "zh": "没有匹配的图元", "en": "No matching symbols" },
	"bag.hint":                     { "zh": "单击放到视图中心，或直接拖到图纸上；右键收藏", "en": "Click to place at the view centre, drag onto the sheet, or right-click to favourite" },
	"status.bag_placed":            { "zh": "已放置：%s", "en": "Placed: %s" },
	"status.bag_empty":             { "zh": "图元库为空", "en": "The symbol library is empty" },
	"make_symbol.undo":             { "zh": "撤销",     "en": "Undo" },
	"make_symbol.redo":             { "zh": "重做",     "en": "Redo" },
	"menu.insert_symbol":           { "zh": "新建图元…", "en": "New Symbol…" },
	"status.symbol_editor_blank":   { "zh": "新建图元：空白编辑器", "en": "New symbol: blank editor" },
	"make_symbol.port_type":        { "zh": "用途",     "en": "Purpose" },
	"make_symbol.port_type_nozzle": { "zh": "工艺管口", "en": "Process nozzle" },
	"make_symbol.port_type_actuator": { "zh": "执行机构", "en": "Actuator" },
	"make_symbol.port_type_signal": { "zh": "信号",     "en": "Signal" },
	"make_symbol.port_type_terminal": { "zh": "通用端点", "en": "Generic terminal" },
	"about.product":          { "zh": "P&ID 编辑器",   "en": "P&ID Editor" },
	"about.license":          { "zh": "MIT 许可",      "en": "MIT License" },
	"about.godot_prefix":     { "zh": "基于 Godot",    "en": "Built on Godot" },
	"status.print_handoff":   { "zh": "已生成 PDF 并交给系统：%s", "en": "PDF generated and handed to the system: %s" },
	"status.grid_on":         { "zh": "网格：开",       "en": "Grid: on" },
	"status.grid_off":        { "zh": "网格：关",       "en": "Grid: off" },
	"status.bg_changed":      { "zh": "画布底色：%s",   "en": "Canvas background: %s" },
	"status.copied":          { "zh": "已复制 %d 项",   "en": "Copied %d item(s)" },
	"status.pasted":          { "zh": "已粘贴 %d 个图元", "en": "Pasted %d symbol(s)" },
	"status.clipboard_empty": { "zh": "剪贴板为空",     "en": "Clipboard is empty" },
	"canvas.ctx_rotate_cw":   { "zh": "顺时针旋转 90°", "en": "Rotate 90° clockwise" },
	"canvas.ctx_mirror":      { "zh": "水平镜像",   "en": "Mirror horizontally" },
	"inspector.shape":        { "zh": "注释图形",   "en": "Annotation Shape" },
	"inspector.shape_kind":   { "zh": "种类",       "en": "Kind" },
	"inspector.shape_points": { "zh": "顶点数",     "en": "Vertices" },
	"inspector.shape_name":   { "zh": "名称",       "en": "Name" },
	"inspector.shape_layer":  { "zh": "图层",       "en": "Layer" },
	"inspector.shape_multi":  { "zh": "已选中 %d 个图形（单选才能编辑）", "en": "%d shapes selected (select one to edit)" },
	"shape.kind_line":        { "zh": "直线",       "en": "Line" },
	"shape.kind_circle":      { "zh": "圆",         "en": "Circle" },
	"shape.kind_rect":        { "zh": "矩形",       "en": "Rectangle" },
	"shape.kind_polyline":    { "zh": "折线",       "en": "Polyline" },
	"shape.kind_arc":         { "zh": "弧线",       "en": "Arc" },
	"shape.layer_annotation": { "zh": "注释",       "en": "Annotation" },
	"shape.layer_border":     { "zh": "图框",       "en": "Border" },
	"shape.layer_dimension":  { "zh": "标注",       "en": "Dimension" },
	"shape.layer_hatch":      { "zh": "填充",       "en": "Hatch" },

	"outline.title":       { "zh": "层级",     "en": "Outline" },
	"outline.col_node":    { "zh": "图元",     "en": "Symbol" },
	"outline.col_type":    { "zh": "类型",     "en": "Type" },
	"outline.hint":        { "zh": "缩进表示「装在谁身上」。右键可改挂载或脱离宿主。",
							 "en": "Indentation means \"mounted on\". Right-click to re-mount or detach." },
	"outline.ctx_detach":  { "zh": "脱离宿主", "en": "Detach from host" },
	"outline.ctx_mount_to":{ "zh": "挂到：%s", "en": "Mount onto: %s" },
	"outline.ctx_none":    { "zh": "没有可接纳它的宿主", "en": "No host can accept this symbol" },

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
	"inspector.default":       { "zh": "默认",     "en": "default" },
	"inspector.required":      { "zh": "必填",     "en": "required" },
	"inspector.no_props":      { "zh": "（该图元暂无可配置属性）", "en": "(no configurable properties)" },
	"inspector.batch":         { "zh": "批量编辑：已选中 %d 个同类图元，修改将同时生效",
								 "en": "Batch edit: %d instances selected — edits apply to all" },
	"inspector.clean_orphans":  { "zh": "清理这 %d 项孤儿值", "en": "Discard these %d orphaned values" },
	"inspector.group_general": { "zh": "通用",     "en": "General" },
	# ---- custom-entry CRUD + property search (Rev.3 stage 1.5, R2) ----
	# ---- 自定义条目增删改 + 属性检索（Rev.3 阶段 1.5，R2） ----
	"inspector.adhoc":          { "zh": "自定义属性", "en": "Custom Properties" },
	"inspector.adhoc_add":      { "zh": "新增条目", "en": "Add Entry" },
	"inspector.adhoc_add_btn":  { "zh": "添加", "en": "Add" },
	"inspector.adhoc_key_ph":   { "zh": "键名", "en": "key name" },
	"inspector.adhoc_val_ph":   { "zh": "初始值（可留空）", "en": "initial value (optional)" },
	"inspector.adhoc_rename_hint": { "zh": "输入新键名后回车即改名（一个撤销步）",
		"en": "Type a new key and press Enter to rename (one undo step)" },
	"inspector.adhoc_delete_hint": { "zh": "删除此条目", "en": "Delete this entry" },
	"inspector.adhoc_declared": { "zh": "该键由图元库声明，请到对应分组修改",
		"en": "This key is declared by the symbol library; edit it in its own group" },
	"inspector.adhoc_exists":   { "zh": "该键已存在", "en": "This key already exists" },
	"inspector.search":         { "zh": "检索", "en": "Search" },
	"inspector.search_ph":      { "zh": "输入后回车过滤属性…", "en": "Type + Enter to filter…" },
	"perm.err_props":           { "zh": "当前无属性编辑权限", "en": "Property editing is not permitted" },
	"adhoc.err_exists":         { "zh": "键已存在", "en": "Key already exists" },
	"adhoc.err_missing":        { "zh": "条目不存在", "en": "Entry not found" },

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

	"edge.port_type_mismatch":   { "zh": "端口类型不符：管道只能连管口，信号线只能连信号 / 执行机构端。", "en": "Port type mismatch: pipes connect nozzles only; signal lines connect signal / actuator ends only." },
	"edge.pipe_needs_one_bound": { "zh": "管道至少需连接一端。", "en": "A pipe needs at least one bound end." },
	"edge.edge_self_loop":       { "zh": "不能连到同一端口。", "en": "Cannot connect to the same port." },
	"edge.port_missing":         { "zh": "端点无法解析（图元或端口缺失）。", "en": "Endpoint could not be resolved (symbol or port missing)." },
	"edge.edge_duplicate":       { "zh": "该连线已存在。", "en": "This connection already exists." },

	"status.mode_pipe":   { "zh": "管道模式", "en": "Pipe mode" },
	"status.mode_signal": { "zh": "信号线模式", "en": "Signal mode" },

	"status.ready":         { "zh": "就绪",             "en": "Ready" },
	"status.none":          { "zh": "—",               "en": "—" },
	"status.selected":      { "zh": "选中：%s",         "en": "Selected: %s" },
	"status.selected_multi":{ "zh": "选中：%d 个图元",   "en": "Selected: %d symbols" },
	"status.selected_edges":{ "zh": "选中：连线 %d 条",  "en": "Selected: %d lines" },
	"status.selected_shapes":{ "zh": "选中：图形 %d 个", "en": "Selected: %d shapes" },
	"status.coord":         { "zh": "X: %d  Y: %d",     "en": "X: %d  Y: %d" },
	"status.zoom":          { "zh": "缩放：%d%%",        "en": "Zoom: %d%%" },
	"status.symbol_picked": { "zh": "已选图元：%s（点画布放置）", "en": "Symbol selected: %s (click canvas to place)" },
	"status.mode_select":   { "zh": "模式：选择",        "en": "Mode: Select" },
	"status.mode_connect":  { "zh": "模式：连线（依次点两个图元）", "en": "Mode: Connect (click two symbols)" },
	"status.mode_line":     { "zh": "绘图：直线（在画布上拖拽）", "en": "Draw: Line (drag on canvas)" },
	"status.mode_circle":   { "zh": "绘图：圆（在画布上拖拽）", "en": "Draw: Circle (drag on canvas)" },
	"status.mode_rect":     { "zh": "绘图：矩形（在画布上拖拽）", "en": "Draw: Rectangle (drag on canvas)" },
	"status.mode_polyline": { "zh": "绘图：折线（逐点单击，双击结束）", "en": "Draw: Polyline (click points, double-click to finish)" },
	"status.mode_arc":      { "zh": "绘图：圆弧（拖出起点与终点）", "en": "Draw: Arc (drag from start to end)" },

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
	"status.autosaved":        { "zh": "已自动保存：%s",   "en": "Auto-saved: %s" },
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
	"status.parse_fail":       { "zh": "解析失败：%s",    "en": "Parse failed: %s" },
	"status.exported":         { "zh": "已导出：%s（节点 %d / 连线 %d）",
								 "en": "Exported: %s (%d nodes / %d edges)" },
	"status.export_fail":      { "zh": "导出失败：%s",    "en": "Export failed: %s" },
	"status.list_exported":    { "zh": "已导出 %d 类清单到 %s", "en": "Exported %d list(s) to %s" },
	"status.export_empty":     { "zh": "没有可导出的内容", "en": "Nothing to export" },
	"status.imported":         { "zh": "已导入：%s（错误 %d / 警告 %d）",
								 "en": "Imported: %s (%d error(s) / %d warning(s))" },
	"status.import_fail":      { "zh": "导入失败：%s",    "en": "Import failed: %s" },
	"status.import_unknown":   { "zh": "不是 G-PID 文件：%s", "en": "Not a G-PID file: %s" },
	"status.import_future":    { "zh": "文件由更新版本创建：%s", "en": "File was created by a newer version: %s" },

	"doc.info": { "zh": "G-PID 工程\n文档元信息（标题 / 图号 / 版本）待接入。",
				  "en": "G-PID Project\nDocument metadata (title / drawing no. / revision) pending." },
	"doc.pid_filter": { "zh": "G-PID 工程 (*.pid.json)", "en": "G-PID Project (*.pid.json)" },
	"doc.dexpi_filter": { "zh": "DEXPI XML (*.pid.xml)", "en": "DEXPI XML (*.pid.xml)" },
	"doc.dxf_filter":    { "zh": "DXF 图形交换 (*.dxf)", "en": "DXF Drawing Exchange (*.dxf)" },
	"doc.pdf_filter":    { "zh": "PDF 文档 (*.pdf)", "en": "PDF Document (*.pdf)" },

	"settings.title":      { "zh": "设置",          "en": "Settings" },
	"settings.font_size":  { "zh": "界面字体大小",   "en": "UI Font Size" },
	"settings.ui_font":    { "zh": "界面字体",       "en": "UI Font" },
	"settings.symbol_font_size": { "zh": "图元字体大小", "en": "Symbol Font Size" },
	"settings.symbol_font":{ "zh": "图元字体",       "en": "Symbol Font" },
	"settings.language":   { "zh": "语言",          "en": "Language" },
	"settings.auto_scale": { "zh": "界面随窗口自适应缩放", "en": "Auto-fit UI to window" },
	"settings.pipe_tag_rotate":   { "zh": "竖管位号旋转", "en": "Rotate vertical line numbers" },
	"settings.pipe_tag_font_size": { "zh": "位号字号（0=图元字号）", "en": "Line number size (0=symbol size)" },
	"settings.motion_enabled": { "zh": "界面动效（放置回弹 / 更新高亮）", "en": "UI motion (drop pop / update flash)" },
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
	"menu.import_dexpi":       { "zh": "导入 DEXPI XML…", "en": "Import DEXPI XML…" },
	"menu.file_quit":          { "zh": "退出",         "en": "Quit" },
	"menu.export":             { "zh": "导出",         "en": "Export" },
	"menu.export_project":     { "zh": "工程…",        "en": "Project…" },
	"menu.export_library":     { "zh": "图元库…",      "en": "Symbol Library…" },
	"menu.export_config":      { "zh": "项目配置…",    "en": "Project Config…" },
	"menu.export_dexpi":       { "zh": "导出 DEXPI XML…", "en": "Export DEXPI XML…" },
	"menu.export_pdf":         { "zh": "导出 PDF…",    "en": "Export PDF…" },
	"menu.export_dxf":         { "zh": "导出 DXF…",    "en": "Export DXF…" },
	"menu.export_lists_xlsx":  { "zh": "分类数据（Excel）…", "en": "Classified Data (Excel)…" },
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
	"general":    { "zh": "通用",     "en": "General" },
	"annotation": { "zh": "注释",     "en": "Annotation" },

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
	"canvas.ctx_add_anchor":     { "zh": "增加锚点", "en": "Add Anchor" },
	"canvas.ctx_delete_bump":    { "zh": "删除锚点", "en": "Delete Anchor" },
	# 图元放置到连线上时的二选一，以及「端口不足无法拆分」的提示。
	# The two-way choice when a symbol is dropped onto a line, plus the "too few ports" note.
	"canvas.ctx_drop_reroute":      { "zh": "让连线绕过图元", "en": "Route line around the symbol" },
	"canvas.ctx_drop_split":        { "zh": "把连线拆成两根接入图元", "en": "Split line through the symbol" },
	"canvas.ctx_drop_title":        { "zh": "无法拆分连线", "en": "Cannot split line" },
	"canvas.ctx_drop_needs_ports":  { "zh": "该图元的端点少于两个，无法拆分连线；请修改图元并增加至少两个端点。", "en": "This symbol has fewer than two ports; cannot split the line. Edit the symbol and add at least two ports." },

	# ---- P2 主图元 / 次级图元（挂载） / primary & secondary symbols (mounting) ----
	# 右键「添加附件 ▶」子菜单的标题与置灰原因。
	# The "Add Attachment" submenu title and the reason a type is greyed out.
	"canvas.ctx_attach":            { "zh": "添加附件", "en": "Add Attachment" },
	"canvas.ctx_attach_no_room":    { "zh": "该宿主上没有空闲的兼容锚点", "en": "No free compatible anchor on this host" },
	"canvas.ctx_detach":            { "zh": "卸载附件", "en": "Detach Attachment" },
	# 附件拒绝原因（GPEditService.gpLastRefusal → 状态栏）。机器可读键不带前缀，前缀 "attach." 由
	# GPCanvasEditFacade.gpReportRefusal() 加上，与既有的 "edge." 命名空间并列。
	# Attach refusal reasons (gpLastRefusal -> status bar). The machine-readable key carries no
	# prefix; "attach." is added by the facade, mirroring the existing "edge." namespace.
	"attach.no_host":               { "zh": "宿主已不存在，无法挂载附件。", "en": "The host no longer exists; cannot attach." },
	"attach.no_anchor":             { "zh": "此处没有可挂载的兼容锚点，未放置。", "en": "No free compatible anchor here; nothing was placed." },
	# 从库中拖动次级图元（模式一）时的状态栏提示。主图元没有挂载类型，因而**不可能**找到锚点，
	# 故在拖动的起点就拒绝，而不是让用户拖到一半才失败。
	# Status-bar text for dragging an attachment out of the library (mode 1). A primary symbol has
	# no mount kind, so it could NEVER find an anchor — the gesture is refused at its source rather
	# than being allowed to fail halfway.
	"status.attach_armed":          { "zh": "拖到宿主图元上放置「%s」。Esc 取消。", "en": "Drop onto a host to place \u201c%s\u201d. Esc to cancel." },
	"status.attach_not_mountable":  { "zh": "「%s」是主图元，不能挂到别的图元上。", "en": "\u201c%s\u201d is a primary symbol \u2014 it cannot be mounted onto another." },

	# ---- Main-canvas annotation draw tools / 主画布注释绘图工具 ----
	"canvas.tool_polyline":   { "zh": "折线", "en": "Polyline" },
	"canvas.tool_circle":     { "zh": "圆", "en": "Circle" },
	"canvas.tool_rect":       { "zh": "矩形", "en": "Rectangle" },
	"canvas.tool_line":       { "zh": "直线", "en": "Line" },
	"canvas.tool_arc":        { "zh": "圆弧", "en": "Arc" },

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

	"canvas.ctx_delete_edge":    { "zh": "删除连线", "en": "Delete Connection" },
	"canvas.ctx_set_process":    { "zh": "改为主工艺管线", "en": "Set as Process Line" },
	"canvas.ctx_set_utility":    { "zh": "改为公用工程管线", "en": "Set as Utility Line" },
	"canvas.ctx_set_signal":     { "zh": "改为信号线", "en": "Set as Signal Line" },
	"canvas.ctx_resnap_ends":    { "zh": "重新吸附端点", "en": "Re-snap Ends" },
	"canvas.ctx_clear_vertices": { "zh": "清除拐点", "en": "Clear Vertices" },
	"canvas.ctx_renumber":       { "zh": "重新编号", "en": "Renumber" },
	"canvas.ctx_auto_connect":   { "zh": "自动连线", "en": "Auto-Connect" },

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

	# ---- classified workbook import (P6) ----
	"menu.import_lists_xlsx":  { "zh": "导入分类清单（Excel）…", "en": "Import Classified Lists (Excel)…" },
	"xlsx.import_title":       { "zh": "导入分类清单", "en": "Import Classified Lists" },
	"xlsx.import_subtitle":    { "zh": "读取改过的 .xlsx，预览后按图纸各一条撤销步应用；不改位号/几何。",
		"en": "Read an edited .xlsx, preview, then apply one undo step per drawing; tags/geometry untouched." },
	"xlsx.import_file":        { "zh": "文件", "en": "File" },
	"xlsx.import_browse":      { "zh": "浏览…", "en": "Browse…" },
	"xlsx.import_read":        { "zh": "读取预览", "en": "Read preview" },
	"xlsx.import_list":        { "zh": "清单", "en": "List" },
	"xlsx.import_auto":        { "zh": "自动识别", "en": "Auto-detect" },
	"xlsx.import_drawings":    { "zh": "图纸", "en": "Drawings" },
	"xlsx.import_apply":       { "zh": "应用", "en": "Apply" },
	"xlsx.import_close":       { "zh": "关闭", "en": "Close" },
	"xlsx.import_initial":     { "zh": "选择文件后读取预览。", "en": "Choose a file, then read the preview." },
	"xlsx.import_no_file":     { "zh": "先选择一个 .xlsx 文件。", "en": "Choose an .xlsx file first." },
	"xlsx.import_no_changes":  { "zh": "没有可应用的变更（或全部是只读/未匹配）。",
		"en": "No applicable changes (all read-only or unmatched)." },
	"xlsx.import_ready":       { "zh": "%d 项变更待应用。", "en": "%d change(s) ready to apply." },
	"xlsx.import_applied":     { "zh": "已应用 %d 项到 %d 张图纸（每图一条撤销）。",
		"en": "Applied %d change(s) to %d drawing(s); one undo step per drawing." },
	"xlsx.import_failed":      { "zh": "应用失败：%s", "en": "Apply failed: %s" },
	"xlsx.import_stale":       { "zh": "跳过 %d 项：预览后原值已变化。",
		"en": "Skipped %d change(s): the live value changed after preview." },
	"xlsx.import_col_drawing": { "zh": "图纸", "en": "Drawing" },
	"xlsx.import_col_list":    { "zh": "清单", "en": "List" },
	"xlsx.import_col_target":  { "zh": "对象", "en": "Target" },
	"xlsx.import_col_field":   { "zh": "字段", "en": "Field" },
	"xlsx.import_col_old":     { "zh": "原值", "en": "Old" },
	"xlsx.import_col_new":     { "zh": "新值", "en": "New" },
	"xlsx.import_col_status":  { "zh": "状态", "en": "Status" },
	"xlsx.import_change":      { "zh": "变更", "en": "Change" },
	"xlsx.import_issue":       { "zh": "问题", "en": "Issue" },
	"xlsx.import_clear":       { "zh": "（清空）", "en": "(clear)" },
	"xlsx.import_name":        { "zh": "名称", "en": "Name" },
	# ---- classified workbook export (P5) ----
	"xlsx.dialog_title":       { "zh": "导出数据清单", "en": "Export Data Lists" },
	"xlsx.dialog_subtitle":    { "zh": "每类清单生成一个独立 .xlsx；可用随包默认模板或你自己的模板。",
		"en": "One .xlsx per list; use the shipped default or your own template." },
	"xlsx.section_drawings":   { "zh": "图纸", "en": "Drawings" },
	"xlsx.section_lists":      { "zh": "清单", "en": "Lists" },
	"xlsx.section_output":     { "zh": "输出", "en": "Output" },
	"xlsx.list.line":          { "zh": "管线一览表", "en": "Line List" },
	"xlsx.list.equipment":     { "zh": "设备一览表", "en": "Equipment List" },
	"xlsx.list.instrument":    { "zh": "仪表索引表", "en": "Instrument Index" },
	"xlsx.list.valve":         { "zh": "阀门一览表", "en": "Valve List" },
	"xlsx.select_all":         { "zh": "全选", "en": "All" },
	"xlsx.select_none":        { "zh": "全不选", "en": "None" },
	"xlsx.include_empty":      { "zh": "空清单也生成文件", "en": "Write empty lists too" },
	"xlsx.template_default":   { "zh": "默认模板", "en": "Default template" },
	"xlsx.template_custom":    { "zh": "自定义模板", "en": "Custom template" },
	"xlsx.template_browse":    { "zh": "选择…", "en": "Browse…" },
	"xlsx.template_clear":     { "zh": "用默认", "en": "Use default" },
	"xlsx.template_bound":     { "zh": "已绑定：%s", "en": "Bound: %s" },
	"xlsx.template_unbound":   { "zh": "未绑定：%s", "en": "Not bound: %s" },
	"xlsx.err_no_key":         { "zh": "缺少关键列：%s。表头可写 {{tag}} / {{line_no}}，或「位号」/「管线号」。",
		"en": "Missing key column: %s. Put {{tag}} / {{line_no}} in the header, or use Tag / Line No." },
	"xlsx.err_sample_row":     { "zh": "列令牌不在表头下一行：表头第 %d 行，令牌第 %d 行。当前模板要求单行表头 + 紧邻的样例行。",
		"en": "Column token is not in the sample row below the header (header row %d, token row %d). The template requires one header row plus the immediately following sample row." },
	"xlsx.output_dir":         { "zh": "输出目录", "en": "Output folder" },
	"xlsx.prefix":             { "zh": "文件名前缀", "en": "File prefix" },
	"xlsx.prefix_hint":        { "zh": "例如 W6", "en": "e.g. W6" },
	"xlsx.rows":               { "zh": "%d 行", "en": "%d rows" },
	"xlsx.summary":            { "zh": "已选 %d/%d 张图纸 · 管线 %d · 设备 %d · 仪表 %d · 阀门 %d",
		"en": "%d/%d drawings · %d lines · %d equipment · %d instruments · %d valves" },
	"xlsx.status_ready":       { "zh": "选择图纸与清单后导出。", "en": "Choose drawings and lists, then export." },
	"xlsx.status_exported":    { "zh": "已写出 %d 个文件。", "en": "Wrote %d file(s)." },
	"xlsx.status_partial":     { "zh": "完成 %d 个，失败 %d 个；详情见下表。", "en": "%d written, %d failed; see the result table." },
	"xlsx.status_failed":      { "zh": "导出失败：%s", "en": "Export failed: %s" },
	"xlsx.no_lists":           { "zh": "至少勾选一类清单。", "en": "Select at least one list." },
	"xlsx.no_sheets":          { "zh": "至少勾选一张图纸。", "en": "Select at least one drawing." },
	"xlsx.result_title":       { "zh": "结果", "en": "Result" },
	"xlsx.col_list":           { "zh": "清单", "en": "List" },
	"xlsx.col_file":           { "zh": "文件", "en": "File" },
	"xlsx.col_rows":           { "zh": "行数", "en": "Rows" },
	"xlsx.col_status":         { "zh": "状态", "en": "Status" },
	"xlsx.col_status_ok":      { "zh": "成功", "en": "OK" },
	"xlsx.col_status_skip":    { "zh": "跳过", "en": "Skipped" },
	"xlsx.col_status_error":   { "zh": "失败", "en": "Failed" },
	"xlsx.export":             { "zh": "导出", "en": "Export" },
	"xlsx.close":              { "zh": "关闭", "en": "Close" },
	"xlsx.browse":             { "zh": "浏览…", "en": "Browse…" },
	"xlsx.err_output_dir":     { "zh": "输出目录无效或不可写。", "en": "Output folder is invalid or not writable." },
	"xlsx.err_no_files":       { "zh": "没有生成任何文件（清单为空或模板失败）。",
		"en": "No file was written (empty lists or template failure)." },
	"status.xlsx_exported":    { "zh": "分类清单已导出", "en": "Classified lists exported" },
	# ---- project menu ----
	"menu.project":               { "zh": "项目", "en": "Project" },
	"menu.project_tag_rules":     { "zh": "位号编号规则…", "en": "Tag Numbering Rules…" },
	"menu.project_export_list":   { "zh": "分类（CSV）…", "en": "Classified (CSV)…" },

	# ---- tag numbering rules dialog ----
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

	"tag.err_duplicate":      { "zh": "位号已被占用", "en": "Tag already in use" },
	"tag.err_no_uid":         { "zh": "缺少实例标识", "en": "Missing instance id" },

	# ---- 图框与标题栏（v0.1 Phase 2 / drawing frame & title block）----
	"menu.frame":             { "zh": "图框与标题栏…", "en": "Drawing Frame & Title Block…" },
	"frame.title":            { "zh": "图框与标题栏", "en": "Drawing Frame & Title Block" },
	"frame.show":             { "zh": "显示图框", "en": "Show drawing frame" },
	"frame.size":             { "zh": "图幅", "en": "Sheet size" },
	"frame.label_mode":       { "zh": "图纸文字语言", "en": "Drawing text language" },
	"frame.mode_zh":          { "zh": "中文", "en": "Chinese" },
	"frame.mode_en":          { "zh": "英文", "en": "English" },
	"frame.mode_both":        { "zh": "中英对照", "en": "Bilingual" },
	"frame.col_zh":           { "zh": "中文", "en": "Chinese" },
	"frame.col_en":           { "zh": "English", "en": "English" },
	"frame.mode_hint":        { "zh": "仅作用于图纸自带文字；位号/管线号始终单语。",
							  "en": "Applies to drawing text only; tag numbers stay monolingual." },
	"frame.applied":          { "zh": "图框已更新", "en": "Drawing frame updated" },
	# 图框边距（Rev.3 阶段 0c 附属：数值入口 + 一键复位）。
	# Frame margins (Rev.3 stage 0c appendix: numeric entry + one-click reset).
	"frame.margin.title":     { "zh": "图框边距（mm）", "en": "Frame margins (mm)" },
	"frame.margin.left":      { "zh": "左", "en": "L" },
	"frame.margin.top":       { "zh": "上", "en": "T" },
	"frame.margin.right":     { "zh": "右", "en": "R" },
	"frame.margin.bottom":    { "zh": "下", "en": "B" },
	"frame.margin.reset":     { "zh": "复位默认", "en": "Reset to default" },
	"frame.margin.hint":      { "zh": "可拖拽调整；负值表示该条边在图幅之外（图框不受纸边限制）。",
							  "en": "Draggable; a negative value puts that edge outside the sheet (the frame is not bound by the paper)." },
	# 图签停靠（Rev.3 阶段 1：锚角 + 吸附；图签位置由图框推导，故它始终跟着图框走）。
	# Title-block docking (Rev.3 stage 1: anchor + snapping; the block's place is DERIVED from the frame,
	# which is what makes it travel with the frame).
	"frame.tb.title":         { "zh": "图签停靠", "en": "Title block docking" },
	"frame.tb.anchor":        { "zh": "锚角", "en": "Anchor" },
	"frame.tb.anchor.br":     { "zh": "右下", "en": "Bottom right" },
	"frame.tb.anchor.bl":     { "zh": "左下", "en": "Bottom left" },
	"frame.tb.anchor.tr":     { "zh": "右上", "en": "Top right" },
	"frame.tb.anchor.tl":     { "zh": "左上", "en": "Top left" },
	"frame.tb.hint":          { "zh": "图签贴住内框的锚角并随图框移动；在画布上拖动它会按内边吸附，越过中线的轴自动换角。",
							  "en": "The block hugs that inner corner and travels with the frame; dragging it on the canvas snaps it to the inner edges, and crossing the centre line flips that axis." },
	# 追踪底图（背景参照层，Phase 5）。
	# Tracing underlay (background reference layer, Phase 5).
	"frame.bg.title":         { "zh": "追踪底图", "en": "Tracing Underlay" },
	"frame.bg.path":          { "zh": "底图路径", "en": "Image path" },
	"frame.bg.browse":        { "zh": "浏览…", "en": "Browse…" },
	"frame.bg.clear":         { "zh": "清除底图", "en": "Clear" },
	"frame.bg.alpha":         { "zh": "底图透明度", "en": "Opacity" },
	"frame.bg.hint":          { "zh": "放入参考图（PNG/JPG/WEBP）后可在其上 1:1 描摹复刻；仅作参考，不参与导出。",
							  "en": "Drop a reference image (PNG/JPG/WEBP) to trace over it 1:1; reference only, not exported." },
	# 标题栏字段双语字段名（固定中英双标，按 GB/T 10609.1 与 ISO 7200）。
	# Bilingual title-block captions (fixed, per GB/T 10609.1 and ISO 7200).
	"frame.fld.company":      { "zh": "单位", "en": "COMPANY" },
	"frame.fld.project":      { "zh": "项目", "en": "PROJECT" },
	"frame.fld.drawing_no":   { "zh": "图号", "en": "DWG NO." },
	"frame.fld.drawing_title": { "zh": "图名", "en": "DRAWING TITLE" },
	"frame.fld.rev":          { "zh": "版次", "en": "REV" },
	"frame.fld.date":         { "zh": "日期", "en": "DATE" },
	"frame.fld.designed":     { "zh": "设计", "en": "DESIGNED" },
	"frame.fld.checked":      { "zh": "校核", "en": "CHECKED" },
	"frame.fld.approved":     { "zh": "审核", "en": "APPROVED" },
	"frame.fld.scale":        { "zh": "比例", "en": "SCALE" },
	"frame.fld.sheet_index":  { "zh": "张次", "en": "SHEET" },
	"frame.fld.sheet_size":   { "zh": "图幅", "en": "SIZE" },
	"frame.fld.drawn":        { "zh": "制图", "en": "DRAWN" },
}


# Translate a key into the current locale. Falls back to the key itself.
# 把键翻译成当前语言。无翻译时回退为键本身。
func gpTr(gpKey: String, gpFallback: String = "") -> String:
	return gpTrIn(gpKey, gpLocale, gpFallback)


# Translate a key into an EXPLICIT locale, ignoring gpLocale.
# WHY: the drawing sheet has its own label mode (中文 / 英文 / 中英对照) that is
# deliberately DECOUPLED from the UI chrome language gpLocale — a Chinese UI may
# legitimately carry an all-English drawing. Routing both through gpTr() would
# couple them, so sheet text asks for the language it wants.
# 把键翻译成**指定**语言，不受 gpLocale 影响。
# 原因：图纸有自己的标签模式（中文/英文/中英对照），刻意与界面语言 gpLocale 解耦 ——
# 中文界面完全可以承载一张纯英文图纸。二者若都走 gpTr() 就会耦合，故图纸文字显式指定语言。
func gpTrIn(gpKey: String, gpLoc: String, gpFallback: String = "") -> String:
	var gpMap: Variant = GP_STRINGS.get(gpKey)
	if gpMap == null:
		return gpFallback if gpFallback != "" else gpKey
	var gpVal: Variant = (gpMap as Dictionary).get(gpLoc)
	if gpVal == null or gpVal == "":
		return gpFallback if gpFallback != "" else gpKey
	return str(gpVal)


# Both languages of a key joined by " / " (e.g. "项目 / PROJECT"), skipping an empty
# side so a partially translated key degrades gracefully instead of trailing a slash.
# 返回一个键的双语串（如"项目 / PROJECT"）；某一侧为空时优雅省略，不留悬空斜杠。
func gpTrBoth(gpKey: String, gpFallback: String = "") -> String:
	var gpZh: String = gpTrIn(gpKey, "zh", "")
	var gpEn: String = gpTrIn(gpKey, "en", "")
	if gpZh == "" and gpEn == "":
		return gpFallback if gpFallback != "" else gpKey
	if gpZh == "":
		return gpEn
	if gpEn == "":
		return gpZh
	return gpZh + " / " + gpEn


# Switch locale and notify listeners.
# 切换语言并通知所有监听者。
func gpSetLocale(gpLocaleCode: String) -> void:
	if gpLocaleCode == gpLocale:
		return
	gpLocale = gpLocaleCode
	gpLocaleChanged.emit(gpLocale)
