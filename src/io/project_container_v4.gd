class_name GPProjectContainerV4
extends RefCounted

# Container v4 assembly & validation (ADR-41, revised 2026-11-09).
# 容器 v4 装配与校验（ADR-41，2026-11-09 修订版）。
#
# WHY A NEW FILE / 为何是新文件：
# ADR-47 (2026-11-06) forbids growing legacy hot files; project_io.gd only carries a
# single delegation line. Everything v4-specific lives here as pure-dict static helpers
# with zero autoload references (io layer purity, layer matrix rule).
# ADR-47（2026-11-06）禁止继续增长既有热点文件；project_io.gd 只允许一行转发。
# v4 专属逻辑全部收在本文件，以纯 dict 静态函数实现，零 autoload 引用（io 层纯净性）。
#
# WHY NO MIGRATION / 为何无迁移链（ADR-41 D3 revision, user ruling 2026-11-09）：
# The project is pre-release; v4 is the ONLY container form and v1-v3 tolerance is
# DROPPED. Historic archives (e.g. repo-root W6.pid.json) are not guaranteed readable.
# 工程尚在开发阶段；v4 是唯一容器形态，v1–v3 宽容读已取消。
# 历史存档（如仓库根 W6.pid.json）不保证可读。
#
# ==================== S1 FROZEN FIELD TABLE (ADR-41 requires freeze before W13) ====
# ==================== S1 冻结字段表（ADR-41 要求 W13 前冻结）=======================
#
# members[] entry / 成员条目（ADR-40 D1/D3/D4 — credentials NEVER live here）：
#   {
#     "user":    String           用户名（非空、项目内唯一；「用户身份」载体）
#     "roles":   Array[String]    非空，取值 ⊆ GP_ROLES，可叠加（权限取并集）
#     "enabled": bool              缺省 true（停用成员保留名单便于审计）
#   }
# GP_ROLES / 三角色：["manager", "designer", "reviewer"]（ADR-40 D3，能力边界见其矩阵）。
# 凭据（密码哈希 + salt）存各自机器 user://，绝不进项目文件（ADR-40 D4）。
#
# GPPermissionProvider signature freeze / 接口签名冻结（ADR-40 D5，core 抽象）：
#   gpCanDo(gpUser: String, gpCapability: String, gpTarget: String) -> bool
#   拒绝原因写 gpLastRefusal（机器可读拒绝码，ADR-12 语义）。UI 只呈现、不自行判断。
#
# sheet_sets[] entry / 图纸集条目（ADR-41 D1 — grouping ONLY, never permissions）：
#   {
#     "id":        String          图纸集 id（非空、项目内唯一）
#     "name":      String          显示名（非空）
#     "sheet_ids": Array[String]   引用 sheets[].id；校验引用完整性
#   }
#
# project_meta / 项目级元信息：Dictionary 占位（字段随 ADR-38 项目信息演进；
# 本篇只冻结「键存在且必为 dict」，不冻结内部字段）。
#
# ==================== v4 SHAPE / v4 形态 ====================
# v3 mechanical keys (meta / sheets / cross_links / library / config / tag_rules) are
# KEPT AS-IS; v4 adds four top-level sections and stamps container_version=4. Rationale:
# the sheet/library rebuild pipeline (GPSchemaMigrate -> GPSheet.gpFromDict) is shared
# by save/load/import; re-nesting those keys would churn five hot files for zero
# behavioural gain. v4 identity rides on its own key so the migrate axis
# (GP_FORMAT_VERSION) is untouched.
# v3 机械键（meta / sheets / cross_links / library / config / tag_rules）**原样保留**；
# v4 新增四个顶层段并盖 container_version=4。理由：图纸/图库重建管线
#（GPSchemaMigrate -> GPSheet.gpFromDict）被保存/载入/导入三方共用，重排这些键要扰动
# 五个热点文件却无行为收益。v4 标识走独立键，使迁移轴（GP_FORMAT_VERSION）零扰动。
#   "container_version": 4
#   "project_meta":  {}            项目级元信息（占位）
#   "members":       []            成员与角色（ADR-40）
#   "sheet_sets":    []            可选图纸集（仅分组/批量，ADR-41 D1）

const GP_CONTAINER_VERSION: int = 4

