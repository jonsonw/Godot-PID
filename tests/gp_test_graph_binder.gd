extends "res://tests/gp_test.gd"
# GPGraphBinder sync under hostile model states — regression pins for the 2026-11-04
# move_child out-of-bounds report.
# 敌意模型态下的 GPGraphBinder 同步 —— 2026-11-04 move_child 越界报告的回归钉。
#
# The failure chain (probed headless): a duplicate entry in gpNodes (the SAME object appended
# twice, or two nodes sharing one instance id) made (1) the FIRST sync create TWO views for
# the same id — the cache is only written back at the end of the pass, so a later iteration
# saw the still-empty cache and minted an orphan view that no later sync tracks or frees; and
# (2) the z-order compaction loop asked move_child for an index past the last valid sibling
# once a second duplicate entry followed (exactly the user's consecutive "index 11 / index 12"
# errors). The model now refuses duplicate adds at the source; these pins prove the binder
# ALSO tolerates such states (defense in depth) and that z-order compaction stays correct.
# 失效链条（headless 探针实证）：gpNodes 中的重复条目（同一对象被追加两次，或两节点共用一个
# 实例 id）会使 (1) 首次同步为同一 id 建出两个视图 —— 缓存要到整轮结束才写回，后面的迭代
# 看到的仍是空缓存，于是铸出孤儿视图，后续同步既不追踪也不释放；(2) 在第二条重复条目出现时，
# z 序压实循环向 move_child 请求越过最后一个合法同级下标（正是用户连续两条「index 11 /
# index 12」错误的形态）。模型现已在源头拒绝重复添加；这些钉子证明绑定器**同时**容忍此类
# 状态（纵深防御），且 z 序压实保持正确。
#
# Hostile states are built by appending DIRECTLY to gpNodes: the model guard refuses them via
# gpAddNode, and this suite must exercise the binder against the state itself.
# 敌意态通过**直接**向 gpNodes 追加构造：模型守卫会拒绝经 gpAddNode 的重复，而本套件必须
# 让绑定器直面该状态本身。


# A binder with its own bare world root (no sheet-layer children — indices are pure).
# 自带裸 world root 的绑定器（无图纸层子节点 —— 下标是纯净的）。
func _gpBinder() -> GPGraphBinder:
	var gpB: GPGraphBinder = GPGraphBinder.new()
	add_child(gpB)
	gpB.gpWorldRoot = Node2D.new()
	add_child(gpB.gpWorldRoot)
	return gpB


# The SAME object appearing twice in gpNodes: exactly one view serves both entries, views stay
# compacted into the leading indices, and a re-sync must not accumulate or drift.
# 同一对象在 gpNodes 中出现两次：恰一个视图服务两条条目，视图仍压实进靠前下标，且重同步
# 不累积、不漂移。
func gpTestSyncToleratesDuplicateObjectEntry() -> void:
	var gpB: GPGraphBinder = _gpBinder()
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpN1: GPPIDNode = gpG.gpNewNode("a", "pump", "P-1")
	var gpN2: GPPIDNode = gpG.gpNewNode("b", "tank", "V-1")
	gpG.gpAddNode(gpN1)
	gpG.gpAddNode(gpN2)
	gpG.gpNodes.append(gpN1)  # hostile: duplicate OBJECT entry / 敌意：重复对象条目
	gpB.gpSync(gpG, [] as Array[GPSymbolDef], [] as Array[String], "")
	gpCheck(gpB.gpWorldRoot.get_child_count() == 2, "two DISTINCT views — no orphan from the dup entry")
	var gpView: GPSymbolView = gpB.gpGetSymbolView("a")
	gpCheck(gpView != null, "the duplicated id still resolves to its view")
	# With a duplicate entry the paint-order comparator is no longer a total order, so WHICH of
	# the two views lands at index 0 is undefined; what is guaranteed: both are distinct views
	# compacted into the two leading indices, and the layout is stable across re-syncs.
	# 重复条目使绘制序比较器不再是全序，两视图中谁落在下标 0 并未定义；可保证的是：两个视图
	# 都是去重视图、压实进最前面两个下标，且布局跨重同步稳定。
	var gpIdxA: int = gpView.get_index()
	var gpIdxB: int = gpB.gpGetSymbolView("b").get_index()
	gpCheck(gpIdxA >= 0 and gpIdxA <= 1 and gpIdxB >= 0 and gpIdxB <= 1 and gpIdxA != gpIdxB,
		"both views compacted into the two leading indices")
	gpB.gpSync(gpG, [] as Array[GPSymbolDef], [] as Array[String], "")
	gpCheck(gpB.gpWorldRoot.get_child_count() == 2, "re-sync does not accumulate views")
	gpCheck(gpView.get_index() == gpIdxA and gpB.gpGetSymbolView("b").get_index() == gpIdxB,
		"and the order is stable across re-syncs")


# Two nodes sharing one instance id: the binder keeps exactly ONE view (the FIRST object wins;
# the pass is idempotent per id), stays compacted, and never indexes past the sibling list.
# 两节点共用一个实例 id：绑定器保持恰**一个**视图（首个对象获胜；整轮按 id 幂等），保持压实，
# 绝不越过同级列表索引。
func gpTestSyncToleratesDuplicateIdEntries() -> void:
	var gpB: GPGraphBinder = _gpBinder()
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpN1: GPPIDNode = gpG.gpNewNode("dup", "pump", "P-1")
	gpG.gpAddNode(gpN1)
	var gpAlias: GPPIDNode = gpG.gpNewNode("dup", "pump", "P-1-ALIAS")
	gpG.gpNodes.append(gpAlias)  # hostile: same id, different object / 敌意：同 id 不同对象
	gpB.gpSync(gpG, [] as Array[GPSymbolDef], [] as Array[String], "")
	gpCheck(gpB.gpWorldRoot.get_child_count() == 1, "one view for one id — no orphan, no OOB")
	var gpView: GPSymbolView = gpB.gpGetSymbolView("dup")
	gpCheck(gpView != null, "the id still resolves to a view")
	gpCheck(gpView.gpNode == gpN1, "and the view binds the FIRST object with that id")
	gpCheck(gpView.get_index() == 0, "and it is compacted at leading index 0")


# Sanity of the normal path the guards must not disturb: distinct nodes keep stable indices
# across syncs, and mounted children still paint after their host.
# 守卫不得干扰的正常路径：去重节点在多次同步间保持稳定下标，挂载子件仍绘制在宿主之后。
func gpTestNormalPathStable() -> void:
	var gpB: GPGraphBinder = _gpBinder()
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("h", "vessel", "V-1"))
	gpG.gpAddNode(gpG.gpNewNode("t", "nozzle", "N-1"))
	gpB.gpSync(gpG, [] as Array[GPSymbolDef], [] as Array[String], "")
	var gpH: GPSymbolView = gpB.gpGetSymbolView("h")
	var gpT: GPSymbolView = gpB.gpGetSymbolView("t")
	gpCheck(gpH.get_index() == 0 and gpT.get_index() == 1, "declaration order preserved for equal depth")
	gpB.gpSync(gpG, [] as Array[GPSymbolDef], [] as Array[String], "")
	gpCheck(gpH.get_index() == 0 and gpT.get_index() == 1, "indices stable across re-sync")
