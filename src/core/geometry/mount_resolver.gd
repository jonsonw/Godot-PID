class_name GPMountResolver
extends RefCounted

# Copyright © 2026 Jonson Wang
# The ONLY place that turns (node, mount anchor) into a world transform for a MOUNTED child.
# 把「节点 + 安装锚点」换算为挂载子件世界变换的唯一场所。
#
# Sibling discipline of GPPortResolver / 与 GPPortResolver 同源的纪律：
# Exactly as an edge end is never persisted (it is resolved live from the node's frame), a
# mounted child's world position is NEVER stored — it is DERIVED from the parent chain on every
# query. That single decision is what makes "drag the parent, the children follow" free, and it
# is why moving a host can never leave a child stranded at a stale coordinate.
# 正如边端点从不入盘（由节点坐标系实时解析），挂载子件的世界坐标**永不存储** —— 每次查询由
# 父链**推导**。这一条决定正是「拖动父件、子件自动跟随」无需额外代码的原因，也是移动宿主
# 绝不会把子件遗留在过期坐标上的原因。
#
# Degradation ladder (never fails, never returns INF) / 降级阶梯（绝不失败、绝不返回 INF）：
#   1. not mounted                  -> the node's own frame (identical to pre-mount behaviour)
#      未挂载                        -> 节点自身坐标系（与挂载功能之前完全一致）
#   2. parent / parent-def missing  -> the node's own frame (host deleted without cleanup)
#      父件 / 父定义缺失             -> 节点自身坐标系（宿主被删但未清理）
#   3. anchor name not found        -> the node sits at the host CENTRE
#      锚点名找不到                  -> 节点落在宿主**中心**
#   4. anchor found                 -> host frame + anchor offset, rotation from anchor direction
#      找到锚点                      -> 宿主坐标系 + 锚点偏移，旋转由锚点方向推导
#
# Coding rule: pure static, zero autoload dependency (core hard constraint); every variable
# declares its type explicitly.
# 编码规范：纯静态，零 autoload 依赖（core 硬约束）；所有变量均显式声明类型。

# Screen-space snap radius for the cursor-driven attach ladder, in pixels. Divided by the camera
# zoom at call time to obtain the world-space radius, so the "magnetic" feel is zoom-invariant.
# 光标驱动挂载阶梯的吸附半径（屏幕像素）。调用时除以相机缩放得到世界半径，
# 故吸附手感与缩放无关。
const GP_MOUNT_SNAP_PX: float = 24.0

# Guard against a degenerate zoom (0 or negative) producing an INF radius.
# 防止退化缩放（0 或负数）产生 INF 半径。
const GP_MIN_ZOOM: float = 0.0001


# ---------------------------------------------------------------------------
# Frame math helpers (mirrored from GPPortResolver so both agree on flip-then-rotate order)
# 坐标系数学辅助（镜像 GPPortResolver，使两者在「先镜像后旋转」的顺序上一致）
# ---------------------------------------------------------------------------

# Orient a LOCAL OFFSET by a frame's flip then rotation. Order matters: mirror first (in the
# symbol's own frame), then rotate — the reverse order puts a flipped symbol's parts on the
# wrong side.
# 用某坐标系的翻转与旋转来变换一个**本地偏移**。顺序要紧：先在图元自身坐标系内镜像，再旋转
# —— 反过来会把已翻转图元的部件放到错误一侧。
static func gpOrientLocal(gpLocal: Vector2, gpFlipped: bool, gpRotDeg: float) -> Vector2:
	var gpL: Vector2 = gpLocal
	if gpFlipped:
		gpL.x = -gpL.x
	if not is_zero_approx(gpRotDeg):
		gpL = gpL.rotated(deg_to_rad(gpRotDeg))
	return gpL


# Orient a DIRECTION by a frame's flip then rotation, normalized (ZERO stays ZERO).
# 用某坐标系的翻转与旋转来变换一个**方向**，并归一化（零向量保持零向量）。
static func gpOrientDir(gpDir: Vector2, gpFlipped: bool, gpRotDeg: float) -> Vector2:
	if gpDir == Vector2.ZERO:
		return Vector2.ZERO
	var gpD: Vector2 = gpDir
	if gpFlipped:
		gpD.x = -gpD.x
	if not is_zero_approx(gpRotDeg):
		gpD = gpD.rotated(deg_to_rad(gpRotDeg))
	return gpD.normalized()


# Local (symbol-centered) offset of an anchor, in the DEFINITION's pixels — the anchor analogue
# of GPSymbolDef.gpPortLocal(). Only the normalized branch applies: anchors are never legacy
# pixel offsets, because the type is new.
# 锚点在**定义**像素中的本地（相对图元中心）偏移 —— 即 GPSymbolDef.gpPortLocal() 的锚点版。
# 只有归一化分支适用：锚点不可能是历史像素偏移，因为该类型是新增的。
static func gpAnchorLocal(gpDef: GPSymbolDef, gpAnchor: GPAttachPoint) -> Vector2:
	if gpDef == null or gpAnchor == null:
		return Vector2.ZERO
	return (gpAnchor.gpPos - Vector2(0.5, 0.5)) * gpDef.gpDefaultSize


# Child world rotation from an anchor's WORLD direction and the child's canonical mount offset.
# 由锚点的**世界**方向与子件的规范安装偏置求出子件的世界旋转。
#
# [param gpAnchorDirWorld] the mounting face's outward normal, already oriented into world space
# (see gpAnchorWorld()). / 安装面的向外法线，已变换到世界空间（见 gpAnchorWorld()）。
# [param gpBaseMountRot] the child's canonical offset in degrees (GPSymbolDef.gpBaseMountRot).
# / 子件的规范偏置（度）（GPSymbolDef.gpBaseMountRot）。
#
# WHY THE CONSTANT EXISTS / 为何需要这个常量：
# A nozzle sticks OUT of the host, an actuator SITS ON it — their mounting faces point opposite
# ways relative to the outward normal, so a single formula cannot serve both. Each symbol folds
# its own convention into gpBaseMountRot. A useful check: the same child on an up-facing and a
# down-facing anchor differs by exactly 180 degrees.
# 管口是**伸出**宿主的，执行机构是**坐在**宿主上的 —— 二者安装面相对向外法线的朝向相反，
# 故单一公式无法同时服务两者。每个图元把自身约定折进 gpBaseMountRot。一个有用的自检：
# 同一子件落在朝上的锚点与朝下的锚点上，旋转恰好相差 180 度。
static func gpAnchorDirToRotation(gpAnchorDirWorld: Vector2, gpBaseMountRot: float) -> float:
	if gpAnchorDirWorld == Vector2.ZERO:
		return gpBaseMountRot
	return rad_to_deg(atan2(gpAnchorDirWorld.y, gpAnchorDirWorld.x)) + gpBaseMountRot


# ---------------------------------------------------------------------------
# Composition queries (pure; the graph is read, never mutated)
# 组合查询（纯函数；只读图，绝不修改）
# ---------------------------------------------------------------------------

# Whether an anchor accepts the given mount kind. An EMPTY accept list means "any kind", and an
# EMPTY kind (a symbol that is not mountable) never matches.
# 锚点是否接受给定挂载类型。**空**接受表表示「任意类型」；**空**类型（不可挂载的图元）永不匹配。
static func gpAcceptsKind(gpAnchor: GPAttachPoint, gpMountKind: String) -> bool:
	if gpAnchor == null or gpMountKind == "":
		return false
	if gpAnchor.gpAccepts.is_empty():
		return true
	return gpMountKind in gpAnchor.gpAccepts


