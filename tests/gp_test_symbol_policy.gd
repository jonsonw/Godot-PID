extends "res://tests/gp_test.gd"
# Copyright © 2026 Jonson Wang
# Stage-2 "annotation-symbol general rules" policy suite (Rev.3 §8).
# 阶段 2「标注类图元通则」策略套件（Rev.3 §8）。
#
# Pins the seven definition-layer policy fields end to end:
# 钉住七个定义层策略字段的端到端行为：
#   1. defaults == today's behaviour (existing packs stay byte-identical);
#      默认值 == 今天的行为（既有图元包逐字节不变）；
#   2. non-default-only persistence (archive stability) + round trip;
#      仅非默认才写出（存档稳定性）+ 往返；
#   3. every CONSUMER honours its field: normalizer size exemption, collision (neither pushes
#      nor is pushed), routing obstacles, pick modes, renumber candidates, release-mount gate,
#      place-policy corner decode;
#      每个**消费点**尊重其字段：归一化尺寸豁免、碰撞（既不推人也不被推）、布线障碍、
#      拾取模式、重排候选集、释放挂载闸、放置策略角点解码；
#   4. the first generator (GENERATOR:multiline) + the TEXT:multiline template.
#      首个生成器（GENERATOR:multiline）与 TEXT:multiline 模板。
#
# ⚠️ 期望值推导纪律：凡是「键 + 前缀」两侧的断言，期望值从常量取，绝不从实现抄。
# ⚠️ Expectation-derivation discipline: expectations come from the constants, never copied
# from the implementation.

# The seven dictionary keys the policy fields own, with their default / non-default values.
# 策略字段拥有的七个字典键，及其默认 / 非默认取值。
const GP_POLICY_KEYS: Array[String] = ["size_mode", "geometry_source", "pick_mode",
	"avoid_routing", "taggable", "place_policy", "mountable"]


# A plain definition with defaults everywhere.
# 一个全默认的普通定义。
func _gpPlainDef() -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = "PLAIN1"
	gpD.gpDefaultSize = Vector2(64.0, 48.0)
	return gpD


# An annotation-style definition: avoid=false (the no-avoid contract), mountable=false.
# 一个注释风格的定义：avoid=false（不避让契约）、mountable=false。
func _gpAnnoDef() -> GPSymbolDef:
	var gpD: GPSymbolDef = _gpPlainDef()
	gpD.gpAvoidRouting = false
	gpD.gpMountable = false
	return gpD


# A def-lookup callable answering from one id->def map.
# 从一张 id->定义 映射作答的定义查找 Callable。
func _gpLookupOf(gpMap: Dictionary) -> Callable:
	return func(gpSymbolId: String) -> GPSymbolDef:
		return gpMap.get(gpSymbolId, null) as GPSymbolDef


# Typed fixed-id list builder (Array[String] literals are awkward inline).
# 类型化固定 id 列表构造（Array[String] 字面量内联书写不便）。
func _gpStr(gpA: String, gpB: String = "", gpC: String = "") -> Array[String]:
	var gpOut: Array[String] = [gpA]
	if gpB != "":
		gpOut.append(gpB)
	if gpC != "":
		gpOut.append(gpC)
	return gpOut


# A graph with one annotation node overlapping one ordinary node.
# 一个「注释节点与普通节点重叠」的图。
func _gpMixedGraph() -> GPPIDGraph:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("t", "anno", "", Vector2(0, 0)))
	gpG.gpAddNode(gpG.gpNewNode("v", "valve", "V-1", Vector2(10, 0)))
	return gpG


# ---------------------------------------------------------------- 1) defaults
# ---------------------------------------------------------------- 1) 默认值

# Every default must equal today's behaviour — the whole backward-compat guarantee.
# 每个默认值都必须等于今天的行为 —— 这是整条向后兼容保证的根基。
func gpTestPolicyDefaultsMatchToday() -> void:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpEq(gpD.gpSizeMode, GPSymbolDef.GP_SIZE_MODE_CATEGORY, "默认尺寸模式应为 CATEGORY")
	gpEq(gpD.gpGeometrySource, GPSymbolDef.GP_GEOMETRY_STATIC, "默认几何来源应为 STATIC")
	gpEq(gpD.gpPickMode, GPSymbolDef.GP_PICK_FULL, "默认拾取模式应为 FULL")
	gpCheck(gpD.gpAvoidRouting, "默认应参与避让")
	gpCheck(gpD.gpTaggable, "默认应可编号")
	gpEq(gpD.gpPlacePolicy, GPSymbolDef.GP_PLACE_FREE, "默认放置策略应为 FREE")
	gpCheck(gpD.gpMountable, "默认应可挂载")


