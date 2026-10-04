class_name GPAttachPoint
extends Resource

# Copyright © 2026 Jonson Wang
# One mounting anchor of a SYMBOL DEFINITION — the "socket" a mounted child snaps into.
# 图元定义的单个安装锚点 —— 挂载子图元吸附进入的「插座」。
#
# Deliberately mirrors GPPort: same normalized 0..1 envelope coordinates, same optional
# direction vector, same "one mapping in one place" serialization, same "legacy pixel offsets
# pass through unchanged" guard. The differences are semantic, and both matter:
# 有意镜像 GPPort：同样的归一化 0..1 包络坐标、同样的可选方向向量、同样「一处映射」的序列化、
# 同样「历史像素偏移原样透传」的护栏。差异是语义性的，且两条都重要：
#   1. gpDir here is the OUTWARD normal of the mounting face — the direction pointing AWAY from
#      the host. A port's gpDir is the direction a line LEAVES along. Same vector, different job.
#      本处 gpDir 是安装面的**向外法线** —— 背离宿主的方向。端口的 gpDir 是连线**离开**的方向。
#      同一个向量，不同的职责。
#   2. An anchor may carry a DEFAULT CHILD (gpDefaultChild), so placing a vessel yields its
#      nozzles + manhole with no extra clicks, and a "" anchor stays reserved (see 规划 §16).
#      锚点可携带**默认子件**（gpDefaultChild），使放置一台储罐即得到其管口 + 人孔而无须额外
#      点击；"" 的锚点则是**预留位**（见规划 §16）。
#
# This is a DEFINITION-side object: the library owns it, every instance shares it.
# 这是**定义侧**对象：图元库持有，所有实例共享。

# Anchor name, unique within one definition, e.g. "top_actuator" / "ves_bottom_nozzle".
# 锚点名，同一定义内唯一，如 "top_actuator" / "ves_bottom_nozzle"。
# INVARIANT: this is the "anchor" string stored in GPPIDNode.gpMountAnchor, and names must be
# unique within one definition — see GPSymbolDef.gpAttachNamesUnique(). Like an edge's port_id,
# the stored anchor is a HINT: GPMountResolver degrades gracefully when it goes missing.
# 不变式：它就是 GPPIDNode.gpMountAnchor 里存的 "anchor" 串，且同一定义内必须唯一 ——
# 见 GPSymbolDef.gpAttachNamesUnique()。与边的 port_id 一样，存下的锚点是**提示**：
# 缺失时 GPMountResolver 优雅降级。
var gpName: String = ""

# Anchor position normalized 0..1 against the nominal envelope ((0,0)=top-left, (1,1)=bottom-right).
# 锚点位置相对标称包络归一化到 0..1（(0,0)=左上角，(1,1)=右下角）。
var gpPos: Vector2 = Vector2(0.5, 0.5)

# OUTWARD normal of the mounting face (normalized; ZERO = no preferred direction).
# 安装面的**向外法线**（归一化；零向量 = 无偏好方向）。
var gpDir: Vector2 = Vector2.ZERO

# Mount kinds this anchor accepts, e.g. ["NOZZLE"] / ["ACTUATOR"]; EMPTY = accepts any kind.
# 本锚点接受的挂载类型，如 ["NOZZLE"] / ["ACTUATOR"]；**空数组 = 接受任意类型**。
var gpAccepts: Array[String] = []

# How many children may occupy this anchor (0 or negative = unlimited).
# 本锚点可容纳的子件数（0 或负数 = 不限）。
var gpMaxOccupancy: int = 0

# Symbol id instantiated on this anchor when the HOST is placed; "" = reserved (empty) anchor.
# 放置**宿主**时本锚点默认实例化的图元 id；"" = 预留（空）锚点。
var gpDefaultChild: String = ""

# Whether that default child is undeletable (A-class key nozzles whose count/position are fixed
# by the equipment type — see 规划 §16.2).
# 该默认子件是否不可删除（A 类关键管口：其数量与位置由设备型式决定 —— 见规划 §16.2）。
var gpRequired: bool = false

# Initial PROPERTY VALUES stamped onto the default child when the host is placed, e.g.
# {"nozzle_id": "N3"}. Empty = the child starts with no properties of its own.
# 放置宿主时盖到默认子件上的**初始属性值**，如 {"nozzle_id": "N3"}。空 = 子件自身不带属性。
#
# WHY IT LIVES ON THE ANCHOR / 为何放在锚点上：
# §16.3 requires the four nozzles of a vertical exchanger to be numbered N3 / N2 / N1 / N4 by
# their ANCHOR — the same nozzle symbol is instantiated four times on four openings, so the
# number cannot live on the child definition. It is also deliberately NOT the instance tag
# ({tag} is the auto-numbered "G-001" handle); the reference drawing's nozzle number is a
# per-opening datum, which is exactly what an anchor is.
# §16.3 要求立式换热器的四个管口**按锚点**编为 N3 / N2 / N1 / N4 —— 同一个管口图元在四个
# 开孔上被实例化四次，故编号不可能挂在子件定义上。它也刻意**不是**实例位号（{tag} 是自动编号
# 得到的 "G-001"）；参照图上的管口编号是「逐开孔」的数据，而锚点正是逐开孔的对象。
var gpDefaultProps: Dictionary = {}


