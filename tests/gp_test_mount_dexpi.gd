extends "res://tests/gp_test.gd"
# P4 acceptance: mount relations, and the hierarchical DEXPI export they drive.
# P4 验收：挂载关系，以及由它驱动的层级化 DEXPI 导出。
#
# WHY THESE ASSERTIONS / 为何是这些断言：
# the deliverable is not the printed XML — it is a receiver that sees a nozzle as a PART of its
# vessel. So the tests check that (1) the relation table CANNOT invent a URI, (2) a mounted child
# lands INSIDE its host's element and nowhere else, (3) the child's position is DERIVED rather
# than the stored local value, and (4) nothing is dropped when the hierarchy is broken.
# 交付物不是打印出来的 XML —— 而是「接收方看到管口是其容器的**部件**」。
# 故测试检查：① 关系表**无法**臆造 URI；② 被挂载子件落在宿主元素**内部**且**仅此一处**；
# ③ 子件位置是**推导**的而非存储的局部值；④ 层级断裂时**什么都不丢**。

const GP_SHEET_W: float = 420.0
const GP_SHEET_H: float = 297.0

const GP_EQUIP_OPEN: String = "<Equipment "
const GP_EQUIP_CLOSE: String = "</Equipment>"
const GP_NOZZLE_OPEN: String = "<Nozzle "


# ---- fixtures -----------------------------------------------------------

static func _gpSheet() -> GPSheet:
	var gpS: GPSheet = GPSheet.new()
	gpS.gpName = "Mount Test"
	gpS.gpWidthMM = GP_SHEET_W
	gpS.gpHeightMM = GP_SHEET_H
	return gpS


# A vessel with ONE nozzle fitted in its bottom socket.
# 一台容器，底部插座上装着**一个**管口。
# ★ THE NOZZLE'S STORED POSITION IS (0,0) ON PURPOSE / ★ 管口存储位置**故意**为 (0,0)：
# a mounted node keeps a LOCAL position, so a correct export must DERIVE the world origin. With
# (0,0) the wrong implementation writes the sheet origin, which the assertions below cannot miss.
# 被挂载节点保存的是**局部**位置，故正确的导出必须**推导**世界原点。设成 (0,0) 后，
# 错误实现会写出图纸原点 —— 下面的断言绝无可能漏掉。
static func _gpVesselWithNozzle() -> GPPIDGraph:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpVessel: GPPIDNode = gpG.gpNewNode("n1", "DTANK001", "V-1001", Vector2(200.0, 150.0))
	gpVessel.gpUid = "uid-vessel"
	gpVessel.gpProps = {"design_pressure": 1.6}
	gpG.gpAddNode(gpVessel)
	var gpNozzle: GPPIDNode = gpG.gpNewNode("n2", "DGENERAL008", "", Vector2.ZERO)
	gpNozzle.gpUid = "uid-nozzle"
	# ★ The host is named by its INSTANCE id ("n1"), because that is what the live graph and every
	# mount command actually write into gpParentUid. The export must then TRANSLATE it to the
	# stable uid — which is exactly what this fixture makes observable.
	# ★ 宿主以其 **instance id**（"n1"）指认 —— 活图与每一条挂载命令写入 gpParentUid 的就是它。
	# 导出时再翻译为稳定 uid —— 这正是本夹具让「翻译」变得可观测的地方。
	gpNozzle.gpParentUid = "n1"
	gpNozzle.gpMountAnchor = "ves_bottom_nozzle"
	gpNozzle.gpProps = {"nozzle_id": "N1", "nominal_size": 100.0}
	gpG.gpAddNode(gpNozzle)
	return gpG


# A ball valve with one actuator on its top socket. Its relation is "reference", NOT "child",
# so it must NOT be nested — and the reason must be reported.
# 一只球阀，顶部插座上装一个执行机构。其关系是 "reference" 而非 "child"，
# 故**不得**嵌套 —— 且必须报告原因。
static func _gpValveWithActuator() -> GPPIDGraph:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpValve: GPPIDNode = gpG.gpNewNode("n1", "DVALVE002", "HV-1001", Vector2(80.0, 80.0))
	gpValve.gpUid = "uid-valve"
	gpG.gpAddNode(gpValve)
	var gpAct: GPPIDNode = gpG.gpNewNode("n2", "DGENERAL004", "", Vector2.ZERO)
	gpAct.gpUid = "uid-actuator"
	gpAct.gpParentUid = "n1"
	gpAct.gpMountAnchor = "top_actuator"
	gpG.gpAddNode(gpAct)
	return gpG


