class_name GPDexpiSchema
extends RefCounted

# DEXPI constants: versions, RDL URI domains, reserved Set names, and the version-capability
# table. Everything the other DEXPI modules need to agree on lives HERE, so a version bump
# is one edit instead of a hunt through string literals.
# DEXPI 常量：版本、RDL URI 域、保留 Set 名，以及版本能力表。
# 其它 DEXPI 模块需要共同遵守的一切都放在**这里**，使版本升级成为一次编辑而非字符串狩猎。
#
# WHY A CONSTANT MODULE / 为何单列常量模块：
# the spec pins three things that are easy to get wrong and impossible to notice when wrong:
# the schema version string, the RDL domain prefix, and the reserved `Set` names. Writing any
# of them inline means two writers will eventually disagree, and the disagreement surfaces as
# a file the receiving tool silently rejects.
# 规范钉死了三件「易写错且错了无法察觉」的事：schema 版本串、RDL 域前缀、保留 `Set` 名。
# 任何一个散落书写，都会让两处实现最终不一致，而这种不一致表现为接收方工具静默拒收。
#
# Scope note / 范围说明：DEXPI is the SECOND external dialect adapter under src/io/, sitting
# beside the native *.pid.json IO. Dependency direction stays ui -> io -> core; this module
# must never reference ui or an autoload (headless testability).
# DEXPI 是 src/io/ 下的**第二个**外部方言适配器，与原生的 *.pid.json IO 平级。
# 依赖方向保持 ui -> io -> core；本模块绝不引用 ui 与 autoload（headless 可测性）。

# --- versions / 版本 -------------------------------------------------------
# Spec 1.4 (2024-12-12, CC BY 4.0); Proteus Schema 4.2.0 is its exchange format.
# 规范 1.4（2024-12-12，CC BY 4.0）；其交换格式为 Proteus Schema 4.2.0。
const GP_DEXPI_VERSION: String = "1.4"
const GP_PROTEUS_SCHEMA_VERSION: String = "4.2.0"

# Versions accepted on IMPORT. Export is fixed at 1.4 (see §9 待确认 8: export writes one
# version on purpose, because a writer that emits three dialects has three dialects to test).
# 导入接受的版本。导出固定为 1.4（见 §9 待确认 8：导出**刻意**只写一个版本 ——
# 会吐三种方言的写出器就要测三种方言）。
const GP_IMPORT_VERSIONS: Array[String] = ["1.2", "1.3", "1.4"]

# --- PlantInformation fixed fields / PlantInformation 固定字段 ---------------
const GP_DISCIPLINE: String = "PID"
# ASSUMPTION (§9 待确认 1): G-PID world units ARE millimetres. Evidence: GPSheet.gpWidthMM /
# gpHeightMM and GPCanvasText's mm semantics. If this is ever disproved the ENTIRE drawing
# scales by 1000x, which is why the exporter asserts on a known geometry rather than trusting
# the constant.
# 假设（§9 待确认 1）：G-PID 世界单位**就是**毫米。依据：GPSheet.gpWidthMM/gpHeightMM 与
# GPCanvasText 的 mm 语义。若此假设被推翻，整图会缩放 1000 倍 —— 正因如此，导出器对
# 已知几何做断言，而不是只信这个常量。
const GP_UNITS: String = "mm"
const GP_ORIGINATING_SYSTEM: String = "G-PID"

# --- RDL URI domains (§4.3: two domains, never mixed) ----------------------
# Standard classes live under posccaesar; DEXPI's own additions live under the sandbox domain.
# Writing the wrong domain makes the reference unresolvable for the receiver — silently.
# 标准类在 posccaesar 域下；DEXPI 自有的增补在 sandbox 域下。
# 写错域会让接收方**静默地**解析不到引用。
const GP_RDL_POSC: String = "http://data.posccaesar.org/rdl/"
const GP_RDL_SANDBOX: String = "http://sandbox.dexpi.org/rdl/"

