class_name GPShellHost
extends Control
# Copyright © 2026 Jonson Wang
# The shell's PORT SURFACE — the one file that declares what a coordinator is allowed to touch
# on its host. GPMainWindow extends this and keeps nothing but assembly and scene-only furniture.
# 外壳的**端口面** —— 唯一声明「协调者可以触碰宿主的哪些成员」的文件。GPMainWindow 继承本类，
# 除装配与场景私有陈设外不再持有任何东西。
#
# WHY THIS EXISTS / 为何存在：
# Before 2026-11-06 the seven coordinators declared `var gpHost: GPMainWindow`, which is a type
# that can be anything: 44 distinct members were reached through it and NOTHING said which of
# them were contract and which were accidents. Every new sibling need added another three-line
# relay to the root, so the root could only grow. The type was the whole class, so the whole
# class was the API.
# 2026-11-06 之前，七个协调者写的是 `var gpHost: GPMainWindow` —— 一个「什么都能是」的类型：
# 经它触达 44 个不同成员，而没有任何东西区分哪些是契约、哪些是顺手拿的。每出现一次兄弟需求，
# 根类就多一个三行中继，于是根类只会变长。类型是整个类，于是整个类就是 API。
#
# THE TWO RULES / 两条规则：
# 1. A member lives here only if a class OTHER than the root reaches it. What only the root
#    touches (the outline, the backpack, the DRC panel, the cross-sheet controller) stays in
#    the root; moving furniture here would make the contract a second god-object.
# 2. Sibling relays are implemented HERE, not in the root. `gpMenuUndo` is a fact about the
#    shell, not about the scene: whoever assembles the shell gets it for free.
# 1. 只有**根类以外**的类会碰的成员才放这里。只有根类碰的（大纲、背包、DRC 面板、跨图纸控制器）
#    留在根类；把陈设搬进来会把契约变成第二个上帝对象。
# 2. 兄弟中继在**本类**实现、不在根类。`gpMenuUndo` 是关于「外壳」的事实，不是关于「场景」的；
#    谁装配外壳谁就免费得到它。
#
# WHAT A TYPE CAN DO THAT A COMMENT CANNOT / 类型能做到而注释做不到的事：
# `gpHost: GPShellHost` makes an undeclared reach a PARSE ERROR at gate 5. A comment saying
# "do not touch the root's internals" is enforced by nobody; a narrow type is enforced by the
# compiler. That is the whole point of this file.
# `gpHost: GPShellHost` 使「伸手拿了没声明的成员」在门 5 变成**解析错误**。写「别碰根类内部」的
# 注释没有执行者；窄类型有编译器。这就是本文件存在的全部理由。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# ============================ dock width floors (pixels) ============================
# ============================ 停靠栏宽度下限（像素） ============================
# Fixed floor widths for the side docks. These replace the old "dock width as a ratio of the
# window" model: docks stay a constant size and the canvas (center pane) absorbs all remaining
# width, which is the standard IDE / CAD behaviour and keeps the docks usable at any window size.
# 左右停靠栏的固定下限宽度（像素）。这取代了旧的"停靠栏占窗口比例"模型：停靠栏保持恒定尺寸，
# 画布（中间栏）吸收所有剩余宽度——这正是 IDE / CAD 的常规做法，可在任意窗口尺寸下保证停靠栏可用。
# Left dock minimum width in pixels (matches LeftDock.custom_minimum_size.x).
# 左停靠栏最小宽度（像素，与 LeftDock.custom_minimum_size.x 一致）。
const GP_LEFT_MIN: float = 160.0
# Left dock INITIAL width in pixels: wide enough that the symbol palette lays out 3 thumbnails
# per row on first launch (the grid derives columns from this width). Kept above GP_LEFT_MIN so
# the startup layout honours the "3 per row" default while the user can still drag the dock
# narrower (down to GP_LEFT_MIN = 2 per row).
# 左停靠栏**初始**宽度（像素）：足以让图元库在首次启动时每行排 3 个缩略图（网格据此宽度推导列数）。
# 刻意高于 GP_LEFT_MIN，使启动布局满足「每行 3 个」默认；用户仍可将停靠栏拖窄（下限 GP_LEFT_MIN = 每行 2 个）。
const GP_LEFT_DEFAULT: float = 200.0
# Right dock minimum width in pixels (matches RightDock.custom_minimum_size.x).
# 右停靠栏最小宽度（像素，与 RightDock.custom_minimum_size.x 一致）。
const GP_RIGHT_MIN: float = 160.0
# Right dock INITIAL width in pixels (2026-09-25 request: start at 200).
# 右停靠栏**初始**宽度（像素）（2026-09-25 需求：初始 200）。
const GP_RIGHT_DEFAULT: float = 200.0