# A vessel carrying an insulation part the user has given a thickness (D3). Its relation is
# "attribute": DEXPI models the thickness as the HOST's own attribute, so the part must
# contribute to the vessel and must NOT become an element of its own.
# 一台容器，带一个用户已填厚度的保温件（D3）。其关系是 "attribute"：
# DEXPI 把厚度建模为**宿主自己**的属性，故该件必须贡献给容器，且**不得**成为自己的元素。
# ★ THE HOST IS SET DIRECTLY / ★ 宿主直接设置：
# this suite pins the SERIALISATION contract, not which anchor accepts insulation — writing
# gpParentUid here keeps the export path exercised on its own.
# 本套件钉的是**序列化**契约，而非「哪个锚点接受保温」—— 此处直接写 gpParentUid，
# 使导出路径可以独立地被跑到。
static func _gpVesselWithInsulation() -> GPPIDGraph:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpVessel: GPPIDNode = gpG.gpNewNode("n1", "DTANK001", "V-1002", Vector2(200.0, 150.0))
	gpVessel.gpUid = "uid-vessel"
	gpVessel.gpProps = {"design_pressure": 1.6}
	gpG.gpAddNode(gpVessel)
	var gpIns: GPPIDNode = gpG.gpNewNode("n2", "DGENERAL009", "", Vector2(180.0, 150.0))
	gpIns.gpUid = "uid-insulation"
	gpIns.gpParentUid = "n1"
	gpIns.gpProps = {"insulation": 80.0}
	gpG.gpAddNode(gpIns)
	return gpG


# Every mount kind the shipped DEXPI pack actually declares.
# 已发布 DEXPI 包**实际**声明的全部挂载类别。
# Read from the pack rather than listed here: a literal list would keep passing after a new
# mountable symbol was added, which is exactly the drift this test exists to catch.
# 取自**包**而非在此罗列：字面量列表在新增可挂载图元后仍会通过，
# 而那正是本测试存在的意义 —— 抓漂移。
static func _gpPackMountKinds() -> Array[String]:
	var gpOut: Array[String] = []
	for gpDef in GPSymbolPackDexpi.gpDefs():
		var gpD: GPSymbolDef = gpDef as GPSymbolDef
		if gpD == null or gpD.gpMountKind.is_empty():
			continue
		if not gpOut.has(gpD.gpMountKind):
			gpOut.append(gpD.gpMountKind)
	gpOut.sort()
	return gpOut


static func _gpEntryOf(gpMid: Dictionary, gpUid: String) -> Dictionary:
	for gpE in (gpMid.get(GPDexpiExporter.GP_KEY_EQUIPMENT, []) as Array):
		var gpD: Dictionary = gpE as Dictionary
		if str(gpD.get("id", "")) == gpUid:
			return gpD
	return {}


static func _gpUsageOf(gpMid: Dictionary, gpInstanceId: String) -> Dictionary:
	for gpU in (gpMid.get(GPDexpiExporter.GP_KEY_USAGES, []) as Array):
		var gpD: Dictionary = gpU as Dictionary
		if str(gpD.get("instance_id", "")) == gpInstanceId:
			return gpD
	return {}


static func _gpCodesOf(gpReport: GPImportReport) -> Array[String]:
	var gpOut: Array[String] = []
	for gpE in gpReport.gpEntries:
		gpOut.append(str((gpE as Dictionary).get("code", "")))
	return gpOut


static func _gpPropsOf(gpMid: Dictionary, gpUid: String) -> Dictionary:
	return _gpEntryOf(gpMid, gpUid).get("props", {}) as Dictionary


# ---- the relation table -------------------------------------------------

# ★ The table must cover every kind the pack ships. An unlisted kind would ship as a silent
# top-level object — the nozzle would still be in the file, but no longer a PART of anything.
# ★ 表必须覆盖包内发布的每一个类别。未列出的类别会**静默**变成顶层对象 ——
# 管口仍在文件里，但不再是任何东西的**部件**。
func gpTestRelationTableCoversEveryPackMountKind() -> void:
	var gpKinds: Array[String] = _gpPackMountKinds()
	gpCheck(gpKinds.size() >= 5,
		"the pack declares mount kinds to cover (guard: got " + str(gpKinds.size()) + ")")
	for gpKind in gpKinds:
		var gpRel: Dictionary = GPDexpiMapping.gpMountRelationFor(gpKind)
		gpCheck(str(gpRel.get("containment", "")) != GPDexpiMapping.GP_MOUNT_UNKNOWN,
			"mount kind '" + gpKind + "' from the pack has a relation row")


