extends "res://tests/gp_test.gd"
# A2 (W12 closure plan §4.2): the GPOffPageStore mutation funnel.
# A2（W12 收口方案 §4.2）：GPOffPageStore 变更汇流口。
#
# Failure modes being guarded against: (1) a mutation path that does NOT notify — the D03
# root cause "screen right / file not dirty"; (2) gpReplaceAll swapping the ARRAY instead
# of its contents, which would orphan every command/provider that captured the live table
# by reference; (3) a copy sneaking into gpLinks() so a provider reads a stale snapshot;
# (4) null links crashing the signal-driven path instead of being skipped.
# 所防范的失效模式：(1) 某条变更路径不通知 —— D03 病根「显示对了 / 文件没脏」；
# (2) gpReplaceAll 换掉**数组**而非其内容，使按引用捕获活表的每条命令/来源变成孤儿；
# (3) 副本混进 gpLinks()，使来源读到过期快照；(4) null link 在信号驱动路径里崩溃而非被跳过。


# A fresh store bound to a live array, plus a signal recorder.
# 绑定到活数组的新 store，外加一个信号记录器。
func _gpRig() -> Dictionary:
	var gpStore: GPOffPageStore = GPOffPageStore.new()
	var gpLinks: Array[GPOffPageLink] = []
	gpStore.gpSetup(gpLinks)
	var gpReasons: Array[String] = []
	gpStore.gpChanged.connect(func(gpReason: String) -> void: gpReasons.append(gpReason))
	return {"store": gpStore, "links": gpLinks, "reasons": gpReasons}


func _gpLink(gpId: String) -> GPOffPageLink:
	var gpL: GPOffPageLink = GPOffPageLink.new()
	gpL.gpInstanceId = gpId
	return gpL


# gpSetup binds by reference: writes through the store are visible in the container's array.
# gpSetup 按引用绑定：经 store 的写入在容器数组里可见。
func gpTestStoreSetupBindsByReference() -> void:
	var gpRig: Dictionary = _gpRig()
	var gpStore: GPOffPageStore = gpRig["store"]
	var gpLinks: Array[GPOffPageLink] = gpRig["links"]
	gpStore.gpAdd(_gpLink("L1"))
	gpEq(gpLinks.size(), 1, "container array sees the store's add / 容器数组看到 store 的追加")
	gpEq(gpStore.gpLinks().size(), 1, "store reads the same size / store 读到同一尺寸")
	# identity, not a copy / 是身份，不是副本
	gpCheck(gpStore.gpLinks() == gpLinks, "gpLinks() returns the LIVE array / gpLinks() 返回活数组")


# gpAdd notifies exactly once with reason "add"; null is a silent no-op.
# gpAdd 以 add 通知恰好一次；null 是静默空操作。
func gpTestAddNotifiesOnceAndSkipsNull() -> void:
	var gpRig: Dictionary = _gpRig()
	var gpStore: GPOffPageStore = gpRig["store"]
	gpStore.gpAdd(_gpLink("L1"))
	gpStore.gpAdd(null)
	var gpReasons: Array[String] = gpRig["reasons"]
	gpEq(gpReasons.size(), 1, "null add must not notify / null 追加不得通知")
	gpEq(gpReasons[0], "add", "reason is add / 原因是 add")


# gpRemove removes the first occurrence, notifies "remove" only when something left.
# gpRemove 移除第一处命中，仅在确实移除时以 remove 通知。
func gpTestRemoveNotifiesOnlyOnHit() -> void:
	var gpRig: Dictionary = _gpRig()
	var gpStore: GPOffPageStore = gpRig["store"]
	var gpL1: GPOffPageLink = _gpLink("L1")
	gpStore.gpAdd(gpL1)
	gpEq(gpStore.gpRemove(_gpLink("L9")), false, "unknown link is not removed / 未知 link 不移除")
	gpEq(gpStore.gpRemove(null), false, "null remove is refused / null 移除被拒绝")
	gpEq((gpRig["reasons"] as Array[String]).size(), 1, "failed removes stay silent / 失败的移除保持沉默")
	gpEq(gpStore.gpRemove(gpL1), true, "known link removed / 已知 link 被移除")
	gpEq(gpStore.gpLinks().size(), 0, "table empty again / 表再次为空")
	gpEq(gpRig["reasons"].size(), 2, "one hit notified / 一次命中通知一次")
	gpEq((gpRig["reasons"] as Array[String])[1], "remove", "reason is remove / 原因是 remove")


