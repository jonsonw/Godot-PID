extends "res://tests/gp_test.gd"
# M11: every attribute edit is now an undoable command — tag / name / property / label anchor,
# plus the single-step batch form.
# M11：每个属性编辑现在都是可撤销的命令 —— 位号 / 名称 / 属性 / 标签锚点，
# 以及「一个撤销步」的批量形式。
#
# Why this matters / 为何重要：
#   a tag ends up in the DCS point list and on the physical nameplate. An edit that cannot be
#   undone in one step, or a duplicate that is silently accepted, ships a drawing that no
#   longer matches the plant.
#   位号会进入 DCS 点表与现场标牌。无法一步撤销的编辑，或被静默接受的重复位号，
#   都会让交付的图纸与现场装置对不上。


func _mkSvc(gpWithTags: bool = true) -> Array:
	var g: GPPIDGraph = GPPIDGraph.new()
	g.gpAddNode(g.gpNewNode("N1", "pump", "P-1001", Vector2(10, 10)))
	g.gpAddNode(g.gpNewNode("N2", "pump", "P-1002", Vector2(100, 10)))
	var svc: GPEditService = GPEditService.new()
	if gpWithTags:
		svc.gpBindGraph(g, GPIdGen.new(), GPTagRegistry.new())
	else:
		svc.gpBindGraph(g, GPIdGen.new())
	var gpOut: Array = [g, svc]
	return gpOut


# ---- 1. tag / 位号 ----

func gpTestSetTagRoundTrips() -> void:
	var f: Array = _mkSvc()
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	gpCheck(svc.gpSetTag("N1", "P-9001"), "the tag is accepted")
	gpEq(g.gpGetNode("N1").gpTag, "P-9001", "and stored on the node")
	svc.gpUndo()
	gpEq(g.gpGetNode("N1").gpTag, "P-1001", "undo restores the previous tag")
	svc.gpRedo()
	gpEq(g.gpGetNode("N1").gpTag, "P-9001", "redo re-applies it")


# The refusal that protects the plant: two instances may never share a tag.
# 保护现场的拒绝：两个实例绝不能共用同一个位号。
func gpTestSetTagRefusesDuplicate() -> void:
	var f: Array = _mkSvc()
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	gpEq(svc.gpSetTag("N1", "P-1002"), false, "a tag owned by N2 is refused")
	gpEq(svc.gpLastRefusal, "tag.err_duplicate", "and the refusal is explained")
	gpEq(g.gpGetNode("N1").gpTag, "P-1001", "the node keeps its old tag")


func gpTestSetTagNoChangeIsNotAnUndoStep() -> void:
	var f: Array = _mkSvc()
	var svc: GPEditService = f[1]
	gpEq(svc.gpSetTag("N1", "P-1001"), false, "re-typing the same tag changes nothing")
	gpEq(svc.gpLastRefusal, "", "and is not reported as an error")


func gpTestSetTagWithoutRegistryStillWorks() -> void:
	var f: Array = _mkSvc(false)
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	# No tag registry (every pre-M9 document): the edit must still apply, just unguarded.
	# 无位号注册表（M9 之前的所有文档）：编辑仍须生效，只是不校验唯一性。
	gpCheck(svc.gpSetTag("N1", "P-7777"), "the tag is accepted without a registry")
	gpEq(g.gpGetNode("N1").gpTag, "P-7777", "and stored")


# ---- 2. name / 名称（按语种） ----

func gpTestSetNameIsPerLocale() -> void:
	var f: Array = _mkSvc()
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	gpCheck(svc.gpSetName("N1", "zh_CN", "给料泵"), "the Chinese name is set")
	gpCheck(svc.gpSetName("N1", "en_US", "Feed Pump"), "the English name is set")
	gpEq(str(g.gpGetNode("N1").gpNames["zh_CN"]), "给料泵", "both locales coexist")
	gpEq(str(g.gpGetNode("N1").gpNames["en_US"]), "Feed Pump", "both locales coexist")


# Undo must ERASE a key the instance never had, so "never named" and "named then cleared"
# do not collapse into the same state.
# 撤销必须**删除**实例从未有过的键，使「从未命名」与「命名后又清空」不塌缩为同一状态。
func gpTestSetNameUndoErasesWhenNeverNamed() -> void:
	var f: Array = _mkSvc()
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	svc.gpSetName("N1", "zh_CN", "给料泵")
	svc.gpUndo()
	gpEq(g.gpGetNode("N1").gpNames.has("zh_CN"), false, "undo removes the key entirely")
	svc.gpRedo()
	gpEq(str(g.gpGetNode("N1").gpNames["zh_CN"]), "给料泵", "redo puts it back")


# ---- 3. property / 属性 ----