# ★ STRUCTURAL GUARANTEE: the table has no URI (and no class) column, so there is nothing in it
# that COULD be fabricated. This assertion is what keeps that guarantee structural — adding one
# row with a "uri" key would quietly re-open the risk §7.5 forbids.
# ★ **结构性**保证：该表没有 URI（也没有 class）列，故其中**不可能**有可臆造之物。
# 本断言正是让该保证保持结构性的东西 —— 加一行带 "uri" 键的行，
# 就会悄悄重开 §7.5 所禁止的风险。
func gpTestRelationTableCannotFabricateAUri() -> void:
	var gpKinds: Array[String] = GPDexpiMapping.gpAllMountKinds()
	gpCheck(gpKinds.size() >= 5, "the table has rows to check (guard)")
	for gpKind in gpKinds:
		var gpRel: Dictionary = GPDexpiMapping.gpMountRelationFor(gpKind)
		gpCheck(not gpRel.has("uri"), "relation '" + gpKind + "' carries no URI field")
		gpCheck(not gpRel.has("class"),
			"relation '" + gpKind + "' names no class — GP_SYMBOLS owns the class names")
		gpEq(bool(gpRel.get("verified", true)), false,
			"relation '" + gpKind + "' is unverified, so it must not pretend otherwise")


# Only "child" nests. The other containments keep the object top-level, which is the VISIBLE
# choice to make when the relation is not certain.
# 只有 "child" 会嵌套。其余 containment 保持对象在顶层 —— 在关系不确定时，那是**可见**的选择。
func gpTestOnlyChildContainmentNests() -> void:
	var gpNest: Array[String] = []
	for gpKind in GPDexpiMapping.gpAllMountKinds():
		var gpRel: Dictionary = GPDexpiMapping.gpMountRelationFor(gpKind)
		var gpIsChild: bool = str(gpRel.get("containment", "")) == GPDexpiMapping.GP_MOUNT_CHILD
		gpEq(GPDexpiMapping.gpIsNestable(gpKind), gpIsChild,
			"gpIsNestable agrees with the table for '" + gpKind + "'")
		if gpIsChild:
			gpNest.append(gpKind)
	gpEq(gpNest.size(), 2, "exactly two kinds nest")
	gpCheck(gpNest.has("NOZZLE") and gpNest.has("MANHOLE"),
		"and they are the equipment-wall parts (nozzle / manhole)")


# An unknown kind is REPORTED, never guessed into a containment.
# 未知类别被**报告**，绝不猜一个 containment。
func gpTestUnknownMountKindIsNotGuessed() -> void:
	var gpRel: Dictionary = GPDexpiMapping.gpMountRelationFor("FLUX_CAPACITOR")
	gpEq(str(gpRel.get("containment", "")), GPDexpiMapping.GP_MOUNT_UNKNOWN,
		"an unmapped kind is unknown, not silently treated as a child")
	gpEq(GPDexpiMapping.gpIsNestable("FLUX_CAPACITOR"), false,
		"and it therefore does not nest")
	gpCheck(str(gpRel.get("note", "")).contains("FLUX_CAPACITOR"),
		"the reason names the offending kind, so the report is actionable")


# ---- projection ---------------------------------------------------------

# The list stays FLAT and each entry carries its own mount fields. Folding children away HERE
# would make the validator, the importer and the summary lose the nozzle without a word.
# 列表保持**扁平**，每条自带挂载字段。在此折走子件会让校验器、导入器与统计
# 一声不吭地丢掉管口。
func gpTestProjectionStaysFlatAndRecordsTheMount() -> void:
	var gpMid: Dictionary = GPDexpiExporter.gpFromGraph(_gpVesselWithNozzle(), _gpSheet())
	gpEq((gpMid.get(GPDexpiExporter.GP_KEY_EQUIPMENT, []) as Array).size(), 2,
		"host AND child are both present in the flat list")
	var gpNozzle: Dictionary = _gpEntryOf(gpMid, "uid-nozzle")
	gpCheck(not gpNozzle.is_empty(), "the nozzle entry exists")
	gpEq(str(gpNozzle.get("parent_uid", "")), "uid-vessel", "its host is recorded")
	gpCheck(str(gpNozzle.get("parent_uid", "")) != "n1",
		"and by STABLE uid — never by the instance id (§7.4)")
	gpEq(str(gpNozzle.get("mount_kind", "")), "NOZZLE",
		"its mount kind is read from the DEFINITION, not from the node")
	gpEq(str(gpNozzle.get("mount_anchor", "")), "ves_bottom_nozzle", "its anchor is recorded")
	var gpVessel: Dictionary = _gpEntryOf(gpMid, "uid-vessel")
	gpEq(str(gpVessel.get("parent_uid", "")), "", "the host itself is top-level")
	gpEq(str(gpVessel.get("mount_kind", "")), "", "and carries no mount kind")


