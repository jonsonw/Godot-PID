class_name GPRenderStyle
extends RefCounted
# Copyright © 2026 Jonson Wang
# 渲染样式快照值对象（架构优化 §4.2）。
# Render-style snapshot value object (architecture optimization §4.2).
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

# Symbol font size in pixels (drives label + tag text height).
# 图元字号（像素），驱动标签与位号文字高度。
var gpSymbolFontSize: int = 16

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
var gpPipeTagRotate: bool = false


# Build a snapshot from the current ui settings. The values are passed in (not read here) so the
# caller owns the autoload dependency and this class stays pure data.
# 用当前 ui 设置构造快照。值由参数传入（本类不读取），使调用方持有 autoload 依赖、本类保持纯数据。
static func gpFrom(gpFont: Font, gpFontSize: int, gpLoc: String, gpConstWidth: bool,
		gpTagFontSize: int, gpTagRotate: bool) -> GPRenderStyle:
	var gpS: GPRenderStyle = GPRenderStyle.new()
	gpS.gpSymbolFont = gpFont
	gpS.gpSymbolFontSize = gpFontSize
	gpS.gpLocale = gpLoc
	gpS.gpScreenConstantWidth = gpConstWidth
	gpS.gpPipeTagFontSize = gpTagFontSize
	gpS.gpPipeTagRotate = gpTagRotate
	return gpS
