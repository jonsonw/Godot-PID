class_name GPFontSeam
extends RefCounted
# Copyright © 2026 Jonson Wang
# Font seam for the inner layers. Render used to reach up into the Settings autoload to ask which
# font the drawing frame should use; that is an upward dependency the layer matrix forbids, and it
# also meant the frame could only be drawn when an autoload happened to exist.
# 内层的字体缝。render 原先向上访问 Settings 自动加载来问「图框该用哪款字体」—— 这是层矩阵禁止的
# 上行依赖，也意味着只有在 autoload 恰好存在时图框才能绘制。
#
# WHY A SEAM AND NOT GP_RENDER_STYLE / 为什么不用 GP_RENDER_STYLE：
# GPRenderStyle.gpSymbolFont is the SYMBOL font (Settings.gpSymbolFontKey, default "calibri"). The
# frame's title block is chrome, not drawing content: it follows the UI font (Settings.gpFontKey).
# The two are different settings and are NOT interchangeable — swapping one for the other changes
# what the sheet looks like. So the seam returns the UI font, and the composition root decides
# which preset that means.
# GPRenderStyle.gpSymbolFont 是**图元**字体（Settings.gpSymbolFontKey，默认 "calibri"）。图框标题栏
# 属于界面，不是图面内容：它跟随 UI 字体（Settings.gpFontKey）。两者是不同设置、**不可互换** ——
# 换掉任何一个都会改变图纸长什么样。故本缝返回 UI 字体，由组合根决定那对应哪个预设。
#
# VALIDITY CONTRACT / 有效性契约：
# The returned Font is owned by the resolver (Settings keeps one instance per key forever), so a
# recorded draw command stays valid until the end of the frame. A seam that built a fresh
# SystemFont per call would resurrect the 2026-10-16 solid-bar bug — see settings.gd gpLoadFont.
# 返回的 Font 由解析器持有（Settings 每键永久保留一个实例），故已记录的绘制命令活到帧末仍然有效。
# 若本缝每次调用都新建 SystemFont，会重现 2026-10-16 的实心条缺陷 —— 见 settings.gd gpLoadFont。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Installed resolver: no arguments, returns a Font (or null to fall through). Invalid = fallback.
# 已装入的解析器：无参，返回 Font（或 null 以继续回退）。无效 = 使用兜底。
static var _gpUiFontResolver: Callable = Callable()


# Install the resolver. Called ONCE by the composition root (src/autoload/settings.gd `_init`).
# 装入解析器。由组合根（src/autoload/settings.gd 的 `_init`）调用**一次**。
static func gpSetUiFontResolver(gpResolver: Callable) -> void:
	_gpUiFontResolver = gpResolver


# Drop the resolver. Used by tests that must prove the fallback path.
# 卸下解析器。供需要证明回退路径的测试使用。
static func gpClearUiFontResolver() -> void:
	_gpUiFontResolver = Callable()


# Whether a real resolver is installed (i.e. the app is running, not a bare script).
# 是否已装入真实解析器（即处于应用运行态，而非裸脚本）。
static func gpHasUiFontResolver() -> bool:
	return _gpUiFontResolver.is_valid()


# The UI font for chrome that draws text (the sheet frame's title block). Never null: with no
# resolver installed this is the engine fallback, which is exactly what the old code did in a
# headless run.
# 供绘制文字的界面元素（图框标题栏）使用的 UI 字体。绝不为 null：未装入解析器时返回引擎兜底字体，
# 这正是旧代码在 headless 下的行为。
static func gpUiFont() -> Font:
	if _gpUiFontResolver.is_valid():
		var gpFont: Font = _gpUiFontResolver.call() as Font
		if gpFont != null:
			return gpFont
	return ThemeDB.fallback_font
