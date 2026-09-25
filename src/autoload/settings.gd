extends Node

# Global settings singleton: persists UI font size, UI font family, symbol font
# size, symbol font family and locale to user://settings.cfg and applies them to
# the whole application.
# 全局设置单例：把界面字号、界面字体、图元字号、图元字体与语言持久化到
# user://settings.cfg，并应用到全应用。
#
# Fonts: resolved from the HOST by family name (SystemFont) instead of shipping
# (45.6 MB combined) forced a ~17-21 MB .fontdata deserialize on every editor and
# runtime start; they were also macOS system fonts, a redistribution risk for an
# MIT-licensed project. SystemFont is resolved lazily by the OS, so startup pays
# nothing up front and Chinese stays crisp via PingFang SC / Microsoft YaHei /
# Noto Sans CJK SC.
# 字体：改为按字体族名从宿主机解析（SystemFont），不再随包字体文件。此前内置的
# ArialUnicode.ttf 与 HiraginoSansGB.ttc（合计 45.6 MB）会在每次编辑器与运行时启动时
# 强制反序列化约 17~21 MB 的 .fontdata；且二者系 macOS 系统字体，对 MIT 许可项目存在
# 再分发风险。SystemFont 由操作系统惰性解析，启动期零开销，中文经
# PingFang SC / Microsoft YaHei / Noto Sans CJK SC 保持清晰。
#
# Coding rule: every variable must declare its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Path to the persisted settings file.
# 持久化设置文件的路径。
const GP_CONFIG_PATH: String = "user://settings.cfg"

# Font preset registry: key -> { "zh", "en", "res" | "names" }.
# "res" = a bundled font file under res:// (preferred, host-independent).
# "names"= OS font family names tried in order (cross-platform fallback).
# 字体预设登记表：键 -> { "zh", "en", "res" | "names" }。
# "res" = res:// 下的内置字体文件（首选，不依赖宿主）；
# "names"= 系统字体族名（按序回退，跨平台）。
const GP_FONT_PRESETS: Dictionary = {
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
	"calibri":   { "zh": "Calibri / Arial（标准）", "en": "Calibri / Arial (standard)",
				   "names": ["Calibri", "Arial", "Liberation Sans", "Noto Sans", "PingFang SC", "Microsoft YaHei"] },
}

# Current UI font size.
# 当前界面字号。
var gpFontSize: int = 16

# Current locale code.
# 当前语言代码。声明默认与 gpLoad() 回退（"zh"）及 I18n 默认一致，避免首启未加载前的窗口期出现 en。
# The declared default matches the gpLoad() fallback ("zh") and the I18n default, so there is no
# "en" window before the saved config is loaded on first boot.
var gpLocale: String = "zh"

# Current UI font preset key.
# 当前界面字体预设键。
var gpFontKey: String = "system"

# Current symbol font preset key.
# 当前图元字体预设键。
var gpSymbolFontKey: String = "calibri"

# Current symbol font size, in millimetres (world units). Drives canvas label + tag text height
# at 1:1; the palette / dock labels use gpFontSize (screen px) instead.
# 当前图元字号（毫米 / 世界单位）。驱动画布标签与位号文字高度（1:1 比例）；图元库 / 停靠栏
# 标签改用 gpFontSize（屏幕像素）。
var gpSymbolFontSize: float = 3.0

# Standard sheet text height (mm) and the threshold above which a stored value can only be a
# pre-v0.1 SCREEN-pixel size (see the migration in gpLoad()). 3.0 mm matches the DEXPI C01
# reference sheet; 6.0 mm is above any plausible sheet text height and below the pixel floor (8).
# 标准图面字高（mm）与「存值只可能是 v0.1 之前的屏幕像素值」的判定阈值（见 gpLoad() 中的迁移）。
# 3.0mm 对齐 DEXPI C01 参考图；6.0mm 高于任何合理的图面字高，又低于像素时代的下限（8）。
const GP_SYMBOL_FONT_MM_DEFAULT: float = 3.0
const GP_SYMBOL_FONT_MM_MIGRATE_ABOVE: float = 6.0

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

# Palette visibility map: symbol id -> true when the user unticked it from the
# left palette via a category's gear menu. Persisted so the choice survives restarts.
# 图元库可见性表：符号 id -> true 表示用户经类目齿轮菜单取消勾选。持久化以在重启后保留。
var gpPaletteHidden: Dictionary = {}

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
	# Persist a one-time config migration immediately, so the corrected value is what the user
	# sees in the settings dialog and what survives the next launch (see the mm migration note in
	# gpLoad()). Without this the old pixel-era value would be re-migrated on every start.
	# 立即持久化一次性配置迁移，使用户在设置对话框看到的就是修正后的值，并在下次启动时保持
	#（见 gpLoad() 中的 mm 迁移说明）。否则旧像素值会在每次启动时被反复迁移。
	if has_meta("gpSymbolFontMigrated"):
		remove_meta("gpSymbolFontMigrated")
		gpSave()
	gpApply()


