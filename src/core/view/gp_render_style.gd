class_name GPRenderStyle
extends RefCounted
# Copyright © 2026 Jonson Wang
# 渲染样式快照值对象。
# Render-style snapshot value object.
#
# 取代 render 层（GPEdgeView / GPSymbolView）直接读 Settings / I18n 自动加载单例的做法：
# 由 ui 层（GPCanvas2D）在装配时从 Settings / I18n 构造本快照并注入每个视图，语言或字号变化时
# 重建并显式重注入。render 层因此不再 import 任何 autoload，可脱离 GUI 单测、分层规则闭合。
# Replaces render-layer direct reads of the Settings / I18n autoloads: the ui layer builds this
# snapshot from Settings / I18n at assembly and injects it into every view; on locale / font change
# it rebuilds and re-injects. The render layer no longer imports any autoload, so it is unit-testable
# without a GUI and the layering rule closes.
#
# 本类只承载纯数据（Font / int / String / bool），不依赖任何 autoload —— 取值动作在调用方完成。
# This class holds pure data only (Font / int / String / bool) and depends on no autoload; reading
# the values is done by the caller so core stays autoload-free.
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Symbol / tag label font (falls back to ThemeDB.fallback_font when null).
# 图元 / 位号标签字体（为 null 时回落 ThemeDB.fallback_font）。
var gpSymbolFont: Font = null

# Symbol font size in millimetres (world units, drives canvas label + tag text height at 1:1).
# The palette / dock labels use Settings.gpFontSize (screen px) instead — see symbol_grid /
# symbol_palette_item. 图元字号（毫米，世界单位；驱动画布标签与位号文字高度，1:1 比例）。
# 图元库 / 停靠栏标签改用 Settings.gpFontSize（屏幕像素），见 symbol_grid / symbol_palette_item。
var gpSymbolFontSize: float = 3.0

# Active UI locale, e.g. "zh_CN" / "en". Drives label text resolution.
# 当前界面语言，如 "zh_CN" / "en"，驱动标签文字解析。
var gpLocale: String = "zh_CN"

# Keep rendered line weight screen-constant across zoom (width / zoom).
# 缩放时保持渲染线宽屏幕恒定（width / zoom）。
var gpScreenConstantWidth: bool = false

# Pipe-tag font size; overrides gpSymbolFontSize when > 0, else inherits.
# 管线位号字号；为正时覆盖 gpSymbolFontSize，否则继承。
var gpPipeTagFontSize: int = 0

# Rotate a vertical-run pipe number by default (overridable per edge via "tag_rotate").
# 竖管位号默认旋转（可被单条边的 "tag_rotate" 属性覆盖）。
# Defaults to TRUE to match Settings.gpPipeTagRotate. The two used to disagree (Settings said true,
# this said false), so the drafting convention silently depended on WHICH of them a given call path
# happened to read — and any path that missed the autoload rendered horizontal numbers on vertical
# pipes. A convention is not a preference: the default has to be the convention, and both sources
# must state it identically.
# 默认**真**，与 Settings.gpPipeTagRotate 一致。二者原不一致（Settings 为真、此处为假），使这条制图
# 约定静默取决于某条调用路径恰好读到哪一个 —— 任何漏掉 autoload 的路径都会在竖管上渲染水平编号。
# 约定不是偏好：默认值必须是该约定，且两处必须写法一致。
var gpPipeTagRotate: bool = true


# Build a snapshot from the current ui settings. The values are passed in (not read here) so the
# caller owns the autoload dependency and this class stays pure data.
# 用当前 ui 设置构造快照。值由参数传入（本类不读取），使调用方持有 autoload 依赖、本类保持纯数据。
static func gpFrom(gpFont: Font, gpFontSize: float, gpLoc: String, gpConstWidth: bool,
		gpTagFontSize: int, gpTagRotate: bool) -> GPRenderStyle:
	var gpS: GPRenderStyle = GPRenderStyle.new()
	gpS.gpSymbolFont = gpFont
	gpS.gpSymbolFontSize = gpFontSize
	gpS.gpLocale = gpLoc
	gpS.gpScreenConstantWidth = gpConstWidth
	gpS.gpPipeTagFontSize = gpTagFontSize
	gpS.gpPipeTagRotate = gpTagRotate
	return gpS


