class_name GPDexpiMapping
extends RefCounted

# Data-driven mapping tables between G-PID and DEXPI, plus the two geometry/presentation
# conversion points that the spec makes easy to get wrong silently.
# G-PID 与 DEXPI 之间的**数据驱动**映射表，外加两个「错了也静默」的几何/呈现转换点。
#
# WHY A TABLE, NOT BRANCHES / 为何用表而非分支（§7.1）：
# DEXPI has 568 types. A mapping expressed as if/else grows a new branch per type and cannot
# be validated as a whole; a table CAN — "every row has a plausible class name, every URI is
# either verified or deliberately empty" is itself a test. Tests iterate gpAllSymbolIds().
# DEXPI 有 568 个类型。用 if/else 表达的映射每加一个类型就多一个分支，且无法整体校验；
# 表则可以 ——「每一行类名都合理、每个 URI 要么已核实要么刻意留空」本身就是一项测试。
# 测试通过 gpAllSymbolIds() 遍历全表。
#
# ★ URI POLICY / URI 原则（不臆造 / never fabricate）:
# `uri` holds ONLY references verified against the spec. Everything else ships with an EMPTY
# uri and a report entry, because a fabricated URI resolves to nothing while a missing one is
# visible and fixable. Entries awaiting a verified URI are marked in the comment below.
# `uri` **只**填规范已核实的引用。其余一律空 uri + 报告条目 ——
# 臆造的 URI 解析到空，缺失的则可见且可修。待补 URI 的条目在下方注释中标出。

# Symbol role values / 图元角色取值。
# equipment -> <Equipment>       piping_component -> a <PipingComponent> on the segment
# annotation -> graphics only (never a concept object)
# actuating -> <ActuatingSystem> (sandbox domain)
# internal  -> NOT exported (UI/layout data: see risk 8)
const GP_ROLE_EQUIPMENT: String = "equipment"
const GP_ROLE_PIPING: String = "piping_component"
const GP_ROLE_ANNOTATION: String = "annotation"
const GP_ROLE_ACTUATING: String = "actuating"
const GP_ROLE_INTERNAL: String = "internal"

# G-PID symbol id -> {class, uri, role}
# Verified URI: dpump001 (CentrifugalPump = RDS416834, from the spec). ALL OTHERS ARE EMPTY
# and await verification — the class names below are engineering judgements from each symbol's
# Chinese display name, which is safe to ship as a NAME but is NOT evidence of a URI.
# 已核实 URI：dpump001（CentrifugalPump = RDS416834，来自规范）。**其余全部为空**待核实 ——
# 下表中的类名是据各图元中文显示名作出的工程判断，作为**名称**可安全输出，
# 但并不构成某个 URI 的证据。
const GP_SYMBOLS: Dictionary = {
	"DPUMP001": {"class": "CentrifugalPump", "uri": GPDexpiSchema.GP_URI_CENTRIFUGAL_PUMP, "role": GP_ROLE_EQUIPMENT},
	"DPUMP002": {"class": "ReciprocatingPump", "uri": "", "role": GP_ROLE_EQUIPMENT},
	"DTANK001": {"class": "Vessel", "uri": "", "role": GP_ROLE_EQUIPMENT},
	"DVALVE001": {"class": "PressureReliefValve", "uri": "", "role": GP_ROLE_EQUIPMENT},
	"DVALVE002": {"class": "BallValve", "uri": "", "role": GP_ROLE_EQUIPMENT},
	"DVALVE003": {"class": "ButterflyValve", "uri": "", "role": GP_ROLE_EQUIPMENT},
	"DVALVE004": {"class": "GlobeValve", "uri": "", "role": GP_ROLE_EQUIPMENT},
	"DVALVE005": {"class": "SwingCheckValve", "uri": "", "role": GP_ROLE_EQUIPMENT},
	"DHEAT001": {"class": "ShellAndTubeHeatExchanger", "uri": "", "role": GP_ROLE_EQUIPMENT},
	"DHEAT002": {"class": "PlateHeatExchanger", "uri": "", "role": GP_ROLE_EQUIPMENT},
	"DINSTRUMENT001": {"class": "InstrumentationUnit", "uri": "", "role": GP_ROLE_EQUIPMENT},
	"DINSTRUMENT002": {"class": "InstrumentationUnit", "uri": "", "role": GP_ROLE_EQUIPMENT},
	# Piping components: fittings belong to the SEGMENT, not to <Equipment> (§4.3).
	# 管件：管件属于**管段**，而非 <Equipment>（§4.3）。
	"DGENERAL003": {"class": "Blind", "uri": "", "role": GP_ROLE_PIPING},
	"DGENERAL010": {"class": "Reducer", "uri": "", "role": GP_ROLE_PIPING},
	"DGENERAL012": {"class": "Tee", "uri": "", "role": GP_ROLE_PIPING},
	# Equipment attachments / 设备附件。
	"DGENERAL007": {"class": "Manhole", "uri": "", "role": GP_ROLE_EQUIPMENT},
	"DGENERAL008": {"class": "Nozzle", "uri": "", "role": GP_ROLE_EQUIPMENT},
	# Actuating system lives in the SANDBOX domain (§4.3 易错点②).
	# 执行机构位于 sandbox 域（§4.3 易错点②）。
	"DGENERAL004": {"class": "ActuatingSystem", "uri": "", "role": GP_ROLE_ACTUATING},
	# Pure graphics: flow arrows, slope marks, insulation hatch. These carry NO concept and
	# must never become an <Equipment> — they are presentation only (P2 exports them as shapes).
	# 纯图形：流向箭头、坡度标记、保温剖面线。它们不含任何概念对象，
	# 绝不可变成 <Equipment> —— 仅属呈现（P2 阶段作为图形导出）。
	"DGENERAL001": {"class": "", "uri": "", "role": GP_ROLE_ANNOTATION},
	"DGENERAL002": {"class": "", "uri": "", "role": GP_ROLE_ANNOTATION},
	"DGENERAL005": {"class": "", "uri": "", "role": GP_ROLE_ANNOTATION},
	"DGENERAL006": {"class": "", "uri": "", "role": GP_ROLE_ANNOTATION},
	"DGENERAL009": {"class": "", "uri": "", "role": GP_ROLE_ANNOTATION},
	"DGENERAL011": {"class": "", "uri": "", "role": GP_ROLE_ANNOTATION},
}

