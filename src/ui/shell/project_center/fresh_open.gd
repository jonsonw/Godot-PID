class_name GPFreshOpen
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# Open an EMPTY project archive (W13 fix, user feedback 2026-11-11): a freshly created
# .pid.json carries zero sheets — that is LEGITIMATE, not a load failure. The shell opens
# it as the SAME one new sheet the "+" button makes (gpAddTab: full I18n name +
# creation-time number), then runs the same post-load refresh as the sheeted path.
# History: the io layer used to pad a NAMELESS sheet here — io cannot reach I18n (layer
# rule), so its name/number stayed empty and _gpTabTitleOf returned "", blanking the tab
# bar, the pop-out window title and every pane picker at once (the user's screenshots:
# a tab with only the close button, an untitled pop-out, unselectable picker entries).
# 打开**空**工程存档（W13 修复，用户反馈 2026-11-11）：新建的 .pid.json 本就零图纸 ——
# 那是**合法**状态，不是载入失败。外壳按「+」按钮的**同一语义**开成一张新图纸
#（gpAddTab：完整 I18n 名 + 创建时编号），随后执行与带图纸路径相同的载入后刷新。
# 历史根因：io 层曾在此补一张**无名**图纸 —— io 拿不到 I18n（分层铁律），名称/编号只能
# 为空，_gpTabTitleOf 返回空串，一次刷空标签栏、摘出窗口标题与全部窗格选择器（即用户
# 截图的三个症状：只剩关闭按钮的标签、无标题的摘出窗口、无从点选的选择器条目）。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# The shell contract (guard shape: every host holder declares the narrow type).
# 外壳契约（守卫形态：凡持有宿主者一律声明窄类型）。
var gpHost: GPShellHost = null


# Static entry: file_coordinator calls this one-liner; the instance holds the contract.
# 静态入口：file_coordinator 一行调用；实例持有契约。
static func gpOpen(gpShell: GPShellHost, gpPath: String) -> void:
	var gpOpener: GPFreshOpen = GPFreshOpen.new()
	gpOpener.gpHost = gpShell
	gpOpener.gpRun(gpPath)


# The actual open sequence. / 实际开图序列。
func gpRun(gpPath: String) -> void:
	gpHost.gpCenter.gpLoadSheets([])
	gpHost.gpCenter.gpAddTab()
	# Same post-load refresh as the sheeted path in file_coordinator, minus graph-only
	# steps (drift reconcile needs content; a fresh graph has none).
	# 与 file_coordinator 带图纸路径相同的载入后刷新，仅省去纯图步骤（漂移调和需要
	# 内容；新图没有）。
	GPSymbolLibrary.gpSetDocSizeScale(1.0)
	gpHost.gpDefs = GPSymbolLibrary.gpDefaultDefs()
	gpHost.gpSyncInspectorDefs()
	gpHost.gpLeftDock.gpPopulate(gpHost.gpDefs)
	var gpCv: GPCanvas2D = gpHost.gpActiveCanvas()
	if gpCv != null:
		gpCv.gpDefs = gpHost.gpDefs
	# Swap the document manager onto the fresh graph (resets dirty, announces on the bus).
	# 文档管理器切到新图（重置脏标记并向总线通告）。
	gpHost.gpDocManager.gpSetGraph(gpHost.gpActiveGraph())
	gpHost.gpCurrentPath = gpPath
	# W14 identity hook — the EMPTY-archive path used to skip it entirely: no login gate
	# on multi-member rosters, no open lock (on-device gap 2026-11-18). Same one-liner
	# as the sheeted path in file_coordinator.
	# W14 身份钩子 —— 空工程通路此前**完全**跳过它：多成员名单不弹登录门、不上开档锁
	#（实机缺口 2026-11-18）。与 file_coordinator 带图纸路径同一行式。
	gpHost.gpIdentity.gpOnProjectLoaded(gpPath)
	gpHost.gpSetState("status.loaded_with_packs", [gpPath, 0])