# Current left-dock width in pixels; seeded from GP_LEFT_DEFAULT (3-per-row layout) and updated
# by drags.
# 当前左停靠栏宽度（像素）；以 GP_LEFT_DEFAULT（每行 3 个）初始化，拖拽时更新。
var gpLeftWidthPx: float = GP_LEFT_DEFAULT
# Current right-dock width in pixels; seeded from GP_RIGHT_DEFAULT (200) and updated by drags.
# 当前右停靠栏宽度（像素）；以 GP_RIGHT_DEFAULT（200）初始化，拖拽时更新。
var gpRightWidthPx: float = GP_RIGHT_DEFAULT

# Previous window content width, used to detect a real resize vs a HiDPI refresh.
# 上一次窗口内容宽度，用于区分真实缩放与 HiDPI 刷新。
var gpPrevWidth: int = 0

# Last known screen index, used to detect a cross-monitor drag so we can refresh the UI at the
# new monitor's density.
# 上一次所在的屏幕索引，用于检测跨显示器拖拽，从而按新显示器密度刷新 UI。
var gpLastScreen: int = -1

# ============================ coordinators ============================
# ============================ 协调者 ============================
# Every coordinator is declared here because EVERY one of them is reachable from at least one
# sibling through a relay below. If a coordinator ever becomes root-private (nobody relays to
# it), it should move back to the root — that is rule 1 applied honestly.
# 每个协调者都在此声明，因为**每一个**都经由下方的中继被至少一个兄弟触达。若某个协调者某天变成
# 根类私有（无人中继到它），就该搬回根类 —— 这是诚实执行规则 1。

# File lifecycle coordinator (save/open/import/export/close guard).
# 文件生命周期协调者（保存/打开/导入/导出/关闭拦截）。
var gpFileCoord: GPFileCoordinator = null

# Symbol library cascade delete, swap/rename, drift reconciliation, user packs and the symbol
# editor host.
# 图元库级联删除、替换与重命名、漂移对账、用户包加载与符号编辑器宿主。
var gpSymbolLibCoord: GPSymbolLibraryCoordinator = null

# Graph-to-panel sync bridge: subscribes to the event bus, refreshes inspector and status bar,
# writes panel edits back through the command layer.
# 图与面板的双向同步桥：订阅事件总线刷新属性面板与状态栏，并把面板改值经命令层回写。
var gpSelCoord: GPSelectionCoordinator = null

# Tag-rule dialog orchestration and the renumber workflow.
# 位号规则对话框编排与重编号工作流。
var gpTagCoord: GPTagRuleCoordinator = null

# Menu dispatch, undo/redo and the settings dialog; file actions are forwarded to GPFileCoordinator.
# 菜单分发、撤销/重做与设置对话框；文件类动作转发给 GPFileCoordinator。
var gpMenuCoord: GPMenuCoordinator = null


# ============================ presenters ============================
# ============================ 呈现器 ============================
# Not coordinators: they own UI furniture (panels / dialogs / overlays) instead of orchestrating a
# domain. Declared here only because a relay below has to reach them. Rule 1 still applies —
# the FURNITURE stays inside them, so nothing here may be a GPDRCPanel / GPDRCDialog / overlay.
# 不是协调者：它们持有 UI 陈设（面板 / 弹窗 / 角标）而不编排领域。在此声明仅因为下方中继要触达它们。
# 规则 1 依旧成立 —— **陈设**留在它们内部，故此处的成员不得是 GPDRCPanel / GPDRCDialog / 角标。

# DRC presentation (S3): dock panel, result dialog, screen-space badges, live scheduler.
# DRC 呈现（S3）：停靠面板、结果弹窗、屏幕空间角标、实时调度器。
var gpDrc: GPDrcPresenter = null

# ============================ content / document ============================
# ============================ 内容 / 文档 ============================
# Available symbol definitions shown in the left palette (and resolved by gpDefFor).
# ⚠️ Reassigned six times at runtime (project import / symbol delete); pass it to siblings as a
# Callable (gpDefsSnapshot), never capture the array.
# 左栏显示的可用图元定义（并由 gpDefFor 解析）。
# ⚠️ 运行期会被重新赋值六次（导入工程 / 删图元）；交给兄弟时用 Callable（gpDefsSnapshot），
# 绝不要捕获数组。
var gpDefs: Array[GPSymbolDef] = []