# G-PID property key (snake_case) -> {name, uri, format, units, units_uri}
# ASSUMPTION (§9 待确认 5): internal keys are snake_case; the table converts them to DEXPI
# camelCase with an `AssignmentClass` suffix, which is the spec's own attribute naming shape.
# 假设（§9 待确认 5）：内部键为 snake_case；由本表转换为 DEXPI camelCase +
# `AssignmentClass` 后缀，这正是规范自身的属性命名形态。
# `internal` rows are NEVER exported: they are UI/layout state, and mixing them into the file
# is risk 8 (UI constants leaking into millimetre geometry).
# `internal` 行**永不导出**：它们是界面/布局状态，混进文件即风险 8（UI 常量泄漏进毫米几何）。
const GP_ATTRIBUTES: Dictionary = {
	"design_pressure": {"name": "DesignPressureAssignmentClass", "uri": "", "format": "double", "units": "", "units_uri": ""},
	"design_temp": {"name": "DesignTemperatureAssignmentClass", "uri": "", "format": "double", "units": "", "units_uri": ""},
	"volume": {"name": "VolumeAssignmentClass", "uri": "", "format": "double", "units": "", "units_uri": ""},
	"dn": {"name": "NominalDiameterAssignmentClass", "uri": "", "format": "string", "units": "", "units_uri": ""},
	"medium": {"name": "FluidAssignmentClass", "uri": "", "format": "string", "units": "", "units_uri": ""},
	"spec": {"name": "PipingClassAssignmentClass", "uri": "", "format": "string", "units": "", "units_uri": ""},
	# Insulation thickness is a physical quantity: value + Units + UnitsURI. Millimetre is the
	# one unit URI verified in the spec, so this row is the only one carrying a units_uri.
	# 保温层厚度是物理量：值 + Units + UnitsURI。毫米是规范中唯一已核实的单位 URI，
	# 故本行是唯一携带 units_uri 的行。
	"insulation": {"name": "InsulationThicknessAssignmentClass", "uri": "", "format": "double",
		"units": "Millimetre", "units_uri": GPDexpiSchema.GP_URI_MILLIMETRE},
	# Layout-only: where the user dragged the edge tag. Not an engineering property.
	# 仅布局：用户把边标签拖到何处。不是工程属性。
	"tag_offset": {"name": "", "uri": "", "format": "", "units": "", "units_uri": "", "internal": true},
}

