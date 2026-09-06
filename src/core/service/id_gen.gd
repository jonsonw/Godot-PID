class_name GPIdGen
extends RefCounted

## Id creation and id hygiene, in one place.
## id 生成与 id 规整，收敛到一处。
##
## Why it exists / 为何存在：
## three copies of the same logic used to live apart — `canvas_2d.gpNextId` (a bare counter
## owned by the canvas), `make_symbol_dialog._gpIdFromName` (name -> filesystem-safe id) and
## `_gpUniqueId` (dedupe against the library). W21 (multi-document) and W22 (off-page cross
## references) require ids that are unique across documents, so the counter cannot stay a
## private field of one Control.
## 同一逻辑此前分散三处：`canvas_2d.gpNextId`（画布私有的裸计数器）、
## `make_symbol_dialog._gpIdFromName`（名称 -> 文件系统安全 id）与 `_gpUniqueId`（与库去重）。
## W21（多文档）与 W22（跨图纸互引）要求 id 跨文档唯一，故计数器不能停留在某个 Control 的私有字段里。
##
## Two flavours, deliberately separated / 刻意区分的两种用法：
##  - static gpSanitize / gpEnsureUnique : pure id hygiene, no state  (stateless / 无状态)
##  - instance gpNext("n")               : a monotonic counter for runtime instance ids

# Fallback when the sanitized result is EMPTY (i.e. a blank name). A name that collapses to
# underscores ("___") is a valid non-empty id and does NOT fall back — matching the historic
# canvas behaviour where a bare "_" was an acceptable id.
# 仅当规整后「结果为空」（即名称为空白）时的兜底。折叠为下划线（"___"）的名称是合法的非空
# id，不触发回退 —— 与画布历史行为一致（裸 "_" 曾是可接受 id）。
const GP_FALLBACK: String = "symbol"


# ---- instance counter ----
# ---- 实例计数器 ----
# Next value to hand out. Starts at 1 so the first node is "n1", matching the historic
# behaviour of the canvas counter (0 was never used as an instance id).
# 下一个待发数值。从 1 开始，使首个节点为 "n1"，与画布计数器的历史行为一致（0 从未作为实例 id）。
var gpCounter: int = 1


# Return the next raw integer and advance the counter. Node and edge ids SHARE one counter
# (historic behaviour: after placing node "n1", the first edge is "e2"), so ids stay unique
# across both kinds without a per-prefix table.
# 返回下一个原始整数并推进计数器。节点与边 id 共用同一计数器（历史行为：放置节点 "n1" 后，
# 第一条边为 "e2"），因此无需分前缀表即可保证两类 id 互不相同。
func gpNextInt() -> int:
	var gpV: int = gpCounter
	gpCounter += 1
	return gpV


# Next id with the given prefix, e.g. gpNext("n") -> "n1".
# 带指定前缀的下一个 id，如 gpNext("n") -> "n1"。
func gpNext(gpPrefix: String) -> String:
	return "%s%d" % [gpPrefix, gpNextInt()]


# Restart the counter (used by File > New / Clear).
# 重置计数器（「文件 > 新建 / 清空」使用）。
func gpReset(gpStart: int = 1) -> void:
	gpCounter = gpStart


# ---- static hygiene ----
# ---- 静态规整 ----
# Filesystem-safe id from a human name: CJK is kept, everything else that is not
# [0-9A-Za-z_] collapses to "_". Returns GP_FALLBACK when nothing survives.
# 由人类可读名称生成文件系统安全 id：中文保留，其余非 [0-9A-Za-z_] 者折叠为 "_"。
# 全被折叠时返回 GP_FALLBACK。
#
# Keeping CJK matters here: P&ID users in this project name symbols in Chinese, and turning
# "离心泵" into "____" would make the pack filename meaningless.
# 保留中文很关键：本项目的 P&ID 用户以中文命名图元，把「离心泵」变成 "____" 会使包文件名失去意义。
static func gpSanitize(gpName: String) -> String:
	var gpOut: String = ""
	for gpI in range(gpName.length()):
		var gpC: String = gpName.substr(gpI, 1)
		var gpU: int = gpC.unicode_at(0)
		var gpCJK: bool = (gpU >= 0x3400 and gpU <= 0x4DBF) or (gpU >= 0x4E00 and gpU <= 0x9FFF)
		if gpCJK or (gpU >= 48 and gpU <= 57) or (gpU >= 65 and gpU <= 90) or (gpU >= 97 and gpU <= 122) or gpC == "_":
			gpOut += gpC
		else:
			gpOut += "_"
	if gpOut == "":
		gpOut = GP_FALLBACK
	return gpOut


# Deduplicate gpId against an existing-id predicate: appends "_2", "_3", ... until free.
# gpIsTaken must be a Callable taking a String and returning a bool, which lets the caller
# query a live library without materializing every id up front.
# 依「已被占用」谓词为 gpId 去重：追加 "_2"、"_3"…… 直到空闲。
# gpIsTaken 须是「接收 String、返回 bool」的 Callable，使调用方无需预先物化全部 id 即可查询活动库。
static func gpEnsureUnique(gpId: String, gpIsTaken: Callable) -> String:
	var gpCandidate: String = gpId
	var gpN: int = 2
	while bool(gpIsTaken.call(gpCandidate)):
		gpCandidate = "%s_%d" % [gpId, gpN]
		gpN += 1
	return gpCandidate


# Convenience overload: dedupe against a plain list of taken ids.
# 便捷重载：依「已占用 id 列表」去重。
static func gpEnsureUniqueIn(gpId: String, gpTaken: Array[String]) -> String:
	var gpCandidate: String = gpId
	var gpN: int = 2
	while gpTaken.has(gpCandidate):
		gpCandidate = "%s_%d" % [gpId, gpN]
		gpN += 1
	return gpCandidate
