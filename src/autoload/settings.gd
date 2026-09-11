extends Node

# Global settings singleton: persists UI font size, UI font family, symbol font
# size, symbol font family and locale to user://settings.cfg and applies them to
# the whole application.
# 全局设置单例：把界面字号、界面字体、图元字号、图元字体与语言持久化到
# user://settings.cfg，并应用到全应用。
#
# Bundled fonts: the project ships real CJK-capable font files under
# res://assets/fonts/ (ArialUnicode.ttf and HiraginoSansGB.ttc, copied from the
# macOS system fonts). Godot's built-in default font has no CJK glyphs, so Chinese
# previously fell back to a low-quality bitmap font and looked blurry. By loading
# these bundled outline fonts we render Chinese crisply and stay host-independent
# (works on Windows/Linux too, since the files travel with the project).
# 内置字体：工程随附真正支持中文的字体文件于 res://assets/fonts/
#（ArialUnicode.ttf 与 HiraginoSansGB.ttc，拷自 macOS 系统字体）。Godot 内置默认
# 字体不含中日韩字形，中文此前回退到模糊位图字体而发虚；改用这些随工程的矢量字体
# 后中文清晰，且不依赖宿主机字体（Windows/Linux 同样可用）。
#
# Coding rule: every variable must declare its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Path to the persisted settings file.
# 持久化设置文件的路径。
const GP_CONFIG_PATH: String = "user://settings.cfg"

# Font preset registry: key -> { "zh", "en", "res" | "names" }.
# "res"  = a bundled font file under res:// (preferred, host-independent).
# "names"= OS font family names tried in order (cross-platform fallback).
# 字体预设登记表：键 -> { "zh", "en", "res" | "names" }。
# "res"  = res:// 下的内置字体文件（首选，不依赖宿主）；
# "names"= 系统字体族名（按序回退，跨平台）。
const GP_FONT_PRESETS: Dictionary = {
	"arial_cjk": { "zh": "Arial Unicode（内置）", "en": "Arial Unicode (bundled)",
				   "res": "res://assets/fonts/ArialUnicode.ttf" },
	"hiragino":  { "zh": "冬青黑体（内置）", "en": "Hiragino Sans GB (bundled)",
				   "res": "res://assets/fonts/HiraginoSansGB.ttc" },
	"system":    { "zh": "系统默认（含中文）", "en": "System (with CJK)",
				   "names": ["PingFang SC", "Microsoft YaHei", "Noto Sans CJK SC", "Source Han Sans SC", "Helvetica Neue", "Arial"] },
	"pingfang":  { "zh": "苹方 PingFang SC", "en": "PingFang SC",
				   "names": ["PingFang SC", "Microsoft YaHei", "Noto Sans CJK SC"] },
	"helvetica": { "zh": "Helvetica Neue", "en": "Helvetica Neue",
				   "names": ["Helvetica Neue", "PingFang SC", "Microsoft YaHei"] },
	"arial":     { "zh": "Arial", "en": "Arial",
				   "names": ["Arial", "PingFang SC", "Microsoft YaHei"] },
	"menlo":     { "zh": "Menlo 等宽", "en": "Menlo Mono",
				   "names": ["Menlo", "PingFang SC", "Microsoft YaHei"] },
}

# Current UI font size.
# 当前界面字号。
var gpFontSize: int = 16

# Current locale code.
# 当前语言代码。
var gpLocale: String = "en"

# Current UI font preset key.
# 当前界面字体预设键。
var gpFontKey: String = "arial_cjk"

# Current symbol font preset key.
# 当前图元字体预设键。
var gpSymbolFontKey: String = "hiragino"

# Current symbol font size.
# 当前图元字号。
var gpSymbolFontSize: int = 16

# When true, a line number on a vertical run is rotated -90° so it reads bottom-to-top
# (the P&ID convention); when false it stays horizontal and right-aligned to the pipe.
# This is the GLOBAL default — a per-edge "tag_rotate" attribute, if present, overrides it.
# 为 true 时，竖管上的位号旋转 -90° 以便自下而上阅读（P&ID 惯例）；为 false 时保持水平、
# 右对齐到管线。这是「全局默认」——若某条边显式带 "tag_rotate" 属性，则该属性优先。
var gpPipeTagRotate: bool = true

# Font size used to draw pipe line numbers. 0 means inherit the symbol font size
# (gpSymbolFontSize); any positive value overrides it for line numbers only.
# 绘制管线位号的字号。0 表示继承图元字号（gpSymbolFontSize）；正数则仅对位号覆盖。
var gpPipeTagFontSize: int = 0