# Whether [param gpChildDef] may be mounted into [param gpAnchor] of [param gpParentDef].
# 判断 [param gpChildDef] 能否挂入 [param gpParentDef] 的 [param gpAnchor]。
static func gpCanMount(gpParentDef: GPSymbolDef, gpAnchor: GPAttachPoint,
		gpChildDef: GPSymbolDef) -> bool:
	if gpParentDef == null or gpAnchor == null or gpChildDef == null:
		return false
	if gpChildDef.gpMountKind == "":
		return false
	# An explicit fit list narrows the child to specific anchor NAMES (empty = any compatible).
	# 显式的匹配表把子件收窄到特定**锚点名**（空 = 任意兼容锚点）。
	if not gpChildDef.gpMountFit.is_empty() and not (gpAnchor.gpName in gpChildDef.gpMountFit):
		return false
	return gpAcceptsKind(gpAnchor, gpChildDef.gpMountKind)


# Every child node mounted directly onto [param gpParentUid].
# 直接挂在 [param gpParentUid] 上的全部子节点。
static func gpChildrenOf(gpGraph: GPPIDGraph, gpParentUid: String) -> Array[GPPIDNode]:
	var gpOut: Array[GPPIDNode] = []
	if gpGraph == null or gpParentUid == "":
		return gpOut
	for gpN in gpGraph.gpNodes:
		if gpN.gpParentUid == gpParentUid:
			gpOut.append(gpN)
	return gpOut


# How many children currently occupy [param gpAnchorName] of [param gpParentUid].
# [param gpParentUid] 的 [param gpAnchorName] 锚点当前占用的子件数。
static func gpOccupancy(gpGraph: GPPIDGraph, gpParentUid: String, gpAnchorName: String) -> int:
	if gpGraph == null or gpParentUid == "" or gpAnchorName == "":
		return 0
	var gpCount: int = 0
	for gpN in gpGraph.gpNodes:
		if gpN.gpParentUid == gpParentUid and gpN.gpMountAnchor == gpAnchorName:
			gpCount += 1
	return gpCount


# Whether an anchor still has room (respecting gpMaxOccupancy; 0/negative = unlimited).
# 锚点是否仍有空位（遵守 gpMaxOccupancy；0/负数 = 不限）。
#
# TIMING DEPENDENCY — read before "optimising" a caller / 时序依赖 —— 优化调用点前必读：
# The DEFAULT CHILDREN of an anchor are instantiated by GPAddNodeCommand, i.e. AFTER the host
# exists but in the same undo step. So while the host is being placed this anchor is still
# EMPTY and this query says "yes, room" — which is correct, because nothing has claimed it yet.
# It is NOT correct to call this query a second time inside that same step expecting the default
# child to be visible; the child is added by the command, not by the definition.
# 锚点的**默认子件**由 GPAddNodeCommand 实例化 —— 即在宿主存在之后、但在同一个撤销步内。
# 故放置宿主的过程中该锚点仍是**空**的，本查询返回「有位」是对的：还没有任何东西占用它。
# 若在同一个撤销步内再调一次本查询并期望看到默认子件，则是错的 —— 子件由命令添加，而非定义。
static func gpAnchorHasRoom(gpGraph: GPPIDGraph, gpParentUid: String, gpAnchor: GPAttachPoint) -> bool:
	if gpAnchor == null:
		return false
	if gpAnchor.gpMaxOccupancy <= 0:
		return true
	return gpOccupancy(gpGraph, gpParentUid, gpAnchor.gpName) < gpAnchor.gpMaxOccupancy


# ---------------------------------------------------------------------------
# Port supersession — a host's OWN connect ports yield to the nozzles mounted on it
# 端口让位 —— 宿主**自身**的连接端口让位于装在它上面的管嘴
# ---------------------------------------------------------------------------
#
# WHY THIS EXISTS / 为何存在：
# A vessel with nozzles has two competing sets of connection points: the wall positions baked
# into its own definition, and the nozzle tips standing on those walls. Two answers to one
# question is worse than one: the wall points sit UNDER the nozzles, so the pick radius of the
# host's port swallowed every press aimed at a nozzle, and pipes started at the vessel wall
# instead of at the nozzle the drawing actually shows (both reported by the user).
# 带管嘴的容器有两套互相竞争的连接点：内置在自身定义里的壁面位置，与立在这些壁面上的管嘴端。
# 同一个问题有两个答案比只有一个更糟：壁面点正压在管嘴**下面**，故宿主端口的拾取半径吞掉了每一次
# 指向管嘴的按下，管线也从罐壁而不是图纸真正画出的管嘴起步（两条均由用户报告）。
#
# The rule is therefore: while a process nozzle is mounted on a node, that node's own ports are
# inert, and the mounted nozzles' ports answer in their place. It is REVERSIBLE — detaching the
# nozzles hands the node's own ports back — and it needs no file migration, because an edge stores
# a port NAME and the resolver still resolves that name for the life of the drawing.
# 故规则为：只要有工艺管嘴挂在某节点上，该节点自身的端口即失效，由已挂载管嘴的端口代为应答。
# 该规则**可逆** —— 卸下管嘴即把自身端口还给节点 —— 且无需文件迁移，因为边存的是端口**名**，
# 只要图纸还在，解析器就仍能解析该名字。

# The mount kind that marks a symbol as a PROCESS NOZZLE. Mirrors MOUNT_KIND in
# tools/gen_symbol_packs.py and GP_MOUNT_KIND in src/core/symbol/symbol_categories.gd — the three
# must agree, or a host will never notice that its nozzles have taken over.
# 标记图元为**工艺管口**的挂载类型。与 tools/gen_symbol_packs.py 的 MOUNT_KIND 及
# src/core/symbol/symbol_categories.gd 的 GP_MOUNT_KIND 互为镜像 —— 三者必须一致，
# 否则宿主永远不会察觉自己的端口已被管嘴接管。
const GP_KIND_NOZZLE: String = "NOZZLE"


# Whether [param gpNode]'s own connect ports are superseded by the nozzles mounted on it.
# [param gpNode] 自身的连接端口是否已被挂在其上的管嘴取代。
#
# An ACTUATOR deliberately does NOT supersede anything: it carries a signal terminal, not a process
# port, so a valve that has been given an actuator must keep its in / out nozzles. Only a mounted
# NOZZLE (a symbol whose gpMountKind is GP_KIND_NOZZLE and which actually has ports) counts.
# 执行机构刻意**不**取代任何东西：它带的是信号端子而非工艺管口，故装了执行机构的阀门必须保留
# 其 in / out。只有已挂载的**管嘴**（gpMountKind 为 GP_KIND_NOZZLE 且确实带端口）才算数。
static func gpPortsSuperseded(gpGraph: GPPIDGraph, gpDefLookup: Callable,
		gpNode: GPPIDNode) -> bool:
	if gpGraph == null or gpNode == null:
		return false
	for gpChild in gpChildrenOf(gpGraph, gpNode.gpInstanceId):
		var gpChildDef: GPSymbolDef = gpDefFor(gpDefLookup, gpChild.gpSymbolId)
		if gpChildDef == null or gpChildDef.gpPorts.is_empty():
			continue
		if gpChildDef.gpMountKind == GP_KIND_NOZZLE:
			return true
	return false