# bus, the active graph and the unsaved-dirty flag, replacing the old GPAppState autoload stub.
# 取代旧 GPAppState 自动加载桩。
var gpDocManager: GPAppDocumentManager = GPAppDocumentManager.new()

# Last opened/saved project path; Save reuses it, Save As / Open prompt for a new one.
# 上次打开/保存的工程路径；保存复用它，另存为/打开则重新选择。
var gpCurrentPath: String = ""

# ============================ scene nodes the ports expose ============================
# ============================ 端口暴露的场景节点 ============================
# Only the nodes a coordinator or a relay actually reaches. The root's own furniture is NOT
# here on purpose (see rule 1).
# 只放协调者或中继真正触达的节点。根类自己的陈设刻意不在此（见规则 1）。

# Top menu bar.
# 顶部菜单栏。
var gpMenuBar: GPPIDMenuBar

# Left symbol-library dock.
# 左侧图元库停靠栏。
var gpLeftDock: GPPIDToolbar

# Standalone top command toolbar row (below the menu bar, horizontally centred). Actions reuse
# menu ids and route through gpMenuCoord.gpOnMenu.
# 独立的顶部命令工具栏行（菜单栏正下方、水平居中）。动作复用菜单 id，经 gpMenuCoord.gpOnMenu 路由。
var gpQuickBar: GPPIDQuickToolbar = null

# Center drawing area: hosts the tabbed multi-sheet editor (one canvas + graph per tab).
# 中心绘图区：承载多标签页绘图编辑器（每标签页一个画布 + 图）。
var gpCenter: GPCenterArea

# The single HSplitContainer that lays out the three panes and lets the user drag both splitters.
# 承载三栏布局的单一 HSplitContainer，用户可拖动两个分隔条独立调整各栏宽度。
var gpBodySplit: HSplitContainer

# Right-side tab container.
# 右侧标签页容器。
var gpTabs: TabContainer

# Property inspector (inside the right tab container).
# 属性面板（在右侧标签页内）。
var gpInspector: GPInspector

# Info label on the Info tab.
# 信息标签页上的信息标签。
var gpInfoLabel: Label

# Status bar label showing the current selection.
# 状态栏标签：显示当前选中。
var gpSelLabel: Label

# Status bar label showing the cursor coordinates.
# 状态栏标签：显示光标坐标。
var gpCoordLabel: Label

# Status bar label showing the current zoom.
# 状态栏标签：显示当前缩放。
var gpZoomLabel: Label

# Status bar label showing the current application state.
# 状态栏标签：显示当前应用状态。
var gpStateLabel: Label

# ============================ file dialog state ============================
# ============================ 文件对话框状态 ============================
# File dialog (open / save-as), created once and reused by the file coordinator.
# 打开/另存为用的文件对话框，创建一次并由文件协调者重复使用。
var gpFileDialog: FileDialog

# What the in-flight file dialog is for: "save" / "open" / "import" / "export_<kind>".
# 当前文件对话框的用途：save / open / import / export_<kind>。
var gpPendingFileAction: String = ""

# Set when the user chose "Save" in the close-confirmation and the project had no path yet, so
# the quit has to wait for the save-as dialog to complete.
# 用户在关闭确认中选了「保存」但工程尚无路径时置位，使退出必须等另存为对话框完成。
var gpQuitAfterSave: bool = false

# ============================ status bar ============================
# ============================ 状态栏 ============================
# Last status snapshot received from the canvas.
# 从画布接收到的上一个状态快照。
var gpLastStatus: Dictionary = {"selection": "", "zoom": 1.0, "world": Vector2.ZERO}

# Current state-bar i18n key.
# 当前状态栏 i18n 键。
var gpStateKey: String = "status.ready"

# Arguments for the current state-bar format string.
# 当前状态栏格式化字符串的参数。
var gpStateArgs: Array = []


# ============================ ports: the host implements them ============================
# ============================ 端口：由宿主实现 ============================
# Sibling relays live here, not in the root: a coordinator that needs another coordinator's
# service asks the shell, and the shell answers. Same signature and same semantics as the
# three-line copies that used to sit in GPMainWindow, minus the copies.
# 兄弟中继在此实现、不在根类：需要另一个协调者服务的协调者问外壳，外壳作答。签名与语义和原先躺在
# GPMainWindow 里的三行拷贝完全一致，只是不再有那些拷贝。


