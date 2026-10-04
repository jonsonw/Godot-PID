class_name GPAddNodeCommand
extends GPCommand
#
# Redo rule / 重做规则:
# The created node object is kept, so redo re-adds the SAME object with the SAME id.
# Re-running gpExecute() on redo would call gpIds.gpNext() again and hand the node a
# brand-new id, silently breaking every edge and every external reference to it.
# 保留所创建的节点对象，因此重做会用相同 id 重新加入同一对象。
# 若重做时再次执行 gpExecute()，会再调 gpIds.gpNext() 拿到全新 id，
# 从而静默断开所有关联边与外部引用。

# Symbol definition id to instantiate (e.g. "pump_centrifugal").
# 要实例化的图元定义 id（如 "pump_centrifugal"）。
var gpSymbolId: String = ""

# Tag/label shown next to the instance (e.g. "P-101"). May be empty.
# 实例旁显示的位号 / 标签（如 "P-101"）。可为空。
var gpTag: String = ""

# Where to place it, in world coordinates.
# 放置位置（世界坐标）。
var gpPos: Vector2 = Vector2.ZERO

# The node this command created. Kept so undo/redo stay id-stable (see header).
# 本命令创建的节点。保留它以保证撤销 / 重做时 id 稳定（见头部说明）。
var _gpNode: GPPIDNode = null

# Optional definition lookup, injected by a caller that already owns a symbol binder. When it is
# invalid the command falls back to the global GPSymbolLibrary — the very source the tag minting
# below already used — so every pre-existing caller keeps its exact behaviour.
# 可选的图元定义查找器，由已持有绑定器的调用方注入。无效时回退到全局 GPSymbolLibrary
# —— 也就是下面铸造位号时本就在用的同一个来源 —— 故所有既有调用方行为完全不变。
var gpDefLookup: Callable = Callable()

# The host's DEFAULT CHILDREN, instantiated in the SAME undo step (规划 §16: placing a vessel
# yields its nozzles + manhole with no extra clicks).
# 宿主的**默认子件**，在**同一个**撤销步内实例化（规划 §16：放置一台设备即得到其管口 + 人孔，
# 无须额外点击）。
#
# WHY THEY LIVE IN THIS COMMAND / 为何由本命令持有：
# One visible user action ("place a vessel") must be one undo step. A second command per part
# would make un-placing a tank take seven Ctrl+Z presses, and the "undo granularity matches the
# perceived action" rule is exactly what this project holds to elsewhere.
# 一次可见的用户动作（「放一台设备」）必须是一个撤销步。每个部件一条命令会让「取消放置一台储罐」
# 要按七次 Ctrl+Z，而「撤销粒度必须与感知到的一次操作对齐」正是本项目在别处同样坚持的规则。
var _gpChildren: Array[GPPIDNode] = []


# Id of the created node, for the caller to select it right after placing. Empty before
# gpExecute() has run.
# 所创建节点的 id，供调用方在放置后立即选中它。gpExecute() 未运行时为空。
# NOTE: this is the HOST id. Its default children are secondary parts and are never what the
# caller wants to select — selecting a pump must not select its discharge stub.
# 注意：这是**宿主** id。其默认子件是次级部件，绝不是调用方想选中的对象 —— 选中一台泵不该同时
# 选中它的排出管口。
var gpCreatedId: String:
	get: return _gpNode.gpInstanceId if _gpNode != null else ""


# Build the command. gpInSymbolId selects the symbol, gpInPos is the world position,
# gpInTag is the optional tag text, gpInLookup resolves symbol definitions (see gpDefLookup).
# 构造命令：gpInSymbolId 选择图元，gpInPos 为世界坐标，gpInTag 为可选位号，
# gpInLookup 解析图元定义（见 gpDefLookup）。
func _init(gpInSymbolId: String, gpInPos: Vector2, gpInTag: String = "",
		gpInLookup: Callable = Callable()) -> void:
	gpSymbolId = gpInSymbolId
	gpPos = gpInPos
	gpTag = gpInTag
	gpDefLookup = gpInLookup
	gpLabel = "添加节点"


# Create (first run) or re-add (redo) the node.
# 首次运行时创建节点，重做时重新加入。
func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or not gpCtx.gpIsReady():
		return false
	if _gpNode == null:
 # "n" (lower case) is the project-wide node-id prefix: the canvas's own placement path
 # and every saved file use it. An upper-case "N" here silently forks the id namespace.
 # "n"（小写）是全项目统一的节点 id 前缀：画布自身的放置路径与所有存档文件都用它。
 # 此处若用大写 "N" 会静默地分叉 id 命名空间。
		var gpId: String = gpCtx.gpIds.gpNext("n")
 # tag must be unique project-wide. Done HERE rather than in gpRedo() so the minted tag
 # is stored on the kept node object and survives undo/redo unchanged.
 # 在此处而非 gpRedo() 中编号，使铸造出的位号存留在被保留的节点对象上，
 # 撤销/重做后保持不变。
		var gpTagToUse: String = gpTag
		if gpTagToUse == "" and gpCtx.gpTags != null:
			gpCtx.gpTags.gpGraph = gpCtx.gpGraph
			gpTagToUse = gpCtx.gpTags.gpNextTag(_gpResolveDef(gpSymbolId))
		_gpNode = gpCtx.gpGraph.gpNewNode(gpId, gpSymbolId, gpTagToUse, gpPos)
		if gpCtx.gpTags != null:
			gpCtx.gpTags.gpRegister(_gpNode.gpInstanceId, _gpNode.gpTag)
		_gpBuildChildren(gpCtx)
	gpCtx.gpGraph.gpAddNode(_gpNode)
	for gpC in _gpChildren:
		gpCtx.gpGraph.gpAddNode(gpC)
	return true