# The ports that actually carry a node's connections, as [{node, def, port}, ...].
# 真正承载某节点连接关系的端口，形如 [{node, def, port}, ...]。
#
# For an ordinary node that is simply its own port list. For a superseded host it is the mounted
# nozzles' ports, so a caller that draws or snaps sees the points the drawing shows. Never returns
# null entries: an unresolvable definition degrades to an empty list, never to a crash.
# 对普通节点就是它自己的端口表。对被取代的宿主则是已挂载管嘴的端口，使绘制或吸附的调用方看到的
# 正是图纸呈现的接点。绝不返回 null 项：定义无法解析时降级为空表，绝不让调用方崩溃。
static func gpServingPorts(gpGraph: GPPIDGraph, gpDefLookup: Callable,
		gpNode: GPPIDNode) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	if gpNode == null:
		return gpOut
	var gpDef: GPSymbolDef = gpDefFor(gpDefLookup, gpNode.gpSymbolId)
	if gpDef == null:
		return gpOut
	if not gpPortsSuperseded(gpGraph, gpDefLookup, gpNode):
		for gpP in gpDef.gpPorts:
			gpOut.append({"node": gpNode, "def": gpDef, "port": gpP})
		return gpOut
	for gpChild in gpChildrenOf(gpGraph, gpNode.gpInstanceId):
		var gpChildDef: GPSymbolDef = gpDefFor(gpDefLookup, gpChild.gpSymbolId)
		if gpChildDef == null or gpChildDef.gpMountKind != GP_KIND_NOZZLE:
			continue
		for gpP in gpChildDef.gpPorts:
			gpOut.append({"node": gpChild, "def": gpChildDef, "port": gpP})
	return gpOut


# Whether [param gpHostNode] could host [param gpChildDef] at all — i.e. it declares a compatible
# anchor, whether or not that anchor is free. This is the "do not run away" test of the placement
# avoidance: a symbol the user is trying to attach a part to must not be pushed aside by that very
# gesture (the reported "dragging a nozzle onto the vessel pushed the vessel away").
# [param gpHostNode] 究竟能否容纳 [param gpChildDef] —— 即它是否声明了兼容锚点，无论该锚点是否空闲。
# 这是放置避让的「不许跑开」判据：用户正试图往其上装部件的那个图元，绝不能被该手势推开
#（即用户报告的「把管嘴拖到罐上却把罐推开了」）。
#
# Occupancy is deliberately IGNORED: a momentarily full host must stay put too, otherwise it would
# be shoved away for the very reason that its nozzles are already all in use.
# 刻意**忽略**占用：一时满位的宿主同样必须留在原地，否则它会因为「管嘴已全部用掉」这一理由被推走。
static func gpAcceptsPartKind(gpGraph: GPPIDGraph, gpDefLookup: Callable, gpHostNode: GPPIDNode,
		gpChildDef: GPSymbolDef) -> bool:
	if gpGraph == null or gpHostNode == null or gpChildDef == null:
		return false
	if gpChildDef.gpMountKind == "":
		return false
	var gpDef: GPSymbolDef = gpDefFor(gpDefLookup, gpHostNode.gpSymbolId)
	if gpDef == null:
		return false
	for gpA in gpDef.gpAttachPoints:
		if gpCanMount(gpDef, gpA, gpChildDef):
			return true
	return false


# The ids of nodes that must NOT be pushed while [param gpMovingIds] is being dragged or placed:
# every other node that could host one of the moving parts. Callers add these to the collision's
# immovable set, which is what makes "drag a part onto its host" a snap instead of a shove.
# 在 [param gpMovingIds] 被拖动或放置期间**不得**被推开的节点 id：除移动集合之外，一切能容纳其中
# 某个部件的节点。调用方把它们并入碰撞的固定集，这正是「把部件拖到宿主上」是吸附而非推开的原因。
#
# Returns [] unless at least one moving node is itself a part, so every ordinary drag and placement
# keeps its previous behaviour exactly (including which neighbours it scatters).
# 只要移动集合中没有任何部件本身，就返回 []，故每一次普通拖拽 / 放置的行为与之前**完全**一致
#（包括它会把哪些邻件散开）。
static func gpPinnedHosts(gpGraph: GPPIDGraph, gpDefLookup: Callable,
		gpMovingIds: Array[String]) -> Array[String]:
	var gpOut: Array[String] = []
	if gpGraph == null or gpMovingIds.is_empty():
		return gpOut
	for gpId in gpMovingIds:
		var gpN: GPPIDNode = gpGraph.gpGetNode(gpId)
		if gpN == null:
			continue
		var gpChildDef: GPSymbolDef = gpDefFor(gpDefLookup, gpN.gpSymbolId)
		if gpChildDef == null or gpChildDef.gpMountKind == "":
			continue
		for gpHost in gpGraph.gpNodes:
			if gpHost.gpInstanceId in gpMovingIds or gpHost.gpInstanceId in gpOut:
				continue
			if gpAcceptsPartKind(gpGraph, gpDefLookup, gpHost, gpChildDef):
				gpOut.append(gpHost.gpInstanceId)
	return gpOut


# Mint the next auto part number for [param gpChildDef] among the children of [param gpHostUid]:
# "M2" for a manhole on a tank whose built-in manhole is "M1". The user's rule — parts number
# sequentially per host and can never repeat inside one host — as one pure function.
# 为 [param gpChildDef] 铸造其在 [param gpHostUid] 子件中的下一个自动编号：自带人孔「M1」的罐上
# 加人孔得「M2」。用户的规则 —— 部件在宿主内按序编号、同一宿主内绝不重复 —— 收敛为一个纯函数。
#
# The scan is definition-driven: a child without gpTagKey/gpTagPrefix (an actuator, say) yields ""
# and the caller assigns nothing. Non-numeric or foreign-series values are skipped, so a hand-typed
# "M3A" still blocks nothing but also never crashes the scan; two series (N / M) can never collide
# because each scan only reads its own prefix.
# 扫描由定义驱动：没有 gpTagKey/gpTagPrefix 的子件（如执行机构）返回 ""，调用方即不赋值。
# 非数字或外系列的取值被跳过 —— 手打的「M3A」既不阻塞扫描也不会使其崩溃；两个系列（N / M）
# 各自只读自己的前缀，故永不相撞。
static func gpNextPartTag(gpGraph: GPPIDGraph, gpDef: GPSymbolDef, gpHostUid: String) -> String:
	if gpGraph == null or gpDef == null or gpHostUid == "":
		return ""
	if gpDef.gpPartTagKey == "" or gpDef.gpPartTagPrefix == "":
		return ""
	var gpMax: int = 0
	for gpN in gpGraph.gpNodes:
		if gpN == null or gpN.gpParentUid != gpHostUid:
			continue
		var gpV: String = str(gpN.gpProps.get(gpDef.gpPartTagKey, ""))
		if not gpV.begins_with(gpDef.gpPartTagPrefix):
			continue
		var gpRest: String = gpV.substr(gpDef.gpPartTagPrefix.length())
		if not gpRest.is_valid_int():
			continue
		gpMax = maxi(gpMax, int(gpRest))
	return gpDef.gpPartTagPrefix + str(gpMax + 1)


# ---------------------------------------------------------------------------
# Default children (the parts a host brings with it when it is placed)
# 默认子件（宿主被放置时随之带来的部件）
# ---------------------------------------------------------------------------

