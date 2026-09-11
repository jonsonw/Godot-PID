class_name GPDuplicateNodesCommand
extends GPCommand
# Copy selected nodes to a small offset (M4).
# 把选中节点复制到小幅偏移处（M4）。
#
# What is copied / 复制了什么:
#   Symbol id, tag, attributes (deep-copied so the copy cannot alias the original's dict),
#   rotation and flip. Exactly what the interactive path copied before this command existed.
#   图元 id、位号、属性（深拷贝，使副本不会与原件的字典共享引用）、旋转与翻转。
#   与本命令出现之前交互路径所复制的内容完全一致。
#
# What is deliberately NOT copied / 刻意不复制的:
#   Edges between the duplicated nodes. The interactive path never did, and auto-wiring a
#   copy would create connections the user did not ask for. Cross-selection internal edges
#   stay a separate, explicit feature.
#   副本之间的连线。交互路径历来不复制，而自动连线会创建用户并未要求的连接。
#   跨选择集的内部连线保持为一个独立的显式功能。

# Step applied to every copy, in world units. Chosen to be visible but not jumpy.
# 每个副本的偏移量（世界单位）。取值以可见但不跳跃为准。
const GP_OFFSET: Vector2 = Vector2(24.0, 24.0)

# Ids of the nodes to copy, captured at construction.
# 待复制节点的 id，构造时捕获。
var _gpSrcIds: Array[String] = []

# The clone objects, kept so redo re-adds the SAME objects with the SAME ids.
# 副本对象。保留它们使重做能用相同 id 重新加入同一批对象。
var _gpClones: Array[GPPIDNode] = []


# Ids of the copies, available after gpExecute so the caller can select them. The natural
# next user action after a duplicate is to drag the copies into place.
# 副本的 id，gpExecute 之后可用，供调用方选中它们。复制之后用户自然要做的是把副本拖到位。
var gpNewIds: Array[String] = []


# Build the command from the ids to copy.
# 由待复制的 id 构造命令。
func _init(gpInIds: Array[String]) -> void:
	_gpSrcIds = gpInIds.duplicate()
	gpLabel = "复制节点"


# Create the copies. Returns false when none of the ids resolves to a real node, so a stale
# selection produces no undo step.
# 创建副本。若所有 id 都找不到真实节点则返回 false，使过期选择集不产生撤销步。
func gpExecute(gpCtx: GPCommandContext) -> bool:
	if gpCtx == null or not gpCtx.gpIsReady():
		return false
	_gpClones.clear()
	gpNewIds.clear()
	for gpId in _gpSrcIds:
		var gpSrc: GPPIDNode = gpCtx.gpGraph.gpGetNode(gpId)
		if gpSrc == null:
			continue
		var gpNid: String = gpCtx.gpIds.gpNext("n")
		# A copy is a DIFFERENT piece of equipment, so it must NOT inherit the source's tag:
		# two identical tags on one sheet is a drafting defect, and the tag ends up in the
		# DCS point list. The registry mints a fresh one (M9). Without a registry the old
		# behaviour is preserved, which is what the pre-M9 tests assert.
		# 副本是另一台设备，故不应继承原件的位号：一张图纸上出现两个相同位号是制图缺陷，
		# 且该位号最终会进 DCS 点表。由注册器铸造新位号（M9）。无注册器时保留旧行为，
		# 这正是 M9 之前测试所断言的。
		var gpCopyTag: String = gpSrc.gpTag
		if gpCtx.gpTags != null:
			gpCtx.gpTags.gpGraph = gpCtx.gpGraph
			gpCopyTag = gpCtx.gpTags.gpNextTag(GPSymbolLibrary.gpFindById(gpSrc.gpSymbolId))
		var gpCopy: GPPIDNode = gpCtx.gpGraph.gpNewNode(
			gpNid, gpSrc.gpSymbolId, gpCopyTag,
			gpSrc.gpPosition + GP_OFFSET,
			gpSrc.gpProps.duplicate(true))
		gpCopy.gpRotationDeg = gpSrc.gpRotationDeg
		gpCopy.gpFlipped = gpSrc.gpFlipped
		gpCtx.gpGraph.gpAddNode(gpCopy)
		if gpCtx.gpTags != null:
			gpCtx.gpTags.gpRegister(gpNid, gpCopyTag)
		_gpClones.append(gpCopy)
		gpNewIds.append(gpNid)
	return not _gpClones.is_empty()


# Remove the copies again.
# 再次移除副本。
func gpUndo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	for gpN in _gpClones:
		gpCtx.gpGraph.gpRemoveNode(gpN.gpInstanceId)
	if gpCtx.gpTags != null:
		for gpN in _gpClones:
			gpCtx.gpTags.gpRelease(gpN.gpInstanceId)


# Re-add the very same clone objects (ids stay stable, so any later reference holds).
# 重新加入同一批副本对象（id 保持稳定，故后续引用依然成立）。
func gpRedo(gpCtx: GPCommandContext) -> void:
	if gpCtx == null or gpCtx.gpGraph == null:
		return
	for gpN in _gpClones:
		gpCtx.gpGraph.gpAddNode(gpN)
		if gpCtx.gpTags != null:
			gpCtx.gpTags.gpRegister(gpN.gpInstanceId, gpN.gpTag)