# ★ ONE NAME, ONE MEANING. "position" names the WORLD-space placement, and that lives in the
# ShapeUsage. The flat equipment entry must therefore carry NO pose at all: a second "position"
# there could only ever hold the STORED (host-local) value — the same key meaning two different
# things inside one structure. That is a trap, not a redundancy.
# ★ **一名一义**。"position" 指**世界**坐标放置，它在 ShapeUsage 里。
# 故扁平的 equipment 条目**完全不该**带位姿：那里若再有第二个 "position"，
# 只可能装**存储**的（宿主局部）值 —— 同一个键在同一结构里表示两种含义：是陷阱而非冗余。
# The key was also DEAD (the validator, the importer and gpWriteXml all take the pose from the
# usage) and LOSSY: the reader rebuilt it as ZERO, so it drifted on every export -> import cycle.
# 该键同时也是**死键**（校验器、导入器、gpWriteXml 都从 usage 取位姿），且**有损**：
# 读取器把它重建为 ZERO，故每次导出 -> 导入都漂移。
func gpTestEquipmentEntryCarriesNoPose() -> void:
	var gpMid: Dictionary = GPDexpiExporter.gpFromGraph(_gpVesselWithNozzle(), _gpSheet())
	var gpEqs: Array = gpMid.get(GPDexpiExporter.GP_KEY_EQUIPMENT, []) as Array
	gpEq(gpEqs.size(), 2, "both objects are in the flat list (guard)")
	for gpE in gpEqs:
		var gpD: Dictionary = gpE as Dictionary
		gpCheck(not gpD.has("position"),
			"equipment '" + str(gpD.get("id", "")) + "' carries no pose of its own")
	gpCheck((_gpUsageOf(gpMid, "n2") as Dictionary).has("position"),
		"while the SAME node's pose does live in its ShapeUsage — placement is not lost")
	# And the omission survives the trip: the reader must not reintroduce the twin key.
	# 且该省略要经得起往返：读取器不得把这对孪生键再加回来。
	var gpBack: Dictionary = GPDexpiReader.gpReadXml(
		GPDexpiExporter.gpWriteXml(gpMid)).gpPayload as Dictionary
	var gpBackEqs: Array = gpBack.get(GPDexpiExporter.GP_KEY_EQUIPMENT, []) as Array
	gpEq(gpBackEqs.size(), 2, "both objects came back (guard)")
	for gpE in gpBackEqs:
		gpCheck(not (gpE as Dictionary).has("position"),
			"the reader does not reintroduce a pose on a concept object")


# ★ The stored LOCAL position must not leak into the graphics layer.
# ★ 存储的**局部**位置绝不可泄漏到图形层。
func gpTestMountedChildExportsItsDerivedWorldPosition() -> void:
	var gpG: GPPIDGraph = _gpVesselWithNozzle()
	var gpMid: Dictionary = GPDexpiExporter.gpFromGraph(gpG, _gpSheet())
	var gpUsage: Dictionary = _gpUsageOf(gpMid, "n2")
	gpCheck(not gpUsage.is_empty(), "the nozzle has a shape usage")
	var gpPos: Vector2 = gpUsage.get("position", Vector2.ZERO) as Vector2
	gpCheck(gpPos != Vector2.ZERO, "the sheet origin was NOT exported (the stored value is (0,0))")
	var gpWant: Vector2 = GPMountResolver.gpWorldTransform(gpG, GPSymbolLibrary.gpFindById,
		gpG.gpGetNode("n2")).get("origin", Vector2.ZERO) as Vector2
	gpApprox(gpPos.x, gpWant.x, 1e-4, "usage X is the DERIVED world origin")
	gpApprox(gpPos.y, gpWant.y, 1e-4, "usage Y is the DERIVED world origin")
	gpCheck(gpPos.y >= 150.0, "a bottom nozzle is at or below its vessel's origin")
	gpCheck(gpPos != Vector2(200.0, 150.0), "and it is not simply the host's own origin")


# ---- serialisation ------------------------------------------------------

# ★ The nozzle appears ONCE in the whole document, and INSIDE the vessel.
# ★ 管口在全文档中**只出现一次**，且位于容器**内部**。
func gpTestXmlNestsTheNozzleInsideItsHost() -> void:
	var gpXml: String = GPDexpiExporter.gpWriteXml(
		GPDexpiExporter.gpFromGraph(_gpVesselWithNozzle(), _gpSheet()))
	gpEq(gpXml.count(GP_NOZZLE_OPEN), 1, "the nozzle element appears exactly once")
	var gpHostAt: int = gpXml.find(GP_EQUIP_OPEN)
	var gpNozzleAt: int = gpXml.find(GP_NOZZLE_OPEN)
	var gpCloseAt: int = gpXml.find(GP_EQUIP_CLOSE)
	gpCheck(gpHostAt != -1 and gpNozzleAt != -1 and gpCloseAt != -1,
		"all three landmark tags are present")
	gpCheck(gpHostAt < gpNozzleAt, "the nozzle comes after its host opens")
	gpCheck(gpNozzleAt < gpCloseAt, "the nozzle comes before its host closes")
	gpEq(gpXml.count(GP_EQUIP_OPEN), 1,
		"only the vessel is an <Equipment> — the nozzle is not ALSO a sibling")