# Every DEFAULT CHILD [param gpHostDef] brings with it, in the definition's own anchor order.
# [param gpHostDef] 随身带来的全部**默认子件**，按定义自身的锚点顺序。
# Returns [{"anchor": String, "symbol_id": String, "props": Dictionary}, ...].
# 返回 [{"anchor", "symbol_id", "props"}, ...]。
#
# WHY NO GRAPH PARAMETER / 为何不接收图参数：
# The plan sketched this as a graph query, but the set is a property of the DEFINITION, not of the
# drawing — the only moment it is consumed is "the host has just been created", when occupancy is
# definitionally zero for every anchor. Taking a graph would therefore let the caller believe the
# answer can vary with the drawing when it cannot, and would make the function untestable without
# contriving a graph. Keeping it definition-only is the honest signature.
# 规划草图把它写成一次图查询，但该集合是**定义**的属性而非图纸的属性 —— 它唯一被消费的时刻是
# 「宿主刚刚被创建」，此时每个锚点的占用数按定义就是 0。接收图参数反而会让调用方误以为答案会随
# 图纸变化（其实不会），并且不得不用人造图才能测试。只依赖定义才是诚实的签名。
#
# A child whose symbol is NOT resolvable is skipped rather than returned as a broken id: a pack
# that names a symbol which is not installed must degrade to "this part is missing", never to a
# node whose definition does not exist.
# 子件图元**无法解析**时跳过，而不是返回一个坏 id：引用了未安装图元的图元包必须降级为
# 「这个部件缺失」，绝不能产生一个定义不存在的节点。
static func gpDefaultChildren(gpDefLookup: Callable, gpHostDef: GPSymbolDef) -> Array[Dictionary]:
	var gpOut: Array[Dictionary] = []
	if gpHostDef == null:
		return gpOut
	for gpA in gpHostDef.gpAttachPoints:
		if gpA.gpDefaultChild == "":
			continue
		if gpDefFor(gpDefLookup, gpA.gpDefaultChild) == null:
			continue
		gpOut.append({
			"anchor": gpA.gpName,
			"symbol_id": gpA.gpDefaultChild,
			"props": gpA.gpDefaultProps.duplicate(true),
		})
	return gpOut


# The name of the REQUIRED anchor [param gpNode] is mounted into, or "" when it may be removed
# freely. This is the guard behind 规划 §16.2: the built-in nozzles of an A-class machine have a
# count and a position fixed by the equipment type, so neither deleting nor detaching one is
# allowed — doing so would leave a drawing that no longer describes the machine.
# [param gpNode] 所装入的**必需**锚点名；可自由移除时返回 ""。这是规划 §16.2 背后的护栏：
# A 类机械的自带管口，其数量与位置由设备型式决定，故既不允许删除也不允许卸载 ——
# 否则图纸就不再描述那台设备了。
#
# A missing host / definition / anchor degrades to "" (= removable). That direction is deliberate:
# the pin exists to protect a known A-class part, and an unresolvable host is precisely the case
# where refusing would trap the user with an undeletable node.
# 宿主 / 定义 / 锚点缺失时降级为 ""（= 可移除）。该方向是刻意的：钉子存在的意义是保护已知的
# A 类部件，而「宿主无法解析」恰恰是**拒绝**会把用户困在一个删不掉的节点上的情形。
static func gpRequiredAnchorName(gpGraph: GPPIDGraph, gpDefLookup: Callable,
		gpNode: GPPIDNode) -> String:
	if gpGraph == null or gpNode == null or not gpNode.gpIsMounted():
		return ""
	var gpParent: GPPIDNode = gpGraph.gpGetNode(gpNode.gpParentUid)
	if gpParent == null:
		return ""
	var gpParentDef: GPSymbolDef = gpDefFor(gpDefLookup, gpParent.gpSymbolId)
	if gpParentDef == null:
		return ""
	var gpAnchor: GPAttachPoint = gpParentDef.gpAttachPointByName(gpNode.gpMountAnchor)
	if gpAnchor == null or not gpAnchor.gpRequired:
		return ""
	return gpAnchor.gpName


# Anchor names on [param gpParentUid] that accept [param gpMountKind] AND still have room.
# [param gpParentUid] 上接受 [param gpMountKind] **且**仍有空位的锚点名。
# This is what greys out (or hides) a context-menu entry, and what makes a drag preview refuse
# to land — the "attachment never orphans itself" rule of 规划 §15.
# 这正是右键菜单项置灰（或隐藏）的依据，也是拖拽预览**拒绝落位**的依据 ——
# 即规划 §15 的「附件绝不成为孤儿」规则。
static func gpFreeAnchors(gpGraph: GPPIDGraph, gpDefLookup: Callable, gpParentUid: String,
		gpMountKind: String) -> Array[String]:
	var gpOut: Array[String] = []
	if gpGraph == null or gpParentUid == "" or gpMountKind == "":
		return gpOut
	var gpParent: GPPIDNode = gpGraph.gpGetNode(gpParentUid)
	if gpParent == null:
		return gpOut
	var gpDef: GPSymbolDef = gpDefFor(gpDefLookup, gpParent.gpSymbolId)
	if gpDef == null:
		return gpOut
	for gpA in gpDef.gpAttachPoints:
		if not gpAcceptsKind(gpA, gpMountKind):
			continue
		if not gpAnchorHasRoom(gpGraph, gpParentUid, gpA):
			continue
		gpOut.append(gpA.gpName)
	return gpOut


# Same as gpFreeAnchors(), but filtered by a child DEFINITION rather than a bare mount kind, so it
# also honours gpMountFit (a child narrowed to specific anchor NAMES). This is the query the
# context menu and the drag preview actually need — "where may THIS symbol go?".
# 与 gpFreeAnchors() 相同，但以子件**定义**（而非裸挂载类型）过滤，故同时遵守 gpMountFit
# （把子件收窄到特定锚点名）。这正是右键菜单与拖拽预览真正需要的查询 ——「**这个**图元能去哪」。
static func gpFreeAnchorsForDef(gpGraph: GPPIDGraph, gpDefLookup: Callable, gpParentUid: String,
		gpChildDef: GPSymbolDef) -> Array[String]:
	var gpOut: Array[String] = []
	if gpGraph == null or gpParentUid == "" or gpChildDef == null:
		return gpOut
	var gpParent: GPPIDNode = gpGraph.gpGetNode(gpParentUid)
	if gpParent == null:
		return gpOut
	var gpDef: GPSymbolDef = gpDefFor(gpDefLookup, gpParent.gpSymbolId)
	if gpDef == null:
		return gpOut
	for gpA in gpDef.gpAttachPoints:
		if not gpCanMount(gpDef, gpA, gpChildDef):
			continue
		if not gpAnchorHasRoom(gpGraph, gpParentUid, gpA):
			continue
		gpOut.append(gpA.gpName)
	return gpOut


# The FIRST free compatible anchor for a child on a host, or "" when there is none. This is where
# 规划 §15.3 step 3 drops the node for the right-click path — no cursor positioning required.
# the host definition's own declaration order decides which one is "first", so the choice is
# stable and explainable (the user sees the same anchor every time).
# 子件在宿主上**第一个**空闲兼容锚点，无则 ""。这是规划 §15.3 第 3 步（右键路径）落点之处 ——
# 无需鼠标定位。哪一个算「第一个」由宿主定义自身的声明顺序决定，故该选择稳定且可解释
# （用户每次看到同一个锚点）。
static func gpFirstFreeAnchorForDef(gpGraph: GPPIDGraph, gpDefLookup: Callable,
		gpParentUid: String, gpChildDef: GPSymbolDef) -> String:
	var gpFree: Array[String] = gpFreeAnchorsForDef(gpGraph, gpDefLookup, gpParentUid, gpChildDef)
	if gpFree.is_empty():
		return ""
	return gpFree[0]


