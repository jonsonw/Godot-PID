class_name GPPopupHelper
extends RefCounted

## Single source of truth for PopupMenu / Popup screen positioning in Godot 4.7.
## 在 Godot 4.7 中 PopupMenu 定位公式的单一事实来源。
##
## Godot 4.7's PopupMenu exposes NO popup_at_cursor() (verified via get_method_list); popup(Rect2i) is the
## only positioning entry, and when popups are NOT embedded (embed_subwindows=false, the default) its
## .position is interpreted in GLOBAL SCREEN coordinates. The three call sites that previously inlined this
## math (main canvas, symbol editor, isolation-layer save dropdown) each got it wrong at least once — this
## helper removes the duplication and the recurring positioning bug.
## Godot 4.7 的 PopupMenu 没有 popup_at_cursor()（已用 get_method_list 实测）；仅有 popup(Rect2i) 可定位，且
## 「非嵌入」（默认值）时其 .position 取全局屏幕坐标。主画布、符号编辑器、隔离层保存下拉三处原本各自内联该
## 公式，每处至少出错一次 —— 本助手消除重复与反复出现的定位 bug。


# Anchor a popup at the OS cursor, opening down-right (the convention).
# 把弹出菜单锚定到 OS 光标，向右下展开（符合惯例）。
# gpOwner: any Node inside the target window (used only to read the viewport + window offset).
# gpOwner：目标窗口内的任意 Node（仅用于读取视口与主窗口偏移）。
static func gpPopupAtMouse(gpMenu: PopupMenu, gpOwner: Node, gpPad: Vector2i = Vector2i(2, 2)) -> void:
	var gpMouseWin: Vector2i = gpOwner.get_viewport().get_mouse_position()
	gpMenu.position = Vector2i(gpOwner.get_window().position) + gpMouseWin + gpPad
	gpMenu.popup()


# Anchor a popup just below gpAnchor (in gpOwner's global space), e.g. a button dropdown.
# 把弹出菜单锚定到 gpAnchor（gpOwner 的全局空间坐标）正下方，如按钮下拉。
static func gpPopupBelow(gpMenu: PopupMenu, gpOwner: Node, gpAnchor: Vector2, gpPad: Vector2i = Vector2i(0, 28)) -> void:
	var gpScreen: Vector2 = gpOwner.get_viewport().get_screen_transform() * gpAnchor
	gpMenu.position = Vector2i(gpOwner.get_window().position) + Vector2i(gpScreen) + gpPad
	gpMenu.popup()
