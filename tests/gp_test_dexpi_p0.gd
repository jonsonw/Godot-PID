extends "res://tests/gp_test.gd"
# P0 acceptance for the DEXPI foundation: GPDexpiSchema (constants + version capability),
# GPXmlText (escaping / numbers / language tags) and GPDexpiMapping (tables + the two single
# conversion points). Everything here is a pure function, so it runs headless with no autoload.
# DEXPI 地基的 P0 验收：GPDexpiSchema（常量 + 版本能力）、GPXmlText（转义/数字/语言标签）、
# GPDexpiMapping（映射表 + 两个单点转换）。此处全为纯函数，故无需 autoload 即可 headless 运行。
#
# These assertions are deliberately about the failure modes the spec calls out: the ones that
# produce a file that LOOKS valid and is silently wrong (Y direction, 0..1 colour, two-letter
# language, null-as-omitted). A green test run here is the licence to start P1.
# 这些断言刻意针对规范点名的失效模式 —— 那些产出「看起来合法、实则静默错误」文件的模式
# （Y 方向、0..1 颜色、两字母语言、null 即省略）。本套件全绿是进入 P1 的许可。


# ---- schema constants ---------------------------------------------------

func gpTestSchemaVersions() -> void:
	gpEq(GPDexpiSchema.GP_DEXPI_VERSION, "1.4", "DEXPI export version is 1.4")
	gpEq(GPDexpiSchema.GP_PROTEUS_SCHEMA_VERSION, "4.2.0", "Proteus schema is 4.2.0")
	gpCheck(GPDexpiSchema.GP_IMPORT_VERSIONS.has("1.2"), "import accepts 1.2")
	gpCheck(GPDexpiSchema.GP_IMPORT_VERSIONS.has("1.3"), "import accepts 1.3")
	gpCheck(GPDexpiSchema.GP_IMPORT_VERSIONS.has("1.4"), "import accepts 1.4")


# The capability table drives the importer's degradation (§7.5). Getting 1.2 wrong means
# interpreting graphics the spec never defined.
# 该能力表驱动导入器的降级（§7.5）。把 1.2 判错意味着去解释规范从未定义的图形。
func gpTestGraphicsCapabilityByVersion() -> void:
	gpEq(GPDexpiSchema.gpGraphicsMode("1.2"), "out_of_scope", "1.2 graphics are outside the spec")
	gpEq(GPDexpiSchema.gpGraphicsMode("1.3"), "informative", "1.3 graphics are informative")
	gpEq(GPDexpiSchema.gpGraphicsMode("1.4"), "normative", "1.4 graphics are normative")
	gpCheck(not GPDexpiSchema.gpGraphicsIsDexpi("1.2"), "1.2 graphics must not be read as DEXPI")
	gpCheck(GPDexpiSchema.gpGraphicsIsDexpi("1.3"), "1.3 graphics may be read as DEXPI")
	gpCheck(GPDexpiSchema.gpGraphicsIsDexpi("1.4"), "1.4 graphics may be read as DEXPI")
	gpCheck(GPDexpiSchema.gpIsSupportedVersion("1.4"), "1.4 is importable")
	gpCheck(not GPDexpiSchema.gpIsSupportedVersion("0.9"), "unknown versions are refused")


# Two RDL domains that must never be mixed (§4.3 易错点②).
# 两个绝不可混用的 RDL 域（§4.3 易错点②）。
func gpTestRdlDomains() -> void:
	gpEq(GPDexpiSchema.gpPoscUri("RDS416834"),
		"http://data.posccaesar.org/rdl/RDS416834", "posccaesar URI shape")
	gpEq(GPDexpiSchema.gpSandboxUri("NoteTextAssignmentClass"),
		"http://sandbox.dexpi.org/rdl/NoteTextAssignmentClass", "sandbox URI shape")
	gpEq(GPDexpiSchema.gpPoscUri(""), "", "empty id yields empty URI (never a bare domain)")
	gpEq(GPDexpiSchema.GP_URI_CENTRIFUGAL_PUMP,
		"http://data.posccaesar.org/rdl/RDS416834", "CentrifugalPump URI is the verified one")
	gpCheck(GPDexpiSchema.GP_URI_NOTE_TEXT.begins_with(GPDexpiSchema.GP_RDL_SANDBOX),
		"NoteText lives in the sandbox domain")


