class_name GPPort
extends Resource
# UNIFIED MODEL (P0): extends Resource so GPSymbolDef can @export Array[GPPort].
# 统一模型（P0）：继承 Resource，使 GPSymbolDef 能 @export Array[GPPort]。

# Copyright © 2026 Jonson Wang
# One connection port of a symbol, in the SAME unified model as GPShape.
# 图元的单个连接端口，与 GPShape 同属统一模型。
# Port position is NORMALIZED 0..1 against the nominal envelope
# (0,0)=top-left, (1,1)=bottom-right); the outward normal "dir" is optional.
# 端口位置相对标称包络归一化到 0..1（(0,0)=左上角，(1,1)=右下角）；向外法线 dir 为可选。
# Normalized ports keep every family member's ports aligned and survive any resize.
# 归一化端口使同族成员端口天然对齐，且在任意缩放下依然成立。
# Replaces the previous raw Dictionary port entry ({"name","pos","dir"}) so the symbol
# editor and the renderer share one strongly typed port model with the graph shapes.
# 取代原先的字典端口条目（{"name","pos","dir"}），使图元编辑器与渲染层共享同一强类型端口模型。

# Human-readable port name, e.g. "in" / "out" / "p1".
# 人类可读的端口名，如 "in" / "out" / "p1"。
var gpName: String = ""

# Port position normalized 0..1 against the nominal envelope.
# 相对标称包络归一化的端口位置（0..1）。
var gpPos: Vector2 = Vector2(0.5, 0.5)

# Outward normal direction (optional); defaults to zero (no preferred direction).
# 向外法线方向（可选）；默认零向量（无偏好方向）。
var gpDir: Vector2 = Vector2.ZERO


# Build a port from its parts.
# 由各分量构造端口。
static func gpMake(gpNameIn: String, gpPosIn: Vector2, gpDirIn: Vector2 = Vector2.ZERO) -> GPPort:
	var gpP: GPPort = GPPort.new()
	gpP.gpName = gpNameIn
	gpP.gpPos = gpPosIn
	gpP.gpDir = gpDirIn
	return gpP


# Serialize to a dictionary (JSON-friendly), mirroring the legacy port entry.
# 序列化为字典（JSON 友好），与历史端口条目同构。
func gpToDict() -> Dictionary:
	return {
		"name": gpName,
		"pos": [gpPos.x, gpPos.y],
		"dir": [gpDir.x, gpDir.y],
	}


# Restore from a dictionary (inverse of gpToDict). Accepts legacy {"name","pos","dir"}.
# 从字典还原（gpToDict 的逆操作）。接受历史 {"name","pos","dir"} 格式。
func gpFromDict(gpD: Dictionary) -> void:
	gpName = str(gpD.get("name", ""))
	var gpRawPos: Array = gpD.get("pos", [0.5, 0.5])
	gpPos = Vector2(float(gpRawPos[0]), float(gpRawPos[1]))
	var gpRawDir: Array = gpD.get("dir", [0.0, 0.0])
	gpDir = Vector2(float(gpRawDir[0]), float(gpRawDir[1]))
