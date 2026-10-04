class_name GPTextRole
extends RefCounted
# Copyright © 2026 Jonson Wang
# Standard text heights by drawing role, measured from the v0.1 reference drawing.
# 按图面角色划分的标准字高，实测自 v0.1 参照图。
#
# WHY A ROLE TABLE INSTEAD OF ONE FONT SIZE / 为何用角色表而非单一字号：
# A P&ID does not use one text height. The reference drawing (DEXPI Example C01, kept at
# `图元库/svg_full_pid.svg`) uses five, and which one applies depends on WHAT the text is, not on
# who drew it. Measured with a script over that file (counts of the font-size attribute, grouped
# by the DEXPI label group the text belongs to):
# 一张 P&ID 并不使用单一字高。参照图（DEXPI Example C01，保存于 `图元库/svg_full_pid.svg`）
# 恰好使用五档，用哪一档取决于**这串文字是什么**，而非谁来画。用脚本对该文件实测（按文字所属
# 的 DEXPI 标注组统计 font-size 属性）：
#
#   4.5  mm  equipmenttagnamelabel          x5    设备位号      H1007 / P4711 / T4750
#   3.0  mm  pipingnetworksystemlabel       x11   管线号        MNb 47121 75HB13 80
#   3.0  mm  valvelabel                     x8    阀门标注      66KL21-80
#   3.0  mm  nozzlestandardlabel            x19   管口标注      N1 / 80
#   3.0  mm  processinstrumentation…label   x4    仪表功能标注  PICSA 4712.02
#   3.0  mm  failactionlabel                x3    故障安全位    F.C. / F.O.
#   2.5  mm  label / equipmentbarlabel      x6    标题栏字段    APPROVED BY / DRAWING NO
#   2.85 mm  (border grid reference)        x40   图框栅格参考号 1..9
#   4.0  mm  (drawing title)                x2    图纸标题      DEXPI example PID
#
# So the drawing area has exactly TWO tiers — 4.5 for equipment tags, 3.0 for everything drawn
# in-line — and the title block is its own tier. One global font size cannot express that, which
# is why these values live here, immediately next to the measurement that proves them.
# 故图面区只有**两档** —— 设备位号 4.5、在管标注统一 3.0 —— 标题栏另成一档。单一全局字号无法
# 表达这件事，故这些数值放在此处，紧挨着证明它们的实测数据。
#
# ENFORCED BY TEST / 由测试保证：gp_test_ui_visual_scale.gd pins every number above, and pins
# that the two category tables below cover the whole of GPSymbolCategories.GP_NOMINAL, so a new
# category cannot silently fall out of the standard.
# gp_test_ui_visual_scale.gd 钉住上述每个数值，并钉住下面两张类别表覆盖
# GPSymbolCategories.GP_NOMINAL 的全部键，使新增类别不会悄悄脱离标准。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# The two tiers of the drawing area / 图面区的两档字高。
# 设备位号：equipmenttagnamelabel，C01 中 H1007 / P4711 / T4750 均取此值。
const GP_EQUIPMENT_TAG_MM: float = 4.5
# 在管标注：管线号 / 阀门 / 管口 / 仪表 / 联锁位，C01 中统一取此值。
const GP_INLINE_TAG_MM: float = 3.0

# Title block, drawing title and frame grid reference, per the measurement above.
# 标题栏字段、图纸标题与图框栅格参考号，依上述实测。
const GP_TITLE_FIELD_MM: float = 2.5
const GP_DRAWING_TITLE_MM: float = 4.0
const GP_FRAME_GRID_MM: float = 2.85

# Categories whose tag is an EQUIPMENT tag, i.e. the 4.5 mm tier.
# 其位号属于**设备位号**（4.5mm 档）的类别。
# C01 draws the vessel (T4750), the exchangers (H1007/H1008) and the pumps (P4711/P4712) at
# 4.5 mm; a valve, an instrument bubble or an inline fitting is annotated at 3.0 mm.
# C01 中容器（T4750）、换热器（H1007/H1008）与泵（P4711/P4712）取 4.5mm；阀门、仪表气泡与在管管件
# 均按 3.0mm 标注。
const GP_EQUIPMENT_CATEGORIES: Array = ["tank", "heat", "pump"]

# Categories whose tag is an IN-LINE annotation, i.e. the 3.0 mm tier.
# 其位号属于**在管标注**（3.0mm 档）的类别。
# "general" holds the inline fittings of the C01 pack (tee, reducer, nozzle, blind cover, manhole,
# slope, insulation), all annotated at 3.0 mm like the valve labels next to them.
# "general" 覆盖 C01 包中的在管管件（三通、异径管、接管嘴、盲板、人孔、坡度、保温），其标注与紧邻的
# 阀门标注同为 3.0mm。
const GP_INLINE_CATEGORIES: Array = ["valve", "instrument", "general"]

