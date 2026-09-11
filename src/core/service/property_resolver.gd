class_name GPPropertyResolver
extends RefCounted
# Copyright © 2026 Jonson Wang
# The ONE bridge between the type layer (library schema + defaults) and the instance layer
# (per-node values). Every read — panel, canvas label, bill of materials, W10 validation —
# must come through here; never read node.gpProps directly.
# 类型层（库 schema + 默认值）与实例层（单节点取值）之间的**唯一**桥梁。所有读取 ——
# 属性面板、画布标签、设备清单、W10 校验 —— 都必须经过这里；禁止直接读 node.gpProps。
#
# The merge rule / 合并规则：
#   library default  ↓  (only when the instance never overrode it / 仅当实例从未覆盖)
#   instance value   ↓  (wins as soon as the key exists / 键一存在即胜出)
#   -> effective value
# Distinguishing "never touched" from "set back to the default" is exactly what `has()` buys:
# an instance that explicitly stores the default keeps its own value when the library default
# later changes.
# 用 `has()` 才能区分「从未动过」与「又改回了默认值」：显式存了默认值的实例，在库默认值
# 日后变更时保留自己的值。
#
# Coding rule: every variable declares its type explicitly; all functions are static (pure).
# 编码规范：所有变量均显式声明类型；函数全部为静态（纯函数）。

# Default canvas label template: the TAG only — the symbol's library name never reaches the
# canvas (its home is the inspector).
# 画布标签默认模板：只显示位号 —— 图元的库名称永不进画布（它的家是属性面板）。
const GP_DEFAULT_LABEL_FORMAT: String = "{tag}"

# Locale tried when the requested one has no translation (this project's primary language).
# 请求的语种无译文时尝试的回落语种（本项目主语言）。
const GP_FALLBACK_LOCALE: String = "zh_CN"

# Anchor value meaning "not set — follow the library default".
# 锚点取值「未设置 —— 跟随库默认」。
const GP_ANCHOR_UNSET: int = -1


# Effective value of one field: instance override wins, otherwise the library default.
# 单字段有效值：实例覆盖优先，否则取库默认值。
# An orphan key (field deleted from the library) is returned AS STORED — data sovereignty means
# we never silently drop a value the user typed.
# 孤儿键（库中已删字段）按**原样**返回 —— 数据主权意味着绝不静默丢弃用户输入的值。
static func gpEffectiveValue(gpSchema: GPPropertySchema, gpProps: Dictionary, gpKey: String) -> Variant:
	if gpSchema == null:
		return gpProps.get(gpKey, null)
	var gpField: GPPropertyDef = gpSchema.gpFieldByKey(gpKey)
	if gpField == null:
		return gpProps.get(gpKey, null)
	if gpProps.has(gpKey):
		return gpField.gpCoerce(gpProps[gpKey])
	return gpField.gpDefault


# Whether this instance carries its own value for gpKey (as opposed to following the default).
# The inspector greys out + marks "default" for fields where this is false.
# 该实例是否为 gpKey 自带取值（而非跟随默认）。面板据此把字段置灰并标「默认」。
static func gpIsOverridden(gpProps: Dictionary, gpKey: String) -> bool:
	return gpProps.has(gpKey)


# Keys present on the instance but no longer declared by the library — orphaned values.
# They stay in gpProps and are surfaced by the inspector under "removed from library".
# 实例上有、但库中已不再声明的键 —— 孤儿值。它们留在 gpProps 中，由面板在
# 「库中已删除」分组中露出。
static func gpOrphanKeys(gpSchema: GPPropertySchema, gpProps: Dictionary) -> Array[String]:
	var gpOut: Array[String] = []
	if gpSchema == null:
		return gpOut
	for gpK in gpProps.keys():
		var gpS: String = str(gpK)
		if gpSchema.gpFieldByKey(gpS) == null and not gpSchema.gpRenameMap().has(gpS):
			gpOut.append(gpS)
	gpOut.sort()
	return gpOut


# Apply gpRenameFrom migrations — old key values move onto the new key.
# 应用 gpRenameFrom 迁移 —— 旧键值搬到新键下。
# Rules / 规则：
#  - the new key wins when BOTH exist (the user already re-entered it) and the stale old key
#    is dropped, so the migration is idempotent and converges;
#    新旧键同时存在时以新键为准（用户已重新录入），并丢弃过期的旧键，故迁移幂等且收敛；
#  - returns a NEW dictionary; the caller assigns it. Nothing is written to disk here.
#    返回**新**字典，由调用方赋值；此处不落盘。
static func gpMigrateProps(gpSchema: GPPropertySchema, gpProps: Dictionary) -> Dictionary:
	var gpOut: Dictionary = {}
	if gpSchema == null:
		return gpProps.duplicate(true)
	var gpRenames: Dictionary = gpSchema.gpRenameMap()
	var gpPending: Dictionary = {}
	for gpK in gpProps.keys():
		var gpS: String = str(gpK)
		if gpRenames.has(gpS):
			gpPending[str(gpRenames[gpS])] = gpProps[gpK]
			continue
		gpOut[gpS] = gpProps[gpK]
	for gpNewK in gpPending.keys():
		# Only fill in when the instance has no value under the new key yet.
		# 仅当实例在新键下尚无取值时才填入。
		if not gpOut.has(gpNewK):
			gpOut[gpNewK] = gpPending[gpNewK]
	return gpOut