# The three v4 role names (ADR-40 D3). Frozen: the permission matrix and future
# UI i18n keys key off these strings.
# 三个 v4 角色名（ADR-40 D3）。冻结：权限矩阵与将来 UI 的 i18n 键都以这些字符串为键。
const GP_ROLES: Array[String] = ["manager", "designer", "reviewer"]

# Validation failure codes, machine-readable (ADR-12 refusal-code semantics).
# 校验失败码，机器可读（沿用 ADR-12 拒绝码语义）。
const GP_ERR_BAD_VERSION: String = "container.bad_version"
const GP_ERR_BAD_META: String = "container.bad_project_meta"
const GP_ERR_BAD_MEMBERS: String = "container.bad_members"
const GP_ERR_BAD_SHEET_SETS: String = "container.bad_sheet_sets"


# Stamp a container dict in place to v4: version key plus the three project-level
# sections guaranteed to EXIST (missing ones are filled empty; present ones are kept
# verbatim). Idempotent: stamp(stamp(d)) == stamp(d).
# 就地把容器字典盖为 v4：版本键 + 保证三个工程级段**存在**（缺失补空，已有原样保留）。
# 幂等：盖两次与盖一次结果一致。
static func gpStampV4(gpContainer: Dictionary) -> void:
	gpContainer["container_version"] = GP_CONTAINER_VERSION
	if not (gpContainer.get("project_meta") is Dictionary):
		gpContainer["project_meta"] = {}
	if not (gpContainer.get("members") is Array):
		gpContainer["members"] = []
	if not (gpContainer.get("sheet_sets") is Array):
		gpContainer["sheet_sets"] = []


# Pure wrapper variant of gpStampV4(): returns a NEW deep-copied dictionary with the
# three sections explicitly overridden by the arguments (an empty argument keeps what
# the container already carries). Callers own the result; the input is untouched.
# gpStampV4() 的纯函数变体：返回**新的**深拷贝字典，三段由参数显式覆盖
#（空参数沿用容器既有内容）。结果归调用方所有；入参不被修改。
static func gpWrapV4(gpContainer: Dictionary, gpProjectMeta: Dictionary = {},
		gpMembers: Array = [], gpSheetSets: Array = []) -> Dictionary:
	var gpOut: Dictionary = gpContainer.duplicate(true)
	gpStampV4(gpOut)
	if not gpProjectMeta.is_empty():
		gpOut["project_meta"] = gpProjectMeta.duplicate(true)
	if not gpMembers.is_empty():
		gpOut["members"] = gpMembers.duplicate(true)
	if not gpSheetSets.is_empty():
		gpOut["sheet_sets"] = gpSheetSets.duplicate(true)
	return gpOut


