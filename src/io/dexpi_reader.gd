class_name GPDexpiReader
extends RefCounted

# Read a Proteus XML document into the SAME intermediate structure the exporter produces.
# 把 Proteus XML 文档读成与导出器**相同**的中间结构。
#
# WHY THE SAME STRUCTURE / 为何用同一结构：
# it makes the round trip a comparison instead of a translation. Export -> import can then be
# asserted as "the structure came back equivalent", which is the §8.4 P2 acceptance and the
# cheapest possible proof that neither direction has drifted.
# 它让往返成为一次**比较**而非一次翻译。于是「导出 -> 导入」可被断言为
# 「结构等价返回」—— 这正是 §8.4 P2 的验收标准，也是证明两个方向都未漂移的最廉价手段。
#
# ERROR POLICY (§7.3) / 错误策略：
# fatal (root is not <PlantModel>, unparsable text) -> gpFailure, nothing returned;
# everything else is a REPORT entry made by GPDexpiValidator, not a reason to stop reading.
# fatal（根不是 <PlantModel>、文本无法解析）-> gpFailure，不返回任何东西；
# 其余一切都是 GPDexpiValidator 产出的报告条目，而非停止读取的理由。

const GP_CODE_NOT_PLANT_MODEL: String = "dexpi.not_plant_model"
const GP_CODE_UNPARSABLE: String = "dexpi.unparsable"