# Every effective value at once (library defaults + instance overrides + orphans).
# This is what the bill of materials and W10 validation read.
# 一次取全部有效值（库默认 + 实例覆盖 + 孤儿）。设备清单与 W10 校验读的就是它。
static func gpEffectiveProps(gpSchema: GPPropertySchema, gpProps: Dictionary) -> Dictionary:
	var gpOut: Dictionary = {}
	for gpK in gpOrphanKeys(gpSchema, gpProps):
		gpOut[gpK] = gpProps[gpK]
	if gpSchema == null:
		return gpOut
	for gpF in gpSchema.gpFields:
		gpOut[gpF.gpKey] = gpEffectiveValue(gpSchema, gpProps, gpF.gpKey)
	return gpOut


# Display name with locale fallback: exact locale -> GP_FALLBACK_LOCALE -> the library's
# gpDisplayName -> the tag itself (so a label is never blank).
# 带语种回落的名称显示：精确语种 -> GP_FALLBACK_LOCALE -> 库的 gpDisplayName -> 位号本身
# （保证标签永不为空）。
static func gpDisplayName(gpNames: Dictionary, gpLibraryName: String, gpLocale: String, gpTag: String = "") -> String:
	if gpNames.has(gpLocale) and str(gpNames[gpLocale]).strip_edges() != "":
		return str(gpNames[gpLocale])
	if gpLocale != GP_FALLBACK_LOCALE and gpNames.has(GP_FALLBACK_LOCALE):
		var gpFb: String = str(gpNames[GP_FALLBACK_LOCALE])
		if gpFb.strip_edges() != "":
			return gpFb
	if gpLibraryName != "":
		return gpLibraryName
	return gpTag


# Expand a label template. Supported tokens: {tag} and {name}.
# Unknown tokens are left verbatim so a typo is visible instead of silently blank.
# 展开标签模板。支持的占位符：{tag} 与 {name}。
# 未知占位符原样保留，使拼写错误可见而非静默变空。
static func gpLabelText(gpFormat: String, gpTag: String, gpName: String) -> String:
	var gpFmt: String = gpFormat if gpFormat != "" else GP_DEFAULT_LABEL_FORMAT
	return gpFmt.replace("{tag}", gpTag).replace("{name}", gpName)


# Active label anchor: the instance wins only when it is set (GP_ANCHOR_UNSET = follow library).
# 生效的标签锚点：实例仅在「已设置」时胜出（GP_ANCHOR_UNSET 表示跟随库）。
static func gpActiveAnchor(gpLibraryAnchor: int, gpInstanceAnchor: int) -> int:
	if gpInstanceAnchor != GP_ANCHOR_UNSET:
		return gpInstanceAnchor
	if gpLibraryAnchor != GP_ANCHOR_UNSET:
		return gpLibraryAnchor
	return GPLabelAnchor.GPAnchor.GP_BELOW


# Active label offset: same "unset follows the library" rule. ZERO is a legitimate value
# ("exactly on the anchor"), so unset must be encoded by a sentinel, not by zero.
# 生效的标签偏移：同样遵循「未设置跟随库」规则。零是合法取值（正好落在锚点上），
# 故「未设置」必须用哨兵编码，不能靠零。
static func gpActiveOffset(gpLibraryOffset: Vector2, gpInstanceOffset: Vector2) -> Vector2:
	if gpInstanceOffset != GPLabelAnchor.GP_OFFSET_UNSET:
		return gpInstanceOffset
	if gpLibraryOffset != GPLabelAnchor.GP_OFFSET_UNSET:
		return gpLibraryOffset
	return Vector2.ZERO


# ==================== M12: library drift & migration ====================
# ==================== M12：库变更与迁移 ====================
# "Edit the library, every project follows" needs one extra guarantee: a drawing that was
# saved against an OLDER library must be able to TELL that the library moved on, and must
# carry its values across a field rename instead of losing them.
# 「改库即全项目同步」还需要一条保证：按**旧库**保存的图纸必须能**察觉**库已经变了，
# 且字段改名时要把取值带过去，而不是丢掉。


# Fingerprint of every symbol, keyed by id — the snapshot stored with the drawing.
# 按 id 索引的全部图元指纹 —— 随图纸一起存储的快照。
static func gpFingerprintsFor(gpDefs: Array[GPSymbolDef]) -> Dictionary:
	var gpOut: Dictionary = {}
	for gpD in gpDefs:
		if gpD == null or gpD.gpId == "":
			continue
		gpOut[gpD.gpId] = gpD.gpSchema.gpFingerprint() if gpD.gpSchema != null else ""
	return gpOut