# Build a Font resource from a preset key. Always returns a usable Font
# (falls back to the "system" preset if the key is unknown).
# 按预设键构造 Font 资源，始终返回可用字体（键未知时回退到 system 预设）。
func gpLoadFont(p_gpKey: String) -> Font:
	var gpSpec: Dictionary = GP_FONT_PRESETS.get(p_gpKey, GP_FONT_PRESETS["system"])
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


# Normalize a persisted font preset key: unknown or removed keys fall back to
# "system" so a stale config can never resurrect a bundled-font load.
# 使陈旧配置无法再次触发内置字体加载。
func _gpSanitizeFontKey(p_gpKey: String) -> String:
	if GP_FONT_PRESETS.has(p_gpKey):
		return p_gpKey
	return "system"


# Load settings from disk, using defaults if the file is missing.
# 从磁盘加载设置；文件不存在时使用默认值。
func gpLoad() -> void:
	var gpCfg: ConfigFile = ConfigFile.new()
	if gpCfg.load(GP_CONFIG_PATH) != OK:
		return
	gpFontSize = gpCfg.get_value("ui", "font_size", 24)
	gpLocale = gpCfg.get_value("ui", "locale", "zh")
	gpFontKey = _gpSanitizeFontKey(gpCfg.get_value("ui", "font", "system"))
	gpSymbolFontKey = _gpSanitizeFontKey(gpCfg.get_value("symbol", "font", "system"))
	gpAutoScale = gpCfg.get_value("ui", "auto_scale", true)
	var gpStoredMM: float = float(gpCfg.get_value("symbol", "font_size", GP_SYMBOL_FONT_MM_DEFAULT))
	gpSymbolFontSize = _gpMigrateSymbolFontMM(gpStoredMM)
	if gpStoredMM != gpSymbolFontSize:
		set_meta("gpSymbolFontMigrated", true)
	gpPipeTagRotate = gpCfg.get_value("pipe", "tag_rotate", true)
	gpPipeTagFontSize = gpCfg.get_value("pipe", "tag_font_size", 0)
	gpScreenConstantWidth = gpCfg.get_value("ui", "screen_constant_width", false)
	gpPaletteHidden = gpCfg.get_value("ui", "palette_hidden", {})


# One-time migration to the mm-based drawing text height (v0.1 / plan Phase 0).
# WHY: the stored value used to be a SCREEN pixel height (8..24). Since the world unit became
# 1 mm, the same key now means a MILLIMETRE text height ON THE SHEET, where the standard sheet
# text is 2.5-3.0 mm. A stored value >= 6 can therefore only be the pixel-era one — nobody
# draws 6 mm text on a 4x2 mm ball valve — so it is snapped to the standard height once.
# 一次性迁移到「以毫米为基准的图纸字高」（v0.1 / 计划 Phase 0）。原因：该键原为**屏幕像素**
# 高度（8..24）；世界单位改为 1mm 后，同一键表示**图纸上的毫米字高**，而标准图面字高为
# 2.5–3.0mm。因此存值 ≥ 6 只可能是像素时代的遗留（没人会在 4×2mm 的球阀上写 6mm 的字），
# 故一次性归位到标准字高。
# Kept as a pure function so the decision is testable without writing a config file — its failure
# mode (a pixel-era 12 surviving as a 12 mm sheet text height) is what made every tag look blurry.
# 保持为纯函数，使该判定无需写配置文件即可测试 —— 其失效模式（像素时代的 12 以 12mm 图面字高
# 留存）正是每一个位号都发虚的成因。
# 存值 → 归位后的图面字高。
func _gpMigrateSymbolFontMM(gpStoredMM: float) -> float:
	if gpStoredMM >= GP_SYMBOL_FONT_MM_MIGRATE_ABOVE:
		return GP_SYMBOL_FONT_MM_DEFAULT
	return gpStoredMM


# Save current settings to disk.
# 保存当前设置到磁盘。
func gpSave() -> void:
	var gpCfg: ConfigFile = ConfigFile.new()
	gpCfg.set_value("ui", "font_size", gpFontSize)
	gpCfg.set_value("ui", "locale", gpLocale)
	gpCfg.set_value("ui", "font", gpFontKey)
	gpCfg.set_value("ui", "auto_scale", gpAutoScale)
	gpCfg.set_value("ui", "screen_constant_width", gpScreenConstantWidth)
	gpCfg.set_value("ui", "palette_hidden", gpPaletteHidden)
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