# Mount kind (G-PID) -> how the mounted child is expressed in DEXPI.
# G-PID 的挂载类别 -> 被挂载子件在 DEXPI 中的表达方式。
#
# WHY A TABLE, AND WHY NO CLASS NAMES HERE / 为何用表，以及为何此处不写类名：
# the mount kind lives on the CHILD's GPSymbolDef (gpMountKind), but what DEXPI does with a
# child is a property of the RELATION, not of the child's class. Repeating the class name here
# would create a SECOND table naming classes — and the first thing two class tables do is
# drift. The class is read from GP_SYMBOLS via gpComponentFor(), so exactly one table names
# classes and it can never disagree with itself.
# 挂载类别长在**子件**的 GPSymbolDef 上（gpMountKind），但「DEXPI 如何处置子件」是**关系**的
# 属性，不是子件类的属性。在此重复类名会造出**第二张**命名类的表 ——
# 而两张类名表做的第一件事就是漂移。类名经 gpComponentFor() 从 GP_SYMBOLS 读取，
# 故「命名类的表」只有一张，永不自相矛盾。
#
# ★ NOTE THE ABSENT COLUMN / ★ 注意本表**没有**的那一列：
# there is no `uri` column at all. A relation is a structural decision (nested? referenced?
# an attribute?), not a standards reference, so there is nothing here to fabricate — the URI
# policy of §7.5 is enforced by the shape of the table rather than by reviewer discipline.
# 本表**根本没有** `uri` 列。关系是结构性判断（嵌套？引用？还是属性？），不是标准引用，
# 故此处没有可臆造之物 —— §7.5 的 URI 原则由**表的结构**保证，而非靠评审员的自觉。
#
# containment values / containment 取值：
#   "child"     -> nested INSIDE the host's DEXPI element (the host is the parent object)
#   "reference" -> the host keeps a reference; the child stays a TOP-LEVEL object
#   "segment"   -> the child belongs to a piping segment, not to <Equipment>
#   "attribute" -> not an element at all: it is a property OF the host
#   "unknown"   -> no row; reported, never guessed
# "child"     -> 嵌在宿主 DEXPI 元素**内部**（宿主即父对象）
# "reference" -> 宿主持有引用；子件**仍是顶层对象**
# "segment"   -> 子件属于管段，不属于 <Equipment>
# "attribute" -> 根本不是元素：它是宿主的**属性**
# "unknown"   -> 无此行；**报告**，绝不猜测
const GP_MOUNT_CHILD: String = "child"
const GP_MOUNT_REFERENCE: String = "reference"
const GP_MOUNT_SEGMENT: String = "segment"
const GP_MOUNT_ATTRIBUTE: String = "attribute"
const GP_MOUNT_UNKNOWN: String = "unknown"

