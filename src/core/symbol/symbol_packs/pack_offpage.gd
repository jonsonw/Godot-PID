class_name GPSymbolPackOffpage
extends RefCounted
# Copyright © 2026 Jonson Wang
# Hand-written definitions for the OFF-PAGE CONNECTOR family (ADR-43 D3, W12/S2).
# 手写的 Off-Page 连接符族定义（ADR-43 D3，W12/S2）。
#
# WHY THIS IS NOT A GENERATED PACK / 为何不是生成包：
# tools/gen_symbol_packs.py turns DEXPI C01's SVGs into glyphs. The off-page connector is NOT in
# that reference drawing (its OffPage mapping is explicitly deferred to W22), so its glyph is
# authored here — the same route GPSymbolAnnotationTemplates takes for the note block and the
# table. Geometry still comes from the GENERATOR registry, not from static shapes, for ONE reason:
# the flag carries a text (the peer sheet number) that is DERIVED at render time, and a generator
# is the only place both the canvas (GPSymbolView) and the print model (GPPrintModel) already
# consume from — one glyph, one text, screen and paper cannot drift (ADR-43 D3).
# 生成器只把 DEXPI C01 的 SVG 转成字形，而 Off-Page 连接符**不在**那张参照图里（其 DEXPI 映射
# 明确推迟到 W22），故其字形在此手写 —— 与 GPSymbolAnnotationTemplates 对备注块/表格所走的路
# 相同。几何仍由 GENERATOR 注册表产出而非静态形状，理由只有一条：旗标上要显示**渲染期推导**的
# 对端图纸号，而生成器是画布（GPSymbolView）与打印模型（GPPrintModel）**都已**消费的唯一位置
# —— 一份字形、一段文字，屏幕与纸面不可能分家（ADR-43 D3）。
#
# TWO SYMBOLS ARE ENOUGH TO START (方案 §2.4): one for piping, one for signals. They differ in
# SILHOUETTE and in PORT PURPOSE, never in size — same family, same envelope.
# 两个符号即可起步（方案 §2.4）：管道一个、信号一个。差别在**轮廓**与**端口用途**，绝不在尺寸
# —— 同族同包络。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# The definition ids. "L" = built-in library source, "OFFPAGE" = the category code, so the two
# follow the project's L/C/D naming rule (ADR-17) like every other built-in symbol.
# 定义 id。「L」= 内置库来源码，「OFFPAGE」= 类别码，故二者与其他内置图元一样遵守项目 L/C/D
# 命名规则（ADR-17）。
const GP_ID_PIPE: String = "LOFFPAGE001"
const GP_ID_SIGNAL: String = "LOFFPAGE002"

# The category key. Drives the palette group, the nominal envelope and the tag tier table.
# 类别键。驱动图元库分组、标称包络与字高档位表。
const GP_CATEGORY: String = "offpage"

# The ENTRY port NAME both symbols share. A connector has exactly ONE inbound connection: the
# pipe (or signal) that leaves the other sheet and enters this flag's flat LEFT edge.
# 两个符号共用的**进入**端口名。连接符只有**一个**入站连接：从另一张图纸离开、进入本旗标
# 平直**左**缘的那根管（或那条信号）。
const GP_PORT_NAME: String = "ref"

# The CONTINUATION port NAME: the outbound side that hands the line to the item this flag
# SERVES (user feedback 2026-11-03, second round — the target-sheet twin reads left-to-right,
# so its line leaves from the pennant's TIP, not from a mirrored flat edge). Its nominal unit
# position is the envelope's right edge; the GENERATOR overrides it per instance so the port
# rides the adaptive body's tip (see GPSymbolGeneratorRegistry.gpPortUnitOverrides).
# **续接**端口名：出站一侧，把线交给本旗标**服务**的对象（用户反馈 2026-11-03 第二轮 ——
# 目标纸上的孪生体读向从左到右，故其线从旗标的**尖部**出发，而非镜像后的平直缘）。标称单位
# 位置为包络右缘；**生成器**逐实例覆盖它，使端口贴着自适应主体的旗尖走
#（见 GPSymbolGeneratorRegistry.gpPortUnitOverrides）。
const GP_PORT_CONT: String = "cont"


