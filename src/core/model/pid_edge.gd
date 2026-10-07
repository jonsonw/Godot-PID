class_name GPPIDEdge
extends RefCounted

# A connection between two ports (port-to-port).
# 一条连接（端口到端口）。
# See Dev Guide §4.5 and 从零落地架构_分步实施.md Step 1.2.
# 见开发指南 §4.5 与「从零落地架构_分步实施.md」Step 1.2。

# Unique instance id, e.g. "e-1"
# 唯一实例 id，如 "e-1"
var gpInstanceId: String = ""

# Reference to the source port: {"node_id": String, "port_id": String}
# 起点端口引用：{"node_id": 节点 id, "port_id": 端口 id}
var gpFromRef: Dictionary = {}

# Reference to the destination port: {"node_id": String, "port_id": String}
# 终点端口引用：{"node_id": 节点 id, "port_id": 端口 id}
var gpToRef: Dictionary = {}

# ---- edge kind (a mutually exclusive three-way split) ----
# ---- 连线类型（互斥三分）----
# PROCESS : 主工艺管线，粗实线 / main process line, thick solid
# UTILITY : 公用工程管线，细实线（与主管线仅靠线宽区分）/ utility line, thin solid
# SIGNAL : 仪表 / 电气控制信号线，线型由 gpSignalType 决定 / signal line, pattern from gpSignalType
# Why one field and not kind + service: the three states are mutually exclusive, so two fields
# would admit three illegal combinations and fork the archive schema.
# 为何只用一个字段而非 kind + service：三种状态互斥，两个字段会放行三种非法组合并使存档 schema 分叉。
const GP_PROCESS: String = "PROCESS"
const GP_UTILITY: String = "UTILITY"
const GP_SIGNAL: String = "SIGNAL"

# Edge kind: PROCESS / UTILITY / SIGNAL.
# 连线类型：PROCESS（主工艺）/ UTILITY（公用工程）/ SIGNAL（信号）。
var gpKind: String = "PROCESS"

# Signal medium — only meaningful when gpKind == GP_SIGNAL; "" for pipes.
# 信号类型 —— 仅当 gpKind == GP_SIGNAL 时有意义；管道为 ""。
# ELECTRIC 电气 / PNEUMATIC 气动 / HYDRAULIC 液压 / DATA（DCS 软连接）/ CAPILLARY 毛细管。
var gpSignalType: String = ""

# Whether this edge is auto-routed orthogonally. A Shift-drawn straight edge stores false.
# 本边是否走正交自动布线。按 Shift 画出的直线存 false。
var gpOrtho: bool = true

# Intermediate waypoints ONLY (world coordinates) — the two ENDPOINTS are never stored here.
# 仅中间拐点（世界坐标）—— 两个端点从不存于此。
# Endpoints are resolved live from the port refs by GPPortResolver, so moving a symbol drags
# its pipe ends along without touching gpRouting. Storing endpoints here would freeze them at
# the moment of drawing and tear the pipe away from its symbol the first time it is moved.
# 端点由 GPPortResolver 依端口引用实时解析，故移动图元时管线端点自动跟随，无需改动 gpRouting。
# 若把端点存于此，它们会冻结在绘制那一刻，图元第一次被移动时管线就会与图元脱开。
# Empty means "let GPEdgeRoute compute an L/Z path from the two port normals".
# 为空表示「由 GPEdgeRoute 依两端口法线自动生成 L/Z 路径」。
var gpRouting: Array[Vector2] = []

# Process tag, e.g. "PL-201"
# 工艺位号，如 "PL-201"
var gpTag: String = ""

# Extra attributes. Well-known keys (documented so the inspector and list export agree):
# 附加属性。约定键（写在注释里，使属性面板与清单导出一致）：
# "dn" 公称直径 / "medium" 介质代号 / "spec" 管道等级 / "insulation" 保温等级（管道）
# "tag_manual" 位号被手工改过（全图重编号时跳过）
# "show_arrow" 是否画流向箭头（管道默认 true）/ "show_tag" 是否画位号（信号线默认 false）
# "tag_offset" 位号手工拖拽偏移 [dx, dy]（世界单位 mm）；零即删除该键（见 gpSetTagOffset）。
#             引出线由净距推导（GPEdgeTagLayout.gpLeader），不落盘。
# "broken_from" / "broken_to" 由坏边自愈写入，见 gpFromDict()
var gpAttrs: Dictionary = {}

# A manual tag offset below this many millimetres is treated as "no offset" and the key is
# erased. The drag path writes continuous floats, so "the user dragged it back onto the pipe"
# arrives as 0.03 rather than an exact zero — without this the file would accumulate a residue
# entry that means nothing.
# 小于此毫米数的手工位号偏移视为「无偏移」并删除该键。拖拽路径写入的是连续浮点数，故
# 「用户把它拖回管线上了」到达时是 0.03 而非精确的零 —— 缺此判断，文件会累积一条毫无意义的残留记录。
const GP_TAG_OFFSET_EPS: float = 0.05


# Manual drag offset of the line number, in world units (mm). Vector2.ZERO means "leave it on
# the automatic placement", which is also what a number that was never dragged stores.
# 管线号的手工拖拽偏移，世界单位（mm）。Vector2.ZERO 意为「留在自动落位处」，也是从未被拖动过的
# 编号所存的值。
# Tolerant of a hand-edited file: anything that is not a 2-element array is read as "no offset"
# rather than crashing or producing a half-valid vector.
# 对手工编辑过的文件容错：任何非「两元素数组」的取值都读作「无偏移」，既不崩溃也不产生半有效向量。
func gpTagOffset() -> Vector2:
	if not gpAttrs.has("tag_offset"):
		return Vector2.ZERO
	var gpRaw: Variant = gpAttrs["tag_offset"]
	if gpRaw is Vector2:
		return gpRaw
	if gpRaw is Array and (gpRaw as Array).size() >= 2:
		return Vector2(float(gpRaw[0]), float(gpRaw[1]))
	return Vector2.ZERO


