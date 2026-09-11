class_name GPSheet
extends RefCounted

# One drawing sheet (tab) inside a project: an identity plus its own node/edge graph.
# 工程中的一张图纸（标签页）：一个标识 + 它自己的节点/边图。
# WHY A SEPARATE MODEL / 为何单独建模型：
# a multi-sheet P&ID is not one big graph, it is SEVERAL graphs that share a project's
# library and numbering rules. Modelling a sheet as a slice of one graph would force every
# cross-sheet edit to renumber global indices; modelling it as its own graph keeps each tab
# independently editable, which is how a drawing office actually works.
# 多图纸 P&ID 不是一张大图，而是**若干张**共享工程图元库与编号规则的图。
# 把图纸建模为一张图的分片，会迫使每次跨页编辑都重排全局索引；把它建模为各自的图，
# 则每个标签页都能独立编辑 —— 这正是设计院的实际工作方式。
# Project-level data (meta, tag_rules, embedded packs) lives on the CONTAINER, not here:
# one project has one set of numbering rules, however many sheets it has.
# 工程级数据（meta、tag_rules、内嵌图元包）位于**容器**而非此处：
# 一个工程只有一套编号规则，无论它有多少张图纸。
# See 持久化实现方案 §6 (v3 sheets[]) / 见「持久化实现方案」§6。
# Coding rule: every variable must declare its type explicitly. / 编码规范：变量显式类型。

# Stable sheet identity. Persisted so a re-open keeps the same id even if tabs are reordered.
# 稳定的图纸标识。持久化保存，使重新打开时即使标签重排也保持同一 id。
var gpId: String = ""

# Human-readable tab title. / 人类可读的标签标题。
var gpName: String = ""

# Position in the tab bar (0-based). Re-derived on load, so a gap never appears.
# 在标签栏中的位置（从 0 起）。载入时重新推导，故永不出现空位。
var gpIndex: int = 0

# The sheet's own geometry. Never null after gpFromDict.
# 本图纸自己的几何。经 gpFromDict 后绝不为 null。
var gpGraph: GPPIDGraph = null


# Serialize to the v3 sheet shape: {id, name, index, nodes, edges, shapes}.
# 序列化为 v3 的图纸形状：{id, name, index, nodes, edges, shapes}。
# Project-level keys (meta / tag_rules / packs) are deliberately NOT written here — they
# belong to the container, and duplicating them per sheet would let two sheets disagree
# about a project's numbering rules.
# 工程级键（meta / tag_rules / packs）刻意不写在此处 —— 它们属于容器，
# 每页各存一份会让两张图纸对工程的编号规则产生分歧。
func gpToDict() -> Dictionary:
	var gpG: Dictionary = {}
	if gpGraph != null:
		gpG = gpGraph.gpToDict()
	return {
		"id": gpId,
		"name": gpName,
		"index": gpIndex,
		"nodes": gpG.get("nodes", []),
		"edges": gpG.get("edges", []),
		"shapes": gpG.get("shapes", []),
	}


# Restore one sheet. Tolerates a sheet dict that carries no geometry at all.
# 还原一张图纸。容忍完全不含几何的图纸字典。
static func gpFromDict(gpD: Dictionary) -> GPSheet:
	var gpS: GPSheet = GPSheet.new()
	gpS.gpId = str(gpD.get("id", ""))
	gpS.gpName = str(gpD.get("name", ""))
	gpS.gpIndex = int(gpD.get("index", 0))
	# Build the graph from the sheet's own geometry only. tag_rules is added conditionally
	# because GPPIDGraph reads it by presence: passing an empty dict would fabricate a
	# default rule set and, worse, mark the project as "has rules" on the next save.
	# 仅用图纸自己的几何构建图。tag_rules 条件性加入，因为 GPPIDGraph 按**键是否存在**
	# 读取它：传空字典会凭空造出一套默认规则，更糟的是会让工程在下次保存时
	# 被标记为「有规则」。
	var gpGraphDict: Dictionary = {
		"meta": gpD.get("meta", {}),
		"nodes": gpD.get("nodes", []),
		"edges": gpD.get("edges", []),
		"shapes": gpD.get("shapes", []),
		"user_symbol_packs": gpD.get("user_symbol_packs", []),
	}
	if gpD.has("tag_rules"):
		gpGraphDict["tag_rules"] = gpD.get("tag_rules", {})
	gpS.gpGraph = GPPIDGraph.gpFromDict(gpGraphDict)
	return gpS


# Convenience: an empty sheet with the given identity.
# 便利方法：带给定标识的空图纸。
static func gpNew(gpId: String, gpName: String, gpIndex: int) -> GPSheet:
	var gpS: GPSheet = GPSheet.new()
	gpS.gpId = gpId
	gpS.gpName = gpName
	gpS.gpIndex = gpIndex
	gpS.gpGraph = GPPIDGraph.new()
	return gpS