# mount_kind -> {containment, element, verified, note, host_attrs}
# `element` is the DEXPI element name a "child" becomes. It is a NAME — safe to ship as a name
# — and explicitly NOT evidence of a URI: `verified` stays false until the class is checked
# against the spec, and the exporter still ships ComponentClassURI="" meanwhile.
# `element` 是 "child" 子件所成为的 DEXPI 元素名。它是**名称**（作为名称可安全输出），
# 且**明确不是** URI 的证据：`verified` 在类名经规范核实前保持 false，
# 期间导出器照旧写 `ComponentClassURI=""`。
#
# `host_attrs` (only meaningful for containment "attribute") lists the G-PID **property keys**
# of the child that are poured into the HOST's attribute block instead of being carried by an
# object of the child's own. WHY THE KEYS LIVE HERE / 为何键写在此表：
# "which of my values end up on you" is a property of the RELATION, exactly like nesting is;
# putting it on the child's definition would ask the child to know its host's file layout.
# ★ It is NOT a second naming table: these are G-PID keys, and their DEXPI name / format /
# units still come from GP_ATTRIBUTES alone — so the "one table names things" rule holds.
# `host_attrs`（仅对 containment "attribute" 有意义）列出子件的 G-PID **属性键**，
# 它们被倒进**宿主**的属性块，而非由子件自己的对象携带。为何键写在此表：
#「我的哪些值会落到你身上」是**关系**的属性，与「是否嵌套」同理；写在子件定义上，
# 等于要求子件知道其宿主的文件布局。
# ★ 它**不是**第二张命名表：这些是 G-PID 键，其 DEXPI 名 / 格式 / 单位仍**只**来自
# GP_ATTRIBUTES —— 故「命名只有一张表」的规矩依然成立。
const GP_MOUNT_RELATIONS: Dictionary = {
	"NOZZLE": {"containment": GP_MOUNT_CHILD, "element": "Nozzle", "verified": false,
		"note": "a nozzle is a component OF its equipment, so it nests inside <Equipment>"},
	"MANHOLE": {"containment": GP_MOUNT_CHILD, "element": "Manhole", "verified": false,
		"note": "an opening in the vessel wall is structurally a nozzle-like part of its equipment"},
	"ACTUATOR": {"containment": GP_MOUNT_REFERENCE, "element": "ActuatingSystem", "verified": false,
		"note": "ActuatingSystem is a TOP-LEVEL object in the sandbox domain referenced by the valve; the reference mechanism is not implemented yet, so the child stays top-level and is reported"},
	"BLIND": {"containment": GP_MOUNT_SEGMENT, "element": "", "verified": false,
		"note": "a blind is a piping component belonging to the SEGMENT, not to <Equipment>"},
	"INSULATION": {"containment": GP_MOUNT_ATTRIBUTE, "element": "", "verified": false,
		"host_attrs": ["insulation"],
		"note": "insulation is the InsulationThicknessAssignmentClass attribute OF the host, not an element in its own right"},
}


# ---- geometry / presentation single points ------------------------------

# Flip a Y coordinate between the conceptual frame (Y DOWN, clockwise) and the Proteus file
# frame (Y UP, counter-clockwise). THIS IS THE SINGLE IMPLEMENTATION POINT (§6.5 risk 1).
# 在概念坐标系（Y 向下、顺时针）与 Proteus 文件坐标系（Y 向上、逆时针）之间翻转 Y。
# 这是**唯一实现点**（§6.5 风险 1）。
# Self-inverse: flipping twice returns the input, which is what makes one function enough for
# both export and import — a separate export/import pair would let the two drift apart.
# 自反：翻转两次回到原值，这正是「一个函数同时服务导出与导入」的原因 ——
# 若分成导出/导入两个函数，二者迟早漂移。
static func gpFlipY(gpY: float) -> float:
	return -gpY


# Normalise a colour to the 0..1 floats Proteus expects (§4.4). Single implementation point
# for risk 3: writing 0..255 here produces white or an overflow, never an error message.
# 把颜色归一化为 Proteus 期望的 0..1 浮点（§4.4）。风险 3 的唯一实现点：
# 此处若写 0..255，结果是全白或溢出，而**不会有任何报错**。
static func gpNormRgb(gpColor: Color) -> Array:
	return [clampf(gpColor.r, 0.0, 1.0), clampf(gpColor.g, 0.0, 1.0), clampf(gpColor.b, 0.0, 1.0)]


# ---- lookups ------------------------------------------------------------

# Component mapping for a G-PID symbol id. Unknown ids fall back to a CUSTOM class rather
# than being dropped (§7.5 降级 ③: 不丢数据 / never discard).
# 某 G-PID 图元 id 的组件映射。未知 id 回退到 Custom 类而非丢弃
# （§7.5 降级 ③：不丢数据）。
static func gpComponentFor(gpSymbolId: String) -> Dictionary:
	var gpRow: Variant = GP_SYMBOLS.get(gpSymbolId)
	if gpRow is Dictionary:
		return (gpRow as Dictionary).duplicate(true)
	return {"class": "Custom" + gpSymbolId, "uri": "", "role": GP_ROLE_EQUIPMENT, "unknown": true}


