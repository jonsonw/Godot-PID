class_name GPEndNoteDialog
extends AcceptDialog
# Copyright © 2026 Jonson Wang
#
# The "open-end note" editor (B08): pick one of the six standard notes, or type your own.
# 「开口端注记」编辑框（B08）：从六个标准注记里选一个，或者自己写。
#
# Why presets FIRST and free text second / 为何先给预置、再给自由文本：
# A P&ID's open ends are 95% one of six sentences (TO ATM / VENT / DRAIN / TO FLARE /
# CONT. ON DWG … / TIE-IN). Offering them as one click keeps the vocabulary consistent across a
# project — free text is still there for the other 5%, but it is the fallback, not the default.
# P&ID 的开口端 95% 是六句话之一（通大气 / 放空 / 排凝 / 去火炬 / 延续至另一图 / 预留接口）。
# 一键提供它们能让整个项目的措辞一致 —— 自由文本仍在，用于剩下那 5%，但它是兜底而非默认。
#
# The dialog OWNS NO STATE beyond what the user types: it emits the text and the shell routes it
# to the command layer, so "who creates the annotation" stays in one place (the command).
# 除用户输入外本对话框**不持有**状态：它只发出文字，由外壳路由到命令层，故「谁创建注释」这件事
# 始终只有一处（命令）。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# The six standard open-end notes, in menu order.
# 六个标准开口端注记，按菜单顺序。
const GP_PRESETS: Array[String] = [
	"TO ATM", "VENT", "DRAIN", "TO FLARE", "CONT. ON DWG ", "TIE-IN",
]

# Emitted when the user confirms; carries the final text (may be "" to clear the note).
# 用户确认时发出；携带最终文字（可为空串表示清除注记）。
signal gpNoteConfirmed(gpText: String)

var _gpPreset: OptionButton = null
var _gpEdit: LineEdit = null


# Build the widgets once; the shell then only sets the initial text and shows the dialog.
# 构建控件一次；之后外壳只负责设初值与显示。
func gpBuild() -> void:
	title = I18n.gpTr("open_end.title")
	ok_button_text = I18n.gpTr("open_end.apply")
	add_cancel_button(I18n.gpTr("open_end.cancel"))
	var gpBox: VBoxContainer = VBoxContainer.new()
	gpBox.add_theme_constant_override("separation", 6)
	gpBox.custom_minimum_size = Vector2(360.0, 0.0)
	var gpLbl: Label = Label.new()
	gpLbl.text = I18n.gpTr("open_end.pick")
	gpBox.add_child(gpLbl)
	_gpPreset = OptionButton.new()
	for gpP in GP_PRESETS:
		_gpPreset.add_item(gpP)
	gpBox.add_child(_gpPreset)
	_gpEdit = LineEdit.new()
	_gpEdit.placeholder_text = I18n.gpTr("open_end.placeholder")
	gpBox.add_child(_gpEdit)
	var gpHint: Label = Label.new()
	gpHint.text = I18n.gpTr("open_end.hint")
	gpHint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gpHint.modulate = Color(0.62, 0.62, 0.68)
	gpBox.add_child(gpHint)
	add_child(gpBox)
	# A FIXED, compact size. Without it an AcceptDialog grows to fit its content (and the autowrap
	# hint label wants the whole viewport width), which pushed the OK / Cancel row off the screen —
	# the dialog then had no visible way to confirm anything.
	# **固定的小尺寸**。否则 AcceptDialog 会撑到内容大小（而自动折行的提示标签想要整个视口宽），
	# 把确定 / 取消挤到屏幕外 —— 那个对话框于是没有任何可见的确认途径。
	min_size = Vector2i(420, 200)
	size = Vector2i(420, 200)
	# Picking a preset FILLS the field instead of bypassing it: the user can append a drawing
	# number ("CONT. ON DWG " → "CONT. ON DWG W-102") before confirming.
	# 选中预置是**填进**输入框而非直接生效：用户可以先补一个图号（"CONT. ON DWG " →
	# "CONT. ON DWG W-102"）再确认。
	_gpPreset.item_selected.connect(func(gpI: int) -> void:
		if gpI >= 0 and gpI < GP_PRESETS.size():
			_gpEdit.text = GP_PRESETS[gpI]
			_gpEdit.grab_focus()
			_gpEdit.caret_column = _gpEdit.text.length())
	confirmed.connect(_gpOnConfirmed)
	# ESC / the window close button both mean "no change": `canceled` is deliberately NOT wired to
	# an empty-string confirm, because "" means "clear the note" — a different intent.
	# ESC / 关闭按钮都表示「不改」：刻意**不**把 canceled 接成空串确认，因为空串表示「清除注记」，
	# 那是另一种意图。


# Show the dialog with the end's current note text.
# 以该端当前注记文字显示对话框。
func gpOpenFor(gpCurrentText: String) -> void:
	if _gpEdit == null:
		return
	_gpEdit.text = gpCurrentText
	_gpPreset.selected = -1
	# popup_centered(size) sets the size AND centres: the dialog never inherits a runaway height
	# from its content.
	# popup_centered(size) 同时设定尺寸并居中：对话框绝不会从内容继承一个失控的高度。
	# First open: an AcceptDialog computes its size from the wrapped content BEFORE the window is
	# created, so `popup_centered(size)` was overridden and the OK / Cancel row fell off screen.
	# The second open looked right because the window already existed. Setting the size once more
	# AFTER the popup is realised is what makes the FIRST open correct too.
	# 首次打开：AcceptDialog 在窗口真正建立**之前**就按内容算了尺寸，故 `popup_centered(size)` 被覆盖，
	# 确定 / 取消 掉到屏幕外；第二次打开看着正常是因为窗口已存在。**弹出之后**再设一次尺寸，
	# 才能让第一次打开也正确。
	popup_centered(Vector2i(420, 200))
	set_deferred("size", Vector2i(420, 200))
	set_deferred("min_size", Vector2i(420, 200))
	_gpEdit.grab_focus()
	_gpEdit.select_all()


func _gpOnConfirmed() -> void:
	if _gpEdit == null:
		return
	gpNoteConfirmed.emit(_gpEdit.text.strip_edges())