# Symbol ids whose live library fingerprint differs from the one stored in the drawing —
# including symbols that vanished from the library altogether (absent from gpLive).
# 活动库指纹与图纸中存储值不一致的图元 id —— 含已彻底从库中消失的图元（gpLive 中不存在）。
static func gpDriftedSymbols(gpLive: Dictionary, gpStored: Dictionary) -> Array[String]:
	var gpOut: Array[String] = []
	for gpId in gpStored:
		var gpS: String = str(gpId)
		var gpWas: String = str(gpStored[gpS])
		# MIGRATION / 迁移：an EMPTY stored fingerprint means this drawing was saved before the
		# typed schema was wired up, back when gpSchema was always null and every fingerprint
		# was "". There is no baseline to compare against, so it must NOT count as drift —
		# otherwise wiring the schema up flags every symbol of every existing drawing at once.
		# 空指纹意味着该图纸保存于类型化 schema 通电之前 —— 当时 gpSchema 恒为 null、指纹全是 ""。
		# 没有可比的基线，故不得计为漂移；否则通电会让所有存量图纸的全部图元同时报警。
		# Trade-off / 取舍：a symbol that has vanished from the library is likewise not reported
		# while its stored fingerprint is ""; it is caught on the next save, which stores real
		# values. We accept missing that one case rather than crying wolf on every old drawing.
		# 取舍：指纹为 "" 的图元即便已从库中消失也暂不报出；下次保存（写入真实值）会捕获它。
		# 宁可漏掉这一例，也不对所有存量图纸狼来了。
		if gpWas == "":
			continue
		if not gpLive.has(gpS) or str(gpLive[gpS]) != gpWas:
			gpOut.append(gpS)
	gpOut.sort()
	return gpOut


# Apply gpRenameFrom migrations to every node. Returns how many nodes actually changed, so the
# shell can report "3 instances were migrated" instead of a vague "something happened".
# 对每个节点应用 gpRenameFrom 迁移。返回实际变化的节点数，使外壳能报
# 「3 个实例已迁移」而非含糊的「有变化发生」。
static func gpMigrateGraph(gpGraph: GPPIDGraph, gpDefs: Array[GPSymbolDef]) -> int:
	var gpChanged: int = 0
	if gpGraph == null:
		return 0
	for gpN in gpGraph.gpNodes:
		if gpN == null:
			continue
		var gpDef: GPSymbolDef = gpDefById(gpDefs, gpN.gpSymbolId)
		if gpDef == null or gpDef.gpSchema == null:
			continue
		var gpMigrated: Dictionary = gpMigrateProps(gpDef.gpSchema, gpN.gpProps)
		# Compare by hash: Dictionary != is deep, but hashing is the comparison the engine
		# guarantees for nested payloads (an orphan value can itself be a Dictionary).
		# 用 hash 比较：Dictionary 的 != 虽是深比较，但对嵌套载荷（孤儿值本身可能是字典）
		# 引擎保证可靠的是 hash。
		if gpMigrated.hash() != gpN.gpProps.hash():
			gpN.gpProps = gpMigrated
			gpChanged += 1
	return gpChanged


# Drop every orphaned value from one node. This is the ONLY way an orphan ever disappears:
# an explicit user action, never an automatic sweep.
# 清除某节点上的全部孤儿值。这是孤儿值**唯一**的消失途径：一次明确的用户操作，
# 绝不是自动清扫。
static func gpCleanOrphans(gpNode: GPPIDNode, gpSchema: GPPropertySchema) -> int:
	if gpNode == null:
		return 0
	var gpOrphans: Array[String] = gpOrphanKeys(gpSchema, gpNode.gpProps)
	for gpK in gpOrphans:
		gpNode.gpProps.erase(gpK)
	return gpOrphans.size()


# How many orphaned values the whole drawing still carries — shown before offering cleanup.
# 整张图纸仍携带多少个孤儿值 —— 在提供清理前展示。
static func gpOrphanCount(gpGraph: GPPIDGraph, gpDefs: Array[GPSymbolDef]) -> int:
	var gpCount: int = 0
	if gpGraph == null:
		return 0
	for gpN in gpGraph.gpNodes:
		if gpN == null:
			continue
		var gpDef: GPSymbolDef = gpDefById(gpDefs, gpN.gpSymbolId)
		gpCount += gpOrphanKeys(gpDef.gpSchema if gpDef != null else null, gpN.gpProps).size()
	return gpCount


# Find a definition by id. Public because the shell needs the same lookup when it reports drift.
# 按 id 查找图元定义。设为公开，因为外壳报告库变更时需要同样的查找。
static func gpDefById(gpDefs: Array[GPSymbolDef], gpSymbolId: String) -> GPSymbolDef:
	if gpSymbolId == "":
		return null
	for gpD in gpDefs:
		if gpD != null and gpD.gpId == gpSymbolId:
			return gpD
	return null
