extends "res://tests/gp_test.gd"
# Headless verification that the P4 i18n keys are present in both locales with non-empty
# values, and that NO English value contains CJK characters (the "no Chinese residual in the
# English UI" acceptance). The key list is hard-coded so a missing key fails loudly; the CJK
# scan runs over the whole table so any future regression is caught too.
# 校验 P4 的 i18n 键在两种语言下均有非空值，且任何 English 值都不含中日韩字符
#（“英文界面无中文残留”验收）。键列表硬编码，缺失即报错；CJK 扫描覆盖整表以防未来回归。

# P4 keys that MUST exist (zh + en non-empty).
# P4 必须存在的键（zh 与 en 均非空）。
const GP_P4_KEYS: Array[String] = [
	"prop.edge",
	"edge.kind", "edge.signal_type", "edge.tag", "edge.dn", "edge.medium",
	"edge.spec", "edge.insulation", "edge.show_arrow", "edge.show_tag",
	"edge.kind_process", "edge.kind_utility", "edge.kind_signal",
	"edge.type_electric", "edge.type_pneumatic", "edge.type_hydraulic",
	"edge.type_data", "edge.type_capillary",
	"line_type_process", "line_type_utility", "line_type_electric",
	"line_type_pneumatic", "line_type_hydraulic", "line_type_data",
	"line_type_capillary", "line_type_unknown",
	"canvas.ctx_delete_edge", "canvas.ctx_set_process", "canvas.ctx_set_utility",
	"canvas.ctx_set_signal", "canvas.ctx_resnap_ends", "canvas.ctx_clear_vertices",
	"canvas.ctx_renumber",
	"status.edge_tag_manual", "status.renumbered", "status.resnapped",
	"settings.pipe_tag_rotate", "settings.pipe_tag_font_size",
]


# Every P4 key must be present with a non-empty zh and en value.
# 每个 P4 键都必须存在且 zh/en 均非空。
func gpTestP4KeysPresentBilingual() -> void:
	for k in GP_P4_KEYS:
		var m: Dictionary = I18n.GP_STRINGS.get(k, {})
		gpCheck(not m.is_empty(), "key present in table: " + k)
		var zh: String = m.get("zh", "")
		var en: String = m.get("en", "")
		gpCheck(zh != "", "zh non-empty for " + k)
		gpCheck(en != "", "en non-empty for " + k)


# No English value anywhere in the table may contain CJK ideographs (acceptance: a zh-only
# string must never leak into the English UI). The whole table is scanned so this also guards
# P1..P3 keys against future edits.
# 整张表中任何 English 值都不得含中日韩汉字（验收：纯中文串绝不可泄漏进英文界面）。
# 覆盖整表，故对 P1..P3 的键也起防护作用。
func gpTestNoCJKInEnglish() -> void:
	var bad: int = 0
	for k in I18n.GP_STRINGS.keys():
		var en: String = I18n.GP_STRINGS[k].get("en", "")
		if _gpHasCJK(en):
			bad += 1
			push_error("CJK in English value of key: " + k + " -> " + en)
	gpEq(bad, 0, "no CJK characters in any English value")


# True when the string contains a CJK (or CJK-compatible) ideograph code point.
# 当字符串含中日韩（或兼容）汉字码点时返回 true。
func _gpHasCJK(gpS: String) -> bool:
	for gpC in gpS:
		var cp: int = gpC.unicode_at(0)
		if (cp >= 0x3400 and cp <= 0x4DBF) or (cp >= 0x4E00 and cp <= 0x9FFF) \
				or (cp >= 0xF900 and cp <= 0xFAFF) or (cp >= 0x20000 and cp <= 0x2FFFF):
			return true
	return false
