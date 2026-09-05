class_name GPProjectIO
extends RefCounted

# Single source of truth for *.pid.json project loading/saving mechanics.
# *.pid.json 工程读写机制的单一事实来源。
# This is a pure filesystem/serialization helper: it knows nothing about the UI, the
# active canvas, the dock panels, or status messages. Those concerns stay in MainScene.
# 这是纯文件系统 / 序列化助手：它不感知 UI、活动画布、停靠面板或状态栏信息——这些关注点
# 留在主场景。数据主权（自包含文件）在「写入前由调用方把用户图元包嵌入图」这一约定下保持，
# 因为内嵌逻辑属于模型层（GPPIDGraph.gpEmbedUserPacks），而非文件 I/O 本身。
# See docs/架构评审_2026-09-04.md P3 (拆离工程 IO).
# 见「架构评审」P3（拆离工程 IO）。


# Force the canonical .pid.json extension on a raw path so the file is recognised on reopen.
# 给原始路径强制加上规范的 .pid.json 扩展名，便于重新打开时识别。
# Returns a NEW string (does not mutate the argument), so callers keep their raw path intact.
# 返回「新字符串」（不修改入参），调用方可保留原始路径。
static func gpEnsurePidExt(gpPath: String) -> String:
	if gpPath.ends_with(".pid.json"):
		return gpPath
	return gpPath + ".pid.json"


# Serialize gpGraph and write it to disk. The .pid.json extension is enforced automatically.
# 序列化 gpGraph 并写入磁盘；.pid.json 扩展名会被自动强制。
# Returns OK on success, or a FileAccess error code when the file cannot be opened for writing.
# 成功返回 OK，无法打开写文件时返回 FileAccess 错误码。
static func gpWriteProject(gpGraph: GPPIDGraph, gpPath: String) -> int:
	var gpFilePath: String = gpEnsurePidExt(gpPath)
	# The caller is expected to have embedded any user symbol packs already (via
	# GPPIDGraph.gpEmbedUserPacks), because gpToDict() serializes them verbatim.
	# 调用方应已先行内嵌用户图元包（经 GPPIDGraph.gpEmbedUserPacks），因为 gpToDict() 会原样序列化之。
	var gpText: String = JSON.stringify(gpGraph.gpToDict(), "", true)
	var gpF: FileAccess = FileAccess.open(gpFilePath, FileAccess.WRITE)
	if gpF == null:
		return FileAccess.get_open_error()
	gpF.store_string(gpText)
	gpF.close()
	return OK


# Read and reconstruct a project graph from gpPath. Returns null on any failure
# (missing file, malformed JSON, or a non-dictionary root).
# 从 gpPath 读取并重建工程图。任意失败（文件缺失、JSON 损坏、根非字典）均返回 null。
# NOTE: GPPIDGraph.gpFromDict() reconciles the embedded user packs back into the live
# symbol library, so custom symbols are available again after reopening — that side effect
# is part of "load project" semantics and lives on the model, not here.
# 注意：GPPIDGraph.gpFromDict() 会把内嵌用户图元包调和回活动图元库，使重新打开后自定义图元
# 再次可用——该副作用属于「载入工程」语义、位于模型层，而非本模块。
static func gpReadProject(gpPath: String) -> GPPIDGraph:
	var gpF: FileAccess = FileAccess.open(gpPath, FileAccess.READ)
	if gpF == null:
		return null
	var gpText: String = gpF.get_as_text()
	gpF.close()
	var gpParsed: Variant = JSON.parse_string(gpText)
	if gpParsed == null or not (gpParsed is Dictionary):
		return null
	return GPPIDGraph.gpFromDict(gpParsed as Dictionary)