# When true, both docks snap to their fixed floor widths on every resize so the
# canvas (center) always absorbs the new width and stays maximal. When false, the
# docks keep the widths the user set by dragging the splitters. The UI font size
# is ALWAYS fixed (never scaled by window size) so text stays crisp and
# predictable.
# 为 true 时，两栏在每次缩放都吸附到固定下限宽度，使画布（中间）始终吸收新增宽度、
# 保持最大；为 false 时，两栏保留用户拖拽分隔条设定的宽度。界面字号始终固定
# （不随窗口缩放），文字清晰且可预期。
var gpAutoScale: bool = true

# When true, edge line weights stay constant in SCREEN pixels across zoom
# (rendered width = world width / zoom), the "plotting lineweight" mode used by
# CAD plotters. When false (default), lines thicken as you zoom in, like CAD model
# space. Either way the screen-space floor (GPEdgeStyle.GP_MIN_PX) protects legibility.
# 为 true 时，连线线宽在缩放中保持「屏幕像素恒定」（渲染宽 = 世界宽 / 缩放），即 CAD
# 出图线宽模式。为 false（默认）时线随放大变粗，如同 CAD 模型空间。两种模式都受
# 屏幕空间下限（GPEdgeStyle.GP_MIN_PX）保护可读性。
var gpScreenConstantWidth: bool = false

# Cached symbol font so the canvas can read it cheaply each frame.
# 缓存的图元字体，供画布逐帧廉价读取。
var gpSymbolFont: Font = null

# Emitted when the symbol font or its size changes, so the canvas redraws.
# 图元字体或字号变化时发出，供画布重绘。
signal gpSymbolStyleChanged

# Emitted when the pipe line-number style (rotation / font size) changes, so the
# canvas redraws the line numbers.
# 管线位号样式（旋转/字号）变化时发出，供画布重绘位号。
signal gpPipeTagStyleChanged

# Emitted when the UI font or its size changes, so the toolbar and other dynamic
# controls can re-apply explicit font size overrides.
# 界面字体或字号变化时发出，供工具栏及其他动态控件重新应用显式字号覆盖。
signal gpUIFontChanged


# Load settings from disk and apply them.
# 从磁盘加载设置并应用。
func _ready() -> void:
	gpLoad()
	gpApply()


# Build a Font resource from a preset key. Always returns a usable Font
# (falls back to the bundled "arial_cjk" preset if the key is unknown).
# 按预设键构造 Font 资源，始终返回可用字体（键未知时回退到内置 arial_cjk 预设）。
func gpLoadFont(p_gpKey: String) -> Font:
	var gpSpec: Dictionary = GP_FONT_PRESETS.get(p_gpKey, GP_FONT_PRESETS["arial_cjk"])
	# 1) Bundled font file: host-independent, always available.
	# 1) 内置字体文件：不依赖宿主，始终可用。
	if gpSpec.has("res") and str(gpSpec["res"]) != "":
		var gpRes: Resource = load(gpSpec["res"])
		if gpRes is FontFile:
			return gpRes as FontFile
		# Not imported yet (very first launch before the import scan). In the editor
		# we can build it from raw bytes; in a headless/script run we fall back to the
		# engine default to avoid allocating a large glyph cache without a display.
		# 尚未导入（首次启动导入扫描前）。编辑器内可用原始字节构造；无显示的
		# headless 脚本运行则回退引擎默认，避免在无窗口环境分配大字形缓存而崩溃。
		if OS.has_feature("editor"):
			var gpBytes: PackedByteArray = FileAccess.get_file_as_bytes(gpSpec["res"])
			if gpBytes != null and gpBytes.size() > 0:
				var gpF: FontFile = FontFile.new()
				gpF.font_data = gpBytes
				gpF.antialiased = true
				return gpF
		return ThemeDB.fallback_font
	# 2) System font referenced by family name (cross-platform fallback).
	# 2) 按字体族名引用系统字体（跨平台回退）。
	if gpSpec.has("names"):
		var gpS: SystemFont = SystemFont.new()
		gpS.font_names = gpSpec["names"]
		return gpS
	# 3) Engine default.
	# 3) 引擎默认字体。
	return ThemeDB.fallback_font