# ---------------------------------------------------------------- 2) persistence
# ---------------------------------------------------------------- 2) 持久化

# A default definition writes NONE of the seven keys (byte stability of old packs); a fully
# opted-in definition writes ALL seven with the opted values.
# 全默认定义**不写**七个键中任何一个（旧包字节稳定）；全部 opting-in 的定义写出全部七个
# 且取 opted 值。
func gpTestPolicyKeysWrittenOnlyWhenNonDefault() -> void:
	var gpD: Dictionary = _gpPlainDef().gpToDict()
	for gpK in GP_POLICY_KEYS:
		gpCheck(not gpD.has(gpK), "默认定义不应写出键 %s" % [gpK])
	var gpDef: GPSymbolDef = _gpPlainDef()
	gpDef.gpSizeMode = GPSymbolDef.GP_SIZE_MODE_EXPLICIT
	gpDef.gpGeometrySource = GPSymbolDef.GP_GEOMETRY_GENERATOR_PREFIX + "multiline"
	gpDef.gpPickMode = GPSymbolDef.GP_PICK_BORDER
	gpDef.gpAvoidRouting = false
	gpDef.gpTaggable = false
	gpDef.gpPlacePolicy = GPSymbolDef.GP_PLACE_SHEET_ANCHOR_PREFIX + "BR"
	gpDef.gpMountable = false
	var gpD2: Dictionary = gpDef.gpToDict()
	gpEq(str(gpD2.get("size_mode", "")), GPSymbolDef.GP_SIZE_MODE_EXPLICIT, "size_mode 应写出")
	gpEq(str(gpD2.get("geometry_source", "")), "GENERATOR:multiline", "geometry_source 应写出")
	gpEq(str(gpD2.get("pick_mode", "")), GPSymbolDef.GP_PICK_BORDER, "pick_mode 应写出")
	gpCheck(not bool(gpD2.get("avoid_routing", true)), "avoid_routing=false 应写出")
	gpCheck(not bool(gpD2.get("taggable", true)), "taggable=false 应写出")
	gpEq(str(gpD2.get("place_policy", "")), "SHEET_ANCHOR:BR", "place_policy 应写出")
	gpCheck(not bool(gpD2.get("mountable", true)), "mountable=false 应写出")


# The seven fields survive a to-dict / from-dict round trip; a default definition still
# round-trips to defaults (the .get(key, default) reads).
# 七个字段在写出 / 读回往返后保持不变；全默认定义往返后仍为默认（.get(key, default) 读取）。
func gpTestPolicyRoundTrip() -> void:
	var gpDef: GPSymbolDef = _gpPlainDef()
	gpDef.gpSizeMode = GPSymbolDef.GP_SIZE_MODE_EXPLICIT
	gpDef.gpPickMode = GPSymbolDef.GP_PICK_NONE
	gpDef.gpAvoidRouting = false
	gpDef.gpPlacePolicy = GPSymbolDef.GP_PLACE_SHEET_ANCHOR_PREFIX + "TL"
	var gpBack: GPSymbolDef = GPSymbolDef.new()
	gpBack.gpFromDict(gpDef.gpToDict())
	gpEq(gpBack.gpSizeMode, GPSymbolDef.GP_SIZE_MODE_EXPLICIT, "size_mode 应随往返")
	gpEq(gpBack.gpPickMode, GPSymbolDef.GP_PICK_NONE, "pick_mode 应随往返")
	gpCheck(not gpBack.gpAvoidRouting, "avoid_routing=false 应随往返")
	gpEq(gpBack.gpPlacePolicy, "SHEET_ANCHOR:TL", "place_policy 应随往返")
	gpCheck(gpBack.gpTaggable, "未写出的 taggable 应回落默认 true")
	gpCheck(gpBack.gpMountable, "未写出的 mountable 应回落默认 true")
	# A pre-stage-2 archive (no policy keys at all) loads with today's behaviour.
	# 阶段 2 之前的存档（完全没有策略键）载入后行为不变。
	var gpOld: GPSymbolDef = GPSymbolDef.new()
	gpOld.gpFromDict({"id": "OLD", "default_size": [10.0, 10.0]})
	gpEq(gpOld.gpSizeMode, GPSymbolDef.GP_SIZE_MODE_CATEGORY, "旧档应回落 CATEGORY")
	gpEq(gpOld.gpGeometrySource, GPSymbolDef.GP_GEOMETRY_STATIC, "旧档应回落 STATIC")


