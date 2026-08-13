class_name GPPIDEdge
extends RefCounted

# A connection between two ports (port-to-port).
# 一条连接（端口到端口）。
# See Dev Guide §4.5.
# 见开发指南 §4.5。

# Unique instance id, e.g. "e-1"
# 唯一实例 id，如 "e-1"
var gpInstanceId: String = ""
# Reference to a port: {node_id, port_id}
# 端口引用：{node_id, port_id}
var gpFromRef: Dictionary = {}
var gpToRef: Dictionary = {}
# Edge kind: PROCESS / SIGNAL / ...
# 连线类型：PROCESS（工艺）/ SIGNAL（信号）/ ...
var gpKind: String = "PROCESS"
# Polyline points for the edge
# 连线的折线路径点
var gpRouting: Array[Vector2] = []
# Process tag, e.g. "PL-201"
# 工艺位号，如 "PL-201"
var gpTag: String = ""
# Extra attributes
# 附加属性
var gpAttrs: Dictionary = {}

# TODO: to_dict() / from_dict()
# TODO：待实现序列化 to_dict() / from_dict()