# Validate a v4 container. Returns the error list (EMPTY = valid). Every finding carries
# a machine-readable code so callers (project center, tests, AI) can branch on them
# instead of parsing strings.
# 校验 v4 容器。返回错误清单（**空**即通过）。每条发现都带机器可读码，
# 使调用方（项目中心、测试、AI）可按码分支，而非解析字符串。
static func gpValidateV4(gpDict: Dictionary) -> PackedStringArray:
	var gpErrors: PackedStringArray = []
	if int(gpDict.get("container_version", 0)) != GP_CONTAINER_VERSION:
		gpErrors.append(GP_ERR_BAD_VERSION)
	if not (gpDict.get("project_meta") is Dictionary):
		gpErrors.append(GP_ERR_BAD_META)
	# Members: shape + uniqueness + role vocabulary. One walk, all findings.
	# 成员：形状 + 唯一性 + 角色词表。一次遍历，收集全部发现。
	var gpSeenUsers: Dictionary = {}
	if not (gpDict.get("members") is Array):
		gpErrors.append(GP_ERR_BAD_MEMBERS)
	else:
		for gpRaw in gpDict.get("members") as Array:
			# Guard BEFORE the typed assignment: `x as Dictionary` on a non-dict value is a
			# hard SCRIPT ERROR in Godot 4.7 (it aborts the pass instead of yielding null),
			# which would silently truncate the findings list.
			# 类型赋值**之前**先守卫：对非字典值做 `as Dictionary` 在 Godot 4.7 是硬性
			# SCRIPT ERROR（会中断整趟收集而非返回 null），错误清单会被静默截断。
			if not (gpRaw is Dictionary):
				gpErrors.append(GP_ERR_BAD_MEMBERS)
				continue
			var gpM: Dictionary = gpRaw
			var gpUser: String = str(gpM.get("user", ""))
			if gpUser.is_empty():
				gpErrors.append(GP_ERR_BAD_MEMBERS)
			elif gpSeenUsers.has(gpUser):
				gpErrors.append(GP_ERR_BAD_MEMBERS)
			else:
				gpSeenUsers[gpUser] = true
			var gpRolesRaw: Variant = gpM.get("roles", null)
			# A hand-edited "roles": "manager" (a bare string) must degrade to a finding,
			# never to a hard cast error. / 手改的 "roles": "manager"（裸字符串）应降级为
			# 一条发现，绝不硬转错误。
			if not (gpRolesRaw is Array):
				gpErrors.append(GP_ERR_BAD_MEMBERS)
			else:
				var gpRoles: Array = gpRolesRaw
				var gpRolesOk: bool = not gpRoles.is_empty()
				for gpR in gpRoles:
					if not GP_ROLES.has(str(gpR)):
						gpRolesOk = false
				if not gpRolesOk:
					gpErrors.append(GP_ERR_BAD_MEMBERS)
	# Sheet sets: shape + id uniqueness + reference integrity against sheets[].id.
	# 图纸集：形状 + id 唯一性 + 对 sheets[].id 的引用完整性。
	if not (gpDict.get("sheet_sets") is Array):
		gpErrors.append(GP_ERR_BAD_SHEET_SETS)
	else:
		var gpSheetIds: Dictionary = {}
		var gpSheetsRaw: Variant = gpDict.get("sheets", null)
		if gpSheetsRaw is Array:
			for gpS in gpSheetsRaw:
				if not (gpS is Dictionary):
					continue
				var gpSheet: Dictionary = gpS
				gpSheetIds[str(gpSheet.get("id", ""))] = true
		var gpSeenSetIds: Dictionary = {}
		for gpRaw in gpDict.get("sheet_sets") as Array:
			if not (gpRaw is Dictionary):
				gpErrors.append(GP_ERR_BAD_SHEET_SETS)
				continue
			var gpSet: Dictionary = gpRaw
			var gpSetId: String = str(gpSet.get("id", ""))
			if gpSetId.is_empty() or gpSeenSetIds.has(gpSetId):
				gpErrors.append(GP_ERR_BAD_SHEET_SETS)
			else:
				gpSeenSetIds[gpSetId] = true
			if str(gpSet.get("name", "")).is_empty():
				gpErrors.append(GP_ERR_BAD_SHEET_SETS)
			var gpRefsRaw: Variant = gpSet.get("sheet_ids", null)
			if gpRefsRaw is Array:
				for gpRef in gpRefsRaw:
					if not gpSheetIds.has(str(gpRef)):
						gpErrors.append(GP_ERR_BAD_SHEET_SETS)
	return gpErrors


# Sheet summaries for the sheet manager list (图纸管理): one lightweight dict per sheet,
# in container order. Pure container-level projection — no graph rebuild, no autoload,
# so the list, the album export and future BOM views can all consume it unchanged
# (high cohesion, low coupling, reusable per the user's standing rule).
# 图纸管理列表的图纸摘要：每张一条轻量 dict，按容器顺序。纯容器层投影——
# 不重建图、不碰 autoload，使列表、图册导出与将来的 BOM 视图都能原样消费
#（遵循「模块化、高内聚低耦合、高可复用」铁律）。
static func gpSheetSummaries(gpDict: Dictionary) -> Array:
	var gpOut: Array = []
	var gpSheetsRaw: Variant = gpDict.get("sheets", null)
	if not (gpSheetsRaw is Array):
		return gpOut
	var gpIdx: int = 0
	for gpS in gpSheetsRaw:
		# is-guard before the typed assignment: hard casts abort the whole projection.
		# 类型赋值前先 is 守卫：硬转会中断整趟投影。
		if not (gpS is Dictionary):
			continue
		var gpSheet: Dictionary = gpS
		var gpNodesRaw: Variant = gpSheet.get("nodes", null)
		gpOut.append({
			"id": str(gpSheet.get("id", "")),
			"name": str(gpSheet.get("name", "")),
			"number": str(gpSheet.get("number", "")),
			"index": gpIdx,
			"node_count": (gpNodesRaw as Array).size() if gpNodesRaw is Array else 0,
		})
		gpIdx += 1
	return gpOut