# ------------------------------------------------------- 3) consumers / 消费点
# ------------------------------------------------------- 3) 消费点

# Normalizer: EXPLICIT keeps the authored size; CATEGORY still takes the category envelope.
# 归一化器：EXPLICIT 保留作者尺寸；CATEGORY 仍取类别包络。
func gpTestNormalizerSizeExemption() -> void:
	var gpRaw: Dictionary = {"id": "T1", "default_size": [40.0, 20.0], "size_mode": "EXPLICIT"}
	var gpDef: GPSymbolDef = GPSymbolNormalizer.gpNormalizeSymbol(gpRaw, "valve")
	gpEq(gpDef.gpDefaultSize, Vector2(40.0, 20.0), "EXPLICIT 应保留作者尺寸（尺寸豁免）")
	var gpRaw2: Dictionary = {"id": "T2", "default_size": [40.0, 20.0]}
	var gpDef2: GPSymbolDef = GPSymbolNormalizer.gpNormalizeSymbol(gpRaw2, "valve")
	gpEq(gpDef2.gpDefaultSize, GPSymbolCategories.gpSizeFor("valve"),
		"CATEGORY 应被类别包络覆写（期望值自类别表推导）")


# Collision: a no-avoid definition is NEITHER pusher NOR pushed — one node pair, one resolve.
# 碰撞：无避让定义**既不推人也不被推** —— 一对节点，一次解析。
func gpTestCollisionSkipsNoAvoidBothWays() -> void:
	var gpMap: Dictionary = {"anno": _gpAnnoDef(), "valve": _gpPlainDef()}
	var gpG: GPPIDGraph = _gpMixedGraph()
	var gpRes: Dictionary = GPNodeCollision.gpResolve(gpG, _gpLookupOf(gpMap), _gpStr("v"))
	gpCheck(gpRes.is_empty(), "注释图元不应被推开（valve 已固定，注释不构成对它的推挤）")
	# Control: the same geometry with a plain def for "anno" DOES push it away.
	# 对照：同样几何、"anno" 换成普通定义时**确实**会推开。
	var gpMap2: Dictionary = {"anno": _gpPlainDef(), "valve": _gpPlainDef()}
	var gpG2: GPPIDGraph = _gpMixedGraph()
	var gpRes2: Dictionary = GPNodeCollision.gpResolve(gpG2, _gpLookupOf(gpMap2), _gpStr("v"))
	gpCheck(gpRes2.has("t"), "对照组：普通定义的重叠节点应被推开")
	# And a no-avoid node never appears in the result even when it is NOT fixed.
	# 且无避让节点即使**未被固定**也绝不出现在结果里。
	var gpMap3: Dictionary = {"anno": _gpAnnoDef(), "valve": _gpPlainDef()}
	var gpG3: GPPIDGraph = _gpMixedGraph()
	var gpRes3: Dictionary = GPNodeCollision.gpResolve(gpG3, _gpLookupOf(gpMap3), _gpStr("v", "t"))
	gpCheck(not gpRes3.has("t"), "无避让节点不应出现在推送结果中")


# Routing: a no-avoid definition is never an obstacle, so pipes may legally cross it.
# 布线：无避让定义不构成障碍，管线可以合法横穿。
func gpTestRoutingObstacleSkipsNoAvoid() -> void:
	var gpMap: Dictionary = {"anno": _gpAnnoDef(), "valve": _gpPlainDef()}
	var gpG: GPPIDGraph = _gpMixedGraph()
	var gpObs: Array[Rect2] = GPEdgeAutoRoute.gpObstacles(gpG, _gpLookupOf(gpMap))
	gpEq(gpObs.size(), 1, "无避让定义不应成为布线障碍（仅普通节点 1 个）")
	var gpMap2: Dictionary = {"anno": _gpPlainDef(), "valve": _gpPlainDef()}
	var gpObs2: Array[Rect2] = GPEdgeAutoRoute.gpObstacles(gpG, _gpLookupOf(gpMap2))
	gpEq(gpObs2.size(), 2, "对照组：普通定义构成障碍（2 个）")