# Load settings from disk, using defaults if the file is missing.
# 从磁盘加载设置；文件不存在时使用默认值。
func gpLoad() -> void:
	var gpCfg: ConfigFile = ConfigFile.new()
	if gpCfg.load(GP_CONFIG_PATH) != OK:
		return
	gpFontSize = gpCfg.get_value("ui", "font_size", 24)
	gpLocale = gpCfg.get_value("ui", "locale", "zh")
	gpFontKey = gpCfg.get_value("ui", "font", "arial_cjk")
	gpSymbolFontSize = gpCfg.get_value("symbol", "font_size", 16)
	gpSymbolFontKey = gpCfg.get_value("symbol", "font", "hiragino")
	gpAutoScale = gpCfg.get_value("ui", "auto_scale", true)
	gpPipeTagRotate = gpCfg.get_value("pipe", "tag_rotate", true)
	gpPipeTagFontSize = gpCfg.get_value("pipe", "tag_font_size", 0)


# Save current settings to disk.
# 保存当前设置到磁盘。
func gpSave() -> void:
	var gpCfg: ConfigFile = ConfigFile.new()
	gpCfg.set_value("ui", "font_size", gpFontSize)
	gpCfg.set_value("ui", "locale", gpLocale)
	gpCfg.set_value("ui", "font", gpFontKey)
	gpCfg.set_value("ui", "auto_scale", gpAutoScale)
	gpCfg.set_value("ui", "screen_constant_width", gpScreenConstantWidth)
	gpCfg.set_value("symbol", "font_size", gpSymbolFontSize)
	gpCfg.set_value("symbol", "font", gpSymbolFontKey)
	gpCfg.set_value("pipe", "tag_rotate", gpPipeTagRotate)
	gpCfg.set_value("pipe", "tag_font_size", gpPipeTagFontSize)
	gpCfg.save(GP_CONFIG_PATH)


# Effective UI font size. The UI font is intentionally fixed and does NOT scale
# with the window size — only the dock widths adapt (see gpAutoScale). This keeps
# text crisp and predictable across resolutions and monitors.
# 有效界面字号。界面字号刻意固定，不随窗口大小缩放——只有停靠栏宽度会自适应
#（见 gpAutoScale）。这样文字在不同分辨率 / 显示器下都清晰且可预期。
func gpEffectiveFontSize() -> int:
	return gpFontSize


# Apply font size AND family by setting the root theme's default font + size.
# 通过设置根主题默认字体与字号来应用界面字体。
func gpApplyFontSize() -> void:
	var gpTheme: Theme = _gpLoadTheme()
	gpTheme.default_font = gpLoadFont(gpFontKey)
	gpTheme.default_font_size = gpEffectiveFontSize()
	if get_tree() != null and get_tree().root != null:
		get_tree().root.theme = gpTheme
	gpUIFontChanged.emit()


# Load the shared dark theme (res://assets/themes/gp_dark.tres) as the root-theme base,
# falling back to a bare Theme if the file is missing. The .tres carries the unified palette
# (light text, dock-dark backgrounds, accent) so every Control reads from one source of truth;
# the manually drawn chrome (splitters, seams, status bar) stays in chrome_style.gd.
# 载入共享深色主题（res://assets/themes/gp_dark.tres）作为根主题基底；文件缺失时回退到裸
# Theme。.tres 承载统一调色板（浅色文字、深色背景、强调色），使所有控件取自同一事实源；
# 自绘 chrome（分隔条、接缝、状态栏）仍留在 chrome_style.gd。
func _gpLoadTheme() -> Theme:
	var gpT: Theme = load("res://assets/themes/gp_dark.tres") as Theme
	if gpT == null:
		gpT = Theme.new()
	return gpT


# Apply locale through the I18n singleton.
# 通过 I18n 单例应用语言。
func gpApplyLocale() -> void:
	I18n.gpSetLocale(gpLocale)


# Build the symbol font and notify the canvas to redraw.
# 构造图元字体并通知画布重绘。
func gpApplySymbolStyle() -> void:
	gpSymbolFont = gpLoadFont(gpSymbolFontKey)
	gpSymbolStyleChanged.emit()


# Notify the canvas that the pipe line-number style changed (rotation / font size).
# 通知画布管线位号样式（旋转/字号）已变。
func gpApplyPipeTagStyle() -> void:
	gpPipeTagStyleChanged.emit()


# Apply all settings at once.
# 一次性应用所有设置。
func gpApply() -> void:
	gpApplyFontSize()
	gpApplyLocale()
	gpApplySymbolStyle()