# Parse gpText into the intermediate structure. Returns GPIOResult whose gpPayload is the
# structure on success.
# 把 gpText 解析为中间结构。成功时返回的 GPIOResult 的 gpPayload 即该结构。
static func gpReadXml(gpText: String) -> GPIOResult:
	if gpText.strip_edges().is_empty():
		return GPIOResult.gpFailure(GP_CODE_UNPARSABLE, "status.import_fail", "empty document")
	var gpParser: XMLParser = XMLParser.new()
	if gpParser.open_buffer(gpText.to_utf8_buffer()) != OK:
		return GPIOResult.gpFailure(GP_CODE_UNPARSABLE, "status.import_fail", "open failed")

	var gpMid: Dictionary = {
		GPDexpiExporter.GP_KEY_PLANT: {},
		GPDexpiExporter.GP_KEY_DIAGRAM: {},
		GPDexpiExporter.GP_KEY_EQUIPMENT: [],
		GPDexpiExporter.GP_KEY_SEGMENTS: [],
		GPDexpiExporter.GP_KEY_SKIPPED: [],
		GPDexpiExporter.GP_KEY_SHAPES: [],
		GPDexpiExporter.GP_KEY_USAGES: [],
		GPDexpiExporter.GP_KEY_DRAWING_SHAPES: [],
	}
	var gpStack: Array[String] = []
	var gpCurEquip: Dictionary = {}
	var gpCurSeg: Dictionary = {}
	var gpCurShape: Dictionary = {}
	var gpCurUsage: Dictionary = {}
	var gpRootSeen: bool = false
	# ★ The open chain of equipment-ish objects, deepest LAST. P4 nests mountable children
	# INSIDE their host's element, so "which object does this GenericAttribute belong to" is
	# answered by "the deepest one still open" — not by a single gpCurEquip.
	# ★ 处于打开状态的「设备类」对象链，**最深者在最后**。P4 把可挂载子件嵌在宿主元素内部，
	# 故「这条 GenericAttribute 属于哪个对象」的答案是「仍处于打开状态的最深那个」——
	# 而不是单个 gpCurEquip。
	var gpEquipStack: Array[Dictionary] = []
	# DEXPI element name -> {kind, nestable} for every relation that HAS an element name. Derived
	# from the mapping table rather than listed here, so adding a relation is one edit in one
	# place — and the reader cannot disagree with the writer about which element means what.
	# DEXPI 元素名 -> {kind, nestable}，覆盖每个有元素名的关系。由映射表推导而非在此罗列，
	# 故新增一种关系只需改一处 —— 且读取器不可能与写出器就「哪个元素代表什么」产生分歧。
	var gpRelEls: Dictionary = _gpRelationElements()

	while true:
		var gpRead: int = gpParser.read()
		if gpRead == ERR_FILE_EOF:
			break
		if gpRead != OK:
			return GPIOResult.gpFailure(GP_CODE_UNPARSABLE, "status.import_fail",
				"parse error at offset " + str(gpParser.get_node_offset()))
		if gpParser.get_node_type() == XMLParser.NODE_ELEMENT_END:
			# Closing an equipment-ish element restores its HOST as "current", so a following
			# sibling child never inherits the closed child's attributes.
			# 关闭一个「设备类」元素会把其**宿主**恢复为「当前」，
			# 使随后的兄弟子件绝不会继承已关闭子件的属性。
			var gpEndName: String = gpParser.get_node_name()
			if gpEndName == "Equipment" or gpRelEls.has(gpEndName):
				if not gpEquipStack.is_empty():
					gpEquipStack.pop_back()
				gpCurEquip = gpEquipStack.back() if not gpEquipStack.is_empty() else {}
			if not gpStack.is_empty():
				gpStack.pop_back()
			continue
		if gpParser.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		var gpName: String = gpParser.get_node_name()
		var gpAttrs: Dictionary = _gpAttrsOf(gpParser)
		if not gpRootSeen:
			# There is no <ConceptualModel> element; the root is <PlantModel> and the presence
			# of concept children is what implies a conceptual model (§4.2).
			# 不存在 <ConceptualModel> 元素；根是 <PlantModel>，
			# 而概念子元素的出现才是概念模型存在的依据（§4.2）。
			if gpName != "PlantModel":
				return GPIOResult.gpFailure(GP_CODE_NOT_PLANT_MODEL, "status.import_fail", gpName)
			gpRootSeen = true
		# ONLY non-empty elements go on the stack. A self-closing element (<Coordinate .../>) is
		# reported by XMLParser as a start event with NO matching end event, so pushing it would
		# make the stack grow forever — "CenterLine" would stay on it for the rest of the file
		# and every later glyph coordinate would be misfiled into the pipe geometry.
		# 只有**非空**元素入栈。自闭合元素（<Coordinate .../>）在 XMLParser 中
		# 只有开始事件而**没有**对应的结束事件，故入栈会让栈无限增长 ——
		# "CenterLine" 会一直留在栈上，其后每个字形坐标都会被错记进管线几何。
		if not gpParser.is_empty():
			gpStack.append(gpName)
		# ★ <Equipment> and its nested parts share ONE creation path. A mounted child is the
		# same kind of object as a root equipment — it differs only by having a parent — so
		# giving it a second code path would be a second place for the two to disagree.
		# ★ <Equipment> 与其嵌套部件共用**同一条**创建路径。被挂载子件与根设备是同一类对象，
		# 区别只在于它有父件；给它第二条代码路径，就是给二者制造第二个可能不一致的地方。
		if gpName == "Equipment" or gpRelEls.has(gpName):
			var gpRowR: Dictionary = gpRelEls.get(gpName, {}) as Dictionary
			var gpKindR: String = str(gpRowR.get("kind", ""))
			var gpNestableR: bool = bool(gpRowR.get("nestable", false))
			var gpSymR: String = GPDexpiMapping.gpSymbolIdFor(str(gpAttrs.get("ComponentClass", "")))
			var gpRoleR: String = GPDexpiMapping.GP_ROLE_EQUIPMENT
			if not gpSymR.is_empty():
				gpRoleR = str(GPDexpiMapping.gpComponentFor(gpSymR).get("role",
					GPDexpiMapping.GP_ROLE_EQUIPMENT))
			# A NESTABLE relation takes the deepest open object as its host. A TOP-LEVEL relation
			# (an ActuatingSystem) is a peer of the equipment, not a part of it, so it starts a
			# chain of its own — and a stray top-level <Nozzle> therefore imports as an object
			# with no parent, rather than as a lost one.
			# **可嵌套**关系取最深的活动对象为宿主。**顶层**关系（ActuatingSystem）是设备的
			# **同级**而非其部件，故它另起一条链 —— 于是顶层孤立的 <Nozzle> 会作为
			# 「无父件的对象」导入，而不是被丢掉。
			var gpHostR: Dictionary = {}
			if gpNestableR and not gpEquipStack.is_empty():
				gpHostR = gpEquipStack.back()
			gpCurEquip = {
				"id": str(gpAttrs.get("ID", "")),
				"class": str(gpAttrs.get("ComponentClass", "")),
				"uri": str(gpAttrs.get("ComponentClassURI", "")),
				"role": gpRoleR,
				"tag": "",
				"names": {},
				"props": {},
				# ★ NO POSE on a concept object — the pose is read into the ShapeUsage below, which
				# is where DEXPI keeps placement. A "position" here would collide meaning with the
				# usage's identically named key (this one could only ever be the stored local
				# value) and, because it was never filled, it silently drifted to ZERO on every
				# round trip.
				# ★ 概念对象上**不**放位姿 —— 位姿读入下方的 ShapeUsage，那才是 DEXPI 放置信息
				# 所在。此处若有 "position"，便与 usage 的同名键语义相撞（此键只可能是存储的
				# 局部值），且由于从不被填充，每次往返都会悄悄漂移成 ZERO。
				"parent_uid": str(gpHostR.get("id", "")),
				# DEXPI carries no anchor name, so the mount is restored but its ANCHOR is not:
				# the resolver then degrades to the host's centre, which is a visible result
				# rather than a silent misplacement. Known gap, flagged in the P4 notes.
				# DEXPI 不携带锚点名，故挂载被恢复而**锚点**没有：解析器随后降级到宿主中心，
				# 那是**可见**的结果，而非静默的错位。已知缺口，已在 P4 备注中标出。
				"mount_anchor": "",
				"mount_kind": gpKindR,
			}
			(gpMid[GPDexpiExporter.GP_KEY_EQUIPMENT] as Array).append(gpCurEquip)
			# ★ Push ONLY when the element is non-empty, because only a non-empty element emits
			# a matching END event. A self-closing <Nozzle .../> would otherwise be pushed and
			# never popped, and every later attribute would be filed onto it.
			# ★ 仅当元素**非空**时入栈 —— 只有非空元素才会有配对的 END 事件。
			# 否则自闭合的 <Nozzle .../> 入栈后永不出栈，其后每个属性都会记到它头上。
			if not gpParser.is_empty():
				gpEquipStack.append(gpCurEquip)
		match gpName:
			"PlantInformation":
				gpMid[GPDexpiExporter.GP_KEY_PLANT] = {
					"date": str(gpAttrs.get("Date", "")),
					"time": str(gpAttrs.get("Time", "")),
					"system": str(gpAttrs.get("OriginatingSystem", "")),
					"vendor": str(gpAttrs.get("OriginatingSystemVendor", "")),
					"version": str(gpAttrs.get("OriginatingSystemVersion", "")),
					"schema": str(gpAttrs.get("SchemaVersion", "")),
					"units": str(gpAttrs.get("Units", "")),
				}
			"Drawing":
				# Extent values arrive in FILE coordinates (Y up); flip them back to concept
				# space so the intermediate structure matches what the exporter produced.
				# 范围值以**文件坐标**（Y 向上）到达；翻回概念空间，
				# 使中间结构与导出器产出的一致。
				gpMid[GPDexpiExporter.GP_KEY_DIAGRAM] = {
					"name": str(gpAttrs.get("Name", "")),
					"min_x": _gpFloat(gpAttrs, "MinX"),
					"min_y": GPDexpiMapping.gpFlipY(_gpFloat(gpAttrs, "MaxY")),
					"max_x": _gpFloat(gpAttrs, "MaxX"),
					"max_y": GPDexpiMapping.gpFlipY(_gpFloat(gpAttrs, "MinY")),
					"background": str(gpAttrs.get("BackgroundColor", "")),
				}
			"Equipment":
				# Handled ABOVE, together with the nestable part elements, so both kinds of
				# object are built by one piece of code.
				# 已在**上方**与可嵌套部件元素一并处理，使两类对象由同一段代码构造。
				pass
			"PipingNetworkSegment":
				gpCurSeg = {
					"id": str(gpAttrs.get("ID", "")),
					"from_uid": "",
					"to_uid": "",
					"points": [],
					"attrs": {},
					"tag": "",
					"why_from": "",
					"why_to": "",
				}
				(gpMid[GPDexpiExporter.GP_KEY_SEGMENTS] as Array).append(gpCurSeg)
			"SourceItem":
				if not gpCurSeg.is_empty():
					gpCurSeg["from_uid"] = str(gpAttrs.get("ItemID", ""))
			"TargetItem":
				if not gpCurSeg.is_empty():
					gpCurSeg["to_uid"] = str(gpAttrs.get("ItemID", ""))
			"PolyLine", "Polygon":
				# A primitive boundary: start a new primitive so two primitives in one shape do
				# not collapse into a single point list.
				# 图元边界：开启一个新图元，使同一图形内的两个图元不会塌缩成一个点表。
				_gpStartPrimitive(gpStack, gpCurShape,
					GPShape.GPKind.GP_POLYLINE, gpName == "Polygon", gpAttrs)
			"Line":
				_gpStartPrimitive(gpStack, gpCurShape, GPShape.GPKind.GP_LINE, false, gpAttrs)
			"Ellipse":
				_gpStartPrimitive(gpStack, gpCurShape, GPShape.GPKind.GP_CIRCLE, false, gpAttrs)
			"Coordinate":
				# Every coordinate is flipped back: the file frame is Y-up, the concept frame
				# is Y-down, and gpFlipY is self-inverse so one function serves both ways.
				# 每个坐标都翻回来：文件坐标系 Y 向上、概念坐标系 Y 向下，
				# 而 gpFlipY 自反，故一个函数服务两个方向。
				_gpAddCoordinate(gpStack, gpMid, gpCurSeg, gpCurShape, gpAttrs)
			"GenericAttribute":
				_gpAddAttribute(gpStack, gpCurEquip, gpCurSeg, gpAttrs)
			"Shape":
				if gpStack.has("ShapeCatalogue"):
					gpCurShape = {"id": str(gpAttrs.get("Name", "")), "primitives": []}
					(gpMid[GPDexpiExporter.GP_KEY_SHAPES] as Array).append(gpCurShape)
			"ShapeUsage":
				gpCurUsage = {
					"item_id": str(gpAttrs.get("ItemID", "")),
					"shape_id": str(gpAttrs.get("Shape", "")),
					"instance_id": "",
					"position": Vector2.ZERO,
					"rotation_deg": GPDexpiMapping.gpFlipY(_gpFloat(gpAttrs, "Rotation")),
					"scale": _gpFloat(gpAttrs, "ScaleX"),
					"mirrored": str(gpAttrs.get("IsMirrored", "no")) == "yes",
				}
				(gpMid[GPDexpiExporter.GP_KEY_USAGES] as Array).append(gpCurUsage)
			"Position":
				if not gpCurUsage.is_empty():
					gpCurUsage["position"] = Vector2(_gpFloat(gpAttrs, "X"),
						GPDexpiMapping.gpFlipY(_gpFloat(gpAttrs, "Y")))
	if not gpRootSeen:
		return GPIOResult.gpFailure(GP_CODE_NOT_PLANT_MODEL, "status.import_fail", "no root")
	return GPIOResult.gpSuccessWith(gpMid, "status.imported")


