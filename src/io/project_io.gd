class_name GPProjectIO
extends RefCounted

# Single source of truth for *.pid.json project loading/saving mechanics.
# *.pid.json 工程读写机制的单一事实来源。
# This is a pure filesystem/serialization helper: it knows nothing about the UI, the
# active canvas, the dock panels, or status messages. Those concerns stay in MainScene.
# 这是纯文件系统 / 序列化助手：它不感知 UI、活动画布、停靠面板或状态栏信息——这些关注点
# 留在主场景。数据主权（自包含文件）在「写入前由调用方把用户图元包嵌入图」这一约定下保持，
# 因为内嵌逻辑属于模型层（GPPIDGraph.gpEmbedUserPacks()），而非文件 I/O 本身。
# See docs/架构评审_.md P3 (拆离工程 IO).
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
static func gpWriteProject(gpGraph: GPPIDGraph, gpPath: String, gpAuthor: String = "local",
		gpAt: String = "", gpPriorRevisions: Array = []) -> int:
	var gpFilePath: String = gpEnsurePidExt(gpPath)
	# The caller is expected to have embedded any user symbol packs already (via
	# GPPIDGraph.gpEmbedUserPacks()), because gpToDict() serializes them verbatim.
	# 调用方应已先行内嵌用户图元包（经 GPPIDGraph.gpEmbedUserPacks()），因为 gpToDict() 会原样序列化之。
	# ATOMIC WRITE (ADR-4): the text is built and verified in a temp file, then renamed over
	# the target. Writing straight into the target (the old behaviour) left a truncated,
	# unparseable archive whenever the process died mid-write. The previous good copy is kept
	# as <path>.bak so a bad save still has a fallback.
	# 原子写（ADR-4）：文本先在临时文件中构造并校验，再 rename 覆盖目标。
	# 直接写目标（旧行为）在进程写入途中死亡时会留下被截断、无法解析的存档。
	# 上一份完好副本保留为 <path>.bak，使一次失败的保存仍有退路。
	# W14 (ADR-40 D6): every save stamps a content revision into the header (optimistic
	# concurrency backstop; GPRevision owns the chain mechanics).
	# W14（ADR-40 D6）：每次保存都向头部盖内容修订（乐观并发兜底；链机制归 GPRevision）。
	var gpOut: Dictionary = gpGraph.gpToDict()
	_gpCarryProjectSections(gpOut, gpFilePath, [])
	GPRevision.gpStampRevision(gpOut, gpAuthor, gpAt, gpPriorRevisions)
	var gpWrite: GPIOResult = GPAtomicFile.gpWriteJsonAtomic(gpFilePath, gpOut)
	if not gpWrite.gpIsOk():
		return FAILED
	return OK


# Result-typed variant of gpWriteProject(): reports WHY a write failed instead of a bare int.
# gpWriteProject() 的结果类型版本：说明写入「为何」失败，而非仅返回裸 int。
# The legacy int API is preserved verbatim and reused, so no existing caller changes.
# 旧 int API 原样保留并被复用，故既有调用方无需改动。
static func gpWriteProjectResult(gpGraph: GPPIDGraph, gpPath: String, gpAuthor: String = "local",
		gpAt: String = "", gpPriorRevisions: Array = []) -> GPIOResult:
	var gpFilePath: String = gpEnsurePidExt(gpPath)
	var gpErr: int = gpWriteProject(gpGraph, gpFilePath, gpAuthor, gpAt, gpPriorRevisions)
	if gpErr != OK:
		return GPIOResult.gpFailure("io.write_failed", "status.save_fail", gpFilePath)
	return GPIOResult.gpSuccess("io.saved", gpFilePath)


