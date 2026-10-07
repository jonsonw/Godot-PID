extends "res://tests/gp_test.gd"
# Drawing frame + bilingual title-block tests (v0.1 Phase 2).
# 图框 + 双语标题栏测试（v0.1 Phase 2）。
# The failure modes being guarded against:
# 所防范的失效模式：
# 1. A new sheet silently loses its A3 size / frame, so the drawing has no boundary.
#    新建图纸静默丢失 A3 图幅 / 图框，导致图纸没有边界。
# 2. A saved frame comes back reset — the user fills in a title block, saves, and the
#    drawing reopens empty. That wastes a real deliverable, not just a setting.
#    保存的图框回来后被重置 —— 用户填好标题栏、保存、重开却是空的。损失的可是真实交付物。
# 3. An archive written before the frame existed opens with a HALF block (or crashes).
#    图框功能之前写的旧档打开后只有半个标题栏（或崩溃）。
# 4. The drawing-text language leaks into tag numbers, corrupting identifiers.
#    图纸文字语言串进位号，污染标识。

# Number of standard title-block fields (GPSheet.GP_TB_FIELDS).
# 标准标题栏字段数（GPSheet.GP_TB_FIELDS）。
const GP_FIELD_COUNT: int = 13


# A brand-new sheet is A3, framed, bilingual, and carries the complete cell grid.
# 全新图纸为 A3、带图框、中英对照，且具备完整格网。
func gpTestNewSheetIsA3FramedBilingual() -> void:
	var gpS: GPSheet = GPSheet.gpNew("sheet-1", "首页", 0)
	gpEq(gpS.gpWidthMM, 420.0, "默认图幅宽应为 A3 的 420mm")
	gpEq(gpS.gpHeightMM, 297.0, "默认图幅高应为 A3 的 297mm")
	gpCheck(gpS.gpFrameOn, "新图纸默认应显示图框")
	gpEq(gpS.gpLabelMode, GPSheet.GP_LABEL_BOTH, "默认应为中英对照")
	gpEq(gpS.gpTitleBlock.size(), GP_FIELD_COUNT, "标题栏应为 %d 个标准字段" % [GP_FIELD_COUNT])
	var gpEntry: Variant = gpS.gpTitleBlock.get("sheet_size")
	gpCheck(gpEntry != null, "标题栏应含「图幅」字段")
	if gpEntry != null:
		var gpV: Variant = (gpEntry as Dictionary).get("value")
		gpEq(str((gpV as Dictionary).get("zh", "")), "A3", "「图幅」格应自动回填 A3")


# Frame size, label mode and title-block values survive a save / load round trip.
# 图幅、语言模式与标题栏取值在存 / 取往返后保持不变。
func gpTestFrameSurvivesRoundTrip() -> void:
	var gpS: GPSheet = GPSheet.gpNew("sheet-1", "首页", 0)
	gpS.gpWidthMM = 594.0
	gpS.gpHeightMM = 420.0
	gpS.gpLabelMode = GPSheet.GP_LABEL_EN
	gpS.gpTitleBlock["project"] = {"value": {"zh": "示例项目", "en": "Sample Project"}}
	var gpD: Dictionary = gpS.gpToDict()
	var gpBack: GPSheet = GPSheet.gpFromDict(gpD)
	gpEq(gpBack.gpWidthMM, 594.0, "图幅宽应随存档往返")
	gpEq(gpBack.gpHeightMM, 420.0, "图幅高应随存档往返")
	gpEq(gpBack.gpLabelMode, GPSheet.GP_LABEL_EN, "语言模式应随存档往返")
	var gpEntry: Variant = gpBack.gpTitleBlock.get("project")
	gpCheck(gpEntry != null, "标题栏的 project 字段应回来")
	if gpEntry != null:
		var gpV: Variant = (gpEntry as Dictionary).get("value")
		gpEq(str((gpV as Dictionary).get("en", "")), "Sample Project", "英文值应随存档往返")
		gpEq(str((gpV as Dictionary).get("zh", "")), "示例项目", "中文值应随存档往返")


# An untouched sheet writes NO frame keys, so archives from older builds stay byte-stable.
# 未动过图框的图纸不写出图框键，使旧版本产出的存档保持逐字节稳定。
func gpTestDefaultFrameStaysOutOfTheArchive() -> void:
	var gpD: Dictionary = GPSheet.gpNew("sheet-1", "首页", 0).gpToDict()
	gpCheck(not gpD.has("label_mode"),
		"默认（中英对照）不应写出 label_mode，否则每份旧档都会被改写")
	gpCheck(gpD.has("width_mm"), "图幅宽应始终写出，使非 A3 图纸不会静默变回 A3")


# An archive predating the frame opens with the FULL standard block, not a partial one.
# 图框功能之前写的旧档应以**完整**标准标题栏打开，而非残缺。
func gpTestLegacyArchiveGetsFullBlock() -> void:
	var gpOld: Dictionary = {"id": "sheet-1", "name": "旧图", "index": 0,
		"nodes": [], "edges": [], "shapes": []}
	var gpS: GPSheet = GPSheet.gpFromDict(gpOld)
	gpEq(gpS.gpTitleBlock.size(), GP_FIELD_COUNT, "旧档应补全为 %d 个标准字段" % [GP_FIELD_COUNT])
	gpEq(gpS.gpWidthMM, 420.0, "旧档应回落到 A3 宽")
	gpEq(gpS.gpLabelMode, GPSheet.GP_LABEL_BOTH, "旧档应回落到中英对照")