# DEXPI element name -> {"kind": mount kind, "nestable": bool}, for every relation that HAS an
# element name. Derived from GP_MOUNT_RELATIONS, so a new relation or element needs no edit here
# — and the reader cannot disagree with the writer about which elements stand for which kind.
# DEXPI 元素名 -> {"kind": 挂载类别, "nestable": bool}，覆盖**每一个**有元素名的关系。
# 由 GP_MOUNT_RELATIONS 推导，故新增关系或元素无需改动此处 ——
# 且读取器**不可能**与写出器就「哪个元素代表哪种类别」产生分歧。
# ★ Nestable is carried per row rather than assumed: a top-level <ActuatingSystem> is a real
# object that must be READ BACK, even though it is never nested.
# ★ nestable 是**逐行**携带而非假定的：顶层的 <ActuatingSystem> 是一个必须**读回来**的真实对象，
# 尽管它从不被嵌套。
static func _gpRelationElements() -> Dictionary:
	var gpOut: Dictionary = {}
	for gpKind in GPDexpiMapping.gpAllMountKinds():
		var gpRel: Dictionary = GPDexpiMapping.gpMountRelationFor(gpKind)
		var gpElement: String = str(gpRel.get("element", ""))
		if gpElement.is_empty():
			continue
		gpOut[gpElement] = {
			"kind": gpKind,
			"nestable": str(gpRel.get("containment", "")) == GPDexpiMapping.GP_MOUNT_CHILD,
		}
	return gpOut


