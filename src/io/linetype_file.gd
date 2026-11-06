class_name GPLinetypeFile
extends RefCounted
# Copyright © 2026 Jonson Wang
# Reader for acad.ltp-style linetype files (assets/linetypes/acad.ltp).
# acad.ltp 式线型文件的读取器（assets/linetypes/acad.ltp）。
#
# WHY THIS MOVED HERE / 为何搬到这里（ADR-2 + ADR-10，2026-11-06）：
# The parser used to live in render/linetype_manager.gd, which meant render opened the disk —
# the io boundary leak D04 in the W12 review. Parsing a file is io's job; the pattern TABLE it
# produces belongs to core (GPLinetypeRegistry). This class therefore returns data and never
# touches render or ui.
# 解析器原在 render/linetype_manager.gd，即 render 直接开磁盘 —— W12 审查里的 D04 io 边界渗漏。
# 解析文件是 io 的职守；它产出的图案**表**归 core（GPLinetypeRegistry）。故本类只返回数据，
# 绝不触碰 render / ui。
#
# SPLIT ON PURPOSE / 刻意拆成两层：
# gpParse() is PURE (text in, table out) so it is headless-testable without touching the disk;
# gpRead() is the thin file wrapper. The old code had only the file version, so the format was
# effectively untested.
# gpParse() 是纯函数（文本进、表出），可 headless 测试而无需碰磁盘；gpRead() 是薄文件包装。
# 旧代码只有读文件那一种，格式实际上处于未测试状态。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。


# Parse acad.ltp text into a name -> PackedFloat32Array table. Bad lines are SKIPPED, never fatal:
# a malformed file must degrade to the built-ins, not stop the renderer.
# 把 acad.ltp 文本解析为 名称 -> PackedFloat32Array 表。坏行**跳过**而非致命：
# 文件写坏了只应退回内置值，不该让渲染停下。
# Format: "<NAME> = <description>" line, then "A,<on>,<off>,..." line.
# 格式：「<名称> = <描述>」行，随后「A,<划>,<空>,...」行。
static func gpParse(gpText: String) -> Dictionary:
	var gpOut: Dictionary = {}
	var gpName: String = ""
	for gpRaw in gpText.split("\n"):
		var gpLine: String = gpRaw.strip_edges()
		if gpLine == "" or gpLine.begins_with("#"):
			continue
		if gpLine.begins_with("A,"):
			# Continuation line: dash lengths. A missing name means the block had no
			# "<NAME> =" header, so the numbers belong to nothing and are dropped.
			# 续行：划长。缺少名称说明该块没有「<名称> =」头，数字无所归属，丢弃。
			var gpBody: String = gpLine.substr(2).strip_edges()
			var gpArr: PackedFloat32Array = PackedFloat32Array()
			for gpP in gpBody.split(","):
				var gpTok: String = gpP.strip_edges()
				if gpTok.is_valid_float():
					gpArr.append(float(gpTok))
			if gpName != "" and not gpArr.is_empty():
				gpOut[gpName] = gpArr
			gpName = ""
		elif gpLine.contains("="):
			gpName = gpLine.substr(0, gpLine.find("=")).strip_edges().to_upper()
		else:
			gpName = ""
	return gpOut


# Read and parse a linetype file. Returns an EMPTY dictionary when the file is missing or empty,
# which callers must treat as "keep the built-ins".
# 读取并解析线型文件。文件缺失或为空时返回**空字典**，调用方须视为「沿用内置值」。
static func gpRead(gpPath: String) -> Dictionary:
	if not FileAccess.file_exists(gpPath):
		return {}
	var gpF: FileAccess = FileAccess.open(gpPath, FileAccess.READ)
	if gpF == null:
		return {}
	var gpText: String = gpF.get_as_text()
	gpF.close()
	return gpParse(gpText)