func gpTestSetPropertyRoundTrips() -> void:
	var f: Array = _mkSvc()
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	gpCheck(svc.gpSetProperty("N1", "rated_flow", 80.0), "the property is set")
	gpEq(float(g.gpGetNode("N1").gpProps["rated_flow"]), 80.0, "and stored")
	svc.gpUndo()
	gpEq(g.gpGetNode("N1").gpProps.has("rated_flow"), false, "undo removes the override")
	svc.gpRedo()
	gpEq(float(g.gpGetNode("N1").gpProps["rated_flow"]), 80.0, "redo restores it")


# Clearing a field means "follow the library default again" — modelled by removing the key,
# never by storing an empty string.
# 清空字段 = 「重新跟随库默认值」—— 以移除该键表达，绝不是存一个空字符串。
func gpTestClearingAPropertyRestoresTheDefault() -> void:
	var f: Array = _mkSvc()
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	svc.gpSetProperty("N1", "rated_flow", 80.0)
	gpCheck(svc.gpSetProperty("N1", "rated_flow", ""), "clearing is accepted")
	gpEq(g.gpGetNode("N1").gpProps.has("rated_flow"), false,
		"the key is gone, so GPPropertyResolver falls back to the library default")


func gpTestSetPropertyNoChangeIsNotAnUndoStep() -> void:
	var f: Array = _mkSvc()
	var svc: GPEditService = f[1]
	svc.gpSetProperty("N1", "rated_flow", 80.0)
	gpEq(svc.gpSetProperty("N1", "rated_flow", 80.0), false, "writing the same value changes nothing")


# ---- 4. label anchor / 标签锚点 ----

func gpTestSetLabelAnchorRoundTrips() -> void:
	var f: Array = _mkSvc()
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	gpCheck(svc.gpSetLabelAnchor("N1", GPLabelAnchor.GPAnchor.GP_ABOVE), "the anchor is set")
	gpEq(g.gpGetNode("N1").gpLabelAnchor, GPLabelAnchor.GPAnchor.GP_ABOVE, "and stored")
	svc.gpUndo()
	gpEq(g.gpGetNode("N1").gpLabelAnchor, GPPropertyResolver.GP_ANCHOR_UNSET,
		"undo returns to 'follow the library'")


func gpTestSetLabelAnchorAcceptsUnset() -> void:
	var f: Array = _mkSvc()
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	svc.gpSetLabelAnchor("N1", GPLabelAnchor.GPAnchor.GP_INSIDE)
	gpCheck(svc.gpSetLabelAnchor("N1", GPPropertyResolver.GP_ANCHOR_UNSET), "resetting is accepted")
	gpEq(g.gpGetNode("N1").gpLabelAnchor, GPPropertyResolver.GP_ANCHOR_UNSET, "and stored as unset")


# ---- 5. batch / 批量 ----

# The whole point of a batch command: ONE Ctrl+Z reverses the whole selection.
# 批量命令的全部意义：按**一次** Ctrl+Z 就整体撤销。
func gpTestBatchIsASingleUndoStep() -> void:
	var f: Array = _mkSvc()
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	var gpIds: Array[String] = ["N1", "N2"]
	gpCheck(svc.gpBatchSetProperty(gpIds, "material", "SS316L"), "the batch is applied")
	gpEq(str(g.gpGetNode("N1").gpProps["material"]), "SS316L", "N1 got it")
	gpEq(str(g.gpGetNode("N2").gpProps["material"]), "SS316L", "N2 got it")
	svc.gpUndo()
	gpEq(g.gpGetNode("N1").gpProps.has("material"), false, "one undo clears N1")
	gpEq(g.gpGetNode("N2").gpProps.has("material"), false, "and the same undo clears N2")


func gpTestBatchRefusesTagBecauseTagsAreUnique() -> void:
	var f: Array = _mkSvc()
	var svc: GPEditService = f[1]
	var gpIds: Array[String] = ["N1", "N2"]
	gpEq(svc.gpBatchSetProperty(gpIds, "tag", "P-5000"), false,
		"one tag cannot be written onto two instances")


func gpTestBatchAppliesNamesToAll() -> void:
	var f: Array = _mkSvc()
	var g: GPPIDGraph = f[0]
	var svc: GPEditService = f[1]
	var gpIds: Array[String] = ["N1", "N2"]
	gpCheck(svc.gpBatchSetProperty(gpIds, "name:zh_CN", "给料泵"), "the batch name is applied")
	gpEq(str(g.gpGetNode("N1").gpNames["zh_CN"]), "给料泵", "N1 got it")
	gpEq(str(g.gpGetNode("N2").gpNames["zh_CN"]), "给料泵", "N2 got it — names may repeat")


func gpTestBatchNoChangeIsNotAnUndoStep() -> void:
	var f: Array = _mkSvc()
	var svc: GPEditService = f[1]
	var gpIds: Array[String] = ["N1", "N2"]
	gpEq(svc.gpBatchSetProperty(gpIds, "rated_flow", ""), false,
		"clearing a field nobody has changes nothing")
