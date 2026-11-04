class_name GPOffPageLink
extends RefCounted

# A CONTAINER-LEVEL cross-sheet connection (ADR-43). One link is the single authority for
# "pipe/signal X continues on sheet N"; each sheet shows an off-page CONNECTOR symbol whose
# attrs only carry link_id — the connection itself is never stored inside a sheet.
# 一条**容器级**跨图纸连接（ADR-43）。link 是「某管线/信号在图纸 N 续接」的唯一权威；
# 每张图纸上的 Off-Page 连接符图元 attrs 只带 link_id —— 连接关系本身绝不存进任何一张图。
#
# WHY TWO LAYERS / 为何分两层：
# if the cross-sheet relation lived only in the connectors' attrs there would be no
# authority for attribute consistency, no cascade on delete, and DRC could not tell
# "unpaired" from "mispaired" (ADR-43 Context).
# 若跨图关系只存在连接符 attrs 里，属性一致性就没有裁判、删除就没有级联、
# DRC 也分不清「未配对」与「配错」（ADR-43 Context）。
#
# PERSISTENCE / 持久化：
# written under the HISTORIC container key "cross_links" (reserved by the multi-document
# era and already preserved by GPSchemaMigrate). New record shape {id, kind, a, b, tag?,
# attrs?}; the historic {from_doc, from_node, ...} shape is READ-TOLERATED as null (kept
# intact by the migration chain, but it has no live entity in v3 so it never enters the
# model). The key is written ONLY when links exist — earlier archives stay byte-stable.
# 写在历史预留的容器键 "cross_links" 下（多文档时代预留、GPSchemaMigrate 已保全）。
# 新记录形状 {id, kind, a, b, tag?, attrs?}；历史形状（from_doc/from_node/…）读取时容忍为
# null（迁移链原样保全，但 v3 里已无对应实体，故不进模型）。键仅在存在连接时写出 ——
# 更早的存档保持字节稳定。
# See ADR-43 / 见 ADR-43。Coding rule: explicit types everywhere. / 编码规范：全程显式类型。

# Reference keys, deliberately identical to GPPIDEdge's ref keys + a sheet dimension.
# 引用键，刻意与 GPPIDEdge 的引用键同名，仅多一个图纸维度。
const GP_KEY_SHEET: String = "sheet_id"
const GP_KEY_NODE: String = "node_id"
const GP_KEY_PORT: String = "port_id"

# The ONE props key a connector symbol carries (ADR-43 D3): the id of the link it stands for.
# Declared here so the symbol pack, the renderer, the print model and the future commands cannot
# spell it three different ways.
# 连接符图元携带的**唯一**属性键（ADR-43 D3）：它所代表的 link 的 id。在本类声明，使图元包、
# 渲染器、打印模型与后续命令不可能各拼出一种写法。
const GP_KEY_LINK_ID: String = "link_id"

# The attr key the flag's BELOW slot renders (user feedback 2026-11-03: the medium is
# INHERITED from the source line at link creation — GPCrossSheetCreateCommand seeds it from
# the edge's contract attrs). Declared here so the generator, the sync command and the props
# panel cannot spell it differently. The remaining contract keys (dn/spec/insulation/
# signal_type) stay plain strings in GPOffPageLink.GP_CONTRACT_KEYS — only keys a RENDERER
# reads earn a constant. (GP_ATTR_EQUIP_DESC was removed the same day: the ABOVE slot is now
# the DERIVED target tag — GPOffPageIndex.gpTargetTagFor — not a stored attribute.)
# 旗标**下**方槽位渲染的属性键（用户反馈 2026-11-03：介质在创建 link 时从源管线**继承**
# —— GPCrossSheetCreateCommand 从边的契约属性播种）。在本类声明，使生成器、同步命令与
# 属性面板不可能各拼出一种写法。其余契约键（dn/spec/insulation/signal_type）仍是
# GPOffPageLink.GP_CONTRACT_KEYS 里的普通字符串 —— 只有**渲染器会读**的键才配得上常量。
#（GP_ATTR_EQUIP_DESC 同日移除：**上**方槽位改为**推导**的目标端位号
# —— GPOffPageIndex.gpTargetTagFor —— 不再是存储属性。）
const GP_ATTR_MEDIUM: String = "medium"