# Pick modes: NONE is unpickable; BORDER only answers on the rim band; FULL answers anywhere.
# 拾取模式：NONE 不可拾取；BORDER 仅边框带应答；FULL 任意处应答。
func gpTestPickModes() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("N1", "blk", "", Vector2(10, 10)))
	# 80x40 envelope centred at (10,10): the rim band is the 3 mm ring between the rect and
	# the rect grown by -3.
	# 以 (10,10) 为中心的 80x40 包络：边框带即矩形与其内缩 3mm 之间的 3mm 环带。
	var gpCenter: Vector2 = Vector2(10.0, 10.0)
	var gpRim: Vector2 = Vector2(10.0, -8.0)
	var gpNone: GPGraphBinder = _gpBinderOf(GPSymbolDef.GP_PICK_NONE)
	gpEq(GPCanvasHitTest.gpHitNode(gpG, gpNone, gpCenter), "", "NONE 模式中心点不应命中")
	gpNone.free()
	var gpBorder: GPGraphBinder = _gpBinderOf(GPSymbolDef.GP_PICK_BORDER)
	gpEq(GPCanvasHitTest.gpHitNode(gpG, gpBorder, gpCenter), "",
		"BORDER 模式中心点不应命中（穿透到下方）")
	gpEq(GPCanvasHitTest.gpHitNode(gpG, gpBorder, gpRim), "N1", "BORDER 模式边框带应命中")
	gpBorder.free()
	var gpFull: GPGraphBinder = _gpBinderOf(GPSymbolDef.GP_PICK_FULL)
	gpEq(GPCanvasHitTest.gpHitNode(gpG, gpFull, gpCenter), "N1", "FULL 模式中心点应命中")
	gpFull.free()


# A binder holding ONE def of the given pick mode with an 80x40 envelope. Caller frees (Node).
# 持有单个指定拾取模式定义（80x40 包络）的绑定器。调用方负责释放（Node）。
func _gpBinderOf(gpPickMode: String) -> GPGraphBinder:
	var gpB: GPGraphBinder = GPGraphBinder.new()
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = "blk"
	gpD.gpDefaultSize = Vector2(80.0, 40.0)
	gpD.gpPickMode = gpPickMode
	gpB.gpDefs = [gpD]
	return gpB


# Renumbering excludes non-taggable definitions explicitly (never by an empty-prefix accident).
# 重排候选集显式排除不可编号定义（绝不靠空前缀碰运气）。
func gpTestRenumberExcludesNonTaggable() -> void:
	GPSymbolLibrary.gpClearRegistered()
	var gpAnno: GPSymbolDef = _gpAnnoDef()
	gpAnno.gpId = "CANN001"
	gpAnno.gpTaggable = false
	var gpDefs: Array[GPSymbolDef] = [gpAnno]
	GPSymbolLibrary.gpRegisterDefs(gpDefs)
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("t", "CANN001", "", Vector2(0, 0)))
	gpG.gpAddNode(gpG.gpNewNode("v", "DVALVE001", "XV-1", Vector2(100, 0)))
	var gpItems: Array[Dictionary] = GPTagRuleService.gpRenumberItems(gpG)
	var gpUids: Array[String] = []
	for gpIt in gpItems:
		gpUids.append(str(gpIt["uid"]))
	gpCheck(not gpUids.has("t"), "不可编号定义的实例不应进入重排候选集")
	gpCheck(gpUids.has("v"), "普通可编号实例应进入重排候选集")
	GPSymbolLibrary.gpClearRegistered()


# Place policy: the corner decode answers each named corner and degrades unknown codes.
# 放置策略：角点解码应答每个命名角，未知编码退化。
func gpTestFrameCornerDecode() -> void:
	var gpR: Rect2 = Rect2(0.0, 0.0, 100.0, 50.0)
	gpEq(GPFrameGeometry.gpFrameCorner(gpR, "BR", Vector2.ZERO), Vector2(100.0, 50.0),
		"BR 应为右下角")
	gpEq(GPFrameGeometry.gpFrameCorner(gpR, "BL", Vector2.ZERO), Vector2(0.0, 50.0),
		"BL 应为左下角")
	gpEq(GPFrameGeometry.gpFrameCorner(gpR, "TR", Vector2.ZERO), Vector2(100.0, 0.0),
		"TR 应为右上角")
	gpEq(GPFrameGeometry.gpFrameCorner(gpR, "TL", Vector2.ZERO), Vector2(0.0, 0.0),
		"TL 应为左上角")
	gpEq(GPFrameGeometry.gpFrameCorner(gpR, "XX", Vector2(7.0, 7.0)), Vector2(7.0, 7.0),
		"未知编码应退化为点击点（兜底）")
	# A moved frame's corners follow its position (paper-origin semantics).
	# 已移动图框的角点跟随其位置（纸面原点语义）。
	var gpM: Rect2 = Rect2(300.0, 200.0, 100.0, 50.0)
	gpEq(GPFrameGeometry.gpFrameCorner(gpM, "TL", Vector2.ZERO), Vector2(300.0, 200.0),
		"角点应随图框位置走")