# Every definition that can be mounted at all (a non-empty gpMountKind), sorted by id so a menu
# built from this list has a stable order frame to frame.
# 一切**可挂载**的定义（gpMountKind 非空），按 id 排序，使据此构建的菜单逐帧顺序稳定。
static func gpMountableDefs(gpDefs: Array[GPSymbolDef]) -> Array[GPSymbolDef]:
	var gpOut: Array[GPSymbolDef] = []
	for gpD in gpDefs:
		if gpD != null and gpD.gpMountKind != "":
			gpOut.append(gpD)
	gpOut.sort_custom(func(gpA: GPSymbolDef, gpB: GPSymbolDef) -> bool:
		return gpA.gpId < gpB.gpId)
	return gpOut


# ---------------------------------------------------------------------------
# World transform / anchor resolution
# 世界变换 / 锚点解析
# ---------------------------------------------------------------------------

# Resolve a node's world transform as {"origin": Vector2, "rot_deg": float, "flipped": bool}.
# 把节点的世界变换解析为 {"origin", "rot_deg", "flipped"}。
# For a top-level node this is exactly its own frame, so every pre-mount call site that swaps in
# this function keeps its current behaviour (the backward-compat anchor of the whole feature).
# 对顶层节点而言，这恰好就是它自身的坐标系，故任何改用本函数的挂载前调用点行为不变
# （这是整个功能的向后兼容锚点）。
static func gpWorldTransform(gpGraph: GPPIDGraph, gpDefLookup: Callable,
		gpNode: GPPIDNode) -> Dictionary:
	return _gpWorldTransform(gpGraph, gpDefLookup, gpNode, [])


# Recursive worker. [param gpSeen] is the ancestor trail used to break a hand-edited parent cycle
# (A mounts onto B, B mounts onto A) instead of recursing forever.
# 递归实现。[param gpSeen] 是祖先链，用于打断手改出来父链环（A 挂 B、B 挂 A），
# 而不是无限递归。
static func _gpWorldTransform(gpGraph: GPPIDGraph, gpDefLookup: Callable, gpNode: GPPIDNode,
		gpSeen: Array[String]) -> Dictionary:
	if gpNode == null:
		return {"origin": Vector2.ZERO, "rot_deg": 0.0, "flipped": false}
	var gpOwn: Dictionary = {
		"origin": gpNode.gpPosition,
		"rot_deg": gpNode.gpRotationDeg,
		"flipped": gpNode.gpFlipped,
	}
	# Ladder 1: not mounted -> its own frame.
	# 阶梯 1：未挂载 -> 自身坐标系。
	if not gpNode.gpIsMounted() or gpGraph == null:
		return gpOwn
	# Cycle guard: a node already on the ancestor trail must not recurse again.
	# 环护栏：已在祖先链上的节点不得再次递归。
	if gpNode.gpInstanceId in gpSeen:
		return gpOwn
	gpSeen.append(gpNode.gpInstanceId)

	# Ladder 2: host vanished (deleted without cleaning up) -> its own frame.
	# 阶梯 2：宿主已消失（删除时未清理）-> 自身坐标系。
	var gpParent: GPPIDNode = gpGraph.gpGetNode(gpNode.gpParentUid)
	if gpParent == null:
		gpSeen.pop_back()
		return gpOwn
	var gpParentDef: GPSymbolDef = gpDefFor(gpDefLookup, gpParent.gpSymbolId)
	var gpChildDef: GPSymbolDef = gpDefFor(gpDefLookup, gpNode.gpSymbolId)
	var gpParentWT: Dictionary = _gpWorldTransform(gpGraph, gpDefLookup, gpParent, gpSeen)
	gpSeen.pop_back()
	if gpParentDef == null:
		return gpOwn

	var gpParentOrigin: Vector2 = gpParentWT["origin"]
	var gpParentRot: float = float(gpParentWT["rot_deg"])
	var gpParentFlip: bool = bool(gpParentWT["flipped"])

	# Ladder 3: anchor not found -> sit at the host CENTRE (locals stay ZERO), still following
	# the host. The per-instance nudge still applies, so a user's fine-tuning is never lost.
	# 阶梯 3：锚点找不到 -> 落在宿主**中心**（本地偏移保持零），但仍跟随宿主。
	# 单实例微调依然生效，故用户的微调绝不丢失。
	var gpLocal: Vector2 = Vector2.ZERO
	var gpAnchorDirWorld: Vector2 = Vector2.ZERO
	var gpAnchor: GPAttachPoint = gpParentDef.gpAttachPointByName(gpNode.gpMountAnchor)
	if gpAnchor != null:
		gpLocal = gpAnchorLocal(gpParentDef, gpAnchor)
		gpAnchorDirWorld = gpOrientDir(gpAnchor.gpDir, gpParentFlip, gpParentRot)

	# Ladder 4: anchor found -> host frame + anchor offset, with the host's flip then rotation.
	# 阶梯 4：找到锚点 -> 宿主坐标系 + 锚点偏移，并应用宿主的翻转再旋转。
	gpLocal += gpNode.gpMountOffset
	var gpOrigin: Vector2 = gpParentOrigin + gpOrientLocal(gpLocal, gpParentFlip, gpParentRot)

	var gpBaseRot: float = 0.0
	if gpChildDef != null:
		gpBaseRot = gpChildDef.gpBaseMountRot
	# The anchor's world direction carries the host's orientation, so the child inherits every
	# parent move / rotation / flip for free. With no anchor direction we fall back to the host's
	# rotation (a bare "same way up as the host" attachment).
	# 锚点的世界方向已携带宿主朝向，故子件自动继承父件的每次移动 / 旋转 / 翻转。
	# 无锚点方向时回落到宿主旋转（即「与宿主同向」的朴素挂载）。
	var gpRot: float = gpParentRot
	if gpAnchorDirWorld != Vector2.ZERO:
		gpRot = gpAnchorDirToRotation(gpAnchorDirWorld, gpBaseRot)
	gpRot += gpNode.gpMountAngleDeg

	return {
		"origin": gpOrigin,
		"rot_deg": gpRot,
		# Flipping the host flips the whole assembly: the child's effective flip is the parity of
		# the two, which is exactly the rigid-body behaviour a mirrored drawing expects.
		# 翻转宿主即翻转整个组合：子件的等效翻转是两者的奇偶性 —— 这正是镜像图纸所期望的刚体行为。
		"flipped": (gpParentFlip != gpNode.gpFlipped),
	}