# The contract fields the two ends must agree on (plan §2.5): synced by
# GPCrossSheetSyncCommand, compared three-way by GPOffPageAudit. Lives on the CORE model so
# the audit (core) and the command (app) cannot spell two lists.
# 两端必须一致的契约字段（方案 §2.5）：由 GPCrossSheetSyncCommand 同步、GPOffPageAudit
# 三方比对。放在 core 模型上，使审计（core）与命令（app）不可能各持一份名单。
const GP_CONTRACT_KEYS: Array[String] = ["dn", "medium", "spec", "insulation", "signal_type"]

# Instance id prefix for minting via GPIdGen (e.g. "xlink-1").
# 经 GPIdGen 铸号用的实例 id 前缀（如 "xlink-1"）。
const GP_ID_PREFIX: String = "xlink"

# Unique instance id, e.g. "xlink-1".
# 唯一实例 id，如 "xlink-1"。
var gpInstanceId: String = ""

# Link kind — reuses GPPIDEdge's mutually exclusive three-way split so an edge that walks
# INTO a connector and the link itself can never disagree on vocabulary.
# 连接类型 —— 复用 GPPIDEdge 的互斥三分，使「接入连接符的边」与 link 本身永不词表分叉。
var gpKind: String = GPPIDEdge.GP_PROCESS

# Endpoint A / B: {"sheet_id", "node_id", "port_id"}. node_id is the CONNECTOR symbol's
# instance id on that sheet (same vocabulary as an edge ref).
# 端点 A / B：{"sheet_id", "node_id", "port_id"}。node_id 是该图纸上连接符图元的实例 id
# （与边引用同词表）。
var gpA: Dictionary = {}
var gpB: Dictionary = {}

# Contract snapshot: the attributes BOTH ends must agree on. Written once at link creation
# (copied from the source edge); DRC compares edge attrs against this baseline (ADR-43 D5).
# 契约快照：两端必须一致的属性。创建 link 时从源边复制一次；DRC 以此为基准比对边属性
# （ADR-43 D5）。
var gpAttrs: Dictionary = {}

# Cross-reference number, auto-minted as "<peer sheet number>-<seq>" and freely editable
# (attrs["tag_manual"] marks a manual override, same convention as edge renumbering).
# 跨图连接编号：自动铸为「<对端图纸号>-<序号>」，可自由手改
# （attrs["tag_manual"] 标记手改，沿用边重编号的既有惯例）。
var gpTag: String = ""


# Stable sort by id so the container's array order is deterministic across saves
# (JSON.stringify orders object keys, but ARRAY order must be pinned by us).
# 按 id 稳定排序，使容器数组顺序在多次保存间确定（JSON.stringify 排对象键，
# 但**数组顺序**必须由我们自己钉住）。
static func gpCompareId(gpL: GPOffPageLink, gpR: GPOffPageLink) -> bool:
	return gpL.gpInstanceId < gpR.gpInstanceId


# One side of the link. / 取 link 的一端。
func gpRefFor(gpIsA: bool) -> Dictionary:
	return gpA if gpIsA else gpB