# THE regression pin for gpReplaceAll: contents swap in place, array IDENTITY survives,
# so an earlier capture keeps seeing the truth (the old gpSetOffPageLinks reassigned the
# member — every earlier capture became an orphan).
# gpReplaceAll 的**回归钉**：内容原地替换、数组身份不变，早前的捕获继续看到真相
#（旧 gpSetOffPageLinks 直接重赋成员 —— 每个早前的捕获都成了孤儿）。
func gpTestReplaceAllKeepsArrayIdentity() -> void:
	var gpRig: Dictionary = _gpRig()
	var gpStore: GPOffPageStore = gpRig["store"]
	var gpLinks: Array[GPOffPageLink] = gpRig["links"]
	gpStore.gpAdd(_gpLink("L1"))
	# An earlier capture, as a command would hold / 一次早前捕获，如同命令所持有
	var gpCaptured: Array[GPOffPageLink] = gpLinks
	var gpFresh: Array[GPOffPageLink] = [_gpLink("L2"), _gpLink("L3")]
	gpStore.gpReplaceAll(gpFresh)
	gpEq(gpStore.gpLinks().size(), 2, "store shows the new contents / store 显示新内容")
	gpEq(gpLinks.size(), 2, "container array swapped in place / 容器数组原地换新")
	gpEq(gpCaptured.size(), 2, "EARLIER capture sees the new contents too / 早前捕获同样看到新内容")
	gpEq(gpCaptured[0].gpInstanceId, "L2", "first entry is L2 / 首条是 L2")
	gpCheck(gpStore.gpLinks() == gpLinks, "array identity survived the replace / 数组身份在替换后不变")
	gpEq(gpRig["reasons"].size(), 2, "replace notified once more / replace 再通知一次")
	gpEq((gpRig["reasons"] as Array[String])[1], "replace", "reason is replace / 原因是 replace")
	# null entries in the incoming list are dropped defensively / 入参中的 null 被防御性丢弃
	var gpWithNull: Array[GPOffPageLink] = [_gpLink("L4"), null]
	gpStore.gpReplaceAll(gpWithNull)
	gpEq(gpStore.gpLinks().size(), 1, "null entries dropped / null 条目被丢弃")


# gpTouch is the raw funnel: it emits verbatim (undo/redo settlements use "history").
# gpTouch 是裸汇流口：原样发射（撤销/重做落定使用 history）。
func gpTestTouchEmitsVerbatim() -> void:
	var gpRig: Dictionary = _gpRig()
	var gpStore: GPOffPageStore = gpRig["store"]
	gpStore.gpTouch()
	gpStore.gpTouch("history")
	var gpReasons: Array[String] = gpRig["reasons"]
	gpEq(gpReasons.size(), 2, "two touches, two emissions / 两次 touch 两次发射")
	gpEq(gpReasons[0], "attr", "default reason is attr / 默认原因是 attr")
	gpEq(gpReasons[1], "history", "verbatim reason passes through / 原样原因透传")