# Resolve one anchor on a host into {"pos": Vector2, "dir": Vector2, "found": bool}.
# 把宿主上的一个锚点解析为 {"pos", "dir", "found"}。
# Never returns INF: a missing anchor or definition degrades to the host's own origin with a ZERO
# direction, so a stale anchor name only misplaces a preview instead of crashing a drag.
# 绝不返回 INF：锚点或定义缺失时降级为宿主自身原点 + 零方向，故过期的锚点名只会让预览错位，
# 而不会让拖拽崩溃。
static func gpAnchorWorld(gpGraph: GPPIDGraph, gpDefLookup: Callable, gpHostNode: GPPIDNode,
		gpAnchorName: String) -> Dictionary:
	if gpHostNode == null:
		return {"pos": Vector2.ZERO, "dir": Vector2.ZERO, "found": false}
	var gpWT: Dictionary = gpWorldTransform(gpGraph, gpDefLookup, gpHostNode)
	var gpOrigin: Vector2 = gpWT["origin"]
	var gpDef: GPSymbolDef = gpDefFor(gpDefLookup, gpHostNode.gpSymbolId)
	if gpDef == null:
		return {"pos": gpOrigin, "dir": Vector2.ZERO, "found": false}
	var gpAnchor: GPAttachPoint = gpDef.gpAttachPointByName(gpAnchorName)
	if gpAnchor == null:
		return {"pos": gpOrigin, "dir": Vector2.ZERO, "found": false}
	var gpLocal: Vector2 = gpAnchorLocal(gpDef, gpAnchor)
	return {
		"pos": gpOrigin + gpOrientLocal(gpLocal, bool(gpWT["flipped"]), float(gpWT["rot_deg"])),
		"dir": gpOrientDir(gpAnchor.gpDir, bool(gpWT["flipped"]), float(gpWT["rot_deg"])),
		"found": true,
	}


# The nearest FREE compatible anchor to a world point — the cursor-driven attach ladder.
# 距世界点最近的**空闲兼容**锚点 —— 光标驱动的挂载阶梯。
# Returns {"hit": bool, "parent_uid": String, "anchor": String, "pos": Vector2, "dir": Vector2,
# "dist": float}. "hit" is false when nothing lies within the zoom-scaled snap radius, which is
# what makes the drag preview show a forbidden cursor instead of landing somewhere arbitrary.
# 返回 {"hit", "parent_uid", "anchor", "pos", "dir", "dist"}。当没有任何锚点落在随缩放变化的
# 吸附半径内时 "hit" 为 false —— 这正是拖拽预览显示禁止光标、而不是随便落位的原因。
static func gpMountCandidate(gpGraph: GPPIDGraph, gpDefLookup: Callable, gpWorld: Vector2,
		gpZoom: float, gpMountKind: String) -> Dictionary:
	var gpBest: Dictionary = {
		"hit": false,
		"parent_uid": "",
		"anchor": "",
		"pos": Vector2.ZERO,
		"dir": Vector2.ZERO,
		"dist": INF,
	}
	if gpGraph == null or gpMountKind == "":
		return gpBest
	# Snap radius is fixed in SCREEN pixels, so zooming in tightens it in world units and the
	# magnet feels the same at every zoom level.
	# 吸附半径固定在**屏幕**像素，故放大时世界半径收紧，磁吸手感在任何缩放下都一致。
	var gpRadius: float = GP_MOUNT_SNAP_PX / maxf(gpZoom, GP_MIN_ZOOM)
	for gpHost in gpGraph.gpNodes:
		var gpNames: Array[String] = gpFreeAnchors(gpGraph, gpDefLookup, gpHost.gpInstanceId,
			gpMountKind)
		for gpName in gpNames:
			var gpAW: Dictionary = gpAnchorWorld(gpGraph, gpDefLookup, gpHost, gpName)
			if not bool(gpAW["found"]):
				continue
			var gpAnchorPos: Vector2 = gpAW["pos"]
			var gpDist: float = gpAnchorPos.distance_to(gpWorld)
			if gpDist >= float(gpBest["dist"]):
				continue
			gpBest = {
				"hit": gpDist <= gpRadius,
				"parent_uid": gpHost.gpInstanceId,
				"anchor": gpName,
				"pos": gpAnchorPos,
				"dir": gpAW["dir"],
				"dist": gpDist,
			}
	return gpBest


# The BODY fallback of gpMountCandidate(): when the drop point lies INSIDE a host that accepts the
# mount kind but outside every anchor's snap radius, the part must still attach — to the nearest
# compatible anchor of the containing host. Without it a nozzle dropped on a vessel's belly fell
# through to a loose top-level placement: horizontal, directionless, sitting on the very host it
# was aimed at (the reported "the nozzle's direction does not adapt").
# gpMountCandidate() 的**本体**兜底：落点位于接受该挂载类型的宿主**体内**、却不在任何锚点的吸附
# 半径内时，部件仍须挂载 —— 挂到该宿主最近的兼容锚点上。否则落在罐腹的管嘴会降级成松散顶层放置：
# 水平、无方向、恰好压在它所瞄准的宿主上（即用户报告的「管嘴方向不自适应」）。
# Anchor occupancy is deliberately NOT a blocker here (default occupancy is unlimited): stacking
# on a busy anchor is the honest outcome of dropping on a fully-occupied host, and the positioning
# drag that follows lets the user move the part off again.
# 此处刻意**不**把锚点占用当作阻碍（默认容纳数不限）：落在全占用宿主上时叠放是诚实的结果，
# 且随后的定位拖拽让用户随时把部件再挪开。
static func gpBodyCandidate(gpGraph: GPPIDGraph, gpDefLookup: Callable, gpWorld: Vector2,
		gpMountKind: String) -> Dictionary:
	var gpBest: Dictionary = {
		"hit": false,
		"parent_uid": "",
		"anchor": "",
		"pos": Vector2.ZERO,
		"dir": Vector2.ZERO,
		"dist": INF,
	}
	if gpGraph == null or gpMountKind == "":
		return gpBest
	for gpHost in gpGraph.gpNodes:
		var gpNames: Array[String] = gpFreeAnchors(gpGraph, gpDefLookup, gpHost.gpInstanceId,
			gpMountKind)
		if gpNames.is_empty():
			continue
		var gpHostDef: GPSymbolDef = gpDefFor(gpDefLookup, gpHost.gpSymbolId)
		if gpHostDef == null:
			continue
		var gpWT: Dictionary = gpWorldTransform(gpGraph, gpDefLookup, gpHost)
		# World point -> host-local frame: the exact inverse of gpOrientLocal's flip-then-rotate
		# order (rotate back FIRST, then unflip).
		# 世界点 -> 宿主本地系：gpOrientLocal「先翻转后旋转」的精确逆序（先转回，再去镜像）。
		var gpLocal: Vector2 = (gpWorld - (gpWT["origin"] as Vector2)).rotated(
			deg_to_rad(-float(gpWT["rot_deg"])))
		if bool(gpWT["flipped"]):
			gpLocal.x = -gpLocal.x
		var gpSz: Vector2 = gpHostDef.gpDefaultSize
		if absf(gpLocal.x) > gpSz.x * 0.5 or absf(gpLocal.y) > gpSz.y * 0.5:
			continue
		# Side-aware choice: among this host's free anchors, one FACING the side the drop lies on
		# wins over a merely nearer one facing elsewhere — "drop at the bottom, face down" holds
		# even when a side anchor is a little closer to the cursor. When no free anchor faces that
		# side, the plain nearest anchor still attaches (its native orientation), so the part is
		# never refused for aiming at an anchorless face. The per-host pick then competes across
		# hosts on raw distance, exactly as before.
		# 侧向感知：本宿主的空闲锚点中，**朝向落点那一侧**者优先于「距离更近但朝向他侧」者 ——
		# 即便侧锚离光标稍近，「放到罐底就朝下」依然成立。该侧没有朝向它的空闲锚点时，仍以
		# 最近的锚点挂载（原生朝向），故瞄准无锚点的面也绝不会落空。宿主内择优后再按原始距离
		# 跨宿主比较，与原先一致。
		var gpSideDir: Vector2 = gpSideOutwardDir(gpGraph, gpDefLookup, gpHost, gpWorld)
		var gpNearPick: Dictionary = {}
		var gpNearPickD: float = INF
		var gpSidePick: Dictionary = {}
		var gpSidePickD: float = INF
		for gpName in gpNames:
			var gpAW: Dictionary = gpAnchorWorld(gpGraph, gpDefLookup, gpHost, gpName)
			if not bool(gpAW["found"]):
				continue
			var gpDist: float = (gpAW["pos"] as Vector2).distance_to(gpWorld)
			var gpEntry: Dictionary = {
				"hit": true,
				"parent_uid": gpHost.gpInstanceId,
				"anchor": gpName,
				"pos": gpAW["pos"],
				"dir": gpAW["dir"],
				"dist": gpDist,
			}
			if gpDist < gpNearPickD:
				gpNearPickD = gpDist
				gpNearPick = gpEntry
			if gpSideDir != Vector2.ZERO \
					and (gpAW["dir"] as Vector2).dot(gpSideDir) \
						>= (gpAW["dir"] as Vector2).length() * 0.5 \
					and gpDist < gpSidePickD:
				gpSidePickD = gpDist
				gpSidePick = gpEntry
		# WITHIN the host the facing side wins outright; across hosts raw distance decides.
		# 宿主**之内**朝向侧直接取胜；跨宿主由原始距离决定。
		var gpHostPick: Dictionary = gpSidePick if not gpSidePick.is_empty() else gpNearPick
		var gpHostPickD: float = gpSidePickD if not gpSidePick.is_empty() else gpNearPickD
		if not gpHostPick.is_empty() and gpHostPickD < float(gpBest["dist"]):
			gpBest = gpHostPick
	return gpBest


