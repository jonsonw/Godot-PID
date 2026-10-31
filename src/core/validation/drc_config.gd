class_name GPDRCConfig
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# DRC configuration + waivers (ADR-39 D3/D7). One pure helper over a plain dictionary stored in
# the project standard: defaults, per-rule overrides, thresholds and the waiver list.
# DRC 配置与豁免（ADR-39 D3/D7）。对工程标准里一个普通字典的纯辅助：默认值、逐规则覆盖、
# 阈值与豁免清单。
#
# Why a dictionary and not a Resource / 为何用字典而非 Resource：
# the project standard is already serialised as a dictionary and copied on every open. Keeping
# validation in the same shape means one migration path, byte-stable old archives, and no second
# object graph to keep in sync.
# 工程标准本就以字典序列化、每次打开时复制。校验用同一形态意味着只有一条迁移路径、旧档字节稳定、
# 且没有第二张需要同步的对象图。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

const GP_SEVERITY_ERROR: String = "error"
const GP_SEVERITY_WARNING: String = "warning"
const GP_SEVERITY_INFO: String = "info"

# Factory defaults. Rules absent from `rules` are enabled at their registry severity.
# 出厂默认。`rules` 中缺席的规则按其注册级别默认启用。
static func gpDefaults() -> Dictionary:
	return {
		# Approximate / advisory checks start OFF until their data source is trustworthy:
		# the label box is still a character-count estimate, and "too close" / media continuity
		# are judgement calls. A project can turn them on explicitly.
		# 近似 / 建议类检查默认关闭，直到数据来源可信：标签盒仍是按字符数估算，「过近」与介质
		# 连续性属于判断。工程可显式开启。
		"rules": {
			"drc.layout.label_overlap": {"enabled": false},
			"drc.layout.label_off_sheet": {"enabled": false},
			"drc.layout.line_too_close": {"enabled": false},
			"drc.layout.annotation_crosses": {"enabled": false},
			"drc.topo.media_continuity": {"enabled": false},
			"drc.doc.title_block_inherit": {"enabled": false},
		},
		"thresholds": {
			"layout_tol_mm": 0.5,
			"line_overlap_mm": 2.0,
			"line_gap_mm": 8.0,
			"parallel_len_mm": 30.0,
			"label_gap_mm": 1.0,
		},
		"policy": {
			"free_shapes": "warning",
			"sem_enabled": false,
			"strict_layout": false,
		},
		"waivers": [],
	}


# Merge a possibly partial / hand-edited dictionary over the factory defaults.
# 把可能不完整或手改过的字典合并到出厂默认之上。
static func gpNormalize(gpRaw: Variant) -> Dictionary:
	var gpOut: Dictionary = gpDefaults()
	if not (gpRaw is Dictionary):
		return gpOut
	var gpIn: Dictionary = gpRaw as Dictionary
	var gpRulesIn: Variant = gpIn.get("rules", null)
	if gpRulesIn is Dictionary:
		for gpKeyRaw in (gpRulesIn as Dictionary).keys():
			var gpKey: String = str(gpKeyRaw)
			var gpVal: Variant = (gpRulesIn as Dictionary)[gpKeyRaw]
			if not (gpVal is Dictionary):
				continue
			var gpRule: Dictionary = (gpVal as Dictionary).duplicate(true)
			var gpSev: String = str(gpRule.get("severity", "")).strip_edges()
			if gpSev != "" and gpSev != GP_SEVERITY_ERROR and gpSev != GP_SEVERITY_WARNING \
					and gpSev != GP_SEVERITY_INFO:
				gpRule.erase("severity")
			gpOut["rules"][gpKey] = gpRule
	var gpThresholds: Variant = gpIn.get("thresholds", null)
	if gpThresholds is Dictionary:
		for gpKeyRaw in (gpThresholds as Dictionary).keys():
			var gpVal: Variant = (gpThresholds as Dictionary)[gpKeyRaw]
			if gpVal is float or gpVal is int:
				gpOut["thresholds"][str(gpKeyRaw)] = float(gpVal)
	var gpPolicy: Variant = gpIn.get("policy", null)
	if gpPolicy is Dictionary:
		for gpKeyRaw in (gpPolicy as Dictionary).keys():
			gpOut["policy"][str(gpKeyRaw)] = (gpPolicy as Dictionary)[gpKeyRaw]
	var gpWaivers: Variant = gpIn.get("waivers", null)
	if gpWaivers is Array:
		gpOut["waivers"] = (gpWaivers as Array).duplicate(true)
	return gpOut