# There is no <ConceptualModel> element; detection is by child presence (§4.2).
# 没有 <ConceptualModel> 元素；判定依据是子元素是否出现（§4.2）。
func gpTestConceptualDetectionList() -> void:
	var gpList: Array[String] = GPDexpiSchema.GP_CONCEPTUAL_ELEMENTS
	gpCheck(gpList.size() >= 8, "detection list is populated")
	for gpName in ["Equipment", "PipingNetworkSystem", "Drawing", "Note"]:
		gpCheck(gpList.has(gpName), "detection list contains " + gpName)
	gpCheck(not gpList.has("ConceptualModel"), "ConceptualModel is NOT an element name")


# ---- XML text -----------------------------------------------------------

# `&` must be escaped first, or the replacements get re-escaped.
# `&` 必须最先转义，否则替换产物会被二次转义。
func gpTestEscape() -> void:
	gpEq(GPXmlText.gpEscape("a & b"), "a &amp; b", "ampersand escaped")
	gpEq(GPXmlText.gpEscape("a<b>c"), "a&lt;b&gt;c", "angle brackets escaped")
	gpEq(GPXmlText.gpEscape("say \"hi\""), "say &quot;hi&quot;", "quotes escaped")
	gpEq(GPXmlText.gpEscape("it's"), "it&apos;s", "apostrophe escaped")
	gpEq(GPXmlText.gpEscape("&amp;"), "&amp;amp;", "an existing entity is escaped, not preserved")


# Numbers must read like the spec's examples: no trailing zeros, no "-0".
# 数字须与规范示例一致：无尾随零、无 "-0"。
func gpTestNumberFormatting() -> void:
	gpEq(GPXmlText.gpNum(2.0), "2", "integral values drop the fraction")
	gpEq(GPXmlText.gpNum(0.498), "0.498", "normalised colour keeps three decimals")
	gpEq(GPXmlText.gpNum(-0.0), "0", "negative zero serialises as 0")
	gpEq(GPXmlText.gpNum(0.0), "0", "zero serialises as 0")
	gpEq(GPXmlText.gpNum(NAN), "0", "NaN degrades to 0 rather than poisoning the file")
	gpEq(GPXmlText.gpNum(INF), "0", "Infinity degrades to 0")
	gpEq(GPXmlText.gpNum(1.0), "1", "one serialises as 1")
	gpEq(GPXmlText.gpNum(0.5, 1), "0.5", "explicit decimals are honoured")


# Language tags: exactly two letters (§4.5 hard constraint).
# 语言标签：恰好两字母（§4.5 硬约束）。
func gpTestLanguageTag() -> void:
	gpEq(GPXmlText.gpLang2("zh"), "zh", "bare zh passes through")
	gpEq(GPXmlText.gpLang2("en"), "en", "bare en passes through")
	gpEq(GPXmlText.gpLang2("zh-CN"), "zh", "zh-CN is trimmed to zh")
	gpEq(GPXmlText.gpLang2("en-US"), "en", "en-US is trimmed to en")
	gpEq(GPXmlText.gpLang2("de-CH-1996"), "de", "a long tag is trimmed to its first two letters")
	gpEq(GPXmlText.gpLang2(""), "", "empty stays empty")


# null means OMIT the attribute (§6.5 risk 2): never write name="".
# null 意味着**省略**该属性（§6.5 风险 2）：绝不写 name=""。
func gpTestAttributeOmission() -> void:
	gpEq(GPXmlText.gpAttr("Value", ""), "", "empty value yields no attribute at all")
	gpEq(GPXmlText.gpAttr("Value", "36"), "Value=\"36\"", "non-empty value yields an attribute")
	gpEq(GPXmlText.gpAttr("Value", "a&b"), "Value=\"a&amp;b\"", "attribute values are escaped")
	gpEq(GPXmlText.gpAttrs(["A=\"1\"", "", "B=\"2\""]), "A=\"1\" B=\"2\"",
		"empty fragments are dropped from the join")