static func _gpAttrsOf(gpParser: XMLParser) -> Dictionary:
	var gpOut: Dictionary = {}
	var gpCount: int = gpParser.get_attribute_count()
	var gpI: int = 0
	while gpI < gpCount:
		gpOut[gpParser.get_attribute_name(gpI)] = gpParser.get_attribute_value(gpI)
		gpI += 1
	return gpOut


static func _gpFloat(gpAttrs: Dictionary, gpKey: String) -> float:
	var gpRaw: String = str(gpAttrs.get(gpKey, ""))
	if gpRaw.is_empty():
		return 0.0
	if gpRaw.is_valid_float():
		return gpRaw.to_float()
	return 0.0


# A Coordinate belongs to a center line (world space) or to a glyph primitive (local space);
# the containing element on the stack decides which.
# 一个 Coordinate 属于中心线（世界空间）或字形图元（局部空间）；
# 由栈上的包含元素决定归属。
# Begin a glyph primitive inside the shape currently being read.
# 在当前读取的图形内开启一个字形图元。
static func _gpStartPrimitive(gpStack: Array[String], gpCurShape: Dictionary,
		gpKind: int, gpClosed: bool, gpAttrs: Dictionary) -> void:
	if not gpStack.has("ShapeCatalogue") or gpCurShape.is_empty():
		return
	var gpColor: Color = Color(0.0, 0.0, 0.0)
	(gpCurShape.get("primitives", []) as Array).append({
		"kind": gpKind,
		"points": [],
		"radius": _gpFloat(gpAttrs, "RX"),
		"closed": gpClosed,
		"color": gpColor,
	})