# Remove the node again, together with the default children it brought in. Edges touching it are
# NOT removed: a freshly added node has none, and removing any would lose user work on undo.
# 再次移除该节点，并连同它带来的默认子件。不删除其关联边：刚添加的节点本无边，
# 且删边会让用户在撤销时丢工作。
#
# ORDER: children FIRST, then the host. A listener that reacts to gpNodeRemoved (the canvas
# binder, the tag registry) then always sees a child disappear while its host is still present,
# instead of briefly holding a child whose parent has already gone.
# 顺序：先子件、后宿主。这样对 gpNodeRemoved 做出反应的监听者（画布绑定器、位号注册表）看到的
# 永远是「宿主还在时子件先消失」，而不会短暂持有一个父件已消失的子件。
func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null or _gpNode == null:
		return
	for gpC in _gpChildren:
		gpCtx.gpGraph.gpRemoveNode(gpC.gpInstanceId)
		if gpCtx.gpTags != null:
			gpCtx.gpTags.gpRelease(gpC.gpInstanceId)
	gpCtx.gpGraph.gpRemoveNode(_gpNode.gpInstanceId)
	if gpCtx.gpTags != null:
		gpCtx.gpTags.gpRelease(_gpNode.gpInstanceId)


# Re-add the very same node object, preserving its id — and the very same children, in the same
# order, so the redo is a faithful replay rather than a re-derivation.
# 重新加入同一个节点对象，保持其 id 不变 —— 以及同一批子件、同一顺序，使重做是忠实重放而非重新推导。
func gpRedo(gpCtx: GPCommandContext) -> void:
	if _gpNode == null:
		gpExecute(gpCtx)
		return
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	gpCtx.gpGraph.gpAddNode(_gpNode)
	if gpCtx.gpTags != null:
		gpCtx.gpTags.gpRegister(_gpNode.gpInstanceId, _gpNode.gpTag)
	for gpC in _gpChildren:
		gpCtx.gpGraph.gpAddNode(gpC)
		if gpCtx.gpTags != null:
			gpCtx.gpTags.gpRegister(gpC.gpInstanceId, gpC.gpTag)


# Instantiate the host definition's built-in parts. Called ONCE, on the first execute; redo replays
# the kept objects (see the header's id-stability rule).
# 实例化宿主定义的自带部件。仅**首次执行**时调用一次；重做重放已保留的对象（见头部的 id 稳定规则）。
#
# The mount fields are written HERE, and the world transform is left DERIVED — a default child is
# indistinguishable from a hand-attached one, which is exactly what keeps one renderer, one
# resolver and one detach path serving both.
# 挂载字段在此写入，世界变换仍保持**推导** —— 默认子件与手工挂载的子件因此无法区分，
# 这正是「一个渲染器、一个解析器、一条卸载路径」能同时服务两者的原因。
func _gpBuildChildren(gpCtx: GPCommandContext) -> void:
	_gpChildren.clear()
	# The lookup handed to GPMountResolver must be the RESOLVED one. An invalid injected lookup
	# still has the global library behind it (see _gpResolveDef), but passing the raw invalid
	# Callable through would make every default child "unresolvable" and silently produce no parts
	# at all — a failure that no gate would catch, because "no children" is also a legal outcome.
	# 传给 GPMountResolver 的查找器必须是**已解析**的那个。无效的注入查找器背后仍有全局图元库
	# 兜底（见 _gpResolveDef），但把那个无效的裸 Callable 透传过去，会让每个默认子件都「无法解析」
	# 从而静默地一个部件都不生成 —— 而这种失败没有任何门禁能抓到，因为「没有子件」本身也是合法结果。
	var gpDefaults: Array[Dictionary] = GPMountResolver.gpDefaultChildren(
		Callable(self, "_gpResolveDef"), _gpResolveDef(gpSymbolId))
	for gpD in gpDefaults:
		var gpId: String = gpCtx.gpIds.gpNext("n")
 # DELIBERATELY NO TAG / 刻意不编位号：
 # a nozzle's identifier is its nozzle_id PROPERTY ("N1", "N2", ...), not a project tag; and
 # minting tags for auto-created parts would advance the project's tag sequence every single time
 # a vessel is placed (place one tank -> N1..N4 + manhole consume five numbers). An empty tag
 # renders nothing, which is exactly what a nozzle needs — its text comes from its label slots.
 # 管口的标识是它的 nozzle_id **属性**（"N1"、"N2"……）而非项目位号；为自动创建的部件编位号会让
 # 项目位号序列每放一台设备就前进若干格（放一台储罐 → N1..N4 + 人孔吃掉五个号）。空位号不渲染
 # 任何文字，正是管口所需 —— 它的文字来自自己的文本槽。
		var gpC: GPPIDNode = gpCtx.gpGraph.gpNewNode(gpId, str(gpD["symbol_id"]), "",
			_gpNode.gpPosition, gpD["props"])
		gpC.gpParentUid = _gpNode.gpInstanceId
		gpC.gpMountAnchor = str(gpD["anchor"])
		_gpChildren.append(gpC)


# Resolve a symbol definition through the injected lookup, falling back to the global library.
# 经注入的查找器解析图元定义，回退到全局图元库。
func _gpResolveDef(gpSymbolIdIn: String) -> GPSymbolDef:
	if gpDefLookup.is_valid():
		return gpDefLookup.call(gpSymbolIdIn) as GPSymbolDef
	return GPSymbolLibrary.gpFindById(gpSymbolIdIn)