func gpTestTagShapes() -> void:
	gpEq(GPXmlText.gpOpen("Equipment", "ID=\"p1\"", 1), "  <Equipment ID=\"p1\">", "open tag")
	gpEq(GPXmlText.gpClose("Equipment", 1), "  </Equipment>", "close tag")
	gpEq(GPXmlText.gpSelf("Coordinate", "X=\"1\"", 2), "    <Coordinate X=\"1\"/>", "self-closing tag")
	gpEq(GPXmlText.gpOpen("Equipment", "", 0), "<Equipment>", "no attrs means no stray space")
	gpEq(GPXmlText.gpIndent(3), "      ", "indent is two spaces per level")


# ---- mapping tables -----------------------------------------------------

# A table-wide test: this is only possible BECAUSE the mapping is data, not branches (§7.1).
# 全表测试：正因映射是**数据**而非分支，这种测试才可能成立（§7.1）。
func gpTestSymbolTableIntegrity() -> void:
	var gpIds: Array[String] = GPDexpiMapping.gpAllSymbolIds()
	gpCheck(gpIds.size() >= 20, "symbol table covers the DEXPI pack")
	var gpRoles: Dictionary = {}
	for gpId in gpIds:
		var gpRow: Dictionary = GPDexpiMapping.gpComponentFor(gpId)
		gpCheck(not gpRow.is_empty(), "row present for " + gpId)
		var gpRole: String = str(gpRow.get("role", ""))
		gpRoles[gpRole] = int(gpRoles.get(gpRole, 0)) + 1
		# An annotation has no class name on purpose; everything else must have one.
		# 纯图形条目刻意无类名；其余必须有类名。
		if gpRole != GPDexpiMapping.GP_ROLE_ANNOTATION:
			gpCheck(str(gpRow.get("class", "")) != "", "class name present for " + gpId)
		# URI policy: either verified or deliberately empty. Never a guess.
		# URI 原则：要么已核实、要么刻意留空。绝不允许猜测值。
		var gpUri: String = str(gpRow.get("uri", ""))
		gpCheck(gpUri == "" or gpUri.begins_with("http://"),
			"uri is empty or a full URL for " + gpId)
	gpCheck(int(gpRoles.get(GPDexpiMapping.GP_ROLE_EQUIPMENT, 0)) >= 10, "equipment rows present")
	gpCheck(int(gpRoles.get(GPDexpiMapping.GP_ROLE_ANNOTATION, 0)) >= 4, "annotation rows present")
	gpCheck(int(gpRoles.get(GPDexpiMapping.GP_ROLE_PIPING, 0)) >= 3, "piping component rows present")


func gpTestAttributeTableIntegrity() -> void:
	var gpKeys: Array[String] = GPDexpiMapping.gpAllAttributeKeys()
	gpCheck(gpKeys.size() >= 6, "attribute table is populated")
	for gpKey in gpKeys:
		var gpRow: Dictionary = GPDexpiMapping.gpAttributeFor(gpKey)
		if bool(gpRow.get("internal", false)):
			continue
		gpCheck(str(gpRow.get("name", "")) != "", "name present for " + gpKey)
		var gpFormat: String = str(gpRow.get("format", ""))
		gpCheck(gpFormat in ["integer", "string", "double", "anyURI"],
			"format is a spec value for " + gpKey)
		# Units and UnitsURI travel together: one without the other is a physical quantity
		# the receiver cannot resolve.
		# Units 与 UnitsURI 必须成对：缺其一即为接收方无法解析的物理量。
		var gpUnits: String = str(gpRow.get("units", ""))
		var gpUnitsUri: String = str(gpRow.get("units_uri", ""))
		gpCheck(gpUnits == "" or gpUnitsUri != "", "units carry a UnitsURI for " + gpKey)