# W14 fix (2026-11-18): saves rebuild the container from the MODEL, so project-level
# sections (project_meta, members) silently revert — the freshly created v4 name was
# clobbered (card title fell back to the sheet tab name: the reported "project name
# changed" bug) and the roster was wiped (which also disarmed the multi-user login
# gate). The CURRENT disk state is the source of truth for these sections: the identity
# panel writes straight to it, a session snapshot goes stale, and the zero-sheet open
# path never had one. A legacy meta["name"] (rename-blade artifact) is PROMOTED into
# project_meta.name — never copied to both keys (ADR-41 rename rule).
# Call BEFORE gpStampRevision so the stamped hash covers what is actually written.
# W14 修复（2026-11-18）：保存按模型重建容器，工程级段（project_meta、members）被静默
# 清空 —— 新建 v4 工程名被盖掉（卡片标题回退成图纸标签名，即用户报的「项目名变了」），
# 名单被抹（连带拆掉了多用户登录门）。这些段以**当前盘上状态**为事实源：身份面板直接
# 写盘，会话快照会陈旧，零图纸打开通路根本没有快照。旧档 meta["name"]（重命名刀产物）
# **升格**为 project_meta.name —— 绝不复制到两个键下（ADR-41 重命名规则）。
# 必须在 gpStampRevision **之前**调用，使盖下的哈希覆盖实际写出的内容。
static func _gpCarryProjectSections(gpOut: Dictionary, gpFilePath: String,
		gpMembers: Array) -> void:
	var gpPrior: GPIOResult = GPAtomicFile.gpReadJsonDict(gpFilePath)
	if gpPrior.gpIsOk() and (gpPrior.gpPayload is Dictionary):
		var gpPriorDict: Dictionary = gpPrior.gpPayload as Dictionary
		if gpPriorDict.get("project_meta") is Dictionary:
			gpOut["project_meta"] = (gpPriorDict.get("project_meta") as Dictionary).duplicate(true)
		elif gpPriorDict.get("meta") is Dictionary \
				and str((gpPriorDict.get("meta") as Dictionary).get("name", "")) != "":
			# Legacy promotion: the rename blade wrote meta.name on a pre-v4 archive.
			# 旧档升格：重命名刀曾对 v4 前存档写过 meta.name。
			gpOut["project_meta"] = {"name": str((gpPriorDict.get("meta") as Dictionary).get("name", ""))}
		if gpPriorDict.get("members") is Array:
			gpOut["members"] = (gpPriorDict.get("members") as Array).duplicate(true)
			return
	# Fallback (unreadable/new archive): the session-carried roster rides through.
	# 兜底（读不到档 / 新档）：随会话携带的名单照常写入。
	if not gpMembers.is_empty():
		gpOut["members"] = gpMembers.duplicate(true)


# Read and reconstruct a project graph from gpPath. Returns null on any failure
# (missing file, malformed JSON, or a non-dictionary root).
# 从 gpPath 读取并重建工程图。任意失败（文件缺失、JSON 损坏、根非字典）均返回 null。
# NOTE: GPPIDGraph.gpFromDict() reconciles the embedded user packs back into the live
# symbol library, so custom symbols are available again after reopening — that side effect
# is part of "load project" semantics and lives on the model, not here.
# 注意：GPPIDGraph.gpFromDict() 会把内嵌用户图元包调和回活动图元库，使重新打开后自定义图元
# 再次可用——该副作用属于「载入工程」语义、位于模型层，而非本模块。
static func gpReadProject(gpPath: String) -> GPPIDGraph:
	# Delegated to GPAtomicFile so every archive read shares one failure taxonomy
	# (io.open_failed vs io.parse_failed) and one place to add BOM / encoding handling later.
	# 委派给 GPAtomicFile，使所有存档读取共用一套失败分类
	# （io.open_failed 与 io.parse_failed）与一处将来加 BOM / 编码处理的地方。
	var gpRead: GPIOResult = GPAtomicFile.gpReadJsonDict(gpPath)
	if not gpRead.gpIsOk():
		return null
	return GPPIDGraph.gpFromDict(gpRead.gpPayload as Dictionary)