# --- authoritative URIs (only those VERIFIED against the spec) -------------
# Policy: URIs are NOT invented. An entry whose URI is unknown ships with an EMPTY URI and a
# report warning (§7.5: 不臆造 / never fabricate). A fabricated URI is worse than a missing
# one — the missing one is visible in the report, the fabricated one resolves to nothing.
# 原则：URI **绝不臆造**。URI 未知的条目以**空 URI** 导出并记 warning（§7.5 不臆造）。
# 臆造的 URI 比缺失的更糟 —— 缺失的在报告里可见，臆造的则解析到空。
const GP_URI_CENTRIFUGAL_PUMP: String = GP_RDL_POSC + "RDS416834"
const GP_URI_PIPING_NETWORK_SYSTEM: String = GP_RDL_POSC + "RDS270359"
const GP_URI_PIPING_NETWORK_SEGMENT: String = GP_RDL_POSC + "RDS267704"
const GP_URI_PROCESS_PLANT: String = GP_RDL_POSC + "RDS7151859"
const GP_URI_MILLIMETRE: String = GP_RDL_POSC + "RDS1357739"
const GP_URI_NOTE_TEXT: String = GP_RDL_SANDBOX + "NoteTextAssignmentClass"

# --- reserved GenericAttributes Set names (§2.3: at most ONE each per parent) --
const GP_SET_DEXPI: String = "DexpiAttributes"
const GP_SET_CUSTOM: String = "DexpiCustomAttributes"

# --- conceptual-layer detection (§4.2) ------------------------------------
# There is NO <ConceptualModel> element in Proteus. The spec says a DexpiModel contains a
# conceptual model IF AND ONLY IF <PlantModel> carries at least one of these children. A
# reader that hunts for a <ConceptualModel> tag will find nothing and conclude "no data".
# Proteus 中**没有** <ConceptualModel> 元素。规范原文：当且仅当 <PlantModel> 含有下列
# 子元素之一时，DexpiModel 才包含概念模型。若 Reader 去找 <ConceptualModel> 标签，
# 它什么也找不到，并会得出「无数据」的错误结论。
const GP_CONCEPTUAL_ELEMENTS: Array[String] = [
	"ActuatingElectricalSystem", "ActuatingSystem", "Drawing", "Equipment",
	"InstrumentationLoopFunction", "MeasuringSystem", "MetaData", "Note",
	"PipingNetworkSystem", "PlantStructureItem",
]

# Namespaces / 命名空间。
const GP_NS_PROTEUS: String = "http://www.proteusxml.org/schemas"
const GP_NS_XSI: String = "http://www.w3.org/2001/XMLSchema-instance"


# Build a posccaesar URI from a bare RDS id.
# 由裸 RDS id 构造 posccaesar URI。
static func gpPoscUri(gpRdsId: String) -> String:
	if gpRdsId.is_empty():
		return ""
	return GP_RDL_POSC + gpRdsId


# Build a sandbox URI from a bare DEXPI-defined name.
# 由裸 DEXPI 自定义名构造 sandbox URI。
static func gpSandboxUri(gpName: String) -> String:
	if gpName.is_empty():
		return ""
	return GP_RDL_SANDBOX + gpName


# Can this version be imported? / 该版本可否导入？
static func gpIsSupportedVersion(gpVersion: String) -> bool:
	return gpVersion in GP_IMPORT_VERSIONS


# Capability table (§1.1): graphics are OUTSIDE the spec through 1.2, informative in 1.3,
# and normative from 1.4. The importer uses this to decide whether it may interpret the
# <Drawing> semantics or must treat shapes as opaque third-party presentation data.
# 能力表（§1.1）：1.2 及以前图形**不在规范范围内**，1.3 为 informative，1.4 起为 normative。
# 导入器据此决定：能否解释 <Drawing> 语义，还是必须把图形当作不透明的第三方呈现数据。
static func gpGraphicsMode(gpVersion: String) -> String:
	if gpVersion == "1.4":
		return "normative"
	if gpVersion == "1.3":
		return "informative"
	return "out_of_scope"


# True when the version's graphics may be interpreted as DEXPI graphics.
# 该版本的图形可否按 DEXPI 图形语义解释。
static func gpGraphicsIsDexpi(gpVersion: String) -> bool:
	return gpGraphicsMode(gpVersion) != "out_of_scope"