# ★ THE TWO DIRECTIONS MUST BE ONE RULE / ★ 两个方向必须是同一条规则：
# the forward map is table-driven (gpAttributeFor), so the reverse one has to be too. Stripping
# "AssignmentClass" and de-camel-casing recovers the key ONLY when the DEXPI name IS its
# camelCase — and four rows deliberately are not. They used to come back under a name that no
# schema field, inspector row or exporter branch matches (dn -> "nominal_diameter",
# medium -> "fluid", spec -> "piping_class", insulation -> "insulation_thickness"), i.e. the
# value WAS read and was then invisible to the whole application.
# 正向映射是**表驱动**的（gpAttributeFor），故反向也必须是。去掉 "AssignmentClass" 再转
# snake_case **只**在 DEXPI 名恰为该键的 camelCase 时成立 —— 而四行刻意不是。
# 它们过去会以没有任何 schema 字段 / 检查器行 / 导出器分支匹配的名字回来
#（dn -> "nominal_diameter"、medium -> "fluid"、spec -> "piping_class"、
# insulation -> "insulation_thickness"），即值**确实**读到了，随后对整个应用不可见。
func gpTestAttributeNamesRoundTripThroughTheTable() -> void:
	var gpKeys: Array[String] = GPDexpiMapping.gpAllAttributeKeys()
	gpCheck(gpKeys.size() >= 6, "attribute table is populated")
	var gpNamed: int = 0
	for gpKey in gpKeys:
		var gpRow: Dictionary = GPDexpiMapping.gpAttributeFor(gpKey)
		if bool(gpRow.get("internal", false)):
			continue
		gpNamed += 1
		var gpName: String = str(gpRow.get("name", ""))
		gpEq(GPDexpiMapping.gpKeyForAttributeName(gpName), gpKey,
			"the DEXPI name maps back to the key it came from: " + gpName)
	gpCheck(gpNamed >= 6, "checked a non-empty set of exported attribute names")
	# The four rows the mechanical rule ALONE gets wrong, pinned by name so a future
	# "simplification" back to stripping cannot pass in silence.
	# 机械规则**单独**会弄错的四行，按名字钉住，使日后「简化」回纯去后缀无法悄悄通过。
	gpEq(GPDexpiMapping.gpKeyForAttributeName("NominalDiameterAssignmentClass"), "dn",
		"dn is not recovered by stripping (that would invent 'nominal_diameter')")
	gpEq(GPDexpiMapping.gpKeyForAttributeName("FluidAssignmentClass"), "medium",
		"medium is not recovered by stripping (that would invent 'fluid')")
	gpEq(GPDexpiMapping.gpKeyForAttributeName("PipingClassAssignmentClass"), "spec",
		"spec is not recovered by stripping (that would invent 'piping_class')")
	gpEq(GPDexpiMapping.gpKeyForAttributeName("InsulationThicknessAssignmentClass"), "insulation",
		"insulation is not recovered by stripping (that would invent 'insulation_thickness')")
	gpEq(GPDexpiMapping.gpKeyForAttributeName("NoSuchAssignmentClass"), "",
		"an unknown name maps to nothing rather than to a guess")


# Unknown ids must degrade, never vanish (§7.5 降级 ③).
# 未知 id 必须降级，绝不消失（§7.5 降级 ③）。
func gpTestUnknownFallbacks() -> void:
	var gpC: Dictionary = GPDexpiMapping.gpComponentFor("DNOTREAL999")
	gpCheck(str(gpC.get("class", "")).begins_with("Custom"), "unknown symbol falls back to Custom*")
	gpCheck(bool(gpC.get("unknown", false)), "unknown row is flagged")
	gpEq(str(gpC.get("uri", "")), "", "unknown row has no invented URI")
	var gpA: Dictionary = GPDexpiMapping.gpAttributeFor("some_future_key")
	gpEq(str(gpA.get("name", "")), "someFutureKeyAssignmentClass",
		"unknown key becomes camelCase + AssignmentClass")
	gpCheck(bool(gpA.get("custom", false)), "unknown attribute is flagged custom")


# Risk 8: UI/layout state must not reach the exported file.
# 风险 8：界面/布局状态不得进入导出件。
func gpTestInternalKeysAreNotExported() -> void:
	gpCheck(GPDexpiMapping.gpIsInternal("tag_offset"), "tag_offset is layout-only, never exported")
	gpCheck(not GPDexpiMapping.gpIsInternal("dn"), "dn is a real engineering attribute")
	gpCheck(not GPDexpiMapping.gpIsInternal("volume"), "volume is a real engineering attribute")


func gpTestCamelCase() -> void:
	gpEq(GPDexpiMapping.gpCamelOf("design_pressure"), "designPressure", "snake to camel")
	gpEq(GPDexpiMapping.gpCamelOf("dn"), "dn", "single word unchanged")
	gpEq(GPDexpiMapping.gpCamelOf("a_b_c"), "aBC", "multi-part conversion")