# Write a MULTI-SHEET project as a v3 container.
# 把**多图纸**工程写成 v3 容器。
# Single-sheet projects keep using gpWriteProject(): it leaves the file in the v2 shape, which
# means every archive written before this feature stays byte-stable. Only a project that
# actually HAS several sheets is upgraded (see 持久化实现方案 §6.3).
# 单图纸工程继续使用 gpWriteProject()：它让文件保持 v2 形态，
# 意味着本功能之前写出的每个存档都保持字节稳定。只有**确实**有多张图纸的工程才升格。
# Project-level data (meta / tag_rules / embedded packs) is taken from the FIRST sheet's
# graph, because that is where GPPIDGraph keeps it today.
# 工程级数据（meta / tag_rules / 内嵌图元包）取自**第一张**图纸的图，
# 因为 GPPIDGraph 目前就是把它存在那里的。
static func gpWriteSheets(gpSheets: Array, gpPath: String, gpLinks: Array = [],
		gpAuthor: String = "local", gpAt: String = "", gpPriorRevisions: Array = [],
		gpMembers: Array = []) -> int:
	if gpSheets.is_empty():
		return FAILED
	var gpFilePath: String = gpEnsurePidExt(gpPath)
	var gpFirst: GPSheet = gpSheets[0] as GPSheet
	var gpBase: Dictionary = {}
	if gpFirst != null and gpFirst.gpGraph != null:
		gpBase = gpFirst.gpGraph.gpToDict()
	var gpOut: Dictionary = GPSchemaMigrate.gpMigrate(gpBase)
	var gpSheetsOut: Array = []
	var gpI: int = 0
	for gpS in gpSheets:
		var gpSheet: GPSheet = gpS as GPSheet
		if gpSheet == null:
			continue
		var gpD: Dictionary = gpSheet.gpToDict()
 # Re-derive the index: a stale index survives a reordered tab bar and would put two
 # sheets in the same slot.
 # 重新推导 index：过期的 index 会在标签重排后存活，导致两张图纸落进同一个位置。
		gpD["index"] = gpI
		gpSheetsOut.append(gpD)
		gpI += 1
	if gpSheetsOut.is_empty():
		return FAILED
	gpOut["sheets"] = gpSheetsOut
	gpOut["kind"] = GPSchemaMigrate.GP_KIND_PROJECT
	gpOut["meta"]["sheets"] = gpSheetsOut.size()
	# ADR-41 (revised 2026-11-09): every multi-sheet save is stamped to container v4 —
	# the ONLY container form (no v1-v3 tolerance). The three project-level sections and
	# the version key are owned by GPProjectContainerV4; this file stays a delegation line.
	# ADR-41（2026-11-09 修订）：每次多图纸保存都盖为容器 v4 —— 唯一容器形态（不做 v1–v3 宽容读）。
	# 三个工程级段与版本键归 GPProjectContainerV4 所有；本文件只保留这一行转发。
	GPProjectContainerV4.gpStampV4(gpOut)
	# W14 fix (2026-11-18): project-level sections are carried from the CURRENT disk
	# state — the session snapshot param (gpMembers) is now the FALLBACK only, because
	# the zero-sheet open path never had one and a snapshot goes stale mid-session.
	# W14 修复（2026-11-18）：工程级段改从**当前盘上状态**携带 —— 会话快照参数
	#（gpMembers）降级为**兜底**：零图纸打开通路没有快照，快照在会话中途也会陈旧。
	_gpCarryProjectSections(gpOut, gpFilePath, gpMembers)
	# ADR-43: container-level cross-sheet links go out under the HISTORIC "cross_links" key
	# (reserved by the multi-document era; the migration chain preserves it). The key is
	# written ONLY when links exist, and the array is sorted by id so repeated saves are
	# byte-stable. A single-sheet project can never carry a VALID link (both ends would sit
	# in one sheet), so the caller passing an empty array here is the normal path.
	# ADR-43：容器级跨图纸连接写入历史预留键 "cross_links"（多文档时代预留、迁移链已保全）。
	# 键仅在确有连接时写出，且数组按 id 排序使重复保存字节稳定。单图纸工程不可能有**合法**
	# link（两端会同处一张图），调用方传空数组即常规路径。
	if not gpLinks.is_empty():
		# Sort the MODEL objects first (the comparator is typed for GPOffPageLink), THEN
		# serialise. Sorting the dict array instead fails the comparator's Object typing —
		# GUT caught it as "Cannot convert argument 1 from Dictionary to Object" and the
		# sort silently never happened.
		# 先对**模型对象**排序（比较器的形参类型是 GPOffPageLink），再序列化。
		# 若直接排字典数组，比较器的 Object 形参失配 —— GUT 以
		# 「Cannot convert argument 1 from Dictionary to Object」抓到，且排序静默失效。
		var gpModels: Array[GPOffPageLink] = []
		for gpL in gpLinks:
			var gpModel: GPOffPageLink = gpL as GPOffPageLink
			if gpModel != null:
				gpModels.append(gpModel)
		if not gpModels.is_empty():
			gpModels.sort_custom(GPOffPageLink.gpCompareId)
			var gpLinksOut: Array = []
			for gpModel in gpModels:
				gpLinksOut.append(gpModel.gpToDict())
			gpOut["cross_links"] = gpLinksOut
	# W14 (ADR-40 D6): every multi-sheet save stamps a content revision into the v4 header
	# AFTER the payload is fully assembled (cross_links included), so the hash covers the
	# exact bytes being written; GPRevision owns the chain mechanics.
	# W14（ADR-40 D6）：每次多图纸保存都在载荷**完全装配后**（含 cross_links）向 v4 头部
	# 盖内容修订，使哈希覆盖即将写出的确切内容；链机制归 GPRevision。
	GPRevision.gpStampRevision(gpOut, gpAuthor, gpAt, gpPriorRevisions)
	var gpWrite: GPIOResult = GPAtomicFile.gpWriteJsonAtomic(gpFilePath, gpOut)
	if not gpWrite.gpIsOk():
		return FAILED
	return OK