# Build an anchor from its parts. Occupancy / required keep their defaults, matching how every
# existing port call site passes three arguments.
# 由各分量构造锚点。容纳数 / 必需性保持默认，与既有端口调用点只传三个实参的做法一致。
static func gpMake(gpNameIn: String, gpPosIn: Vector2, gpDirIn: Vector2 = Vector2.ZERO,
		gpAcceptsIn: Array[String] = [], gpDefaultChildIn: String = "",
		gpDefaultPropsIn: Dictionary = {}) -> GPAttachPoint:
	var gpA: GPAttachPoint = GPAttachPoint.new()
	gpA.gpName = gpNameIn
	gpA.gpPos = gpPosIn
	gpA.gpDir = gpDirIn
	# Copy element by element so the stored array is a genuine Array[String] regardless of how
	# the caller built its input.
	# 逐元素拷贝，使存下的数组一定是真正的 Array[String]，与调用方如何构造入参无关。
	var gpAcceptList: Array[String] = []
	for gpKind in gpAcceptsIn:
		gpAcceptList.append(gpKind)
	gpA.gpAccepts = gpAcceptList
	gpA.gpDefaultChild = gpDefaultChildIn
	gpA.gpDefaultProps = gpDefaultPropsIn.duplicate(true)
	return gpA


# Serialize to a dictionary (JSON-friendly). Keys that carry their DEFAULT value are omitted, so
# a definition with plain anchors keeps the smallest possible footprint in a symbol pack.
# 序列化为字典（JSON 友好）。取默认值的键**省略**，使只含普通锚点的定义在图元包中占最小体积。
func gpToDict() -> Dictionary:
	var gpOut: Dictionary = {
		"name": gpName,
		"pos": [gpPos.x, gpPos.y],
		"dir": [gpDir.x, gpDir.y],
		"accepts": gpAccepts.duplicate(),
	}
	if gpMaxOccupancy != 0:
		gpOut["max_occupancy"] = gpMaxOccupancy
	if gpDefaultChild != "":
		gpOut["default_child"] = gpDefaultChild
	if gpRequired:
		gpOut["required"] = gpRequired
	if not gpDefaultProps.is_empty():
		gpOut["default_props"] = gpDefaultProps.duplicate(true)
	return gpOut


# Restore from a dictionary (inverse of gpToDict()). Every key is read through get(key, default)
# so a hand-edited or older pack still loads.
# 从字典还原（gpToDict() 的逆操作）。每个键都以 get(key, default) 读取，故手改或旧图元包仍可载入。
func gpFromDict(gpD: Dictionary) -> void:
	gpName = str(gpD.get("name", ""))
	var gpRawPos: Array = gpD.get("pos", [0.5, 0.5])
	if gpRawPos.size() >= 2:
		gpPos = Vector2(float(gpRawPos[0]), float(gpRawPos[1]))
	else:
		gpPos = Vector2(0.5, 0.5)
	var gpRawDir: Array = gpD.get("dir", [0.0, 0.0])
	if gpRawDir.size() >= 2:
		gpDir = Vector2(float(gpRawDir[0]), float(gpRawDir[1]))
	else:
		gpDir = Vector2.ZERO
	var gpAcceptsIn: Variant = gpD.get("accepts", [])
	var gpAcceptsOut: Array[String] = []
	if gpAcceptsIn is Array:
		for gpKind in (gpAcceptsIn as Array):
			gpAcceptsOut.append(str(gpKind))
	gpAccepts = gpAcceptsOut
	gpMaxOccupancy = int(gpD.get("max_occupancy", 0))
	gpDefaultChild = str(gpD.get("default_child", ""))
	gpRequired = bool(gpD.get("required", false))
	var gpPropsIn: Variant = gpD.get("default_props", {})
	gpDefaultProps = (gpPropsIn as Dictionary).duplicate(true) if gpPropsIn is Dictionary else {}


# Build an array of anchors from an array of dicts — the single mapping every definition,
# pack builder and importer shares (mirrors GPPortSpec.gpFromDicts()).
# 由字典数组构建锚点数组 —— 所有定义、图元包构建器与导入器共享的唯一映射
# （镜像 GPPortSpec.gpFromDicts()）。
static func gpFromDicts(gpArr: Array) -> Array[GPAttachPoint]:
	var gpOut: Array[GPAttachPoint] = []
	for gpD in gpArr:
		if gpD is Dictionary:
			var gpA: GPAttachPoint = GPAttachPoint.new()
			gpA.gpFromDict(gpD as Dictionary)
			gpOut.append(gpA)
	return gpOut


# Serialize an array of anchors back to dicts. Inverse of gpFromDicts().
# 把锚点数组序列化回字典数组。gpFromDicts() 的逆操作。
static func gpToDicts(gpAnchors: Array[GPAttachPoint]) -> Array:
	var gpOut: Array = []
	for gpA in gpAnchors:
		gpOut.append(gpA.gpToDict())
	return gpOut