# ---- single conversion points -------------------------------------------

# Risk 1: the Y flip. Self-inverse so one function serves both directions.
# 风险 1：Y 翻转。自反，故一个函数同时服务两个方向。
func gpTestFlipY() -> void:
	gpEq(GPDexpiMapping.gpFlipY(40.0), -40.0, "conceptual Y 40 becomes file Y -40")
	gpEq(GPDexpiMapping.gpFlipY(-60.0), 60.0, "conceptual Y -60 becomes file Y 60")
	gpEq(GPDexpiMapping.gpFlipY(0.0), 0.0, "zero is unchanged")
	# Self-inverse: this is the property that lets export and import share one function.
	# 自反性：正是这个性质让导出与导入共用同一函数。
	for gpV in [0.0, 12.5, -37.25, 420.0]:
		gpApprox(GPDexpiMapping.gpFlipY(GPDexpiMapping.gpFlipY(gpV)), gpV, 1e-9,
			"flip is self-inverse for " + str(gpV))
	# A known diagonal: both ends must flip, so the slope inverts.
	# 一条已知斜线：两端都翻转，故斜率反转。
	var gpA: Vector2 = Vector2(-30.0, 40.0)
	var gpB: Vector2 = Vector2(50.0, -60.0)
	var gpFA: Vector2 = Vector2(gpA.x, GPDexpiMapping.gpFlipY(gpA.y))
	var gpFB: Vector2 = Vector2(gpB.x, GPDexpiMapping.gpFlipY(gpB.y))
	gpEq(gpFA, Vector2(-30.0, -40.0), "first point flips")
	gpEq(gpFB, Vector2(50.0, 60.0), "second point flips")
	gpApprox(gpFA.y - gpFB.y, -(gpA.y - gpB.y), 1e-9, "slope sign inverts under the flip")


# Risk 3: colour must be 0..1, not 0..255.
# 风险 3：颜色必须是 0..1，而非 0..255。
# NOTE ON EPSILON / 关于误差的说明：Godot's Color channels are SINGLE precision, so
# Color(0, 0.498, 1) actually holds 0.49799999594688. Assertions on colour must use 1e-6,
# not the 1e-9 that works for GDScript's own (double) floats. Using 1e-9 here produces a
# failure that looks like a mapping bug but is purely a precision artefact.
# 注意：Godot 的 Color 通道是**单精度**，故 Color(0, 0.498, 1) 实际持有 0.49799999594688。
# 颜色断言必须用 1e-6，而非适用于 GDScript 自身（双精度）浮点的 1e-9。
# 此处若用 1e-9，会得到一个看似映射缺陷、实则纯精度假象的失败。
func gpTestNormalisedRgb() -> void:
	var gpBlack: Array = GPDexpiMapping.gpNormRgb(Color(0.0, 0.0, 0.0))
	gpApprox(float(gpBlack[0]), 0.0, 1e-6, "black R is 0")
	var gpWhite: Array = GPDexpiMapping.gpNormRgb(Color(1.0, 1.0, 1.0))
	gpApprox(float(gpWhite[2]), 1.0, 1e-6, "white B is 1")
	# The spec's own example: #007fff -> R=0 G=0.498 B=1.
	# 规范自身示例：#007fff -> R=0 G=0.498 B=1。
	var gpSpec: Array = GPDexpiMapping.gpNormRgb(Color(0.0, 0.498, 1.0))
	gpApprox(float(gpSpec[1]), 0.498, 1e-6, "spec example green channel")
	gpApprox(float(GPXmlText.gpNum(float(gpSpec[1]))), 0.498, 1e-6,
		"the channel survives formatting as 0.498")
	# Out-of-range input is clamped rather than overflowing into the file.
	# 越界输入被钳制，而非溢出进文件。
	var gpOver: Array = GPDexpiMapping.gpNormRgb(Color(2.5, -1.0, 0.5))
	gpApprox(float(gpOver[0]), 1.0, 1e-6, "above 1 clamps to 1")
	gpApprox(float(gpOver[1]), 0.0, 1e-6, "below 0 clamps to 0")