# Per-rule setting (empty dictionary when the rule has no override).
# 某规则的覆盖设置（无覆盖时为空字典）。
static func gpRuleSetting(gpCfg: Dictionary, gpRuleId: String) -> Dictionary:
	var gpRules: Dictionary = gpCfg.get("rules", {}) as Dictionary
	var gpVal: Variant = gpRules.get(gpRuleId, null)
	return (gpVal as Dictionary).duplicate(true) if gpVal is Dictionary else {}


# Whether a rule is enabled (default true).
# 某规则是否启用（默认启用）。
static func gpEnabled(gpCfg: Dictionary, gpRuleId: String) -> bool:
	var gpSet: Dictionary = gpRuleSetting(gpCfg, gpRuleId)
	return bool(gpSet.get("enabled", true))


# Effective severity: per-rule override, else the registry default. Invalid overrides are ignored.
# 生效级别：逐规则覆盖优先，否则取注册默认。非法覆盖忽略。
static func gpSeverity(gpCfg: Dictionary, gpRuleId: String, gpDefault: String) -> String:
	var gpSet: Dictionary = gpRuleSetting(gpCfg, gpRuleId)
	var gpSev: String = str(gpSet.get("severity", gpDefault)).strip_edges()
	if gpSev == GP_SEVERITY_ERROR or gpSev == GP_SEVERITY_WARNING or gpSev == GP_SEVERITY_INFO:
		return gpSev
	return gpDefault


# A numeric threshold, falling back to the factory value when the key is absent / bad.
# 数值阈值；键缺失或非法时回退出厂值。
static func gpThreshold(gpCfg: Dictionary, gpKey: String, gpFallback: float) -> float:
	var gpTh: Dictionary = gpCfg.get("thresholds", {}) as Dictionary
	var gpVal: Variant = gpTh.get(gpKey, null)
	if gpVal is float or gpVal is int:
		return float(gpVal)
	return gpFallback


# A policy value with a fallback.
# 取策略值，缺失时用回退值。
static func gpPolicy(gpCfg: Dictionary, gpKey: String, gpFallback: Variant) -> Variant:
	var gpPol: Dictionary = gpCfg.get("policy", {}) as Dictionary
	return gpPol.get(gpKey, gpFallback)


# Today's date, YYYY-MM-DD, in the same lexical form waivers use for `expires`.
# 今天的日期，YYYY-MM-DD，与豁免 `expires` 使用同一可比较的词法形态。
static func gpToday() -> String:
	return Time.get_date_string_from_system()


# The waiver that covers one finding, or an empty dictionary.
# 覆盖某条发现的豁免；无则空字典。
# A waiver addresses the CHECK (fine-grained) and the stable entity uid. `rule` is accepted as a
# compatibility alias so a hand-written waiver for a coarse rule keeps working.
# 豁免按**细分检查号**与稳定对象 uid 定位。`rule` 作为兼容别名接受，使手写的粗粒度豁免仍有效。
static func gpWaiverFor(gpCfg: Dictionary, gpFinding: GPFinding) -> Dictionary:
	if gpFinding == null:
		return {}
	var gpWaivers: Array = gpCfg.get("waivers", []) as Array
	var gpCheck: String = gpFinding.gpCheckId if gpFinding.gpCheckId != "" else gpFinding.gpRuleId
	for gpRaw in gpWaivers:
		if not (gpRaw is Dictionary):
			continue
		var gpW: Dictionary = gpRaw as Dictionary
		var gpRule: String = str(gpW.get("rule", "")).strip_edges()
		if gpRule != "" and gpRule != gpFinding.gpRuleId and gpRule != gpCheck:
			continue
		# A waiver without a reason / approver is not a waiver — it is a silent mute. ADR-39 D3
		# requires traceability, so malformed entries are ignored rather than honoured.
		# 没有理由 / 批准人的「豁免」只是静音。ADR-39 D3 要求可追溯，故畸形条目不生效。
		if str(gpW.get("reason", "")).strip_edges() == "" \
				or str(gpW.get("approver", "")).strip_edges() == "":
			continue
		var gpUid: String = str(gpW.get("entity_uid", "")).strip_edges()
		if gpUid != "" and gpUid != gpFinding.gpEntityUid:
			continue
		var gpExpires: String = str(gpW.get("expires", "")).strip_edges()
		if gpExpires != "" and gpExpires < gpToday():
			continue
		return gpW
	return {}


