class_name GPPort
extends Resource

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

# Port purpose (which kind of line may attach to it).
# 端口用途（决定可接哪类连线）。
# NOZZLE : 工艺管口，只接管道 / process nozzle, pipes only
# ACTUATOR : 阀门执行机构接点，只接信号线 / valve actuator terminal, signal lines only
# SIGNAL : 仪表信号端子，只接信号线 / instrument signal terminal, signal lines only
# TERMINAL : 通用端点（跨页接续等），两类线都可接 / generic terminal, accepts both
const GP_NOZZLE: String = "NOZZLE"
const GP_ACTUATOR: String = "ACTUATOR"
const GP_SIGNAL: String = "SIGNAL"
const GP_TERMINAL: String = "TERMINAL"

# Human-readable port name, e.g. "in" / "out" / "p1".
# 人类可读的端口名，如 "in" / "out" / "p1"。
var gpName: String = ""

# Port position normalized 0..1 against the nominal envelope.
# 相对标称包络归一化的端口位置（0..1）。
var gpPos: Vector2 = Vector2(0.5, 0.5)

# Outward normal direction (optional); defaults to zero (no preferred direction).
# 向外法线方向（可选）；默认零向量（无偏好方向）。
var gpDir: Vector2 = Vector2.ZERO

# Whether an empty port is a DEFECT (DRC rule 2). Default false, because most nozzles are
# legitimately spare — marking a port required is a deliberate content decision on the symbol,
# not a guess the checker may make.
# 空端口是否算缺陷（DRC 规则 2）。默认 false —— 多数管口本就允许空置；把端口标为必需是图元上的
# 刻意内容决定，不是检查器可以代猜的。
var gpRequired: bool = false

# Port purpose. Legacy packs and legacy archives carry no "type" key and therefore default
# to NOZZLE, which reproduces the pre-P1 behaviour exactly.
# 端口用途。旧图元包与旧存档无 "type" 键，默认 NOZZLE，与 P1 之前的行为完全一致。
var gpType: String = GP_NOZZLE


# Build a port from its parts. The type defaults to NOZZLE so every existing call site
# (which passes three arguments) keeps its meaning.
# 由各分量构造端口。类型默认 NOZZLE，使每个既有调用点（传三个实参）保持原义。
static func gpMake(gpNameIn: String, gpPosIn: Vector2, gpDirIn: Vector2 = Vector2.ZERO,
		gpTypeIn: String = GP_NOZZLE) -> GPPort:
	var gpP: GPPort = GPPort.new()
	gpP.gpName = gpNameIn
	gpP.gpPos = gpPosIn
	gpP.gpDir = gpDirIn
	gpP.gpType = gpTypeIn
	return gpP


# Serialize to a dictionary (JSON-friendly), mirroring the legacy port entry.
# 序列化为字典（JSON 友好），与历史端口条目同构。
func gpToDict() -> Dictionary:
	var gpD: Dictionary = {
		"name": gpName,
		"pos": [gpPos.x, gpPos.y],
		"dir": [gpDir.x, gpDir.y],
		"type": gpType,
	}
	# Emitted only when true, so every existing pack keeps its previous byte shape.
	# 仅在为 true 时输出，使既有包保持原有字节形态。
	if gpRequired:
		gpD["required"] = true
	return gpD


# Restore from a dictionary (inverse of gpToDict()). Accepts legacy {"name","pos","dir"}.
# 从字典还原（gpToDict() 的逆操作）。接受历史 {"name","pos","dir"} 格式。
func gpFromDict(gpD: Dictionary) -> void:
	gpName = str(gpD.get("name", ""))
	var gpRawPos: Array = gpD.get("pos", [0.5, 0.5])
	gpPos = Vector2(float(gpRawPos[0]), float(gpRawPos[1]))
	var gpRawDir: Array = gpD.get("dir", [0.0, 0.0])
	gpDir = Vector2(float(gpRawDir[0]), float(gpRawDir[1]))
	gpType = str(gpD.get("type", GP_NOZZLE))
	gpRequired = bool(gpD.get("required", false))
