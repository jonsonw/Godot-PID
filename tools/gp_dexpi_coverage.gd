extends SceneTree
# Copyright © 2026 Jonson Wang
# H02: reproducible DEXPI coverage report. It reads the SINGLE mapping tables (no duplicate
# judgement), counts concept classes / verified URIs / attributes, and prints stable JSON.
# H02：可复现的 DEXPI 覆盖报告。只读**唯一**映射表（不另写判断），统计概念类/已验证 URI/属性，
# 输出稳定 JSON。
#
# Usage / 用法:
#   godot --headless --script res://tools/gp_dexpi_coverage.gd
#   godot --headless --script res://tools/gp_dexpi_coverage.gd -- --write
# 没有时间戳/随机量：同一份表生成同一份报告。

func _init() -> void:
	var gpSymbols: Dictionary = GPDexpiMapping.GP_SYMBOLS
	var gpRoles: Dictionary = {}
	var gpFull: Array[String] = []
	var gpPartial: Array[String] = []
	var gpAnnotation: Array[String] = []
	var gpNoClass: Array[String] = []
	for gpIdRaw in gpSymbols.keys():
		var gpId: String = str(gpIdRaw)
		var gpRow: Dictionary = gpSymbols[gpId] as Dictionary
		var gpClass: String = str(gpRow.get("class", ""))
		var gpUri: String = str(gpRow.get("uri", ""))
		var gpRole: String = str(gpRow.get("role", ""))
		gpRoles[gpRole] = int(gpRoles.get(gpRole, 0)) + 1
		if gpClass == "":
			gpNoClass.append(gpId)
			if gpRole == GPDexpiMapping.GP_ROLE_ANNOTATION:
				gpAnnotation.append(gpId)
		elif gpUri != "":
			gpFull.append(gpId)
		else:
			gpPartial.append(gpId)
	var gpAttrs: Dictionary = GPDexpiMapping.GP_ATTRIBUTES
	var gpAttrInternal: Array[String] = []
	var gpAttrUri: Array[String] = []
	var gpAttrNoUri: Array[String] = []
	for gpKeyRaw in gpAttrs.keys():
		var gpKey: String = str(gpKeyRaw)
		var gpRow: Dictionary = gpAttrs[gpKey] as Dictionary
		if bool(gpRow.get("internal", false)):
			gpAttrInternal.append(gpKey)
		elif str(gpRow.get("uri", "")) != "":
			gpAttrUri.append(gpKey)
		else:
			gpAttrNoUri.append(gpKey)
	gpFull.sort(); gpPartial.sort(); gpNoClass.sort(); gpAnnotation.sort()
	gpAttrInternal.sort(); gpAttrUri.sort(); gpAttrNoUri.sort()
	var gpJson: Dictionary = {
		"standard": "DEXPI " + GPDexpiSchema.GP_DEXPI_VERSION + " / Proteus " + GPDexpiSchema.GP_PROTEUS_SCHEMA_VERSION,
		"symbols": {
			"total": gpSymbols.size(), "roles": gpRoles,
			"full": gpFull, "partial": gpPartial,
			"no_class": gpNoClass, "annotation_only": gpAnnotation,
		},
		"attributes": {
			"total": gpAttrs.size(), "internal": gpAttrInternal,
			"uri_verified": gpAttrUri, "uri_missing": gpAttrNoUri,
		},
		"gaps": {
			"mapped_classes_without_uri": gpPartial.size(),
			"attribute_rows_without_uri": gpAttrNoUri.size(),
			"unmapped_dexpi_types": "DEXPI 1.4 declares 568 types; this table only claims the symbols listed above. No 568-row completeness is claimed.",
		},
	}
	var gpText: String = JSON.stringify(gpJson, "\t", true)
	var gpHashing: String = gpText.sha256_text()
	print(gpText)
	print("REPORT_SHA256 " + gpHashing)
	var gpArgs: PackedStringArray = OS.get_cmdline_user_args()
	if "--write" in gpArgs:
		_gpWriteMarkdown(gpJson, gpHashing)
	quit()


