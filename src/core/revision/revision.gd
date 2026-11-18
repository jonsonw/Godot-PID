class_name GPRevision
extends RefCounted
# Copyright © 2026 Jonson Wang
# Content revision hash chain (ADR-40 D6 optimistic concurrency, Todo F02; W14).
# 内容修订哈希链（ADR-40 D6 乐观并发，Todo F02；W14）。
#
# WHY / 为何存在：
# A LAN file server lets two workstations open the same *.pid.json; the second writer would
# silently overwrite the first. The ONLY reliable backstop (SMB/NFS locks are best-effort)
# is an optimistic check: every save stamps a content hash (the "revision"), and the shell
# refuses to write when the on-disk revision moved since this session loaded it. The hash
# also makes any byte tampering detectable, and the entries chain parent -> child so a
# trimmed history still proves internal consistency.
# 局域网文件服务器允许两个工作站打开同一个 *.pid.json；后写者会静默覆盖先写者。
# 唯一可靠的兜底（SMB/NFS 锁只是尽力而为）是乐观校验：每次保存盖一个内容哈希
# （即「修订」），当盘上修订与本会话载入时不一致时，外壳拒绝写入。哈希同时使任何
# 字节篡改可被察觉，条目按 parent -> child 链接，使被截断的历史仍可证明内部一致。
#
# HEADER KEYS / 头部键（v4 容器明文 header，冻结登记见 project_container_v4.gd）：
#   "revision":       String  当前内容哈希（hex）
#   "revisions":      Array   修订清单，每条 {revision, parent, author, at}，上限 GP_MAX_REVISIONS
#   "last_saved_by":  String  最后保存者（会话用户；未登录＝"local"）
#   "last_saved_at":  String  最后保存时间（ISO，由调用方传入）
#
# LAYER RULE / 分层约束：pure static helpers, zero autoload / FileAccess — core stays
# headless-testable. HashingContext is an engine class, not an autoload.
# 纯静态助手，零 autoload / FileAccess —— core 保持 headless 可测。
# HashingContext 是引擎类，不是 autoload。
#
# NUMBER NORMALIZATION / 数值归一：JSON round-trips ints as floats in Godot, so the
# canonical form renders an integral float as an integer string; otherwise the same
# document would hash differently before and after a save/load cycle.
# JSON 在 Godot 中往返会把整数变成浮点，故规范形把「整值浮点」渲染为整数字符串；
# 否则同一文档在存读前后会得到不同哈希。

# Keys excluded from the hash: they ARE the revision metadata, so hashing them would
# make the hash self-referential.
# 从哈希中排除的键：它们本身就是修订元数据，纳入会使哈希自我指涉。
const GP_EXCLUDED_KEYS: Array[String] = [
	"revision", "revisions", "last_saved_by", "last_saved_at",
]

# Machine-readable codes (ADR-12 refusal-code semantics).
# 机器可读码（沿用 ADR-12 拒绝码语义）。
const GP_ERR_BAD_HASH: String = "revision.bad_hash"
const GP_ERR_BAD_CHAIN: String = "revision.bad_chain"

# Cap on the retained revision list so a long-lived project file cannot grow without
# bound; the oldest entries are dropped (the chain among survivors stays intact).
# 修订清单保留上限，使长寿命工程文件不会无界增长；最老条目被丢弃
#（幸存条目间的链仍完整）。
const GP_MAX_REVISIONS: int = 100


# Deterministic JSON form: object keys sorted, numbers normalized, arrays in order.
# 确定性 JSON 形态：对象键排序、数值归一、数组按序。
static func gpCanonicalJson(gpValue: Variant) -> String:
	return _gpCanonicalValue(gpValue)