# A relation that is not "child" keeps its object top-level AND says why.
# 非 "child" 的关系让对象留在顶层**并说明原因**。
func gpTestNonChildRelationStaysTopLevelWithAReason() -> void:
	var gpG: GPPIDGraph = _gpValveWithActuator()
	var gpCodes: Array[String] = _gpCodesOf(GPDexpiExporter.gpPreflight(gpG, _gpSheet()))
	gpCheck(gpCodes.has(GPDexpiExporter.GP_CODE_MOUNT_NOT_NESTED),
		"the non-nested mount is reported, not silently flattened")
	gpCheck(not gpCodes.has(GPDexpiExporter.GP_CODE_MOUNT_UNMAPPED),
		"ACTUATOR has a row, so it is not reported as unmapped")
	var gpXml: String = GPDexpiExporter.gpWriteXml(GPDexpiExporter.gpFromGraph(gpG, _gpSheet()))
	gpEq(gpXml.count(GP_EQUIP_OPEN), 1, "only the valve is an <Equipment>")
	gpEq(gpXml.count("<ActuatingSystem"), 1,
		"the actuator keeps its own element name — a loose part must stay identifiable")
	gpEq(gpXml.count("<ActuatingSystem") , gpXml.count("</ActuatingSystem>"),
		"and that element is closed")


# A mount whose host is gone must still be exported — visibly, at the top level.
# 宿主已消失的挂载仍必须导出 —— 且**可见地**留在顶层。
func gpTestOrphanMountIsReportedAndStillExported() -> void:
	var gpG: GPPIDGraph = _gpVesselWithNozzle()
	gpG.gpGetNode("n2").gpParentUid = "uid-vanished"
	var gpPre: GPImportReport = GPDexpiExporter.gpPreflight(gpG, _gpSheet())
	gpCheck(_gpCodesOf(gpPre).has(GPDexpiExporter.GP_CODE_ORPHAN_MOUNT), "the orphan is reported")
	gpCheck(not gpPre.gpHasErrors(), "an orphan is a warning, not a fatal finding")
	var gpXml: String = GPDexpiExporter.gpWriteXml(GPDexpiExporter.gpFromGraph(gpG, _gpSheet()))
	gpEq(gpXml.count(GP_NOZZLE_OPEN), 1, "the orphan nozzle is still exported")
	gpEq(gpXml.count("</Nozzle>"), 1, "and as its own top-level <Nozzle>")
	gpEq(gpXml.count(GP_EQUIP_CLOSE), 1, "which no longer hides inside the vessel")


# A hand-edited parent loop must not make BOTH objects vanish (nor spin forever).
# 手改出来的父链环绝不可让两个对象**双双**消失（也不可空转）。
func gpTestParentLoopIsBrokenNotFatal() -> void:
	var gpG: GPPIDGraph = _gpVesselWithNozzle()
	var gpVessel: GPPIDNode = gpG.gpGetNode("n1")
	gpVessel.gpParentUid = "n2"                   # n1 <-> n2: a loop
	gpVessel.gpMountAnchor = "ves_bottom_nozzle"
	var gpPre: GPImportReport = GPDexpiExporter.gpPreflight(gpG, _gpSheet())
	gpCheck(_gpCodesOf(gpPre).has(GPDexpiExporter.GP_CODE_MOUNT_CYCLE), "the loop is reported")
	gpCheck(not gpPre.gpHasErrors(), "a loop is a warning, not a fatal finding")
	var gpXml: String = GPDexpiExporter.gpWriteXml(GPDexpiExporter.gpFromGraph(gpG, _gpSheet()))
	gpEq(gpXml.count(GP_NOZZLE_OPEN), 1, "the nozzle did not disappear into the fold")
	gpEq(gpXml.count(GP_EQUIP_OPEN), 1, "the vessel did not either")
	gpEq(gpXml.count("</Nozzle>"), 1, "and the document is still well formed")


# ★ The backward-compat anchor: content with no mounts is untouched.
# ★ 向后兼容锚点：无挂载的内容逐字节不变。
func gpTestUnmountedContentIsUnaffected() -> void:
	var gpG: GPPIDGraph = GPPIDGraph.new()
	var gpPump: GPPIDNode = gpG.gpNewNode("n1", "DPUMP001", "P-1001", Vector2(100.0, 90.0))
	gpPump.gpUid = "uid-pump"
	gpPump.gpRotationDeg = 30.0
	gpG.gpAddNode(gpPump)
	var gpMid: Dictionary = GPDexpiExporter.gpFromGraph(gpG, _gpSheet())
	var gpUsage: Dictionary = _gpUsageOf(gpMid, "n1")
	gpApprox((gpUsage.get("position", Vector2.ZERO) as Vector2).x, 100.0, 1e-4,
		"an unmounted node still exports its own frame")
	gpApprox(float(gpUsage.get("rotation_deg", 0.0)), 30.0, 1e-4, "and its own rotation")
	var gpXml: String = GPDexpiExporter.gpWriteXml(gpMid)
	gpEq(gpXml.count(GP_EQUIP_OPEN), 1, "no element was nested")
	gpEq(gpXml.count("<Nozzle"), 0, "and no nozzle element appeared out of nowhere")