static func _gpAddCoordinate(gpStack: Array[String], gpMid: Dictionary, gpCurSeg: Dictionary,
		gpCurShape: Dictionary, gpAttrs: Dictionary) -> void:
	var gpPt: Vector2 = Vector2(_gpFloat(gpAttrs, "X"), GPDexpiMapping.gpFlipY(_gpFloat(gpAttrs, "Y")))
	if gpStack.has("CenterLine") and not gpCurSeg.is_empty():
		(gpCurSeg["points"] as Array).append(gpPt)
		return
	if gpStack.has("ShapeCatalogue") and not gpCurShape.is_empty():
		var gpPrims: Array = gpCurShape.get("primitives", []) as Array
		# Coordinates arrive flat under a primitive element, so they are attached to the last
		# primitive of the current shape — the primitive elements themselves carry no points.
		# 坐标以平铺方式出现在图元元素之下，故挂到当前图元的最后一个图元上 ——
		# 图元元素自身不携带点。
		if gpPrims.is_empty():
			gpPrims.append({"kind": GPShape.GPKind.GP_POLYLINE, "points": [],
				"radius": 0.0, "closed": false, "color": Color(0.0, 0.0, 0.0)})
		((gpPrims[gpPrims.size() - 1] as Dictionary)["points"] as Array).append(gpPt)