# The two built-in connector definitions, appended to the library after the annotation templates.
# 两个内置连接符定义，追加在注释模板之后进入图元库。
static func gpDefs() -> Array[GPSymbolDef]:
	var gpOut: Array[GPSymbolDef] = []
	gpOut.append(_gpConnector(GP_ID_PIPE, "sym.offpage_pipe", GPPort.GP_NOZZLE))
	gpOut.append(_gpConnector(GP_ID_SIGNAL, "sym.offpage_signal", GPPort.GP_SIGNAL))
	return gpOut


# One connector definition. The port PURPOSE is the ONLY difference in the data — the generator
# reads it to pick the silhouette, so no id list lives in any renderer (decision D3).
# 一个连接符定义。端口**用途**是数据层唯一的差别 —— 生成器据此挑选轮廓，故任何渲染器里都不存在
# id 名单（决策 D3）。
static func _gpConnector(gpId: String, gpDisplayKey: String, gpPortType: String) -> GPSymbolDef:
	var gpDef: GPSymbolDef = GPSymbolDef.new()
	gpDef.gpId = gpId
	# i18n KEY, matching every other pack's convention (gpTr resolves it per locale).
	# i18n **键**，与其它图元包一致（gpTr 按语种解析）。
	gpDef.gpDisplayName = gpDisplayKey
	gpDef.gpCategory = GP_CATEGORY
	# Envelope from the CATEGORY table — the single source of "how big is this family", so the
	# canvas and the palette thumbnail cannot disagree. Read here instead of duplicating 24x14.
	# 包络取自**类别**表 —— 「这一族多大」的唯一来源，使画布与库缩略图不可能不一致。
	# 在此读取，而不是把 24×14 抄一遍。
	gpDef.gpDefaultSize = GPSymbolCategories.gpSizeFor(GP_CATEGORY)
	gpDef.gpGeometrySource = GPSymbolDef.GP_GEOMETRY_GENERATOR_PREFIX + "offpage"
	# FULL pick (the stage-2 feedback rule: click the thing = select the thing). A connector is a
	# deliberate placement whose whole flag is its click target.
	# FULL 拾取（阶段 2 的反馈规则：点什么选什么）。连接符是刻意摆放的，整个旗标都是点击目标。
	# NOT taggable: a connector is not equipment. Its cross-reference number lives on the LINK
	# (ADR-43 D4), so the project numbering pass must never mint a project tag for it.
	# **不**可编号：连接符不是设备。它的跨图编号存在 **link** 上（ADR-43 D4），故工程编号
	# 流程绝不会为它铸一个项目位号。
	gpDef.gpTaggable = false
	# NOT mountable: dropping a connector onto a vessel must never weld it there (Rev.3 §8 —
	# "not pushed" and "not mounted" are orthogonal, and a connector belongs to no equipment).
	# **不**可挂载：把连接符丢到容器上绝不该焊在那里（Rev.3 §8 —— 「不推挤」与「不挂载」正交，
	# 且连接符不属于任何设备）。
	gpDef.gpMountable = false
	# No static shapes: the generator owns the whole glyph (see the file header).
	# 无静态形状：整个字形归生成器所有（见文件头）。
	gpDef.gpShapes = []
	# TWO ports / 两个端口:
	# - "ref" on the LEFT edge (the side the pipe enters the flag from) — the inbound half.
	#   左缘的 "ref"（管线进入旗标的一侧）—— 入站半边。
	# - "cont" nominally on the RIGHT edge (the envelope's rightmost point at mid height) —
	#   the outbound half toward the served item. The glyph points RIGHT, so the default
	#   orientation reads "continues to the right / outward"; the generator overrides the
	#   cont position per instance so it hugs the adaptive body's tip for ANY reference width.
	#   标称在**右**缘（中高处的最右点）的 "cont" —— 朝向被服务对象的出站半边。字形朝**右**，
	#   故默认朝向读作「向右 / 向外继续」；生成器逐实例覆盖 cont 位置，使任何编号宽度下
	#   它都贴着自适应主体的旗尖。
	var gpPort: GPPort = GPPort.gpMake(GP_PORT_NAME, Vector2(0.0, 0.5), Vector2(-1.0, 0.0),
		gpPortType)
	var gpCont: GPPort = GPPort.gpMake(GP_PORT_CONT, Vector2(1.0, 0.5), Vector2(1.0, 0.0),
		gpPortType)
	gpDef.gpPorts = [gpPort, gpCont]
	# Built-in per decision D3: read-only in the library; editing derives a C-rule copy.
	# 按决策 D3 标记内置：库内只读；编辑时派生 C 规则副本。
	gpDef.gpBuiltin = true
	return gpDef