# revision = sha256(canonical(payload-minus-header) || parent). Parent chains the entry
# to what this session loaded; "" starts a fresh chain (first save / legacy archive).
# When the value is a Dictionary (a project container) the excluded header keys are
# stripped before hashing, so stamp / verify / tamper tests all hash the same payload.
# revision = sha256(规范形(去头部载荷) || parent)。parent 把条目链到本会话载入的修订；
# 空串表示开启新链（首次保存 / 旧档）。值为 Dictionary（工程容器）时，哈希前先剔除
# 排除的头部键，使盖章 / 校验 / 篡改测试对同一载荷取哈希。
static func gpComputeRevision(gpValue: Variant, gpParent: String) -> String:
	var gpPayload: Variant = gpValue
	if gpValue is Dictionary:
		gpPayload = _gpHashPayload(gpValue)
	return _gpSha256Hex(gpCanonicalJson(gpPayload) + "||" + gpParent)


# Stamp header keys onto a container IN PLACE. parent = the container's current
# "revision" ("" when absent — a legacy archive or a rebuilt container). Prior entries
# (carried through the session from the last load/save) are preserved so the list is a
# running history, trimmed to GP_MAX_REVISIONS. Returns the new revision.
# 就地给容器盖头部键。parent ＝容器当前 "revision"（缺省为空串——旧档或重建的容器）。
# 会话携带的先前条目被保留，使清单成为连续历史，并按 GP_MAX_REVISIONS 截断。
# 返回新修订值。
static func gpStampRevision(gpContainer: Dictionary, gpAuthor: String, gpAt: String,
		gpPriorRevisions: Array = []) -> String:
	var gpParent: String = str(gpContainer.get("revision", ""))
	var gpNew: String = gpComputeRevision(gpContainer, gpParent)
	gpContainer["revision"] = gpNew
	# The save stamp (who / when) is header metadata, NOT part of the hash (excluded keys).
	# 保存盖章（谁 / 何时）是头部元数据，**不参与哈希**（排除键）。
	gpContainer["last_saved_by"] = gpAuthor
	gpContainer["last_saved_at"] = gpAt
	var gpList: Array = []
	for gpRaw in gpPriorRevisions:
		if gpRaw is Dictionary:
			gpList.append((gpRaw as Dictionary).duplicate(true))
	gpList.append({
		"revision": gpNew,
		"parent": gpParent,
		"author": gpAuthor,
		"at": gpAt,
	})
	while gpList.size() > GP_MAX_REVISIONS:
		gpList.pop_front()
	gpContainer["revisions"] = gpList
	return gpNew


# Verify a container read from disk. EMPTY list = consistent; otherwise findings carry
# machine-readable codes so callers can branch instead of parsing strings.
# 校验从磁盘读出的容器。返回空数组即一致；否则每条发现带机器可读码，
# 调用方按码分支而非解析字符串。
static func gpVerify(gpContainer: Dictionary) -> PackedStringArray:
	var gpErrors: PackedStringArray = []
	var gpHeader: String = str(gpContainer.get("revision", ""))
	if gpHeader == "":
		# Legacy archive without a stamp: nothing to verify (progressive compatibility).
		# 未盖章的旧档：无可校验（渐进兼容）。
		return gpErrors
	var gpRevisions: Array = []
	if gpContainer.get("revisions") is Array:
		gpRevisions = gpContainer.get("revisions") as Array
	# The hash's parent is the last entry's parent (the state this stamp was computed from).
	# 哈希的 parent 取最后条目的 parent（即本次盖章所依据的状态）。
	var gpParent: String = ""
	if not gpRevisions.is_empty() and (gpRevisions[gpRevisions.size() - 1] is Dictionary):
		gpParent = str((gpRevisions[gpRevisions.size() - 1] as Dictionary).get("parent", ""))
	var gpWant: String = gpComputeRevision(gpContainer, gpParent)
	if gpWant != gpHeader:
		gpErrors.append(GP_ERR_BAD_HASH)
	# Chain integrity: entry[i].parent must equal entry[i-1].revision; the header must
	# equal the last entry's revision. entry[0].parent is intentionally unchecked (it may
	# reference a trimmed / foreign history).
	# 链完整性：entry[i].parent 必须等于 entry[i-1].revision；头部必须等于最后条目的
	# revision。entry[0].parent 刻意不校验（它可能引用被截断 / 外来的历史）。
	if not gpRevisions.is_empty():
		for gpI in range(1, gpRevisions.size()):
			var gpPrev: Variant = gpRevisions[gpI - 1]
			var gpCur: Variant = gpRevisions[gpI]
			if not (gpPrev is Dictionary) or not (gpCur is Dictionary):
				gpErrors.append(GP_ERR_BAD_CHAIN)
				continue
			if str((gpCur as Dictionary).get("parent", "")) != str((gpPrev as Dictionary).get("revision", "")):
				gpErrors.append(GP_ERR_BAD_CHAIN)
		var gpLast: Variant = gpRevisions[gpRevisions.size() - 1]
		if gpLast is Dictionary and str((gpLast as Dictionary).get("revision", "")) != gpHeader:
			gpErrors.append(GP_ERR_BAD_CHAIN)
	return gpErrors