# Reverse lookup: DEXPI class name -> G-PID symbol id. Needed by the importer, which arrives
# with a ComponentClass and has to decide what to place on the canvas.
# 反向查询：DEXPI 类名 -> G-PID 图元 id。导入器需要它 ——
# 导入器拿到的是 ComponentClass，必须决定在画布上放什么。
# Two recovery paths, in order / 两条恢复路径，按顺序：
# 1. an exact class match in the table;
# 2. a class shaped like "CustomXXXX" — which is what gpComponentFor() emits for an unknown
#    symbol, so the original id is recoverable and the round trip closes.
# 1. 表中精确匹配的类名；
# 2. 形如 "CustomXXXX" 的类名 —— 这正是 gpComponentFor() 对未知图元的产出，
#    故原 id 可恢复，往返得以闭合。
# Returns "" when neither applies: the caller reports it rather than inventing a symbol.
# 两者都不适用时返回 ""：由调用方报告，而非臆造一个图元。
static func gpSymbolIdFor(gpClass: String) -> String:
	if gpClass.is_empty():
		return ""
	for gpId in GP_SYMBOLS.keys():
		if str((GP_SYMBOLS.get(gpId) as Dictionary).get("class", "")) == gpClass:
			return str(gpId)
	if gpClass.begins_with("Custom"):
		return gpClass.substr("Custom".length())
	return ""


# Attribute mapping for a G-PID property key. Unknown keys land in the CUSTOM Set container
# with a generated camelCase name — kept, not dropped.
# 某 G-PID 属性键的属性映射。未知键落到 CUSTOM Set 容器并生成 camelCase 名 —— 保留而非丢弃。
static func gpAttributeFor(gpKey: String) -> Dictionary:
	var gpRow: Variant = GP_ATTRIBUTES.get(gpKey)
	if gpRow is Dictionary:
		return (gpRow as Dictionary).duplicate(true)
	return {
		"name": gpCamelOf(gpKey) + "AssignmentClass",
		"uri": "",
		"format": "string",
		"units": "",
		"units_uri": "",
		"custom": true,
	}


# True when the attribute must NOT be exported (layout-only state).
# 该属性是否**不得**导出（仅布局状态）。
static func gpIsInternal(gpKey: String) -> bool:
	return bool(gpAttributeFor(gpKey).get("internal", false))


# The G-PID key whose attribute row NAMES [param gpAttributeName], or "" when no row does.
# 其属性行的 `name` 等于 [param gpAttributeName] 的那个 G-PID 键；无此行时返回 ""。
# ★ WHY THIS EXISTS AT ALL / ★ 为何需要它：
# the mechanical inverse — strip "AssignmentClass", camelCase→snake_case — recovers the key ONLY
# when the DEXPI name happens to BE the camelCase of it. Several rows deliberately do not work
# that way: `insulation` → InsulationThicknessAssignmentClass, `dn` → NominalDiameterAssignmentClass,
# `medium` → FluidAssignmentClass, `spec` → PipingClassAssignmentClass. Without this lookup the
# reverse direction alone invented names like "nominal_diameter" that no schema field matches, so
# the value was read back but landed on a key nothing could consume.
# ★ 机械式的逆运算（去掉 "AssignmentClass"、camelCase→snake_case）**只有**在 DEXPI 名恰好是该键的
# camelCase 时才能还原。若干行刻意不是这样：`insulation` → InsulationThicknessAssignmentClass、
# `dn` → NominalDiameterAssignmentClass、`medium` → FluidAssignmentClass、
# `spec` → PipingClassAssignmentClass。没有这次查表，仅靠反向规则会自己发明出
#「nominal_diameter」这类没有任何 schema 字段与之匹配的名字 —— 值读回来了，
# 却落在无人能消费的键上。
# ★ The forward direction and this one read the SAME table, which is what makes them a pair
# rather than two rules that agree by luck.
# ★ 正向与此处读的是**同一张**表 —— 这正是二者是一对、而非两条靠运气一致的规则的原因。
static func gpKeyForAttributeName(gpAttributeName: String) -> String:
	# gpAllAttributeKeys() is SORTED, so a duplicate name (which would be a table defect) resolves
	# the same way on every run instead of following dictionary order.
	# gpAllAttributeKeys() 是**有序**的，故重名（那将是表的缺陷）每次都解析成同一个结果，
	# 而不是随字典顺序变化。
	for gpKey in gpAllAttributeKeys():
		if str(gpAttributeFor(gpKey).get("name", "")) == gpAttributeName:
			return gpKey
	return ""