# ---- round trip ---------------------------------------------------------

# Export -> read must bring the hierarchy back.
# 导出 -> 读取必须把层级带回来。
func gpTestRoundTripRestoresTheMount() -> void:
	var gpG: GPPIDGraph = _gpVesselWithNozzle()
	var gpXml: String = GPDexpiExporter.gpWriteXml(GPDexpiExporter.gpFromGraph(gpG, _gpSheet()))
	var gpRes: GPIOResult = GPDexpiReader.gpReadXml(gpXml)
	gpCheck(gpRes.gpIsOk(), "our own export is readable: " + gpRes.gpToString())
	var gpMid: Dictionary = gpRes.gpPayload as Dictionary
	gpEq((gpMid.get(GPDexpiExporter.GP_KEY_EQUIPMENT, []) as Array).size(), 2,
		"the nested nozzle came back as an OBJECT, not as a lost element")
	var gpBackNozzle: Dictionary = _gpEntryOf(gpMid, "uid-nozzle")
	gpEq(str(gpBackNozzle.get("parent_uid", "")), "uid-vessel", "the mount survived the trip")
	gpEq(str(gpBackNozzle.get("mount_kind", "")), "NOZZLE", "so did the mount kind")
	gpEq(str(_gpEntryOf(gpMid, "uid-vessel").get("parent_uid", "")), "",
		"the host is still top-level")
	# A nested <GenericAttributes> block belongs to the element that CONTAINS it: the nozzle's
	# properties must land on the nozzle, not leak up into the vessel.
	# 嵌套的 <GenericAttributes> 块属于**包含**它的元素：管口的属性必须落在管口上，
	# 而不可上溢到容器。
	gpCheck(not _gpPropsOf(gpMid, "uid-nozzle").is_empty(),
		"the nozzle kept its own properties")
	gpCheck(not _gpPropsOf(gpMid, "uid-vessel").has("nozzle_id"),
		"and the vessel did NOT inherit them")


# DEXPI carries no anchor NAME, so the importer recovers the anchor IDENTITY by position:
# a mounted child sits ON one of its host's anchors, and the nearest anchor's world position
# identifies it. The rotation the anchor direction explains is consumed exactly; only a genuine
# residual (a user drag / lateral angle) survives as mount_offset / mount_angle_deg.
# DEXPI 不携带锚点**名**，故导入器按**位置**找回锚点的**身份**：
# 被挂载子件必然坐在宿主某个锚点上，「世界位置最近的锚点」即其锚点。
# 锚点方向能解释的旋转被精确吸收；只有真正的剩余量（用户拖拽/侧向角）
# 才以 mount_offset / mount_angle_deg 存活。
func gpTestImportedChildRecoversItsAnchorIdentity() -> void:
	var gpG: GPPIDGraph = _gpVesselWithNozzle()
	var gpXml: String = GPDexpiExporter.gpWriteXml(GPDexpiExporter.gpFromGraph(gpG, _gpSheet()))
	var gpMid: Dictionary = GPDexpiReader.gpReadXml(gpXml).gpPayload as Dictionary
	var gpV3: Dictionary = GPDexpiImporter.gpToV3(gpMid, GPSymbolLibrary.gpFindById)
	gpEq((gpV3.get("sheets", []) as Array).size(), 1, "one sheet came back")
	var gpNodes: Array = ((gpV3.get("sheets", []) as Array)[0] as Dictionary).get("nodes", []) as Array
	gpEq(gpNodes.size(), 2, "two nodes were rebuilt")
	var gpNozzleN: Dictionary = {}
	for gpN in gpNodes:
		var gpND: Dictionary = gpN as Dictionary
		if str(gpND.get("uid", "")) == "uid-nozzle":
			gpNozzleN = gpND
	gpCheck(not gpNozzleN.is_empty(), "the nozzle node exists")
	gpEq(str(gpNozzleN.get("parent_uid", "")), "uid-vessel", "the node is mounted")
	gpEq(str(gpNozzleN.get("mount_anchor", "")), "ves_bottom_nozzle",
		"the anchor IDENTITY was recovered from the child's world placement")
	var gpOff: Array = gpNozzleN.get("mount_offset", []) as Array
	gpEq(gpOff.size(), 2, "and a local offset was reconstructed")
	gpCheck(Vector2(float(gpOff[0]), float(gpOff[1])).length() < 1e-3,
		"the offset is ~ZERO — the child sat exactly on its anchor")