func _gpWriteMarkdown(gpJ: Dictionary, gpHashing: String) -> void:
	var gpLines: PackedStringArray = PackedStringArray()
	gpLines.append("# DEXPI 覆盖报告 / DEXPI Coverage")
	gpLines.append("")
	gpLines.append("> 由 `tools/gp_dexpi_coverage.gd -- --write` 生成；不要手改。")
	gpLines.append("> **DO NOT EDIT** — regenerate with the command above.")
	gpLines.append("")
	gpLines.append("- 标准 / Standard: `%s`" % gpJ["standard"])
	gpLines.append("- 报告哈希 / Report SHA-256: `%s`" % gpHashing)
	gpLines.append("- 生成命令 / Command: `HOME=/tmp/gpidhome godot --headless --script res://tools/gp_dexpi_coverage.gd -- --write`")
	gpLines.append("")
	gpLines.append("## 概念类 / Concept symbols")
	gpLines.append("")
	gpLines.append("| 项 | 数量 |")
	gpLines.append("|---|---:|")
	var gpS: Dictionary = gpJ["symbols"] as Dictionary
	gpLines.append("| 映射图元 / mapped symbols | %d |" % int(gpS["total"]))
	gpLines.append("| 类 + URI 已验证 / class + verified URI | %d |" % (gpS["full"] as Array).size())
	gpLines.append("| 类已定、URI 待核实 / class, URI pending | %d |" % (gpS["partial"] as Array).size())
	gpLines.append("| 纯图形 / annotation-only | %d |" % (gpS["annotation_only"] as Array).size())
	gpLines.append("| 无类 / no class | %d |" % (gpS["no_class"] as Array).size())
	gpLines.append("")
	gpLines.append("### URI 缺口 / URI gaps")
	gpLines.append("")
	for gpId in gpS["partial"] as Array:
		gpLines.append("- `%s` — class mapped, URI intentionally empty (not fabricated)" % str(gpId))
	gpLines.append("")
	gpLines.append("## 属性 / Attributes")
	gpLines.append("")
	gpLines.append("| 项 | 数量 |")
	gpLines.append("|---|---:|")
	var gpA: Dictionary = gpJ["attributes"] as Dictionary
	gpLines.append("| 映射属性 / mapped | %d |" % int(gpA["total"]))
	gpLines.append("| URI 已验证 / verified URI | %d |" % (gpA["uri_verified"] as Array).size())
	gpLines.append("| 无 URI / no URI | %d |" % (gpA["uri_missing"] as Array).size())
	gpLines.append("| 内部 / internal (never exported) | %d |" % (gpA["internal"] as Array).size())
	gpLines.append("")
	gpLines.append("## 明确缺口 / Explicit gaps")
	gpLines.append("")
	gpLines.append("- DEXPI 1.4 的 568 个类型中，本报告**只**声明上表映射到的图元；不声称 568 全量覆盖。")
	gpLines.append("- 无 URI 的行是**刻意留空**，不是已验证；见 `GP_DEXPI_MAPPING` 的 URI 原则。")
	gpLines.append("- 本报告不修改映射实现；缺口只能通过补表和验证 URI 关闭。")
	gpLines.append("")
	gpLines.append("## 复算 / Reproduce")
	gpLines.append("")
	gpLines.append("```bash")
	gpLines.append("cd Godot-PID-Core")
	gpLines.append("HOME=/tmp/gpidhome godot --headless --script res://tools/gp_dexpi_coverage.gd")
	gpLines.append("```")
	gpLines.append("")
	gpLines.append("JSON 中的 `REPORT_SHA256` 必须与上方哈希一致。")
	var gpFile: FileAccess = FileAccess.open("res://docs/DEXPI_COVERAGE.md", FileAccess.WRITE)
	if gpFile != null:
		gpFile.store_string("\n".join(gpLines))
		gpFile.close()