# Result-typed variant of gpWriteSheets(). / gpWriteSheets() 的结果类型版本。
static func gpWriteSheetsResult(gpSheets: Array, gpPath: String, gpLinks: Array = [],
		gpAuthor: String = "local", gpAt: String = "", gpPriorRevisions: Array = [],
		gpMembers: Array = []) -> GPIOResult:
	var gpErr: int = gpWriteSheets(gpSheets, gpPath, gpLinks, gpAuthor, gpAt, gpPriorRevisions,
		gpMembers)
	if gpErr != OK:
		return GPIOResult.gpFailure("io.write_failed", "status.save_fail", gpPath)
	return GPIOResult.gpSuccess("io.saved", gpPath)


# Read a project as a list of sheets PLUS the container-level off-page links (ADR-43).
# Works for v1/v2/v3 alike: a single-sheet archive comes back as a ONE-element sheet array
# and an EMPTY link array, so callers need no special case. Historic {from_doc,...}
# cross_links entries are read-tolerated as skipped (ADR-43 D2).
# 把工程读成「图纸列表 + 容器级跨图纸连接」（ADR-43）。对 v1/v2/v3 一视同仁：单图纸存档
# 返回**单元素**图纸数组与**空**连接数组，调用方无需特例分支。历史 {from_doc,…} 形状的
# cross_links 读取时容忍跳过（ADR-43 D2）。
static func gpReadSheetsWithLinks(gpPath: String) -> GPIOResult:
	var gpRead: GPIOResult = GPProjectImport.gpReadArchive(gpPath)
	if not gpRead.gpIsOk():
		return gpRead
	var gpV3: Dictionary = gpRead.gpPayload as Dictionary
	if gpV3.is_empty():
		# W13 fix (2026-11-11): an empty payload is reported HONESTLY as zero sheets — io
		# cannot reach I18n (layer rule), so a padded sheet could only ever be NAMELESS,
		# and its empty title blanked the tab bar / pop-out title / pane pickers. The SHELL
		# owns the "one fresh sheet" semantics (GPFreshOpen.gpOpen).
		# W13 修复：空载荷**如实**上报零张图纸 —— io 拿不到 I18n（分层铁律），补的图纸
		# 只能无名，空名曾刷空标签栏/摘出窗口标题/窗格选择器。开图语义归外壳
		#（GPFreshOpen.gpOpen）。
		GPSymbolLibrary.gpSetDocSizeScale(1.0)
		# W14: the empty payload honestly reports empty revision state too.
		# W14：空载荷同样如实上报空的修订状态。
		return GPIOResult.gpSuccessWith(
			{"sheets": [], "links": [], "revision": "", "revisions": []}, "io.loaded", gpPath)
	# P0-5: set the shared library's symbol scale BEFORE any sheet / user pack is rebuilt.
	# The previous document may have left a legacy 0.5 active; registering this archive's
	# packs against the wrong scale would double-shrink (or double-grow) them.
	# P0-5：在重建任何图纸 / 用户包**之前**设置共享图库尺度。上一份文档可能留下旧档 0.5；
	# 用错误尺度注册本档用户包会把它二次缩小（或放大）。
	var gpRawSheets: Array = gpV3.get("sheets", []) as Array
	if gpRawSheets.is_empty():
		GPSymbolLibrary.gpSetDocSizeScale(1.0)
	else:
		var gpFirstRaw: Dictionary = (gpRawSheets[0] as Dictionary).duplicate(true)
		gpFirstRaw["meta"] = (gpV3.get("meta", {}) as Dictionary).duplicate(true)
		GPSymbolLibrary.gpSetDocSizeScale(GPSheet.gpScaleForSheetDict(gpFirstRaw))
	var gpSheetsOut: Array = []
	var gpI: int = 0
	for gpS in gpRawSheets:
		var gpD: Dictionary = (gpS as Dictionary).duplicate(true)
		gpD["index"] = gpI
 # Project-level data is copied onto every sheet so the graph rebuild can reconcile
 # embedded packs regardless of which tab is opened first.
 # 工程级数据复制到每张图纸上，使无论先打开哪一页，图重建都能调和内嵌图元包。
 # ADR-36: numbering rules are NOT copied per sheet any more — one standard is parsed from
 # the container and ADOPTED by every sheet's graph below, so all tabs share one convention
 # (and one set of sequence marks) instead of diverging copies.
 # ADR-36：编号规则不再逐图纸复制 —— 由容器解析出**一份**标准，下面被每张图纸的图采纳，
 # 使所有标签页共享同一套约定（与同一组水位线），而不是各自分叉的副本。
		gpD["meta"] = (gpV3.get("meta", {}) as Dictionary).duplicate(true)
		gpD["user_symbol_packs"] = ((gpV3.get("library", {}) as Dictionary).get(
			"packs", []) as Array).duplicate(true)
		gpD.erase("tag_rules")
		gpSheetsOut.append(GPSheet.gpFromDict(gpD))
		gpI += 1
	# W13 fix (2026-11-11): an explicitly empty sheet list is reported AS EMPTY — the old
	# pad produced a NAMELESS sheet (v4 containers carry project_meta, not meta) whose
	# empty title blanked every title surface. The SHELL opens it via GPFreshOpen.gpOpen.
	# W13 修复：显式空图纸列表**如实**上报为空 —— 旧的补图产出**无名**图纸（v4 容器是
	# project_meta 而非 meta），空名刷空所有标题表面。开图归外壳 GPFreshOpen.gpOpen。
	# One standard object, adopted by every sheet. Absent in a v1/v2 file without rules:
	# then the graphs stay null and a first mint creates one lazily (single-sheet behaviour
	# is unchanged; cross-sheet sharing is seeded on the first rule edit or by a new tab).
	# 一个标准对象，由每张图纸采纳。v1/v2 文件若没有规则则缺失：此时图保持 null，
	# 首次铸号时惰性创建（单图纸行为不变；跨页共享由首次改规则或新建标签页播下）。
	if gpV3.has("tag_rules"):
		var gpStd: GPProjectStandard = GPProjectStandard.gpFromDict(
			gpV3.get("tag_rules", {}) as Dictionary)
		var gpNoUsed: Dictionary = GPSheetNumbering.gpUsedNumbers(gpSheetsOut)
		for gpSheetRaw in gpSheetsOut:
			var gpSheetObj: GPSheet = gpSheetRaw as GPSheet
			if gpSheetObj != null and gpSheetObj.gpGraph != null:
				gpSheetObj.gpGraph.gpAdoptStandard(gpStd)
				# ADR-38: a sheet with no number yet (an archive from before numbering) gets
				# one from the project rule, and its EMPTY title-block fields inherit the
				# project info — per-sheet values the user typed are left alone.
				# ADR-38：尚无编号的图纸（编号功能之前的存档）按项目规则补号，其**空缺**的标题栏
				# 字段继承项目信息 —— 用户逐张填过的值不动。
				if gpSheetObj.gpNumber.strip_edges() == "":
					var gpNo: String = GPSheetNumbering.gpNextNumber(gpNoUsed, gpStd)
					gpSheetObj.gpAssignNumber(gpNo)
					gpNoUsed[gpNo] = true
				gpSheetObj.gpApplyProjectInfo(gpStd)
	# ADR-43: rebuild the container-level links. Only the NEW record shape enters the
	# model; historic shape entries are skipped (and stay untouched on disk until the
	# next save, which rebuilds the container from models — the same policy as every
	# other project-level section).
	# ADR-43：重建容器级连接。仅新记录形状进入模型；历史形状条目跳过（磁盘上原样保留，
	# 直到下一次保存按模型重建容器 —— 与其他工程级数据段同一策略）。
	var gpLinksOut: Array[GPOffPageLink] = []
	# Typed as Variant then guarded: a hand-edited file may carry cross_links as a dict or
	# scalar, and `null as Array` would crash the loop below instead of degrading.
	# 以 Variant 读取并加守卫：手改文件可能把 cross_links 写成字典或标量，
	# `null as Array` 会让下面的循环崩溃而非优雅降级。
	var gpRawLinks: Variant = gpV3.get("cross_links", null)
	if gpRawLinks is Array:
		for gpRaw in gpRawLinks as Array:
			if not (gpRaw is Dictionary):
				continue
			var gpLink: GPOffPageLink = GPOffPageLink.gpFromDict(gpRaw as Dictionary)
			if gpLink != null:
				gpLinksOut.append(gpLink)
	return GPIOResult.gpSuccessWith(
		{
			"sheets": gpSheetsOut,
			"links": gpLinksOut,
			# W14 (ADR-40 D6): carry the header revision state out to the shell, which
			# compares it against the on-disk revision before the NEXT save (optimistic
			# concurrency). The revisions list rides along for chain continuity.
			# W14（ADR-40 D6）：把头部修订状态带出给外壳，供下一次保存前与盘上修订比对
			#（乐观并发）。修订清单随行，保证链的连续性。
			"revision": str(gpV3.get("revision", "")),
			"revisions": (gpV3.get("revisions", []) as Array) if (gpV3.get("revisions") is Array) else [],
			# T4a: the roster rides along for the session save write-back.
			# T4a：名单随行，供会话保存回写。
			"members": (gpV3.get("members", []) as Array) if (gpV3.get("members") is Array) else [],
		},
		"io.loaded", gpPath)