# Integration: edit_service touches the store after a successful cross-sheet create.
# 集成：edit_service 在跨图纸创建成功后 touch store。
func gpTestEditServiceTouchesStoreOnCreate() -> void:
	var gpLocal: GPPIDGraph = GPPIDGraph.new()
	var gpN: GPPIDNode = gpLocal.gpNewNode("n1", "PUMP001", "P-101", Vector2(100, 100), {})
	gpLocal.gpAddNode(gpN)
	var gpSvc: GPEditService = GPEditService.new()
	var gpIds: GPIdGen = GPIdGen.new()
	gpSvc.gpBindGraph(gpLocal, gpIds)
	var gpLinks: Array[GPOffPageLink] = []
	var gpStore: GPOffPageStore = GPOffPageStore.new()
	gpStore.gpSetup(gpLinks)
	gpSvc.gpLinkStore = gpStore
	var gpReasons: Array[String] = []
	gpStore.gpChanged.connect(func(gpReason: String) -> void: gpReasons.append(gpReason))
	var gpLinkId: String = gpSvc.gpCrossSheetCreate(
		{"node_id": "n1", "port_id": "out"}, GPPIDEdge.GP_PROCESS, "", false,
		Vector2(30, 40), Vector2(50, 60), "sheet-1", "sheet-2", "7",
		gpLocal, gpLinks)
	gpCheck(gpLinkId != "", "create succeeded / 创建成功")
	gpEq(gpLinks.size(), 1, "link table grew / link 表增长")
	gpEq(gpReasons.size(), 1, "store notified exactly once / store 通知恰好一次")
	gpEq(gpReasons[0], "add", "reason is add / 原因是 add")
	var gpLink: GPOffPageLink = gpLinks[0]
	# Unlink #1 succeeds and notifies; unlink #2 is refused by the command's redo guard
	# (the link is already gone) and stays SILENT — no link, no touch.
	# 第一次断开成功并通知；第二次被命令的重做守卫拒绝（link 已不在表中）并保持沉默 ——
	# 无 link 无 touch。
	gpCheck(gpSvc.gpUnlinkOffPage(gpLink, gpLinks, gpLocal, gpLocal),
		"first unlink succeeded / 第一次断开成功")
	gpEq(gpLinks.size(), 0, "link left the table / link 离开了表")
	gpEq(gpReasons.size(), 2, "add + remove each notified once / add 与 remove 各通知一次")
	gpCheck(not gpSvc.gpUnlinkOffPage(gpLink, gpLinks, gpLocal, gpLocal),
		"second unlink refused / 第二次断开被拒")
	gpEq(gpReasons.size(), 2, "refusal did not notify / 拒绝不通知")


# Undo/redo settlement: the history signal route calls gpOnCrossSheetHistory on the
# center area — modeled here at the store level as a "history" touch, which is the same
# funnel the center handler feeds. What must NOT happen: an undo leaving the store silent.
# 撤销/重做落定：历史信号路由调用 center 的 gpOnCrossSheetHistory —— 这里在 store 层以
# history touch 建模，与 center 处理器喂的是同一汇流口。绝不允许的是：撤销让 store 沉默。
func gpTestUnlinkTouchesStore() -> void:
	var gpLocal: GPPIDGraph = GPPIDGraph.new()
	var gpN: GPPIDNode = gpLocal.gpNewNode("n1", "PUMP001", "P-101", Vector2(100, 100), {})
	gpLocal.gpAddNode(gpN)
	var gpSvc: GPEditService = GPEditService.new()
	var gpIds: GPIdGen = GPIdGen.new()
	gpSvc.gpBindGraph(gpLocal, gpIds)
	var gpLinks: Array[GPOffPageLink] = []
	var gpStore: GPOffPageStore = GPOffPageStore.new()
	gpStore.gpSetup(gpLinks)
	gpSvc.gpLinkStore = gpStore
	var gpReasons: Array[String] = []
	gpStore.gpChanged.connect(func(gpReason: String) -> void: gpReasons.append(gpReason))
	var gpLinkId: String = gpSvc.gpCrossSheetCreate(
		{"node_id": "n1", "port_id": "out"}, GPPIDEdge.GP_PROCESS, "", false,
		Vector2(30, 40), Vector2(50, 60), "sheet-1", "sheet-2", "7",
		gpLocal, gpLinks)
	var gpLink: GPOffPageLink = gpLinks[0]
	gpCheck(gpSvc.gpUnlinkOffPage(gpLink, gpLinks, gpLocal, gpLocal),
		"unlink succeeded / 断开成功")
	gpEq(gpLinks.size(), 0, "link left the table / link 离开了表")
	gpEq(gpReasons.size(), 2, "create + unlink each notified once / 创建与断开各通知一次")
	gpEq(gpReasons[1], "remove", "unlink reason is remove / 断开原因是 remove")
	# Undo restores the link — and the undo path is exercised through the stack directly
	# (headless test), so it must NOT have burned an extra touch here; the shell's history
	# signal carries the settlement instead (gpOnCrossSheetHistory).
	# 撤销恢复 link —— 撤销路径经栈直驱（headless 测试），故此处**不得**多烧一次 touch；
	# 落定由外壳的历史信号承载（gpOnCrossSheetHistory）。
	gpSvc.gpStack.gpUndo(gpSvc.gpCtx)
	gpEq(gpLinks.size(), 1, "undo restored the link / 撤销恢复了 link")
	gpEq(gpReasons.size(), 2, "undo does not double-notify here / 撤销在此不多发通知")