# Mark findings covered by a waiver. Mutates the findings (they are fresh engine output).
# 标记被豁免覆盖的发现（引擎刚产出的新对象，故就地标记）。
static func gpApplyWaivers(gpFindings: Array[GPFinding], gpCfg: Dictionary) -> void:
	for gpF in gpFindings:
		if gpF == null:
			continue
		if not gpWaiverFor(gpCfg, gpF).is_empty():
			gpF.gpWaived = true


# Count findings by severity, excluding waived ones (they are counted separately).
# 按级别计数，排除已豁免项（单独计数）。
static func gpCountActive(gpFindings: Array[GPFinding], gpSeverity: String) -> int:
	var gpN: int = 0
	for gpF in gpFindings:
		if gpF != null and not gpF.gpWaived and gpF.gpSeverity == gpSeverity:
			gpN += 1
	return gpN


# Count waived findings.
# 统计已豁免发现数。
static func gpCountWaived(gpFindings: Array[GPFinding]) -> int:
	var gpN: int = 0
	for gpF in gpFindings:
		if gpF != null and gpF.gpWaived:
			gpN += 1
	return gpN


# Store one waiver for a finding in a project standard. Reason / approver are required; the
# stable entity uid is the key. Returns true when written.
# 把一条发现的豁免写入项目标准。理由 / 批准人必填；稳定对象 uid 为键。写入成功返回 true。
static func gpAddWaiver(gpStd: GPProjectStandard, gpFinding: GPFinding, gpReason: String,
		gpApprover: String) -> bool:
	if gpStd == null or gpFinding == null or gpFinding.gpEntityUid == "":
		return false
	if gpReason.strip_edges() == "" or gpApprover.strip_edges() == "":
		return false
	var gpCfg: Dictionary = gpStd.gpValidationConfig()
	var gpWaivers: Array = gpCfg.get("waivers", []) as Array
	gpWaivers.append({
		"rule": gpFinding.gpCheckId if gpFinding.gpCheckId != "" else gpFinding.gpRuleId,
		"entity_uid": gpFinding.gpEntityUid,
		"reason": gpReason.strip_edges(),
		"approver": gpApprover.strip_edges(),
		"at": Time.get_datetime_string_from_system(),
	})
	gpCfg["waivers"] = gpWaivers
	gpStd.gpSetValidationConfig(gpCfg)
	return true


# Remove every waiver that covers a finding (same check + stable entity uid).
# 删除覆盖某条发现的全部豁免（同检查号 + 稳定对象 uid）。
static func gpRemoveWaiver(gpStd: GPProjectStandard, gpFinding: GPFinding) -> bool:
	if gpStd == null or gpFinding == null or gpFinding.gpEntityUid == "":
		return false
	var gpCfg: Dictionary = gpStd.gpValidationConfig()
	var gpWaivers: Array = gpCfg.get("waivers", []) as Array
	var gpRule: String = gpFinding.gpCheckId if gpFinding.gpCheckId != "" else gpFinding.gpRuleId
	var gpKeep: Array = []
	var gpRemoved: bool = false
	for gpRaw in gpWaivers:
		if gpRaw is Dictionary:
			var gpW: Dictionary = gpRaw as Dictionary
			var gpWRule: String = str(gpW.get("rule", ""))
			var gpWUid: String = str(gpW.get("entity_uid", ""))
			if gpWUid == gpFinding.gpEntityUid and (gpWRule == gpRule
					or gpWRule == gpFinding.gpRuleId):
				gpRemoved = true
				continue
		gpKeep.append(gpRaw)
	if not gpRemoved:
		return false
	gpCfg["waivers"] = gpKeep
	gpStd.gpSetValidationConfig(gpCfg)
	return true