# The mount tuple a LOOSE part released at [param gpWorld] should receive, or {} when the release
# must stay an ordinary move. This closes the gap the place path already covers: dragging an
# existing loose nozzle onto a vessel used to leave it as a loose, directionless symbol sitting on
# the equipment — and an unmounted part never turns its label with a mount axis because it has none.
# 松散部件释放在 [param gpWorld] 时应得到的挂载元组；若此次释放应保持为普通移动则返回 {}。
# 这补上了放置路径早已覆盖的缺口：把已有的松散管嘴拖到容器上，过去只会得到一个压在设备上的
# 松散无方向图元 —— 而未挂载的部件没有安装轴，其标签自然也谈不上随轴转向。
static func gpLooseReleaseAttach(gpGraph: GPPIDGraph, gpDefLookup: Callable, gpNodeId: String,
		gpWorld: Vector2, gpZoom: float) -> Dictionary:
	if gpGraph == null or gpNodeId == "":
		return {}
	var gpN: GPPIDNode = gpGraph.gpGetNode(gpNodeId)
	if gpN == null or gpN.gpIsMounted():
		return {}
	var gpDef: GPSymbolDef = gpDefFor(gpDefLookup, gpN.gpSymbolId)
	if gpDef == null or gpDef.gpMountKind == "":
		return {}
	var gpCand: Dictionary = gpMountCandidate(gpGraph, gpDefLookup, gpWorld, gpZoom,
		gpDef.gpMountKind)
	# Snapping onto a real anchor keeps the anchor's own outward normal as the truth (angle 0);
	# only the BODY fallback needs the facing derived from the side the part was dropped on —
	# otherwise a nozzle dropped on the tank's underside mounts there still pointing up.
	# 吸附到真实锚点时，锚点自身的外法线即为权威（角度 0）；只有**本体兜底**才需要按落点所在侧
	# 推导朝向 —— 否则落到罐底的管嘴会挂在底部却仍朝上。
	var gpViaAnchor: bool = bool(gpCand.get("hit", false))
	if not gpViaAnchor:
		gpCand = gpBodyCandidate(gpGraph, gpDefLookup, gpWorld, gpDef.gpMountKind)
	if not bool(gpCand.get("hit", false)):
		return {}
	var gpAngle: float = 0.0
	if not gpViaAnchor:
		var gpHost: GPPIDNode = gpGraph.gpGetNode(str(gpCand["parent_uid"]))
		var gpSide: Vector2 = gpSideOutwardDir(gpGraph, gpDefLookup, gpHost, gpWorld)
		if gpSide != Vector2.ZERO:
			gpAngle = wrapf(rad_to_deg(gpSide.angle())
				- gpAnchorDirToRotation(gpCand["dir"], gpDef.gpBaseMountRot), -180.0, 180.0)
	return {
		"parent_uid": str(gpCand["parent_uid"]),
		"mount_anchor": str(gpCand["anchor"]),
		"mount_offset": Vector2.ZERO,
		"mount_angle_deg": gpAngle,
	}


# The mount tuple a palette DRAG should land with when dropped at [param gpWorld] — the ONE rule
# shared by the live ghost preview and the actual drop, so what the user sees while dragging is
# exactly what they get on release.
# 图元库**拖出**的部件释放在 [param gpWorld] 时应得到的挂载元组 —— 幽灵实时预览与真正落位共用
# 这**一条**规则，故用户拖动时看到的正是松手后得到的。
#
# Two landings / 两种落点：
#   * within snap range of a free anchor -> the part seats ON the anchor (offset ZERO, angle 0):
#     the snap is the point of being near an anchor, and its outward normal is the truth;
#     吸附距离内有空闲锚点 -> 部件**坐在锚点上**（偏移 ZERO、角度 0）：吸附正是靠近锚点的意义，
#     其外法线即权威；
#   * inside a host's body (no anchor in range) -> the part lands AT THE CURSOR: the stored offset
#     is whatever puts the part's centre under the pointer (host-local), and the facing follows the
#     side the drop lies on.
#     宿主**体内**（无锚点在范围） -> 部件落在**光标处**：存储偏移恰好把部件中心放在指针下
#    （宿主本地系），朝向跟随落点所在的一侧。
#
# {} when the drop is on empty space — the caller keeps its pending gesture then.
# 落在空白处时返回 {} —— 调用方随后保持其待命手势。
static func gpPlacementTuple(gpGraph: GPPIDGraph, gpDefLookup: Callable, gpWorld: Vector2,
		gpZoom: float, gpChildDef: GPSymbolDef) -> Dictionary:
	if gpGraph == null or gpChildDef == null or gpChildDef.gpMountKind == "":
		return {}
	var gpCand: Dictionary = gpMountCandidate(gpGraph, gpDefLookup, gpWorld, gpZoom,
		gpChildDef.gpMountKind)
	if bool(gpCand.get("hit", false)):
		return {
			"hit": true,
			"on_anchor": true,
			"parent_uid": str(gpCand["parent_uid"]),
			"anchor": str(gpCand["anchor"]),
			"anchor_dir": gpCand["dir"],
			"anchor_pos": gpCand["pos"],
			"mount_offset": Vector2.ZERO,
			"mount_angle_deg": 0.0,
		}
	gpCand = gpBodyCandidate(gpGraph, gpDefLookup, gpWorld, gpChildDef.gpMountKind)
	if not bool(gpCand.get("hit", false)):
		return {}
	var gpHost: GPPIDNode = gpGraph.gpGetNode(str(gpCand["parent_uid"]))
	var gpHostDef: GPSymbolDef = gpDefFor(gpDefLookup, gpHost.gpSymbolId) if gpHost != null else null
	if gpHost == null or gpHostDef == null:
		return {}
	var gpAnchor: GPAttachPoint = gpHostDef.gpAttachPointByName(str(gpCand["anchor"]))
	var gpAnchorLocal: Vector2 = gpAnchorLocal(gpHostDef, gpAnchor)
	var gpWT: Dictionary = gpWorldTransform(gpGraph, gpDefLookup, gpHost)
	# The part lands AT THE CURSOR: the offset is the pointer's position expressed in the frame the
	# anchor lives in (un-rotate, then un-flip — the inverse of gpOrientLocal's order).
	# 部件落在**光标处**：偏移即指针位置在锚点所在坐标系中的表达（先反旋转、再去镜像 ——
	# 与 gpOrientLocal 相反的次序）。
	var gpOffset: Vector2 = GPMountDragOps.gpUnorientLocal(gpWorld - (gpWT["origin"] as Vector2),
		bool(gpWT["flipped"]), float(gpWT["rot_deg"])) - gpAnchorLocal
	# Facing: the side the drop lies on wins over the chosen anchor's native normal, so a nozzle
	# dropped on the tank's underside points down even when it rides on a right-facing anchor.
	# 朝向：落点所在侧**胜过**所选锚点的原生法向 —— 即便部件骑在朝右的锚点上，落到罐底的管嘴
	# 也必须朝下。
	var gpAngle: float = 0.0
	var gpSide: Vector2 = gpSideOutwardDir(gpGraph, gpDefLookup, gpHost, gpWorld)
	if gpSide != Vector2.ZERO:
		gpAngle = wrapf(rad_to_deg(gpSide.angle())
			- gpAnchorDirToRotation(gpCand["dir"], gpChildDef.gpBaseMountRot), -180.0, 180.0)
	return {
		"hit": true,
		"on_anchor": false,
		"parent_uid": str(gpCand["parent_uid"]),
		"anchor": str(gpCand["anchor"]),
		"anchor_dir": gpCand["dir"],
		"anchor_pos": gpCand["pos"],
		"mount_offset": gpOffset,
		"mount_angle_deg": gpAngle,
	}