# Mount relation for a G-PID mount kind. An unmapped kind yields containment "unknown" WITH a
# reason instead of a plausible-looking guess, so the caller reports it (§7.5 不臆造).
# 某 G-PID 挂载类别的挂载关系。未映射的类别返回 containment "unknown" **并附原因**，
# 而非一个看着合理的猜测，使调用方能够报告它（§7.5 不臆造）。
static func gpMountRelationFor(gpMountKind: String) -> Dictionary:
	var gpRow: Variant = GP_MOUNT_RELATIONS.get(gpMountKind)
	if gpRow is Dictionary:
		return (gpRow as Dictionary).duplicate(true)
	return {"containment": GP_MOUNT_UNKNOWN, "element": "", "verified": false,
		"note": "unmapped mount kind: " + gpMountKind}


# True when a mounted child must be emitted INSIDE its host's DEXPI element.
# 被挂载的子件是否必须写在宿主 DEXPI 元素**内部**。
# ★ WHY THIS IS THE ONLY NESTING CASE / 为何只有这一种会嵌套：
# a wrong NESTING is invisible to the receiver (the child silently becomes part of the wrong
# object), whereas a wrong TOP-LEVEL object merely loses one grouping — and it is visible in
# the report. When in doubt, stay top-level and say so.
# 错误的**嵌套**对接收方不可见（子件静默地变成了错误对象的部件），
# 而错误的**顶层**对象只是丢了一层分组 —— 且它在报告里可见。拿不准就留顶层，并说明原因。
static func gpIsNestable(gpMountKind: String) -> bool:
	return str(gpMountRelationFor(gpMountKind).get("containment", "")) == GP_MOUNT_CHILD


# G-PID property keys that a mounted child of this kind contributes to its HOST rather than
# carrying on an object of its own. Empty for every relation that is not "attribute", and for
# an unmapped kind — so an unknown part annotates nothing instead of guessing a property name.
# 某类别的被挂载子件**贡献给宿主**（而非由自身对象携带）的 G-PID 属性键。
# 对每个非 "attribute" 的关系、以及未映射的类别均为空 ——
# 故未知部件不会去猜一个属性名，而是什么都不注解。
# ★ WHY DERIVED FROM THE RELATION AND NOT FROM THE CHILD'S DEFINITION / 为何取自关系而非子件定义：
# the SAME symbol could one day be mounted on a host that stores thickness on the segment; the
# question "whose attribute is this?" is answered by the mount, which is exactly where the
# nesting question is answered too.
# ★ 同一个图元将来可能被挂到「把厚度记在管段上」的宿主上；「这是谁的属性」由挂载回答 ——
# 嵌套问题也正是由挂载回答的。
static func gpHostAttrKeys(gpMountKind: String) -> Array[String]:
	var gpRaw: Variant = gpMountRelationFor(gpMountKind).get("host_attrs", [])
	var gpOut: Array[String] = []
	if gpRaw is Array:
		for gpKey in (gpRaw as Array):
			gpOut.append(str(gpKey))
	return gpOut


# Every mapped mount kind (for table-wide tests).
# 全部已映射的挂载类别（供全表测试遍历）。
static func gpAllMountKinds() -> Array[String]:
	var gpOut: Array[String] = []
	for gpKey in GP_MOUNT_RELATIONS.keys():
		gpOut.append(str(gpKey))
	gpOut.sort()
	return gpOut


# snake_case -> camelCase (spec attribute naming shape, §9 待确认 5).
# snake_case -> camelCase（规范属性命名形态，§9 待确认 5）。
static func gpCamelOf(gpKey: String) -> String:
	var gpParts: PackedStringArray = gpKey.split("_", false)
	var gpOut: String = ""
	var gpFirst: bool = true
	for gpPart in gpParts:
		var gpP: String = str(gpPart)
		if gpFirst:
			gpOut += gpP
			gpFirst = false
		else:
			gpOut += gpP.substr(0, 1).to_upper() + gpP.substr(1)
	return gpOut


# Every mapped symbol id (for table-wide tests).
# 全部已映射图元 id（供全表测试遍历）。
static func gpAllSymbolIds() -> Array[String]:
	var gpOut: Array[String] = []
	for gpKey in GP_SYMBOLS.keys():
		gpOut.append(str(gpKey))
	gpOut.sort()
	return gpOut


# Every mapped attribute key (for table-wide tests).
# 全部已映射属性键（供全表测试遍历）。
static func gpAllAttributeKeys() -> Array[String]:
	var gpOut: Array[String] = []
	for gpKey in GP_ATTRIBUTES.keys():
		gpOut.append(str(gpKey))
	gpOut.sort()
	return gpOut
