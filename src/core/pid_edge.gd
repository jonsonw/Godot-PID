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

# Edge kind: PROCESS / SIGNAL / ...
# 连线类型：PROCESS（工艺）/ SIGNAL（信号）/ ...
var gpKind: String = "PROCESS"

# Polyline points for the edge (world coordinates)
# 连线的折线路径点（世界坐标）
var gpRouting: Array[Vector2] = []

# Process tag, e.g. "PL-201"
# 工艺位号，如 "PL-201"
var gpTag: String = ""

# Extra attributes
# 附加属性
var gpAttrs: Dictionary = {}


# Serialize this edge to a plain dictionary (object graph -> dict graph).
# 将本边序列化为普通字典（对象图 → 字典图）。
# The shape matches docs/samples/pani_detox.pid.json so JSON stays forward-compatible.
# 该形状与 docs/samples/pani_detox.pid.json 一致，保证 JSON 向前兼容。
func gpToDict() -> Dictionary:
	var gpRoutingOut: Array = []
	for gpP in gpRouting:
		gpRoutingOut.append([gpP.x, gpP.y])
	return {
		"instance_id": gpInstanceId,
		"from_ref": gpFromRef.duplicate(),
		"to_ref": gpToRef.duplicate(),
		"kind": gpKind,
		"routing": gpRoutingOut,
		"tag": gpTag,
		"attrs": gpAttrs.duplicate(),
	}


# Restore this edge from a dictionary (inverse of gpToDict).
# 从字典还原本边（gpToDict 的逆操作）。
# Tolerant of the old dictionary-graph shape (id/from/to/attrs) so legacy
# *.pid.json files still load.
# 兼容旧字典图形状（id/from/to/attrs），使旧版 *.pid.json 仍可载入。
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
	var gpRoutingIn: Array = gpD.get("routing", [])
	gpRouting = []
	for gpP in gpRoutingIn:
		if gpP is Array and gpP.size() >= 2:
			gpRouting.append(Vector2(float(gpP[0]), float(gpP[1])))
	gpTag = gpD.get("tag", "")
	gpAttrs = gpD.get("attrs", {})