# The world-space outward normal of the side of [param gpHostNode]'s envelope that [param gpWorld]
# lies on: RIGHT of the centre -> +X, below -> +Y, and so on, with the host's own flip and
# rotation carried along. This is what makes "drop the nozzle at the tank's bottom and it faces
# down" a rule instead of an accident of anchor declaration order.
# [param gpWorld] 落在 [param gpHostNode] 包络的哪一侧，就返回那一侧的**世界系**外法向：
# 中心右侧 -> +X、下方 -> +Y……并携带宿主自身的翻转与旋转。由此「管嘴放到罐底就朝下」
# 成为一条规则，而不是锚点声明顺序的偶然。
# ZERO when the point sits at the host centre (no dominant side) or the host has no definition —
# callers keep the native anchor orientation then.
# 点位于宿主中心（无主导侧）或宿主无定义时返回 ZERO —— 此时调用方保持锚点原生朝向。
static func gpSideOutwardDir(gpGraph: GPPIDGraph, gpDefLookup: Callable, gpHostNode: GPPIDNode,
		gpWorld: Vector2) -> Vector2:
	if gpGraph == null or gpHostNode == null:
		return Vector2.ZERO
	var gpWT: Dictionary = gpWorldTransform(gpGraph, gpDefLookup, gpHostNode)
	var gpDef: GPSymbolDef = gpDefFor(gpDefLookup, gpHostNode.gpSymbolId)
	if gpDef == null:
		return Vector2.ZERO
	var gpLocal: Vector2 = (gpWorld - (gpWT["origin"] as Vector2)).rotated(
		deg_to_rad(-float(gpWT["rot_deg"])))
	if bool(gpWT["flipped"]):
		gpLocal.x = -gpLocal.x
	if is_zero_approx(gpLocal.x) and is_zero_approx(gpLocal.y):
		return Vector2.ZERO
	var gpOut: Vector2 = Vector2(signf(gpLocal.x), 0.0) if absf(gpLocal.x) >= absf(gpLocal.y) \
			else Vector2(0.0, signf(gpLocal.y))
	return gpOrientDir(gpOut, bool(gpWT["flipped"]), float(gpWT["rot_deg"])).normalized()


# The anchor among [param gpNames] nearest to [param gpWorld], or the FIRST name when no position
# is known (ZERO) or none resolves. This is what the context-menu attach choice uses so
# "right-click the top of the vessel" adds the nozzle at the top facing up.
# [param gpNames] 中距 [param gpWorld] 最近的锚点；无位置（ZERO）或全部无法解析时回退**第一个**。
# 右键附件选择即用它，使「右键点容器上部」添加的管嘴落在上部朝上。
static func gpNearestAnchorName(gpGraph: GPPIDGraph, gpDefLookup: Callable, gpHostUid: String,
		gpNames: Array[String], gpWorld: Vector2) -> String:
	if gpNames.is_empty():
		return ""
	var gpBest: String = str(gpNames[0])
	if gpGraph == null or gpWorld == Vector2.ZERO:
		return gpBest
	var gpHost: GPPIDNode = gpGraph.gpGetNode(gpHostUid)
	if gpHost == null:
		return gpBest
	var gpBestD: float = INF
	for gpName in gpNames:
		var gpAW: Dictionary = gpAnchorWorld(gpGraph, gpDefLookup, gpHost, gpName)
		if not bool(gpAW["found"]):
			continue
		var gpD: float = (gpAW["pos"] as Vector2).distance_to(gpWorld)
		if gpD < gpBestD:
			gpBestD = gpD
			gpBest = gpName
	return gpBest


# ---------------------------------------------------------------------------
# Subtree (selection / cascade delete / duplicate)
# 子树（框选 / 级联删除 / 复制）
# ---------------------------------------------------------------------------

# The uid plus every descendant uid, breadth-first — the set a cascade delete or a "select with
# subtree" marquee acts on. Cycle-safe.
# uid 及其全部后代 uid，广度优先 —— 级联删除或「连子树一起框选」所作用的集合。环安全。
static func gpSubtree(gpGraph: GPPIDGraph, gpUid: String) -> Array[String]:
	var gpOut: Array[String] = []
	if gpGraph == null or gpUid == "":
		return gpOut
	gpOut.append(gpUid)
	var gpI: int = 0
	while gpI < gpOut.size():
		for gpChild in gpChildrenOf(gpGraph, gpOut[gpI]):
			if not (gpChild.gpInstanceId in gpOut):
				gpOut.append(gpChild.gpInstanceId)
		gpI += 1
	return gpOut


# Resolve a definition through the caller-supplied lookup. A missing / invalid lookup yields
# null, and every caller above treats null as "degrade", never as "crash".
# 经调用方传入的查找器解析定义。查找器缺失 / 无效时返回 null，
# 且上方每个调用方都把 null 当作「降级」，绝不当作「崩溃」。
static func gpDefFor(gpDefLookup: Callable, gpSymbolId: String) -> GPSymbolDef:
	if not gpDefLookup.is_valid():
		return null
	return gpDefLookup.call(gpSymbolId) as GPSymbolDef