# Build a snapshot by READING the two settings sources, falling back to safe defaults when either
# is absent (headless / out-of-tree). This is the only place that pokes at the settings objects'
# properties; the caller's single job is to hand the objects over.
# 通过**读取**两个设置来源构造快照；任一来源缺失（headless / 树外）时回落安全默认值。这里是唯一读取
# 设置对象属性的地方；调用方唯一的职责就是把对象交进来。
# WHY THIS LIVES IN core / 为何放在 core：
# it was previously inlined in GPCanvas2D, which made it reachable only through a canvas in a tree —
# so no test could feed it a known settings object, and the bug below survived a green suite.
# 它原先内联在 GPCanvas2D 中，只能经「树中的画布」到达 —— 于是没有任何测试能喂给它一个已知的设置对象，
# 下面的缺陷才得以在一套全绿的测试下存活。
# ⚠️ NEVER resolve these from Engine.get_singleton() / has_singleton(): in Godot 4 an autoload is a
# node under /root, NOT an Engine singleton, so both return nothing and EVERY default below is what
# the running app actually used — silently. Symptom seen by the user: vertical line numbers stayed
# horizontal although settings.cfg held tag_rotate=true; font / font size / locale / tag size /
# screen-constant width were dead too, with no error and no failing test.
# ⚠️ 切勿用 Engine.get_singleton() / has_singleton() 解析这两者：Godot 4 中 autoload 是 /root 下的
# 节点、**不是** Engine 单例，故两者都取不到东西 —— 于是下列每一项默认值就成了运行中的应用**真正**
# 在用的值，且悄无声息。用户看到的症状：settings.cfg 中 tag_rotate=true，竖管位号却仍是水平文字；
# 字体 / 图元字号 / 语言 / 位号字号 / 屏幕恒定线宽同样全部失效，既无报错也无测试变红。
static func gpFromSources(gpSettings: Object, gpI18n: Object) -> GPRenderStyle:
	var gpFont: Font = null
	var gpFontSize: float = 3.0
	# The fallback locale is GPPropertyResolver.GP_FALLBACK_LOCALE — the DRAWING's own default key,
	# which is what the label lookup falls back to anyway. Not the UI locale, deliberately.
	# 回落语言取 GPPropertyResolver.GP_FALLBACK_LOCALE —— 即**图纸**自身的默认键，也正是标签查找本身
	# 会回落到的那一个。刻意不用界面语言。
	var gpLoc: String = "zh_CN"
	var gpConstWidth: bool = false
	var gpTagFontSize: int = 0
	var gpTagRotate: bool = true
	if gpSettings != null:
		if gpSettings.get("gpSymbolFont") != null:
			gpFont = gpSettings.gpSymbolFont
		if gpSettings.get("gpSymbolFontSize") != null:
			gpFontSize = gpSettings.gpSymbolFontSize
		if gpSettings.get("gpScreenConstantWidth") != null:
			gpConstWidth = gpSettings.gpScreenConstantWidth
		if gpSettings.get("gpPipeTagFontSize") != null:
			gpTagFontSize = gpSettings.gpPipeTagFontSize
		if gpSettings.get("gpPipeTagRotate") != null:
			gpTagRotate = gpSettings.gpPipeTagRotate
	if gpI18n != null and gpI18n.get("gpLocale") != null:
		gpLoc = gpI18n.gpLocale
	return gpFrom(gpFont, gpFontSize, gpLoc, gpConstWidth, gpTagFontSize, gpTagRotate)