# W14 (ADR-40 D6 / F02): read ONLY the plaintext header revision state of an archive —
# the cheap probe the shell runs before overwriting a file, so two stations editing the
# same archive on a LAN share detect the conflict BEFORE either write lands.
# W14（ADR-40 D6 / F02）：只读取档的明文头部修订状态 —— 外壳在覆盖文件前运行的廉价探针，
# 使局域网共享盘上编辑同一存档的两个工作站**在任何一方写入前**就发现冲突。
# Payload on success: {"revision": String, "revisions": Array}（缺键 → 空串 / 空数组）。
static func gpReadHeader(gpPath: String) -> GPIOResult:
	var gpRead: GPIOResult = GPAtomicFile.gpReadJsonDict(gpPath)
	if not gpRead.gpIsOk():
		return gpRead
	var gpDict: Dictionary = gpRead.gpPayload as Dictionary
	var gpList: Array = (gpDict.get("revisions", []) as Array) if (gpDict.get("revisions") is Array) else []
	var gpMembers: Array = (gpDict.get("members", []) as Array) if (gpDict.get("members") is Array) else []
	return GPIOResult.gpSuccessWith(
		{
			"revision": str(gpDict.get("revision", "")),
			"revisions": gpList,
			# W14 T4a: the roster rides along so the identity coordinator can decide the
			# login mode without a second file read.
			# W14 T4a：名单随行，使身份协调者无需第二次读文件即可判定登录模式。
			"members": gpMembers,
		},
		"io.loaded", gpPath)


