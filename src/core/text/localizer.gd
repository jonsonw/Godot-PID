class_name GPLocalizer
extends RefCounted
# Copyright © 2026 Jonson Wang
# Translation seam for the inner layers. Core (and any layer that may not touch autoloads) asks
# this class for a string; the ui/autoload layer INSTALLS the real translator once at startup.
# 内层的翻译缝。core（以及任何不可触碰 autoload 的层）向本类要字符串；ui / autoload 层在启动时
# 一次性装入真正的翻译器。
#
# WHY NOT CALL I18n DIRECTLY / 为何不直接调 I18n：
# I18n is an autoload — a scene-tree singleton. Calling it from core made the pure logic layer
# depend on a global that does not exist in a headless run, which is why the DRC message text
# could only ever be asserted as "non-empty" instead of compared against an expected string.
# The seam inverts that: core names a Callable it owns, and the composition root decides what the
# Callable does. This is the same move as ADR-13's canvas ports, applied to text.
# I18n 是 autoload，即场景树单例。core 直接调它，等于让纯逻辑层依赖一个在 headless 运行中并不存在
# 的全局对象 —— 这也正是 DRC 提示文案此前只能断言「非空」、无法与期望字符串比对的原因。
# 本缝把它倒过来：core 只认自己持有的一个 Callable，由组合根决定它做什么。这与 ADR-13 的画布端口
# 是同一手法，只是用在文字上。
#
# DEFAULT IS THE IDENTITY, ON PURPOSE / 默认刻意是恒等：
# With nothing installed, a key resolves to itself. That is honest (the caller sees an untranslated
# key, not a crash or an empty line) and it makes core testable with zero setup.
# 未装入时，键解析为自身。这是诚实的（调用方看到未翻译的键，而不是崩溃或空行），也使 core 无需任何
# 装配即可测试。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Installed translator: key -> localised string. Invalid = identity.
# 已装入的翻译器：键 -> 本地化字符串。无效 = 恒等。
static var _gpTranslator: Callable = Callable()

# Second shape of the same query: both languages joined ("项目 / PROJECT"). Kept as its own
# Callable because a drawing sheet legitimately shows bilingual captions while the chrome shows
# one language — the two are different questions, so they get different seams.
# 同一查询的第二种形态：双语并置（"项目 / PROJECT"）。单独一个 Callable，因为图纸标题合法地双语，
# 而界面只显一种语言 —— 这是两个不同的问题，故各有各的缝。
static var _gpBothTranslator: Callable = Callable()


# Install the translator. Called ONCE by the composition root (src/autoload/i18n.gd `_ready`).
# 装入翻译器。由组合根（src/autoload/i18n.gd 的 `_ready`）调用**一次**。
static func gpSetTranslator(gpTranslator: Callable) -> void:
	_gpTranslator = gpTranslator


# Install the bilingual translator ("zh / en" joined). Optional; gpTrBoth() degrades to gpTr().
# 装入双语翻译器（"中 / 英"并置）。可选；未装入时 gpTrBoth() 退化为 gpTr()。
static func gpSetBothTranslator(gpBothTranslator: Callable) -> void:
	_gpBothTranslator = gpBothTranslator


# Drop the translator, restoring the identity. Used by tests and by a "switch language" reload.
# 卸下翻译器，恢复恒等。测试与「切换语言」重装时使用。
static func gpClearTranslator() -> void:
	_gpTranslator = Callable()
	_gpBothTranslator = Callable()


# The installed translator (invalid when none). Needed to SAVE and RESTORE it around a swap,
# e.g. a test that proves the identity fallback without leaving the app untranslated.
# 当前的翻译器（未装入时无效）。用于在临时替换前后**保存与恢复**，例如测试恒等回退又不让应用失译。
static func gpTranslator() -> Callable:
	return _gpTranslator


# Whether a real translator is installed (i.e. the app is running, not a bare script).
# 是否已装入真实翻译器（即处于应用运行态，而非裸脚本）。
static func gpHasTranslator() -> bool:
	return _gpTranslator.is_valid()


# Translate a key. Never fails: with no translator installed the key is returned unchanged.
# 翻译一个键。绝不失败：未装入翻译器时原样返回键。
static func gpTr(gpKey: String) -> String:
	if _gpTranslator.is_valid():
		return str(_gpTranslator.call(gpKey))
	return gpKey


# Translate a key into BOTH languages joined by " / ". Falls back to the single-language form,
# then to the key itself — so a caption is never empty and never crashes.
# 把键翻译成**双语**并置（" / " 分隔）。退化为单语形态，再退化为键本身 —— 故标题永不为空、不会崩。
static func gpTrBoth(gpKey: String) -> String:
	if _gpBothTranslator.is_valid():
		return str(_gpBothTranslator.call(gpKey))
	return gpTr(gpKey)