# ★ THE ROUND TRIP IS RIGID: the imported child's WORLD transform — position AND rotation —
# equals the original's. Regression nail for the 2026-10-04 bug where the import restored
# every position but dropped every anchor rotation: nozzles rendered upright regardless of
# their socket, and pipes latched onto the displaced port points.
# ★ **往返是刚性的**：导入子件的**世界**变换 —— 位置**与**旋转 —— 与原件相等。
# 这是 2026-10-04 缺陷的回归钉：当时的导入还原了全部位置却丢掉全部锚点旋转 ——
# 管口无视插座朝向一律立正，管线吸附到错位的端口点上。
func gpTestRoundTripIsRigidForMountedChildren() -> void:
	var gpG: GPPIDGraph = _gpVesselWithNozzle()
	var gpXml: String = GPDexpiExporter.gpWriteXml(GPDexpiExporter.gpFromGraph(gpG, _gpSheet()))
	var gpMid: Dictionary = GPDexpiReader.gpReadXml(gpXml).gpPayload as Dictionary
	var gpV3: Dictionary = GPDexpiImporter.gpToV3(gpMid, GPSymbolLibrary.gpFindById)
	var gpGraphB: GPPIDGraph = GPPIDGraph.gpFromDict(GPSchemaMigrate.gpToGraphDict(gpV3, 0))
	var gpNozA: GPPIDNode = gpG.gpGetNode("n2")
	var gpNozB: GPPIDNode = null
	for gpN in gpGraphB.gpNodes:
		var gpNB: GPPIDNode = gpN as GPPIDNode
		if gpNB.gpUid == "uid-nozzle":
			gpNozB = gpNB
	gpCheck(gpNozB != null, "the imported nozzle exists (guard)")
	if gpNozB == null:
		return
	var gpWTA: Dictionary = GPMountResolver.gpWorldTransform(gpG, GPSymbolLibrary.gpFindById,
		gpNozA)
	var gpWTB: Dictionary = GPMountResolver.gpWorldTransform(gpGraphB, GPSymbolLibrary.gpFindById,
		gpNozB)
	var gpPA: Vector2 = gpWTA.get("origin", Vector2.ZERO) as Vector2
	var gpPB: Vector2 = gpWTB.get("origin", Vector2.ZERO) as Vector2
	gpCheck(gpPA.distance_to(gpPB) < 1e-3,
		"world position is preserved exactly (%s vs %s)" % [gpPA, gpPB])
	gpApprox(float(gpWTB.get("rot_deg", 0.0)), float(gpWTA.get("rot_deg", 0.0)), 1e-3,
		"world ROTATION is preserved too — the anchor direction was recovered, not dropped")


# ---- D3: a part that IS an attribute of its host -------------------------

# Only an "attribute" relation may pour values into its host, and every key it names must have a
# REAL row in the attribute table — a guessed "Custom…AssignmentClass" name would still export,
# which is precisely why it has to be refused here rather than noticed in the field.
# 只有 "attribute" 关系可以把值倒进宿主，且它命名的每个键都必须在属性表里有**真实**的一行 ——
# 猜出来的 "Custom…AssignmentClass" 名照样能导出，这正是必须在此拒绝、
# 而不能等到现场才发现的原因。
func gpTestOnlyAttributeRelationsDeclareHostAttributes() -> void:
	var gpChecked: int = 0
	for gpKind in GPDexpiMapping.gpAllMountKinds():
		var gpKeys: Array[String] = GPDexpiMapping.gpHostAttrKeys(gpKind)
		if gpKeys.is_empty():
			continue
		gpChecked += 1
		gpEq(str(GPDexpiMapping.gpMountRelationFor(gpKind).get("containment", "")),
			GPDexpiMapping.GP_MOUNT_ATTRIBUTE,
			"only an 'attribute' relation may pour values into its host: " + gpKind)
		for gpKey in gpKeys:
			gpCheck(not bool(GPDexpiMapping.gpAttributeFor(gpKey).get("custom", false)),
				"'" + gpKey + "' has a real row in the attribute table, not a guessed name")
	gpCheck(gpChecked >= 1,
		"some kind declares host attributes (guard against a vacuous loop: got %d)" % gpChecked)