# Backward-compatible wrapper: sheets only. / 兼容包装：仅图纸列表。
# Kept for callers that do not care about links (and for older tests); new shell code
# should call gpReadSheetsWithLinks() so links are not silently dropped.
# 供不关心连接的调用方（及既有测试）使用；新的外壳代码应调 gpReadSheetsWithLinks()，
# 否则连接会被静默丢弃。
static func gpReadSheets(gpPath: String) -> GPIOResult:
	var gpRead: GPIOResult = gpReadSheetsWithLinks(gpPath)
	if not gpRead.gpIsOk():
		return gpRead
	var gpPayload: Dictionary = gpRead.gpPayload as Dictionary
	return GPIOResult.gpSuccessWith(gpPayload.get("sheets", []), "io.loaded", gpPath)


# Result-typed variant of gpReadProject(): distinguishes "file missing/unreadable" from
# "malformed JSON" and returns the reconstructed graph in gpPayload on success.
# gpReadProject() 的结果类型版本：区分「文件缺失/不可读」与「JSON 损坏」，
# 并在成功时把重建出的图放入 gpPayload。
# The legacy GPPIDGraph API is preserved and reused, so no existing caller changes.
# 旧 GPPIDGraph API 原样保留并被复用，故既有调用方无需改动。
static func gpReadProjectResult(gpPath: String) -> GPIOResult:
	if not FileAccess.file_exists(gpPath):
		return GPIOResult.gpFailure("io.open_failed", "status.load_fail", gpPath)
	var gpGraph: GPPIDGraph = gpReadProject(gpPath)
	if gpGraph == null:
		return GPIOResult.gpFailure("io.parse_failed", "status.load_fail", gpPath)
	return GPIOResult.gpSuccessWith(gpGraph, "io.loaded", gpPath)
