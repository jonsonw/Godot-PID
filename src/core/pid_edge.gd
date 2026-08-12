class_name PIDEdge
extends RefCounted

# A connection between two ports (port-to-port).
# 一条连接（端口到端口）。
# See Dev Guide §4.5.
# 见开发指南 §4.5。

var instance_id: String = ""          # Unique instance id, e.g. "e-1" / 唯一实例 id，如 "e-1"
# Reference to a port: {node_id, port_id}
# 端口引用：{node_id, port_id}
var from_ref: Dictionary = {}
var to_ref: Dictionary = {}
var kind: String = "PROCESS"          # Edge kind: PROCESS / SIGNAL / ... / 连线类型：PROCESS（工艺）/ SIGNAL（信号）/ ...
var routing: Array[Vector2] = []      # Polyline points for the edge / 连线的折线路径点
var tag: String = ""                  # Process tag, e.g. "PL-201" / 工艺位号，如 "PL-201"
var attrs: Dictionary = {}            # Extra attributes / 附加属性

# TODO: to_dict() / from_dict()
# TODO：to_dict() / from_dict()