# Tolerant reader: NEW shape -> model; anything else (historic {from_doc,...} shape, junk,
# partial records) -> null so the caller can skip it. The migration chain keeps historic
# entries intact on disk; they simply have no live entity in v3.
# 容忍读取：新形状 -> 模型；其余（历史 {from_doc,…} 形状、垃圾、残缺记录）-> null，
# 由调用方跳过。迁移链在磁盘上保全历史条目，但它们在 v3 中已无对应实体。
static func gpFromDict(gpD: Dictionary) -> GPOffPageLink:
	var gpId: String = str(gpD.get("id", ""))
	if gpId.is_empty():
		return null
	# New shape requires at least one DICTIONARY endpoint; the historic shape has none.
	# 新形状要求至少一端是**字典**；历史形状没有。
	if not (gpD.get("a") is Dictionary) and not (gpD.get("b") is Dictionary):
		return null
	var gpOut: GPOffPageLink = GPOffPageLink.new()
	gpOut.gpInstanceId = gpId
	var gpKindIn: String = str(gpD.get("kind", GPPIDEdge.GP_PROCESS))
	# Tolerate a hand-edited kind: fall back to PROCESS rather than drifting out of the
	# shared three-way vocabulary.
	# 容忍手改的 kind：回落 PROCESS，而不让词表漂移出共享的三分。
	if gpKindIn != GPPIDEdge.GP_PROCESS and gpKindIn != GPPIDEdge.GP_UTILITY \
			and gpKindIn != GPPIDEdge.GP_SIGNAL:
		gpKindIn = GPPIDEdge.GP_PROCESS
	gpOut.gpKind = gpKindIn
	gpOut.gpA = _gpCleanRefRead(gpD.get("a", {}))
	gpOut.gpB = _gpCleanRefRead(gpD.get("b", {}))
	if gpD.get("attrs") is Dictionary:
		gpOut.gpAttrs = (gpD.get("attrs") as Dictionary).duplicate(true)
	gpOut.gpTag = str(gpD.get("tag", ""))
	return gpOut


# Serialise. Write policy mirrors the model layer's rules: id/kind/a/b always (a link
# without them is not a link), tag/attrs only when non-default — an untouched link with
# empty refs round-trips byte-stably.
# 序列化。写出策略沿用模型层规则：id/kind/a/b 恒写（缺了就不成其为 link），
# tag/attrs 仅非默认时写出 —— 未改动的空引用 link 往返保持字节稳定。
func gpToDict() -> Dictionary:
	var gpOut: Dictionary = {
		"id": gpInstanceId,
		"kind": gpKind,
		"a": _gpCleanRefWrite(gpA),
		"b": _gpCleanRefWrite(gpB),
	}
	if gpTag != "":
		gpOut["tag"] = gpTag
	if not gpAttrs.is_empty():
		gpOut["attrs"] = gpAttrs.duplicate(true)
	return gpOut


# Read-side ref cleaning: keep only the three known string keys, drop the rest — a
# hand-edited file cannot smuggle arbitrary keys into the model.
# 读取侧引用净化：只保留三个已知字符串键，其余丢弃 —— 手改文件无法把任意键带进模型。
static func _gpCleanRefRead(gpRaw: Variant) -> Dictionary:
	var gpOut: Dictionary = {}
	if not (gpRaw is Dictionary):
		return gpOut
	var gpD: Dictionary = gpRaw as Dictionary
	for gpKey in [GP_KEY_SHEET, GP_KEY_NODE, GP_KEY_PORT]:
		var gpVal: String = str(gpD.get(gpKey, ""))
		if gpVal != "":
			gpOut[gpKey] = gpVal
	return gpOut


# Write-side ref cleaning: same three keys, written ONLY when non-empty (byte-stability:
# a ref with no sheet_id yet — legal while a link is being built — stays absent).
# 写出侧引用净化：同样三个键，仅非空时写出（字节稳定：尚未填 sheet_id 的引用 ——
# 构建 link 期间合法 —— 保持缺席）。
static func _gpCleanRefWrite(gpRef: Dictionary) -> Dictionary:
	var gpOut: Dictionary = {}
	for gpKey in [GP_KEY_SHEET, GP_KEY_NODE, GP_KEY_PORT]:
		var gpVal: String = str(gpRef.get(gpKey, ""))
		if gpVal != "":
			gpOut[gpKey] = gpVal
	return gpOut