# Release-mount gate: null (unknown def) may mount; a mountable def may; a non-mountable one may not.
# 释放挂载闸：null（未知定义）可挂载；可挂载定义可；不可挂载定义不可。
func gpTestReleaseMayMount() -> void:
	gpCheck(GPMountResolver.gpReleaseMayMount(null), "未知定义应保持既有行为（可尝试挂载）")
	gpCheck(GPMountResolver.gpReleaseMayMount(_gpPlainDef()), "普通定义应可挂载")
	gpCheck(not GPMountResolver.gpReleaseMayMount(_gpAnnoDef()), "mountable=false 定义不得挂载")


# ------------------------------------------------- 4) generator + template
# ------------------------------------------------- 4) 生成器 + 模板

# Registry routing: STATIC is not a generator; the prefix strips to the id; unknown ids and
# null inputs degrade to the explicit no-draw result.
# 注册表路由：STATIC 非生成器；前缀剥离得 id；未知 id 与 null 输入退化为「显式不画」结果。
func gpTestRegistryRouting() -> void:
	gpCheck(not GPSymbolGeneratorRegistry.gpIsGenerator(GPSymbolDef.GP_GEOMETRY_STATIC),
		"STATIC 不应被当作生成器")
	gpCheck(GPSymbolGeneratorRegistry.gpIsGenerator("GENERATOR:multiline"),
		"GENERATOR: 前缀应识别为生成器")
	gpEq(GPSymbolGeneratorRegistry.gpGeneratorId("GENERATOR:multiline"), "multiline",
		"前缀剥离应得到生成器 id")
	gpEq(GPSymbolGeneratorRegistry.gpGeneratorId(GPSymbolDef.GP_GEOMETRY_STATIC), "",
		"非生成器来源的 id 应为空串")
	var gpDef: GPSymbolDef = _gpPlainDef()
	# Stage 3: "grid" is a REAL generator now — use a genuinely unknown id for the
	# degradation pin (the pin's intent is unknown-id degradation, not "grid is fictional").
	# 阶段 3："grid" 已是真实生成器 —— 退化钉改用真正未知的 id
	#（该钉的本意是「未知 id 安全退化」，而非「grid 不存在」）。
	gpDef.gpGeometrySource = "GENERATOR:no_such_gen"
	var gpN: GPPIDNode = GPPIDNode.new()
	var gpOut: Dictionary = GPSymbolGeneratorRegistry.gpGenerate(gpDef, gpN)
	gpCheck((gpOut.get("spec", {}) as Dictionary).is_empty(), "未知生成器应退化为空规格")
	gpEq((gpOut.get("text_lines", PackedStringArray()) as PackedStringArray).size(), 0,
		"未知生成器不应产出文字行")
	gpEq(GPSymbolGeneratorRegistry.gpGenerate(null, null).get("spec", {}), {},
		"null 输入应安全退化")


# The multiline generator: content from the node's "text" prop, split on newlines; empty
# content -> zero lines; the text prop key is declared so the editor can target it.
# multiline 生成器：内容取自节点 "text" 属性、按换行拆分；空内容 -> 零行；文字属性键有
# 声明，供编辑器瞄准。
func gpTestMultilineGenerator() -> void:
	var gpDef: GPSymbolDef = _gpPlainDef()
	gpDef.gpGeometrySource = "GENERATOR:multiline"
	var gpN: GPPIDNode = GPPIDNode.new()
	gpN.gpProps["text"] = "第一行\n\n第三行"
	var gpOut: Dictionary = GPSymbolGeneratorRegistry.gpGenerate(gpDef, gpN)
	var gpLines: PackedStringArray = gpOut.get("text_lines", PackedStringArray()) as PackedStringArray
	gpEq(gpLines.size(), 3, "按换行应拆出 3 行（含空行）")
	gpEq(str(gpLines[0]), "第一行", "第 1 行应保持原文")
	gpEq(str(gpLines[1]), "", "空行应保持为空行")
	gpEq((gpOut.get("spec", {}) as Dictionary).is_empty(), true,
		"纯文字生成器不应产出矢量规格（显式不画）")
	var gpN2: GPPIDNode = GPPIDNode.new()
	gpEq((GPSymbolGeneratorRegistry.gpGenerate(gpDef, gpN2)
		.get("text_lines", PackedStringArray()) as PackedStringArray).size(), 0,
		"未填写内容应为零行（不画任何东西）")
	gpEq(GPSymbolGeneratorRegistry.gpTextPropKey(gpDef), "text",
		"multiline 生成器应声明其文字属性键")
	gpEq(GPSymbolGeneratorRegistry.gpTextPropKey(_gpPlainDef()), "",
		"非生成器定义不应声明文字属性键")