# GenericAttributes sit under an object; the stack says which one.
# GenericAttributes 位于某对象之下；栈告诉我们是哪一个。
static func _gpAddAttribute(gpStack: Array[String], gpCurEquip: Dictionary,
		gpCurSeg: Dictionary, gpAttrs: Dictionary) -> void:
	var gpName: String = str(gpAttrs.get("Name", ""))
	var gpValue: String = str(gpAttrs.get("Value", ""))
	var gpLanguage: String = str(gpAttrs.get("Language", ""))
	if gpStack.has("PipingNetworkSegment") and not gpCurSeg.is_empty():
		if gpName == "TagNameAssignmentClass":
			gpCurSeg["tag"] = gpValue
		else:
			(gpCurSeg["attrs"] as Dictionary)[_gpReverseKey(gpName)] = gpValue
		return
	if gpCurEquip.is_empty():
		return
	if gpName == "TagNameAssignmentClass":
		gpCurEquip["tag"] = gpValue
	elif gpName == "DescriptionAssignmentClass" and not gpLanguage.is_empty():
		(gpCurEquip["names"] as Dictionary)[gpLanguage] = gpValue
	else:
		(gpCurEquip["props"] as Dictionary)[_gpReverseKey(gpName)] = gpValue


# DEXPI camelCase + AssignmentClass -> G-PID snake_case. The forward direction adds the suffix
# and camel-cases; this strips both. Unknown keys keep their DEXPI name rather than being
# dropped, so a later round trip still finds them.
# DEXPI camelCase + AssignmentClass -> G-PID snake_case。正向添加后缀并转 camelCase；
# 此处两者都去掉。未知键保留其 DEXPI 名而非丢弃，使后续往返仍能找到它们。
# ★ THE TABLE IS ASKED FIRST / ★ **先**查表：
# the mechanical rule below reproduces the key only when the DEXPI name IS its camelCase. Four
# rows are deliberately not (insulation, dn, medium, spec), so stripping alone produced keys no
# schema, inspector or exporter field matches — the value came back and was then invisible.
# GP_ATTRIBUTES is the forward map, so asking it here makes the two directions one rule.
# ★ 下面的机械规则**只有**在 DEXPI 名恰为该键的 camelCase 时才能还原。有**四行**刻意不是
#（insulation / dn / medium / spec），故仅靠去后缀会产出没有任何 schema / 检查器 / 导出器字段
# 与之匹配的键 —— 值读回来了，随后却不可见。GP_ATTRIBUTES 是正向映射，
# 在此查它，两个方向便成了同一条规则。
static func _gpReverseKey(gpName: String) -> String:
	var gpMapped: String = GPDexpiMapping.gpKeyForAttributeName(gpName)
	if not gpMapped.is_empty():
		return gpMapped
	var gpBase: String = gpName
	if gpBase.ends_with("AssignmentClass"):
		gpBase = gpBase.substr(0, gpBase.length() - "AssignmentClass".length())
	var gpOut: String = ""
	var gpFirst: bool = true
	for gpC in gpBase:
		var gpCh: String = str(gpC)
		# The first character must NOT gain a leading underscore, or "DesignPressure" becomes
		# "_design_pressure" and the round trip silently loses the key.
		# 首字符**不得**获得前导下划线，否则 "DesignPressure" 会变成
		# "_design_pressure"，往返会静默丢掉这个键。
		if not gpFirst and gpCh == gpCh.to_upper() and gpCh != gpCh.to_lower():
			gpOut += "_" + gpCh.to_lower()
		else:
			gpOut += gpCh.to_lower() if gpFirst else gpCh
		gpFirst = false
	return gpOut