# Read the header revision ("", when the key is absent — legacy archive).
# 读取头部修订值（键缺失时为空串——旧档）。
static func gpHeaderRevision(gpContainer: Dictionary) -> String:
	return str(gpContainer.get("revision", ""))


# The payload the hash covers: the container minus the excluded header keys (NOT mutated).
# 哈希覆盖的载荷：容器去掉排除键（不修改原容器）。
static func _gpHashPayload(gpContainer: Dictionary) -> Dictionary:
	var gpOut: Dictionary = {}
	for gpKey in gpContainer.keys():
		if GP_EXCLUDED_KEYS.has(str(gpKey)):
			continue
		gpOut[gpKey] = gpContainer[gpKey]
	return gpOut


# SHA-256 of UTF-8 text, hex-encoded.
# UTF-8 文本的 SHA-256，十六进制编码。
static func _gpSha256Hex(gpText: String) -> String:
	var gpCtx: HashingContext = HashingContext.new()
	gpCtx.start(HashingContext.HASH_SHA256)
	gpCtx.update(gpText.to_utf8_buffer())
	var gpDigest: PackedByteArray = gpCtx.finish()
	return gpDigest.hex_encode()


# Recursive canonical serializer. Dictionary keys are sorted by their string form; every
# value type gets a deterministic rendering (see NUMBER NORMALIZATION above).
# 递归规范序列化器。字典键按其字符串形式排序；每个值类型都有确定性渲染
#（见上「数值归一」）。
static func _gpCanonicalValue(gpValue: Variant) -> String:
	if gpValue == null:
		return "null"
	if gpValue is bool:
		return "true" if (gpValue as bool) else "false"
	if gpValue is int:
		return str(gpValue)
	if gpValue is float:
		var gpF: float = gpValue
		# Integral floats render as integers so the hash is stable across a JSON
		# round-trip (Godot parses JSON numbers as float).
		# 整值浮点渲染为整数字符串，使哈希在 JSON 往返后保持稳定
		#（Godot 把 JSON 数字解析为浮点）。
		if is_finite(gpF) and absf(gpF) < 9.0e15 and gpF == floorf(gpF):
			return str(int(gpF))
		return str(gpF) if is_finite(gpF) else "null"
	if gpValue is String:
		return JSON.stringify(gpValue)
	if gpValue is Array:
		var gpParts: PackedStringArray = PackedStringArray()
		for gpItem in gpValue as Array:
			gpParts.append(_gpCanonicalValue(gpItem))
		return "[" + ",".join(gpParts) + "]"
	if gpValue is Dictionary:
		var gpDict: Dictionary = gpValue
		var gpKeys: Array = gpDict.keys()
		var gpSorted: Array[String] = []
		for gpK in gpKeys:
			gpSorted.append(str(gpK))
		gpSorted.sort()
		var gpParts: PackedStringArray = PackedStringArray()
		for gpK in gpSorted:
			gpParts.append(JSON.stringify(gpK) + ":" + _gpCanonicalValue(gpDict[gpK]))
		return "{" + ",".join(gpParts) + "}"
	# Unknown type (should not occur in a JSON-shaped payload): fall back to str().
	# 未知类型（JSON 形载荷不应出现）：退回 str()。
	return JSON.stringify(str(gpValue))