# Set the manual drag offset. A (near) zero offset REMOVES the key instead of storing [0, 0], so
# a number dragged back onto its pipe leaves no residue and an untouched sheet keeps serialising
# byte-for-byte as it did before this feature existed.
# 设置手工拖拽偏移。（近）零偏移**删除**该键而非存 [0, 0]，故被拖回管线上的编号不留残留，
# 未被动过的图纸也保持与本功能存在之前逐字节相同的序列化结果。
func gpSetTagOffset(gpOffset: Vector2) -> void:
	if gpOffset.length() < GP_TAG_OFFSET_EPS:
		gpAttrs.erase("tag_offset")
		return
	gpAttrs["tag_offset"] = [gpOffset.x, gpOffset.y]


# Whether the given end is a free-floating point rather than a port bound to a node.
# 指定端（true 表示起点）是否为自由悬空点，而非绑定到某节点的端口。
# A pipe is allowed to dangle at one end ("continues off-sheet / to be connected later").
# 管道允许一端悬空（「延续到他页 / 待接」）。
func gpIsDangling(gpIsFrom: bool) -> bool:
	var gpRef: Dictionary = gpFromRef if gpIsFrom else gpToRef
	return str(gpRef.get("node_id", "")) == "" and gpRef.has("point")


# World position of a dangling end; Vector2.INF when the end is not dangling.
# 悬空端的世界坐标；该端非悬空时返回 Vector2.INF。
func gpDanglingPoint(gpIsFrom: bool) -> Vector2:
	var gpRef: Dictionary = gpFromRef if gpIsFrom else gpToRef
	var gpP: Array = gpRef.get("point", [])
	if gpP.size() < 2:
		return Vector2.INF
	return Vector2(float(gpP[0]), float(gpP[1]))


# Move a dangling end. No-op when the end is bound to a node.
# 移动悬空端。该端绑定到节点时不做任何事。
func gpSetDanglingPoint(gpIsFrom: bool, gpPos: Vector2) -> void:
	var gpRef: Dictionary = gpFromRef if gpIsFrom else gpToRef
	if str(gpRef.get("node_id", "")) != "":
		return
	gpRef["port_id"] = ""
	gpRef["point"] = [gpPos.x, gpPos.y]


# Serialize this edge to a plain dictionary (object graph -> dict graph).
# 将本边序列化为普通字典（对象图 → 字典图）。
# The shape matches the historic multi-document form so JSON stays forward-compatible.
# 该形状与历史多文档形态一致，保证 JSON 向前兼容。
func gpToDict() -> Dictionary:
	var gpRoutingOut: Array = []
	for gpP in gpRouting:
		gpRoutingOut.append([gpP.x, gpP.y])
	return {
		"instance_id": gpInstanceId,
		"from_ref": gpFromRef.duplicate(),
		"to_ref": gpToRef.duplicate(),
		"kind": gpKind,
		"signal_type": gpSignalType,
		"ortho": gpOrtho,
		"routing": gpRoutingOut,
		"tag": gpTag,
		"attrs": gpAttrs.duplicate(),
	}


# Restore this edge from a dictionary (inverse of gpToDict()).
# 从字典还原本边（gpToDict() 的逆操作）。
# Tolerant of the old dictionary-graph shape (id/from/to/attrs) so legacy
# *.pid.json files still load.
func gpFromDict(gpD: Dictionary) -> void:
	gpInstanceId = gpD.get("instance_id", gpD.get("id", ""))
	# New object-graph shape: port-to-port refs.
	# 新对象图形状：端口到端口引用。
	gpFromRef = gpD.get("from_ref", {})
	if gpFromRef.is_empty():
 # Old dictionary-graph shape: node-to-node ids.
 # 旧字典图形状：节点到节点 id。
		gpFromRef = {"node_id": gpD.get("from", ""), "port_id": ""}
	gpToRef = gpD.get("to_ref", {})
	if gpToRef.is_empty():
		gpToRef = {"node_id": gpD.get("to", ""), "port_id": ""}
	gpKind = gpD.get("kind", "PROCESS")
	gpSignalType = str(gpD.get("signal_type", ""))
	gpOrtho = bool(gpD.get("ortho", true))
	var gpRoutingIn: Array = gpD.get("routing", [])
	gpRouting = []
	for gpP in gpRoutingIn:
		if gpP is Array and gpP.size() >= 2:
			gpRouting.append(Vector2(float(gpP[0]), float(gpP[1])))
	gpTag = gpD.get("tag", "")
	gpAttrs = gpD.get("attrs", {})
	# Self-heal LAST, after gpAttrs is in place — flagging before the assignment above would
	# be silently wiped by it.
	# 自愈放在最后（在 gpAttrs 就位之后）—— 若在上面那句赋值之前打标记，会被它静默抹掉。
	# An end with neither node_id nor point comes from a NEWER file read by an OLDER build, or
	# from a hand-edited JSON. Keep it loadable as a dangling end at the origin instead of
	# producing an edge that can never be rendered.
	# 将其保留为原点处的悬空端，而不是产生一条永远无法渲染的边。
	if str(gpFromRef.get("node_id", "")) == "" and not gpFromRef.has("point"):
		gpFromRef["point"] = [0.0, 0.0]
		gpAttrs["broken_from"] = true
	if str(gpToRef.get("node_id", "")) == "" and not gpToRef.has("point"):
		gpToRef["point"] = [0.0, 0.0]
		gpAttrs["broken_to"] = true