# ★ A host-attribute key the part does not DECLARE is untypeable: the user has no field for it,
# so the annotation would be permanently empty while every test still passed.
# ★ 部件**没有声明**的宿主属性键是填不进去的：用户没有那个输入框，
# 于是这个注解永远是空的 —— 而所有测试却照样通过。
func gpTestHostAttributeKeysAreRealPropertiesOfThePart() -> void:
	var gpChecked: int = 0
	for gpDef in GPSymbolPackDexpi.gpDefs():
		var gpD: GPSymbolDef = gpDef as GPSymbolDef
		if gpD == null:
			continue
		var gpKeys: Array[String] = GPDexpiMapping.gpHostAttrKeys(gpD.gpMountKind)
		if gpKeys.is_empty():
			continue
		gpChecked += 1
		var gpDeclared: Array[String] = []
		if gpD.gpSchema != null:
			for gpF in gpD.gpSchema.gpFields:
				gpDeclared.append(gpF.gpKey)
		for gpKey in gpKeys:
			gpCheck(gpDeclared.has(gpKey),
				"%s declares host-attribute key '%s' as a real property" % [gpD.gpId, gpKey])
	gpCheck(gpChecked >= 1,
		"the pack still ships at least one host-annotating part (guard: got %d)" % gpChecked)


# D3: the thickness reaches the file as the HOST's own attribute, and the part never becomes an
# element. Position is what makes it an annotation: it must sit INSIDE the vessel's element.
# D3：厚度以**宿主自己**的属性进入文件，且该件永不成为元素。
# 位置才是「注解」的实质：它必须落在容器元素**内部**。
func gpTestInsulationThicknessIsWrittenOnItsHost() -> void:
	var gpXml: String = GPDexpiExporter.gpWriteXml(
		GPDexpiExporter.gpFromGraph(_gpVesselWithInsulation(), _gpSheet()))
	gpEq(gpXml.count(GP_EQUIP_OPEN), 1, "only the vessel is an <Equipment> — insulation is not one")
	gpEq(gpXml.count("<Insulation"), 0, "and no element is invented for it")
	gpEq(gpXml.count("InsulationThicknessAssignmentClass"), 1,
		"the thickness appears exactly once, as an attribute")
	gpEq(gpXml.count("Millimetre"), 1, "carrying the one verified unit (+ its URI)")
	var gpOpenAt: int = gpXml.find(GP_EQUIP_OPEN)
	var gpAttrAt: int = gpXml.find("InsulationThicknessAssignmentClass")
	var gpCloseAt: int = gpXml.find(GP_EQUIP_CLOSE)
	gpCheck(gpOpenAt != -1 and gpAttrAt != -1 and gpCloseAt != -1, "all three landmarks are present")
	gpCheck(gpOpenAt < gpAttrAt, "the thickness comes after the vessel opens")
	gpCheck(gpAttrAt < gpCloseAt, "and before it closes — so it is the VESSEL's attribute")


# A "child" relation must NOT leak into the host's attribute block; only "attribute" does.
# "child" 关系**不得**渗进宿主的属性块；只有 "attribute" 会。
func gpTestChildRelationContributesNoHostAttributes() -> void:
	var gpXml: String = GPDexpiExporter.gpWriteXml(
		GPDexpiExporter.gpFromGraph(_gpVesselWithNozzle(), _gpSheet()))
	gpEq(gpXml.count("InsulationThicknessAssignmentClass"), 0,
		"a nested nozzle adds no host attribute")
	var gpMid: Dictionary = GPDexpiReader.gpReadXml(gpXml).gpPayload as Dictionary
	gpEq(_gpPropsOf(gpMid, "uid-vessel").size(), 1,
		"the vessel keeps exactly its own one property — nothing leaked up from the child")


# ★ THE VALUE SURVIVES ON THE HOST, AND THE ASYMMETRY IS PINNED — not discovered later.
# DEXPI has no object id to come back to, because it models the thickness as an attribute of the
# host. So the round trip keeps the NUMBER and re-expresses it on the vessel: losing the part
# while keeping the engineering data is a deliberate, reviewable outcome.
# ★ 该值存续在**宿主**上，且这处不对称被**钉住** —— 而不是日后才发现。
# DEXPI 把厚度建模为宿主的属性，故没有可供回返的对象 id。于是往返保住了**数值**，
# 只是把它重新表达在容器上：丢掉「件」而保住工程数据，是刻意且可复核的结果。
func gpTestInsulationThicknessComesBackOnTheHost() -> void:
	var gpXml: String = GPDexpiExporter.gpWriteXml(
		GPDexpiExporter.gpFromGraph(_gpVesselWithInsulation(), _gpSheet()))
	var gpMid: Dictionary = GPDexpiReader.gpReadXml(gpXml).gpPayload as Dictionary
	var gpBack: String = str(_gpPropsOf(gpMid, "uid-vessel").get("insulation", ""))
	gpCheck(absf(float(gpBack) - 80.0) < 0.0001,
		"the host got the thickness back, got '" + gpBack + "'")
	gpEq((gpMid.get(GPDexpiExporter.GP_KEY_EQUIPMENT, []) as Array).size(), 1,
		"and DEXPI models it as an attribute, so no second object is built for it")
