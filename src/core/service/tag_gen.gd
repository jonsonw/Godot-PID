class_name GPTagGen
extends RefCounted
# Copyright © 2026 Jonson Wang
# Monotonic, never-recycled process tag allocator (e.g. PL-1001, PL-1002 ...).
# 单调递增、绝不回收的工艺位号分配器（如 PL-1001、PL-1002 ...）。
#
# Why not GPIdGen / 为何不用 GPIdGen：
#   GPIdGen's counter is shared by nodes and edges and is reset by File > New. A pipe number
#   must survive a save/load round trip and must NEVER be reused after a delete — otherwise two
#   different pipes in the project's history carry the same number, which is a drafting defect,
#   not a cosmetic one. So the high-water marks live in gpGraph.gpMeta and travel with the file.
#   GPIdGen 的计数器由节点与边共用，且「文件 > 新建」会重置它。而管道号必须经存/读往返存活，
#   且删除后绝不重用 —— 否则工程历史里两条不同管线同号，这是制图缺陷而非外观问题。
#   因此水位线落在 gpGraph.gpMeta，随文件一同旅行。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Where the per-prefix high-water marks live inside gpGraph.gpMeta.
# 各前缀水位线在 gpGraph.gpMeta 中的落点。
const GP_META_KEY: String = "tag_seq"

# First number handed out is GP_BASE + 1, i.e. PL-1001.
# 首个发出的号是 GP_BASE + 1，即 PL-1001。
const GP_BASE: int = 1000

# Default prefix for a pipe line. / 管道线的默认前缀。
const GP_PIPE_PREFIX: String = "PL"

# Guard against a pathological archive whose gpMeta was hand-edited into an endless loop.
# 防止 gpMeta 被手改成死循环的病态存档。
const GP_MAX_SKIPS: int = 100000


# Allocate the next tag for a prefix and persist the new high-water mark into gpMeta.
# 为某前缀分配下一个位号，并把新水位线持久化进 gpMeta。
# Skips numbers already taken by an existing edge, which covers the case where the user
# hand-typed "PL-1005" before the counter got there.
# 跳过已被现有边占用的号，覆盖「用户在计数器走到之前手打了 PL-1005」的情况。
static func gpNextTag(gpGraph: GPPIDGraph, gpPrefix: String = GP_PIPE_PREFIX) -> String:
	if gpGraph == null:
		return ""
	var gpSeq: Dictionary = gpGraph.gpMeta.get(GP_META_KEY, {}) as Dictionary
	var gpN: int = int(gpSeq.get(gpPrefix, GP_BASE))
	var gpTaken: Dictionary = {}
	for gpE in gpGraph.gpEdges:
		if gpE.gpTag != "":
			gpTaken[gpE.gpTag] = true
	var gpCandidate: String = ""
	var gpSkips: int = 0
	while gpSkips < GP_MAX_SKIPS:
		gpN += 1
		gpCandidate = "%s-%d" % [gpPrefix, gpN]
		if not gpTaken.has(gpCandidate):
			break
		gpSkips += 1
	gpSeq[gpPrefix] = gpN
	gpGraph.gpMeta[GP_META_KEY] = gpSeq
	return gpCandidate


# Current high-water mark (for tests and for the future "renumber" dialog).
# 当前水位线（供测试与将来的「重新编号」对话框使用）。
static func gpPeek(gpGraph: GPPIDGraph, gpPrefix: String = GP_PIPE_PREFIX) -> int:
	if gpGraph == null:
		return GP_BASE
	var gpSeq: Dictionary = gpGraph.gpMeta.get(GP_META_KEY, {}) as Dictionary
	return int(gpSeq.get(gpPrefix, GP_BASE))


# Whether a tag is already used by another edge (gpExcludeId is the edge being edited).
# 某位号是否已被其他边占用（gpExcludeId 为正在编辑的那条边）。
static func gpIsTaken(gpGraph: GPPIDGraph, gpTag: String, gpExcludeId: String = "") -> bool:
	if gpGraph == null or gpTag == "":
		return false
	for gpE in gpGraph.gpEdges:
		if gpE.gpInstanceId == gpExcludeId:
			continue
		if gpE.gpTag == gpTag:
			return true
	return false