# The TEXT:multiline template itself: one row of policy, no art, a declared content prop.
# TEXT:multiline 模板本体：一行策略、无图形、声明内容属性。
func gpTestTextMultilineTemplate() -> void:
	var gpDefs: Array[GPSymbolDef] = GPSymbolAnnotationTemplates.gpDefs()
	gpEq(gpDefs.size(), 2, "注释模板应有两个（阶段 3 起含设备参数表；详见 gp_test_table_grid）")
	var gpD: GPSymbolDef = gpDefs[0]
	gpEq(gpD.gpId, "TEXT:multiline", "模板 id 应为 TEXT:multiline")
	gpEq(gpD.gpCategory, "annotation", "模板类目应为 annotation")
	gpEq(gpD.gpSizeMode, GPSymbolDef.GP_SIZE_MODE_EXPLICIT, "模板应为显式尺寸（尺寸豁免）")
	gpEq(gpD.gpGeometrySource, "GENERATOR:multiline", "模板几何应来自 multiline 生成器")
	gpEq(gpD.gpPickMode, GPSymbolDef.GP_PICK_FULL,
		"模板拾取应为 FULL（用户反馈：点文字本身即选中，非仅边框带）")
	gpCheck(not gpD.gpAvoidRouting, "模板不参与避让")
	gpCheck(not gpD.gpTaggable, "模板不可编号")
	gpCheck(not gpD.gpMountable, "模板不可挂载")
	gpEq(gpD.gpShapes.size(), 0, "模板不应有静态形状（几何归生成器）")
	gpEq(gpD.gpPorts.size(), 0, "文本块不应有端口")
	gpCheck(gpD.gpBuiltin, "模板应为内置（D3 只读）")
	gpEq(gpD.gpDefaultSize, Vector2(80.0, 40.0), "模板显式包络应为 80x40mm（A1 ×2 重定基 + 用户反馈注释文字翻倍）")
	gpCheck(gpD.gpSchema != null, "模板应声明属性 schema")
	if gpD.gpSchema != null:
		var gpF: GPPropertyDef = (gpD.gpSchema as GPPropertySchema).gpFieldByKey("text")
		gpCheck(gpF != null, "schema 应声明 text 键")
		if gpF != null:
			gpEq(int(gpF.gpKind), int(GPPropertyDef.GPKind.GP_TEXT),
				"text 键应为多行文本类型（属性面板渲染多行字段）")


# The library serves the template, and the template rides the in-place editing channel.
# 图元库应提供模板，且模板接入就地编辑通道。
func gpTestLibraryServesTextMultiline() -> void:
	var gpD: GPSymbolDef = GPSymbolLibrary.gpFindById("TEXT:multiline")
	gpCheck(gpD != null, "图元库应能按 id 找到 TEXT:multiline")
	if gpD == null:
		return
	gpCheck(not gpD.gpAvoidRouting, "库中模板应保持不避让策略")
	gpEq(GPSymbolGeneratorRegistry.gpTextPropKey(gpD), "text", "库中模板应声明文字属性键")
	# In-place edit channel (stage 1.5 reuse): no slots + tag-like format => double-click
	# opens the editor; the hit target is the envelope itself.
	# 就地编辑通道（复用阶段 1.5）：无槽 + 位号型格式 => 双击打开编辑器；命中目标即包络本身。
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("t", "TEXT:multiline", "", Vector2(50.0, 60.0)))
	var gpN: GPPIDNode = gpG.gpGetNode("t")
	gpCheck(GPNodeTextEditor.gpWantsInPlace(gpN, gpD), "文本块双击应允许就地编辑")
	var gpRect: Rect2 = GPNodeTextEditor.gpTextRectWorld(gpN, gpD, gpG, Callable())
	gpEq(gpRect.grow(-2.0).size, Vector2(80.0, 40.0), "编辑命中矩形应为包络本身（去除 grow 余量）")
	gpEq(gpRect.get_center(), Vector2(50.0, 60.0), "编辑命中矩形应以节点为中心")