# Equipment tier divided by in-line tier: 4.5 / 3.0. The scale the standard prescribes BETWEEN
# the two tiers, kept as a named constant so the ratio (not just the endpoints) is pinned.
# 设备档与在管档之比：4.5 / 3.0。标准规定的两档之间的倍数，独立成常量，使被钉住的是**比例**
# 而不只是两个端点值。
const GP_EQUIPMENT_SCALE: float = 1.5


# Tag text height (mm) for a symbol of this category.
# 某类别图元的位号字高（mm）。
# [param gpCategory] GPSymbolDef.gpCategory, e.g. "valve" / 图元定义的类别，如 "valve"
# [param gpBaseMM] the user's symbol font size, used as the IN-LINE tier and as the fallback for
#   an unknown category / 用户设置的图元字号：既作为**在管档**取值，也作为未知类别的兜底
#
# WHY THE RESULT SCALES WITH gpBaseMM INSTEAD OF BEING A HARD 4.5 / 为何结果随 gpBaseMM 缩放而非写死 4.5：
# The standard fixes the RATIO between the two tiers (4.5 : 3.0 == 1.5), not an absolute value, and
# the user's font-size setting is the in-line tier. Returning `gpBaseMM * GP_EQUIPMENT_SCALE`
# therefore reproduces the standard exactly at the default setting (3.0 -> 4.5) while keeping the
# setting meaningful instead of a knob that silently does nothing.
# 标准固定的是两档之间的**比例**（4.5 : 3.0 == 1.5），而非绝对值，而用户字号设置就是在管档。
# 故返回 `gpBaseMM * GP_EQUIPMENT_SCALE`：默认设置下（3.0）精确复现标准（4.5），同时让该设置
# 保持有意义，而不是一个悄悄失效的旋钮。
static func gpTagMM(gpCategory: String, gpBaseMM: float) -> float:
	var gpBase: float = maxf(gpBaseMM, 0.1)
	if GP_EQUIPMENT_CATEGORIES.has(gpCategory):
		return gpBase * GP_EQUIPMENT_SCALE
	if GP_INLINE_CATEGORIES.has(gpCategory):
		return gpBase
	return gpBase


# Text height (mm) for a LABEL SLOT's declared tier (see GPLabelSlot.gpTier).
# 某个**文本槽**所声明字高档的文本高度（mm）（见 GPLabelSlot.gpTier）。
#
# Rationale identical to gpTagMM(): the standard fixes the RATIO between the two tiers, and the
# user's font-size setting IS the in-line tier. A nozzle number / DN and an actuator's F.C./F.O.
# are both measured at 3.0 mm in C01, i.e. the in-line tier — so they need no new tier, only the
# mapping below.
# 理由与 gpTagMM() 相同：标准固定的是两档之间的**比例**，而用户字号设置**就是**在管档。
# 管口编号 / DN 与执行机构的 F.C./F.O. 在 C01 中均实测为 3.0mm，即属于在管档 ——
# 故它们不需要新的档位，只需要下面的映射。
static func gpTierMM(gpTier: String, gpBaseMM: float) -> float:
	var gpBase: float = maxf(gpBaseMM, 0.1)
	if gpTier == "equipment":
		return gpBase * GP_EQUIPMENT_SCALE
	return gpBase


# Text height (mm) for a label SLOT on a symbol of this envelope: the role tier, clamped so the
# text is never taller than the symbol's SHORTER side. A 4x2 mm nozzle annotated at the 3 mm
# in-line tier carried text one and a half times its own height — the reported "the text is too
# big". Equipment is untouched: its shorter side is far above every tier.
# 某包络尺寸图元的标签**槽位**字高（mm）：按角色分档取值，再钳制为**永不超过图元较短边**。
# 4x2mm 的管嘴按 3mm 在管档标注，字高是它自身高度的 1.5 倍 —— 即用户报告的「文字偏大」。
# 设备不受影响：其短边远高于任何分档。
static func gpSlotMM(gpTier: String, gpBaseMM: float, gpEnvelope: Vector2) -> float:
	return minf(gpTierMM(gpTier, gpBaseMM), minf(gpEnvelope.x, gpEnvelope.y))


# Line-number text height (mm) for a pipe.
# 管线的管线号字高（mm）。
# [param gpOverride] the per-project pipe-tag size; 0 or less means "use the standard in-line
#   tier", which is what a line number is annotated at in C01 (3.0 mm)
# [param gpOverride] 项目级管线位号字号；<= 0 表示采用标准在管档 —— C01 中管线号正是 3.0mm
# [param gpBaseMM] the user's symbol font size, i.e. the in-line tier / 用户图元字号，即在管档
static func gpPipeTagMM(gpOverride: float, gpBaseMM: float) -> float:
	if gpOverride > 0.0:
		return gpOverride
	return maxf(gpBaseMM, 0.1)