# The label mode selects which language a title-block VALUE renders in.
# 语言模式决定标题栏**取值**用哪种语言渲染。
func gpTestLabelModeSelectsValueLanguage() -> void:
	var gpS: GPSheet = GPSheet.gpNew("sheet-1", "首页", 0)
	gpS.gpTitleBlock["drawing_title"] = {"value": {"zh": "工艺流程图", "en": "Process Flow Diagram"}}
	gpS.gpLabelMode = GPSheet.GP_LABEL_ZH
	gpEq(gpS.gpTitleValue("drawing_title"), "工艺流程图", "中文模式应取中文值")
	gpS.gpLabelMode = GPSheet.GP_LABEL_EN
	gpEq(gpS.gpTitleValue("drawing_title"), "Process Flow Diagram", "英文模式应取英文值")


# Tag numbers are identifiers, not prose: they must be reachable regardless of label mode.
# 位号是标识而非文字：无论语言模式如何都必须可取。
func gpTestLabelModeNeverReachesTags() -> void:
	var gpS: GPSheet = GPSheet.gpNew("sheet-1", "首页", 0)
	gpS.gpLabelMode = GPSheet.GP_LABEL_EN
	var gpN: GPPIDNode = gpS.gpGraph.gpNewNode("n1", "pump", "P-101", Vector2(10.0, 20.0))
	gpS.gpGraph.gpAddNode(gpN)
	gpEq(gpN.gpTag, "P-101", "切到英文模式后位号必须原样为 P-101，不得被翻译")


# Standard sheet presets are the ISO 216 sizes in mm.
# 标准图幅预设即 ISO 216 的毫米尺寸。
func gpTestSheetPresetsAreIsoSizes() -> void:
	var gpA4: Vector2 = GPSheet.GP_SHEET_PRESETS["A4"]
	var gpA3: Vector2 = GPSheet.GP_SHEET_PRESETS["A3"]
	var gpA0: Vector2 = GPSheet.GP_SHEET_PRESETS["A0"]
	gpEq(gpA4.x, 297.0, "A4 宽应为 297mm")
	gpEq(gpA4.y, 210.0, "A4 高应为 210mm")
	gpEq(gpA3.x, 420.0, "A3 宽应为 420mm")
	gpEq(gpA0.x, 1189.0, "A0 宽应为 1189mm")


# Changing the sheet size rewrites the SIZE cell instead of leaving a stale value.
# 改图幅会重写「图幅」格，而非留下过期值。
func gpTestSheetSizeCellTracksSheet() -> void:
	var gpS: GPSheet = GPSheet.gpNew("sheet-1", "首页", 0)
	gpS.gpWidthMM = 841.0
	gpS.gpHeightMM = 594.0
	gpS.gpSyncSheetSizeField()
	var gpEntry: Variant = gpS.gpTitleBlock.get("sheet_size")
	gpCheck(gpEntry != null, "应存在「图幅」字段")
	if gpEntry != null:
		var gpV: Variant = (gpEntry as Dictionary).get("value")
		gpEq(str((gpV as Dictionary).get("zh", "")), "A1", "图幅改为 A1 后「图幅」格应回填 A1")


# Tracing-underlay path + alpha must round-trip through the archive, and a sheet that never
# touched the underlay must NOT write background keys (ADR-7 byte-stability for old archives).
# 追踪底图的路径与透明度必须随存档往返；从未设置底图的图纸不得写出背景键
# （ADR-7 旧档字节稳定）。
func gpTestBackgroundRoundTrip() -> void:
	var gpS: GPSheet = GPSheet.gpNew("sheet-1", "首页", 0)
	gpS.gpBackgroundPath = "user://trace_underlay.png"
	gpS.gpBackgroundAlpha = 0.5
	var gpD: Dictionary = gpS.gpToDict()
	gpCheck(gpD.has("background_path"), "设置了底图应写出 background_path")
	gpCheck(gpD.has("background_alpha"), "非默认透明度应写出 background_alpha")
	var gpBack: GPSheet = GPSheet.gpFromDict(gpD)
	gpEq(gpBack.gpBackgroundPath, "user://trace_underlay.png",
		"底图路径应随存档往返")
	gpEq(gpBack.gpBackgroundAlpha, 0.5, "底图透明度应随存档往返")


func gpTestBackgroundStaysOutOfTheArchiveByDefault() -> void:
	var gpD: Dictionary = GPSheet.gpNew("sheet-1", "首页", 0).gpToDict()
	gpCheck(not gpD.has("background_path"),
		"无底图不应写出 background_path，否则旧档会被改写")
	gpCheck(not gpD.has("background_alpha"),
		"默认透明度（0.35）不应写出 background_alpha，保持旧档字节稳定")