# Set the status bar text by i18n key and optional format arguments.
# 通过 i18n 键与可选格式化参数设置状态栏文本。
func gpSetState(gpKey: String, gpArgs: Array = []) -> void:
	gpStateKey = gpKey
	gpStateArgs = gpArgs
	var gpFmt: String = I18n.gpTr(gpKey)
	gpStateLabel.text = gpFmt % gpArgs if gpArgs.size() > 0 else gpFmt


# The active canvas/graph are owned by the GPCenterArea; these accessors route the legacy
# single-canvas logic to whichever sheet is currently active.
# 活动画布/图由 GPCenterArea 持有；这些访问器把原先针对单一画布的逻辑，路由到当前活动图纸。
func gpActiveCanvas() -> GPCanvas2D:
	return gpCenter.gpActiveCanvas()


func gpActiveGraph() -> GPPIDGraph:
	return gpCenter.gpActiveGraph()


# The live symbol-definition table, handed to a sibling on every call so it can never go stale.
# 实时图元定义表；每次调用都交给兄弟，故不会过期。
func gpDefsSnapshot() -> Array[GPSymbolDef]:
	return gpDefs


# Find a symbol definition by its type id.
# 按类型 id 查找图元定义。
func gpDefFor(gpTypeId: String) -> GPSymbolDef:
	for gpD in gpDefs:
		if gpD.gpId == gpTypeId:
			return gpD
	return null


# Find a graph node by its id in the ACTIVE sheet.
# 在**活动图纸**中按 id 查找图节点。
func gpNodeFor(gpId: String) -> GPPIDNode:
	var gpG: GPPIDGraph = gpActiveGraph()
	if gpG == null:
		return null
	for gpN in gpG.gpNodes:
		if gpN.gpInstanceId == gpId:
			return gpN
	return null


# Refresh the inspector for the current selection, then let the root mirror it wherever else it
# has to appear (its outline tree).
# 按当前选中刷新属性面板，随后让根类把它镜像到其它必须出现的地方（它的大纲树）。
func gpRefreshSelection() -> void:
	gpSelCoord.gpRefreshSelection()
	gpOnSelectionMirrored()


# Hook for the root: the tree mirrors the selection; without this, picking a symbol on the
# canvas leaves the outline pointing at whatever was selected before.
# 供根类覆写的钩子：树镜像选择；少了这一步，在画布上点选图元后大纲会停在之前选中的行。
# Empty by default — the contract must not depend on furniture the root happens to own.
# 默认空实现 —— 契约不得依赖根类碰巧拥有的陈设。
func gpOnSelectionMirrored() -> void:
	pass


# Push the live definition table into the inspector's cached copy.
# 把实时定义表推入属性面板的缓存副本。
func gpSyncInspectorDefs() -> void:
	gpSymbolLibCoord.gpSyncInspectorDefs()


# Reconcile a freshly loaded graph against the live symbol library.
# 把刚载入的图与实时图元库对账。
func gpReconcileLibraryDrift(gpGraph: GPPIDGraph) -> void:
	gpSymbolLibCoord.gpReconcileLibraryDrift(gpGraph)


func gpMenuUndo() -> void:
	gpMenuCoord.gpMenuUndo()


func gpMenuRedo() -> void:
	gpMenuCoord.gpMenuRedo()


func gpOpenSettings() -> void:
	gpMenuCoord.gpOpenSettings()


func gpDeleteSelected() -> void:
	gpMenuCoord.gpDeleteSelected()


# DRC entry points. They were DECLARED here and implemented in the root while the DRC furniture
# lived there (S2); S3 moved the furniture into GPDrcPresenter, so they are relays now. The
# declaration stayed because the menu dispatcher still reaches them through gpHost.
# DRC 入口。S2 时在此**声明**、由根类实现，因为陈设还在根类；S3 把陈设搬进 GPDrcPresenter，
# 故现在它们是中继。声明保留，因为菜单分发仍经 gpHost 到达它们。
#
# NOTE / 注：this contract has NO unimplemented stubs left. A stub (push_error) is only honest
# when someone really must override it; when nobody does, it is a runtime error waiting for a
# menu click. Prefer declaring a relay, or a hook with a `pass` default (gpOnSelectionMirrored).
# 本契约**已没有**未实现的空体。空体（push_error）只在确实必须有人覆写时才诚实；无人覆写时，
# 它就是一个等着菜单点击触发的运行期错误。优先写中继，或写默认 `pass` 的钩子（gpOnSelectionMirrored）。
func gpRunDrc() -> void:
	gpDrc.gpRun()


func gpShowDrcDialog() -> void:
	gpDrc.gpShowDialog()
