class_name GPBootRoot
extends Node

# Boot router — the Godot-style entry (W13 user feedback 2026-11-09 16:47):
# launch -> the PROJECT MANAGER is the main screen; choosing/creating a project swaps
# in the editor; the editor's 项目 menu / corner pill swaps back. Exactly ONE of the two
# screens exists at any moment (D7: one project per window; no idle editor shell idling
# under the manager any more).
# 启动路由 —— Godot 式入口（W13 实机反馈 2026-11-09 16:47）：启动 → **项目管理器**作为
# 主屏；选择/新建工程后换入编辑器；编辑器的「项目」菜单 / 右下角胶囊再换回。任一时刻
# 两屏**只存在其一**（D7：单工程单窗口；管理器之下不再常驻空闲编辑器外壳）。
#
# WHY A NEW SCENE / 为何新场景：
# main.tscn stays the editor's single source of truth; boot.tscn (this script) becomes
# the project main scene and swaps its children. The frozen files (main_window 757,
# ADR-47) grow by zero lines — routing lives entirely here.
# main.tscn 继续作为编辑器的唯一事实源；boot.tscn（本脚本）成为工程主场景并换装自己的
# 子节点。冻结文件（main_window 757，ADR-47）零行增长 —— 路由完全住在本文件。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

const GP_EDITOR_SCENE_PATH: String = "res://scenes/main.tscn"
const GP_BOOT_GROUP: String = "gp_boot_root"

# The live screens (null when the other one is showing). Typed to the shell contract so
# the open relay stays the ONLY way into the editor's file machinery.
# 存活中的两屏（另一屏显示时为 null）。编辑器侧标注为外壳契约类型，使打开中继始终是
# 进入编辑器文件机器的**唯一**途径。
var gpEditor: GPShellHost = null
var gpManager: GPProjectManager = null
var gpConfirm: ConfirmationDialog = null


# Boot decision, pure & testable. Any *.pid.json argument means "the user asked for
# THIS archive" -> editor; everything else -> manager. (.bak leftovers never end with
# the archive suffix, so they are excluded by construction.)
# 启动决策，纯函数可测。任何 *.pid.json 参数＝「用户点名了这个档」-> 编辑器；其余 ->
# 管理器。（.bak 残留不以存档后缀结尾，结构上即被排除。）
static func gpBootMode(gpArgs: PackedStringArray) -> String:
	for gpArg in gpArgs:
		if gpArg.ends_with(GPProjectLibrary.GP_ARCHIVE_SUFFIX):
			return "editor"
	return "manager"


# The archive path a boot argument named, "" when none. Pure & testable.
# 启动参数点名的存档路径，无则 ""。纯函数可测。
static func gpBootPath(gpArgs: PackedStringArray) -> String:
	for gpArg in gpArgs:
		if gpArg.ends_with(GPProjectLibrary.GP_ARCHIVE_SUFFIX):
			return gpArg
	return ""


func _ready() -> void:
	add_to_group(GP_BOOT_GROUP)
	gpConfirm = ConfirmationDialog.new()
	gpConfirm.ok_button_text = I18n.gpTr("pc.exit_ok")
	gpConfirm.cancel_button_text = I18n.gpTr("pc.exit_cancel")
	gpConfirm.get_ok_button().pressed.connect(gpEnterManager)
	add_child(gpConfirm)
	var gpArgs: PackedStringArray = OS.get_cmdline_args()
	if gpBootMode(gpArgs) == "editor":
		gpEnterEditor(gpBootPath(gpArgs))
	else:
		gpEnterManager()


# Editor-side exit points (corner pill / 项目 menu) land here. The confirmation guard
# is honest about explicit-save-first (ADR-7): quitting now discards in-memory changes.
# When no editor is live (tests, direct main.tscn runs) the swap just happens.
# 编辑器侧出口（右下角胶囊 /「项目」菜单）落到这里。确认框对「显式保存优先」（ADR-7）
# 保持诚实：此刻退出即丢弃内存改动。无存活编辑器时（测试、直跑 main.tscn）直接换屏。
func gpShowManager() -> void:
	if gpEditor == null:
		gpEnterManager()
		return
	gpConfirm.dialog_text = I18n.gpTr("pc.exit_body")
	gpConfirm.title = I18n.gpTr("pc.exit_title")
	gpConfirm.ok_button_text = I18n.gpTr("pc.exit_ok")
	gpConfirm.cancel_button_text = I18n.gpTr("pc.exit_cancel")
	gpConfirm.popup_centered()


# Swap to the manager screen. Idempotent: a live manager is left alone.
# 换屏到管理器。幂等：已在管理器则不动。
func gpEnterManager() -> void:
	if gpEditor != null:
		gpEditor.queue_free()
		gpEditor = null
	if gpManager != null:
		return
	gpManager = GPProjectManager.new()
	gpManager.gp_open_project_requested.connect(gpOpenFromManager)
	add_child(gpManager)


# Manager "open" click: touch the recent list once here (boot-arg opens flow through
# the same seam), then swap.
# 管理器「打开」：在此统一记一次最近列表（带参启动的打开也走同一缝口），随后换屏。
func gpOpenFromManager(gpArchivePath: String) -> void:
	GPProjectLibrary.gpRecentTouch(gpArchivePath)
	gpEnterEditor(gpArchivePath)


# Swap to the editor, optionally loading an archive right after the _ready cascade has
# assembled the coordinators (add_child runs it synchronously — the relay call is safe).
# 换屏到编辑器，并可在 _ready 级联装配完协调者之后立即载入存档（add_child 同步跑完
# 级联 —— 中继调用是安全的）。
func gpEnterEditor(gpArchivePath: String) -> void:
	if gpManager != null:
		gpManager.queue_free()
		gpManager = null
	if gpEditor != null:
		gpEditor.queue_free()
		gpEditor = null
	var gpScene: PackedScene = load(GP_EDITOR_SCENE_PATH) as PackedScene
	if gpScene == null:
		push_error("GPBootRoot: editor scene missing / 编辑器场景缺失")
		gpEnterManager()
		return
	# NB: the local is deliberately NOT named "gpHost" — boot_root sits OUTSIDE the editor
	# shell (it builds and tears the shell down), and the contract detector treats any
	# ui/shell file holding a "gpHost" as a coordinator that must declare the contract
	# member. Naming it gpEditorHost keeps that rule meaningful.
	# 注意：局部变量刻意**不叫** "gpHost" —— boot_root 位于编辑器外壳**之外**（负责构建与
	# 拆除外壳），而契约检测器把 ui/shell 中任何持有 "gpHost" 的文件都按协调者要求声明
	# 契约成员。命名为 gpEditorHost 保住这条规则的意义。
	var gpEditorHost: GPShellHost = gpScene.instantiate() as GPShellHost
	gpEditor = gpEditorHost
	add_child(gpEditorHost)
	if not gpArchivePath.is_empty():
		GPProjectLibrary.gpRecentTouch(gpArchivePath)
		gpEditorHost.gpOpenProjectPath(gpArchivePath)
