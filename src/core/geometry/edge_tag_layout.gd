class_name GPEdgeTagLayout
extends RefCounted
# Copyright © 2026 Jonson Wang
# Where a line number sits on its pipe.
# 管线编号落在其管线的什么位置。
#
# The drafting rule / 制图规则：
# "number sits above a horizontal run, to the left of a vertical one". "Above / left" is
# defined in SCREEN space (y grows downwards), not along the line's own direction, so a pipe
# drawn right-to-left still gets its number above — otherwise flipping two symbols would flip
# the drawing convention with them.
# 「编号位于水平管正上方、竖管左侧」。「上方 / 左侧」以屏幕空间定义（y 向下增长），而非
# 沿管线自身方向 —— 否则把两个图元左右对调，制图约定也会跟着翻转。
#
# ... and WHICH of those two rules applies is decided by the LEG the number is over — not by the
# pipe as a whole. A routed pipe turns corners, so its longest leg can be vertical while the number
# has been dragged onto one of its horizontal legs; the number must then read LEFT-TO-RIGHT. Only a
# number still over a VERTICAL leg stands as a column. Deciding this per-pipe (which is what the
# code did) left a number dragged onto a horizontal leg stuck as an upside-down column.
# ... 而这两条规则之中适用哪一条，取决于编号所压的**那一段** —— 而非整条管线。布线后的管线会拐角，
# 其最长段可以是竖直的、而编号已被拖到它的某条水平段上；此时编号必须**自左向右**阅读。唯有仍压在
# **竖直**段上的编号才立为竖排字列。按「整条管线」判定（代码原先的做法）会让拖到水平段上的编号
# 卡在竖排形态。
#
# ... and a number that has been pulled CLEAR of its pipe is laid FLAT, with its shelf beneath it.
# 而一旦编号被拉离其管线，则一律**放平**，托线位于其下方。
# The rotation above is a space-saving device that only makes sense while the number hugs its pipe;
# once it is a detached callout, horizontal is the reading direction. gpPlaceCallout() applies that
# rule — it is the ONE entry point the renderer uses, so placement and leader are decided together
# and can never disagree.
# 上述旋转是仅在编号贴着管线时才成立的省地方手段；一旦成为脱离的引出标注，阅读方向即为横排。
# gpPlaceCallout() 执行该规则 —— 它是渲染层唯一入口，故落位与引出线一并判定，永不会各执一词。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Clearance between the pipe centre-line and the text BASELINE (== the bottom edge of digits and
# capitals, which is all a line number ever contains).
# 管线中心线与文字**基线**（＝数字与大写字母的底边，而管线号只由这两类字符构成）之间的净距。
#
# WHY 2.5 AND NOT THE OLD 8.0 / 为何是 2.5 而非旧的 8.0：
# 8.0 mm is 2.7x the 3.0 mm in-line text height, so the number visibly detached from its pipe and
# read as a floating note rather than an annotation OF that pipe — the reported "管线号离管线太远".
# Reference sheets keep the bottom of the number about one character height off the line; 2.5 mm
# still leaves the glyph 1.6 mm clear of the 1.75 mm-wide flow arrow drawn underneath it, while
# making the attachment unmistakable.
# 8.0mm 是 3.0mm 在管字高的 2.7 倍，编号会明显脱离其管线，读起来像一条浮在空中的注释而非
# 「属于该管线」的标注 —— 即用户报告的「管线号离管线太远」。参照图中编号底边距管线约一个字高；
# 2.5mm 仍在字形与下方 1.75mm 宽的流向箭头之间留出 1.6mm，同时让从属关系一目了然。
const GP_GAP: float = 2.5

# Clearance beyond which a detached number acquires a LEADER line back to its pipe.
# 脱离的编号超过此净距，即获得一条指回其管线的**引出线**。
# Expressed as a MULTIPLE of the default clearance: within twice the default distance the eye
# still pairs the number with its pipe, so no line is needed; beyond it that pairing is no longer
# self-evident and the leader has to state it. Derived from GP_GAP rather than hard-coded so that
# re-tuning the gap keeps the "when is it detached?" decision consistent with it.
# 以默认净距的**倍数**表达：两倍默认距离以内，眼睛仍能把编号与其管线配对，故不必画线；超出后这种
# 配对不再不证自明，必须由引出线明示。由 GP_GAP 推导而非硬编码，使调整净距时「何时算脱离」的
# 判定与之保持一致。
const GP_LEADER_MIN: float = GP_GAP * 2.0

# Distance from the text BASELINE down to the leader's horizontal shoulder.
# 文字基线向下到引出线水平肩线的距离。
# The shoulder is a drafting "shelf": it cradles the number instead of leaving it to float, and it
# is what makes the leader read as a callout rather than as a second underline that happened to
# land near the glyphs.
# 肩线即制图中的「托线」：它托住编号而非任其悬浮，也是让引出线读作「标注引出」而非
# 「碰巧落在字形附近的第二条下划线」的关键。
const GP_LEADER_PAD: float = 1.2

# How far the shoulder extends past the text on each side.
# 肩线在文字两侧各延伸的长度。
# A shoulder ending flush with the glyphs looks clipped; the small overhang makes it look drawn.
# 与字形齐平的肩线看起来像被裁掉了；这点外伸使其看起来是「画出来的」。
const GP_LEADER_OVERHANG: float = 1.0

# Angle of the leader's slanted segment, measured from the horizontal.
# 引出线斜段相对水平方向的夹角。
# 60 deg is the steepest of the conventional leader angles (30 / 45 / 60) and the one the reference
# sheet uses: steep enough that the shoulder never crowds the glyphs, slanted enough that the
# segment is unmistakably a leader and not a stray perpendicular tick — which is what the earlier
# straight box-to-pipe segment read as.
# 60° 是常规引出线夹角（30 / 45 / 60）中最陡的一个，也是参照图所用者：够陡，使肩线不挤占字形；
# 又够斜，使该段明确是引出线而非一道游离的垂直短线 —— 前者（盒到管线的直连线）正是原来读起来的样子。
const GP_LEADER_ANGLE_DEG: float = 60.0


# Index of the longest leg, or -1 when the polyline has none.
# 最长段的索引；折线无段时返回 -1。
# The longest leg is used because it is the leg a reader's eye follows first, and it is the only
# leg guaranteed to have room for the whole number on a short zig-zag.
# 取最长段是因为读者的视线首先落在它上面，且在短促的 Z 形走线中，也只有它保证放得下整个编号。
static func gpLongestSegment(gpPts: PackedVector2Array) -> int:
	if gpPts.size() < 2:
		return -1
	var gpBest: int = 0
	var gpBestLen: float = -1.0
	for gpI in range(gpPts.size() - 1):
		var gpL: float = gpPts[gpI].distance_to(gpPts[gpI + 1])
		if gpL > gpBestLen:
			gpBestLen = gpL
			gpBest = gpI
	return gpBest


# Index of the polyline leg nearest gpP (each leg's perpendicular foot, clamped into that leg), or
# -1 when the polyline is degenerate: fewer than two points, or every leg of zero length.
# 折线上距 gpP 最近的那一段的索引（各段取其夹到段内的垂足）；折线退化时返回 -1：
# 点少于两个，或各段皆零长。
# Shared by gpNearestOnPolyline() so "the nearest point" and "the leg it lies on" can never be two
# different legs — the orientation rule reads the leg, while the leader anchors on the point.
# 与 gpNearestOnPolyline() 共用，使「最近点」与「该点所在的那一段」永不会是两段不同的段 —— 方向规则
# 读的是段，而引出线锚的是点。
static func gpNearestSegment(gpPts: PackedVector2Array, gpP: Vector2) -> int:
	if gpPts.size() < 2:
		return -1
	var gpBest: int = -1
	var gpBestD: float = INF
	for gpI in range(gpPts.size() - 1):
		if (gpPts[gpI + 1] - gpPts[gpI]).length_squared() <= 1e-9:
			continue
		var gpD: float = gpP.distance_to(_gpFoot(gpPts, gpI, gpP))
		if gpD < gpBestD:
			gpBestD = gpD
			gpBest = gpI
	return gpBest


# Perpendicular foot of gpP on leg gpI, clamped into that leg.
# gpP 在段 gpI 上的垂足，并夹到该段之内。
static func _gpFoot(gpPts: PackedVector2Array, gpI: int, gpP: Vector2) -> Vector2:
	var gpA: Vector2 = gpPts[gpI]
	var gpSeg: Vector2 = gpPts[gpI + 1] - gpA
	var gpLen2: float = gpSeg.length_squared()
	if gpLen2 <= 1e-9:
		return gpA
	return gpA + gpSeg * clampf((gpP - gpA).dot(gpSeg) / gpLen2, 0.0, 1.0)


# Nearest point ON the polyline to an arbitrary point (perpendicular foot, clamped to each
# segment). A degenerate polyline returns gpP itself, so callers never receive INF.
# 折线上距任意点最近的点（各段的垂足，并夹到段内）。折线退化时返回 gpP 本身，故调用方永不会收到 INF。
static func gpNearestOnPolyline(gpPts: PackedVector2Array, gpP: Vector2) -> Vector2:
	var gpI: int = gpNearestSegment(gpPts, gpP)
	if gpI < 0:
		return gpP
	return _gpFoot(gpPts, gpI, gpP)


# Is the leg nearest gpP a VERTICAL one? — i.e. does the vertical drafting rule (a column beside the
# pipe) apply HERE, rather than the horizontal rule (a caption above it)?
# gpP 最近的那一段是竖直段吗？—— 即此处适用「竖管字列」规则，还是「水平管上方标注」规则？
# Evaluated AT THE NUMBER, not for the pipe as a whole: see the header. A routed pipe that turns a
# corner carries one leg of each orientation, and the number can be dragged from one onto the other.
# Ties (a 45 deg leg) go to the horizontal rule, which is also what an unmeasurable/degenerate
# polyline gets — a readable horizontal number is the safe answer in every doubtful case.
# 在**编号处**判定，而非整条管线（见文件头）：拐过角的管线同时带有一条竖直段与一条水平段，而编号可以
# 从一段被拖到另一段上。正 45° 的段归入水平规则，退化 / 不可测的折线同样如此 —— 任何存疑情形下，
# 「横排可读」都是安全的答案。
static func gpIsVerticalAt(gpPts: PackedVector2Array, gpP: Vector2) -> bool:
	var gpI: int = gpNearestSegment(gpPts, gpP)
	if gpI < 0:
		return false
	var gpD: Vector2 = gpPts[gpI + 1] - gpPts[gpI]
	return absf(gpD.y) > absf(gpD.x)


# The point of a rectangle closest to an outside point — a plain per-axis clamp. A point already
# inside the rectangle yields itself, which is the correct degenerate answer for the leader test.
# 矩形上距外部点最近的点 —— 即逐轴夹取。点已在矩形内时返回其自身，这对引出线判定正是正确的退化答案。
static func gpClampToRect(gpRect: Rect2, gpP: Vector2) -> Vector2:
	return Vector2(
		clampf(gpP.x, gpRect.position.x, gpRect.end.x),
		clampf(gpP.y, gpRect.position.y, gpRect.end.y))


# Place a tag on a polyline.
# 把位号放到折线上。
# [param gpPts] the routed polyline / 已完成布线的折线
# [param gpTextW] measured text width in world units / 实测文字宽度（世界单位）
# [param gpTextH] measured text height in world units / 实测文字高度（世界单位）
# [param gpRotate] rotate the text -90 deg when the number sits on a VERTICAL leg
#   / 编号位于**竖直**段上时是否把文字旋转 -90°
# [param gpGap] clearance override / 净距覆盖值
# [param gpOffset] manual drag offset in world units (mm), applied AFTER the automatic placement
#   / 手工拖拽偏移，世界单位（mm），在自动落位**之后**施加
# [return] {"pos": Vector2, "rot": float, "vertical": bool, "anchor": Vector2}
# pos is the text ORIGIN (draw_string's baseline start), in world coordinates and already
# carrying gpOffset. "vertical" answers "is the leg UNDER THE NUMBER vertical?" — it is the local
# question, not the pipe's. anchor is the point on the pipe this number belongs to (the longest
# leg's midpoint) — where a leader line points back to.
# pos 是文字原点（draw_string 的基线起点），已是世界坐标且已含 gpOffset。"vertical" 回答的是
# 「编号**底下那一段**是否竖直」—— 这是局部问题，而非整条管线的问题。anchor 是编号所属的管线上那
# 一点（最长段中点）—— 引出线指回的位置。
#
# The leg that decides the form is looked up at the number's own place — the placement anchor shifted
# by the manual drag. Using the offset (rather than the finished box) keeps the lookup a pure
# function of the stored data: the box would depend on the form it is being used to choose, so the
# two could chase each other. See gpIsVerticalAt().
# 决定形态的那一段，是在**编号自身所在处**查得的 —— 即落位锚点加上手工拖拽量。用偏移量（而非最终的
# 包围盒）使该查询成为所存数据的纯函数：包围盒会依赖于「正由它来选定」的那个形态，两者会互相追逐。
# 见 gpIsVerticalAt()。
static func gpPlace(gpPts: PackedVector2Array, gpTextW: float, gpTextH: float,
		gpRotate: bool, gpGap: float = GP_GAP, gpOffset: Vector2 = Vector2.ZERO) -> Dictionary:
	var gpI: int = gpLongestSegment(gpPts)
	if gpI < 0:
		return {"pos": Vector2.ZERO, "rot": 0.0, "vertical": false, "anchor": Vector2.ZERO}
	var gpA: Vector2 = gpPts[gpI]
	var gpB: Vector2 = gpPts[gpI + 1]
	var gpMid: Vector2 = (gpA + gpB) * 0.5
	# WHICH rule applies is read at the number, not from the longest leg: dragging the number onto a
	# horizontal leg of the same pipe must turn it horizontal, and back into a column only when it
	# returns over a vertical leg. With no drag the probe sits ON the longest leg (its midpoint), so
	# the default placement is unchanged, leg for leg.
	# 适用哪条规则是在**编号处**读得的，而非取自最长段：把编号拖到同一管线的水平段上就该让它横排，
	# 唯有再回到竖直段上时才重新立为字列。未拖拽时探查点正落在最长段上（其中点），故默认落位逐段不变。
	var gpVertical: bool = gpIsVerticalAt(gpPts, gpMid + gpOffset)
	# The offset is added LAST and in world units, so where the number ends up is independent of
	# the zoom — the same reason the manual offset is stored in mm rather than pixels.
	# 偏移在**最后**加入且以世界单位计，故编号落点与缩放无关 —— 这正是手工偏移按 mm 而非像素存储的原因。
	if not gpVertical:
		# Horizontal run: centred, sitting on top of the line.
		# 水平管：居中，位于管线正上方。
		return {
			"pos": Vector2(gpMid.x - gpTextW * 0.5, gpMid.y - gpGap) + gpOffset,
			"rot": 0.0,
			"vertical": false,
			"anchor": gpMid,
		}
	if gpRotate:
		# Rotated -90 deg: the text baseline runs bottom-to-top, so the origin starts half a
		# text-width BELOW the midpoint and the glyph column is nudged right by half its height
		# so the column (not the baseline) is what sits gpGap to the left of the pipe.
		# 旋转 -90°：文字基线自下而上，故原点起于中点「下方」半个文字宽度处；字形列再右移
		# 半个字高，使「字形列（而非基线）」位于管线左侧 gpGap 处。
		return {
			"pos": Vector2(gpMid.x - gpGap + gpTextH * 0.5, gpMid.y + gpTextW * 0.5) + gpOffset,
			"rot": -PI * 0.5,
			"vertical": true,
			"anchor": gpMid,
		}
	# Unrotated: keep it readable, right-aligned to the pipe.
	# 不旋转：保持可读，右对齐到管线。
	return {
		"pos": Vector2(gpMid.x - gpGap - gpTextW, gpMid.y + gpTextH * 0.35) + gpOffset,
		"rot": 0.0,
		"vertical": true,
		"anchor": gpMid,
	}


# The glyph box in world coordinates, from a placement plus the measured text size.
# 由落位结果与实测文字尺寸推出字形包围盒（世界坐标）。
#
# THE BOX IS ANCHORED ON THE BASELINE, NOT CENTRED ON IT / 包围盒以**基线**为基准，而非居中：
# draw_string() takes the baseline, and a line number never descends below it, so pos IS the
# bottom edge and the glyph occupies exactly gpTextH above it. Treating the box as centred (which
# the symbol-label path does, because THERE the anchor is a box centre) would overstate the
# clearance by half a text height and fire the leader while the number still touches its pipe.
# draw_string() 以基线为起点，而管线号从不落到基线之下，故 pos 就是底边、字形恰好占据其上 gpTextH。
# 若按居中处理（符号标签路径那样 —— 那里的锚点是盒**中心**），会把净距多算半个字高，
# 使编号还贴着管线时就误触发引出线。
static func gpBox(gpPl: Dictionary, gpTextW: float, gpTextH: float) -> Rect2:
	var gpPos: Vector2 = gpPl.get("pos", Vector2.ZERO)
	if float(gpPl.get("rot", 0.0)) != 0.0:
		# Rotated -90 deg: the baseline runs upward from the origin and the glyph column lies to
		# its LEFT. Approximated as one full text height left of the baseline (the true split is
		# ascent/descent, which Font does not report here); the sub-millimetre error is far below
		# the GP_LEADER_MIN threshold it feeds.
		# 旋转 -90°：基线自原点向上延伸，字形列位于其**左侧**。近似为「基线左侧满一个字高」
		#（真实划分是升部/降部，而 Font 在此并不提供）；其亚毫米级误差远小于它所喂给的
		# GP_LEADER_MIN 阈值。
		return Rect2(gpPos.x - gpTextH, gpPos.y - gpTextW, gpTextH, gpTextW)
	return Rect2(gpPos.x, gpPos.y - gpTextH, gpTextW, gpTextH)


# The closest pair between the pipe and the glyph box, as [point_on_pipe, point_on_box].
# 管线与字形包围盒之间的最近点对，形如 [管上点, 盒上点]。
# One computation shared by gpClearance() and gpLeader(), so the reported distance and the
# decision to draw a leader can never disagree.
# 由 gpClearance() 与 gpLeader() 共用的一次计算，使「报告的距离」与「是否画引出线」永不冲突。
static func _gpNearestPair(gpPts: PackedVector2Array, gpPl: Dictionary,
		gpTextW: float, gpTextH: float) -> Array:
	var gpBox: Rect2 = gpBox(gpPl, gpTextW, gpTextH)
	var gpNear: Vector2 = gpNearestOnPolyline(gpPts, gpBox.get_center())
	return [gpNear, gpClampToRect(gpBox, gpNear)]


# Shortest distance between the glyph box and the pipe — the quantity GP_LEADER_MIN is compared
# against. Never negative; 0.0 when the number overlaps the pipe.
# 字形包围盒与管线之间的最短距离 —— GP_LEADER_MIN 正是与之比较的量。恒非负；编号与管线重叠时为 0.0。
static func gpClearance(gpPts: PackedVector2Array, gpPl: Dictionary,
		gpTextW: float, gpTextH: float) -> float:
	if gpPts.size() < 2:
		return 0.0
	var gpPair: Array = _gpNearestPair(gpPts, gpPl, gpTextW, gpTextH)
	return (gpPair[0] as Vector2).distance_to(gpPair[1] as Vector2)


# First crossing of a RAY with a polyline, or a miss record.
# 射线与折线的第一个交点，或未命中记录。
# [param gpTMax] how far along the ray to look / 沿射线搜索的最大距离
# [return] {"hit": bool, "pos": Vector2} — pos is the crossing when hit, else gpOrigin.
# [return] {"hit": bool, "pos": Vector2} —— 命中时为交点，否则为 gpOrigin。
# The NEAREST crossing wins, not the first one found: a routed pipe can fold back on itself, and
# the nearest crossing is the one the eye reads as "the" attachment point.
# 取**最近**交点而非最先找到者：布线后的管线可能折返，而最近交点才是眼睛认作「那个」依附点者。
static func _gpRayHitPolyline(gpOrigin: Vector2, gpDir: Vector2, gpTMax: float,
		gpPts: PackedVector2Array) -> Dictionary:
	if gpPts.size() < 2 or gpTMax <= 0.0:
		return {"hit": false, "pos": gpOrigin}
	var gpFar: Vector2 = gpOrigin + gpDir * gpTMax
	var gpBest: Vector2 = Vector2.ZERO
	var gpBestT: float = INF
	for gpI in range(gpPts.size() - 1):
		# Geometry2D has no segment-vs-ray primitive, so the ray is faked as a long segment.
		# Geometry2D 没有「线段对射线」的原语，故把射线伪装成一条长线段。
		var gpX: Variant = Geometry2D.segment_intersects_segment(
			gpOrigin, gpFar, gpPts[gpI], gpPts[gpI + 1])
		if gpX == null:
			continue
		var gpP: Vector2 = gpX as Vector2
		var gpT: float = gpOrigin.distance_to(gpP)
		if gpT > 1e-6 and gpT < gpBestT:
			gpBestT = gpT
			gpBest = gpP
	if gpBestT == INF:
		return {"hit": false, "pos": gpOrigin}
	return {"hit": true, "pos": gpBest}


# The leader of a detached number, ready to stroke as ONE polyline:
# [point_on_pipe, shoulder_elbow, shoulder_tail].
# 脱离编号的引出线，可作为**一条**折线直接描画：[管上点, 肩线拐点, 肩线末端]。
#
# Shape / 形状：
#   pipe ●
#         \  slanted segment at GP_LEADER_ANGLE_DEG / 斜段，夹角 GP_LEADER_ANGLE_DEG
#          ●───────────●   horizontal shoulder under the number / 编号下方的水平肩线
#        elbow      tail
# The earlier implementation drew a single straight box-to-pipe segment, which read as a stray
# perpendicular tick rather than a callout. A leader is TWO parts — a slanted segment and a
# horizontal shoulder — and it is the shoulder that makes the number look annotated rather than
# merely floating near its pipe.
# 早先的实现只画一条「盒到管线」的直连段，读起来像一道游离的垂直短线而非引出标注。
# 引出线是**两部分** —— 斜段 + 水平肩线 —— 而正是肩线让编号看起来是「被标注的」，
# 而非仅仅浮在管线附近。
#
# EMPTY while the number is still close enough to read as attached — so the leader is DERIVED
# state, never stored, and it appears/disappears on its own as the number is dragged or as the
# pipe is reshaped underneath it.
# 编号仍近到可读作「附着」时返回**空数组** —— 故引出线是**推导**态、从不落盘，随编号被拖动或
# 其下方管线被改形而自行出现 / 消失。
static func gpLeader(gpPts: PackedVector2Array, gpPl: Dictionary,
		gpTextW: float, gpTextH: float) -> PackedVector2Array:
	var gpOut: PackedVector2Array = PackedVector2Array()
	if gpPts.size() < 2:
		return gpOut
	var gpBox: Rect2 = gpBox(gpPl, gpTextW, gpTextH)
	var gpNear: Vector2 = gpNearestOnPolyline(gpPts, gpBox.get_center())
	var gpOnBox: Vector2 = gpClampToRect(gpBox, gpNear)
	# Gated on the exact value gpClearance() reports, so the two readouts can never disagree.
	# 以 gpClearance() 报告的同一取值判定，故两者永不冲突。
	if gpNear.distance_to(gpOnBox) <= GP_LEADER_MIN:
		return gpOut
	# ---- Built in the TAG'S OWN frame / 在**位号自身**的坐标系中构造 -------------------------
	# gpE1 runs along the text baseline, gpE2 from the baseline out to the shoulder side. For an
	# unrotated tag these are exactly the world axes — so the horizontal case is bit-for-bit
	# unchanged — while a number rotated onto a vertical run gets a VERTICAL shoulder hugging its
	# glyph column. That is what keeps a rotated callout reading as a shelf UNDER the text instead of
	# as a tick drawn ACROSS its end, which is what the world-axis version produced.
	# gpE1 沿文字基线，gpE2 自基线指向肩线一侧。位号未旋转时二者恰为世界坐标轴 —— 故水平情形逐位不变；
	# 而被旋转到竖管上的编号则得到一条贴着其字列的**竖直**肩线。这正是使旋转后的标注仍读作
	# 「托住文字」而非「横切文字末端的一道短线」的原因（世界坐标轴版本画出的正是后者）。
	var gpOrigin: Vector2 = gpPl.get("pos", Vector2.ZERO)
	var gpRot: float = float(gpPl.get("rot", 0.0))
	var gpE1: Vector2 = Vector2(cos(gpRot), sin(gpRot))
	var gpE2: Vector2 = Vector2(-sin(gpRot), cos(gpRot))
	# The glyphs occupy gpE1 in [0, textW] and gpE2 in [-textH, 0] — they sit ABOVE the baseline,
	# i.e. on the -gpE2 side — so the shoulder lies one pad beyond the baseline, on the +gpE2 side.
	# 字形占据 gpE1 的 [0, textW] 与 gpE2 的 [-textH, 0]（位于基线**之上**，即 -gpE2 一侧），
	# 故肩线落在基线之外 +gpE2 侧一个 pad 处。
	var gpPadLine: Vector2 = gpOrigin + gpE2 * GP_LEADER_PAD
	var gpAt0: Vector2 = gpPadLine + gpE1 * (-GP_LEADER_OVERHANG)
	var gpAt1: Vector2 = gpPadLine + gpE1 * (gpTextW + GP_LEADER_OVERHANG)
	# The slanted segment leaves from the shoulder end on the SAME side as the pipe, so it can
	# never cut back across the glyphs it annotates. The opposite end stays free.
	# 斜段自「与管线同侧」那个肩线端出发，故绝不会回切穿过它所标注的字形。另一端保持自由。
	var gpGoEnd1: bool = (gpNear - gpBox.get_center()).dot(gpE1) >= 0.0
	var gpElbow: Vector2 = gpAt1 if gpGoEnd1 else gpAt0
	var gpTail: Vector2 = gpAt0 if gpGoEnd1 else gpAt1
	var gpSignU: float = 1.0 if gpGoEnd1 else -1.0
	# Which side of the shoulder the pipe lies on. -1 when it is level with the shoulder — a
	# degenerate case that still needs a defined direction (same fallback as the old hard-coded one).
	# 管线位于肩线的哪一侧。与肩线齐平时取 -1 —— 退化情形仍需一个确定方向（与旧硬编码回落一致）。
	var gpSignV: float = signf((gpNear - gpElbow).dot(gpE2))
	if gpSignV == 0.0:
		gpSignV = -1.0
	# Slanted at the conventional angle, measured from the SHOULDER (the baseline it cradles):
	# cast a ray from the shoulder end toward the pipe and land on the first crossing. The lateral
	# offset this produces is exactly what makes the segment read as a leader, not a perpendicular
	# tick. / 按常规夹角（自肩线 —— 即它所托的基线 —— 量起）画斜段：自肩线端向管线投射射线，
	# 落在第一个交点上。由此产生的横向偏移，正是使该段读作「引出线」而非「垂直短线」的原因。
	var gpTan: float = tan(deg_to_rad(GP_LEADER_ANGLE_DEG))
	var gpDir: Vector2 = (gpE1 * gpSignU + gpE2 * gpSignV * gpTan).normalized()
	# Bound the search to a couple of times the drop, so a long folded pipe cannot be hit far off
	# to the side and drag the leader across the drawing.
	# 搜索距离限制在垂距的若干倍内，使长折返管线不会被命中在很远的一侧、把引出线拉过整张图。
	var gpReach: float = gpElbow.distance_to(gpNear) * 2.0 + 20.0
	var gpAnchor: Vector2 = gpNear
	var gpHit: Dictionary = _gpRayHitPolyline(gpElbow, gpDir, gpReach, gpPts)
	if bool(gpHit.get("hit", false)):
		gpAnchor = gpHit.get("pos", gpNear)
	else:
		# Mirror attempt: a SHORT pipe can sit entirely beyond the chosen shoulder end, so the
		# outward ray sails past it. Firing from the opposite end still lands a proper slanted
		# leader — and because that ray also points away from the glyphs, the mirrored attachment
		# can never cut back across the number either.
		# 镜像尝试：**短**管线可能完全落在所选肩线端之外，使外向射线擦肩而过。改从另一端发射，
		# 仍能得到规范的斜向引出线 —— 且该射线同样背向字形，故镜像依附也绝不会回切穿过编号。
		var gpMirror: Vector2 = gpAt0 if gpGoEnd1 else gpAt1
		var gpMirrorDir: Vector2 = (gpE1 * -gpSignU + gpE2 * gpSignV * gpTan).normalized()
		var gpMirrorHit: Dictionary = _gpRayHitPolyline(gpMirror, gpMirrorDir, gpReach, gpPts)
		if bool(gpMirrorHit.get("hit", false)):
			gpAnchor = gpMirrorHit.get("pos", gpNear)
			gpElbow = gpMirror
			gpTail = gpAt1 if gpGoEnd1 else gpAt0
	gpOut.append(gpAnchor)
	gpOut.append(gpElbow)
	gpOut.append(gpTail)
	return gpOut


# The number's FINAL placement TOGETHER WITH its leader, with the rule for a DETACHED number
# applied: it is laid FLAT.
# 编号的**最终**落位**及其**引出线，并施加「脱离的编号一律放平」这条规则。
#
# WHY a detached number must go back to horizontal / 为何脱离的编号必须回到横排：
# The -90 deg rotation on a vertical run is a SPACE-SAVING device — the glyph column hugs the pipe,
# so the number costs the drawing only its own height. The moment the number is pulled clear that
# saving buys nothing, while the rotation keeps costing: the reader has to tilt their head to read a
# floating column, and the leader's shelf would have to stand vertical too, reading as a tick across
# the glyphs rather than as a shelf under them. Detaching is exactly the moment the number stops
# being an in-line annotation and becomes a callout — and a callout is read flat, shelf underneath.
# 竖管上的 -90° 旋转是**省地方**的手段 —— 字形列贴着管线，编号在图面上只占自身高度。一旦编号被
# 拉离，这份节省已无意义，而旋转仍在付代价：读者要歪头去读一列浮空的字；且引出线的托线也得跟着
# 竖起来，读作横切字形的一道短线而非托住文字的托线。脱离的那一刻，编号恰从「在管标注」变为
# 「引出标注」—— 而引出标注一律横排阅读、托线在其下方。
#
# The form a number takes therefore has exactly three sources, and they are applied here in order:
# the LEG it is over picks horizontal vs column (inside gpPlace), the global / per-edge switch decides
# whether a column is allowed at all, and detachment overrides both by laying the number flat.
# 故编号的形态恰有三个来源，此处依序施加：它所压的**段**决定横排还是字列（在 gpPlace 内）；全局 /
# 单边开关决定是否允许字列；而「已脱离」覆盖前两者，一律放平。
#
# ONE decision, never iterated / 只判定一次，绝不迭代：
# The verdict is taken from the rotated placement alone, so the form cannot oscillate between the
# two states: either the number is still attached (the rotated form stands) or it is detached (the
# flat form is used). Because the flat form is laid at the SAME standoff, the leader appears at the
# very instant of the flip rather than a few millimetres of dragging later — that coupling is the
# whole point of deciding both here instead of leaving the flip to the renderer and the leader to
# gpLeader().
# 判定仅取自旋转态落位，故形态不会在两种状态间摆动：要么仍附着（保留旋转形态），要么已脱离
#（采用横排形态）。由于横排形态以**同样的净距**落位，引出线在翻转的那一刻当场出现，而不是再拖
# 几毫米后才出现 —— 这正是「把落位与引出线一并在此判定、而不把翻转留给渲染层、把引线留给
# gpLeader()」的全部意义。
# [return] the gpPlace record plus "leader" / "detached" / "flipped" (true only when a COLUMN was
#   turned flat — a number already over a horizontal leg is flat from the start, so it never flips).
# [return] gpPlace 的记录，另有 "leader" / "detached" / "flipped"（仅当**字列**被放平时为真 —— 本就压在
#   水平段上的编号一开始便是横排，从不翻转）。
static func gpPlaceCallout(gpPts: PackedVector2Array, gpTextW: float, gpTextH: float,
		gpRotate: bool, gpGap: float = GP_GAP, gpOffset: Vector2 = Vector2.ZERO) -> Dictionary:
	var gpPl: Dictionary = gpPlace(gpPts, gpTextW, gpTextH, gpRotate, gpGap, gpOffset)
	var gpClear: float = gpClearance(gpPts, gpPl, gpTextW, gpTextH)
	var gpDetached: bool = gpClear > GP_LEADER_MIN
	var gpFlipped: bool = false
	if gpDetached and float(gpPl.get("rot", 0.0)) != 0.0:
		gpPl = _gpFlatten(gpPts, gpPl, gpTextW, gpTextH, gpClear)
		gpFlipped = true
	gpPl["leader"] = gpLeader(gpPts, gpPl, gpTextW, gpTextH)
	gpPl["detached"] = gpDetached
	gpPl["flipped"] = gpFlipped
	return gpPl


# Lay a rotated number flat, keeping both its place and its standoff from the pipe.
# 把一个已旋转的编号放平，同时保住它的位置与其对管线的净距。
# [param gpWanted] the standoff the rotated column had / 旋转字列原本的净距
# TWO constraints, and neither may be dropped / 两条约束，均不可省：
#  1. It un-rotates IN PLACE. The pivot is the baseline midpoint — the point the glyphs and the
#     shelf are both measured from. Pivoting on the box centre instead sends the far end of a wide
#     flat number swinging across the drawing.
#  2. The standoff is RESTORED. A flat box is wider than the column was (its width is the text's
#     LENGTH, not its height), so its nearest edge lands much closer to the pipe — far enough, for a
#     long number, to lie right across it and swallow the very leader that says what it belongs to.
#     Pushing straight away from the pipe until the clearance matches the column's keeps the number
#     off its own pipe AND keeps the leader's appearance in lockstep with the flip.
#  1. **原地**转正。轴点取基线中点 —— 字形与托线共同的度量起点。若绕包围盒中心转动，一个扁而宽的
#     编号的远端会甩过整张图。
#  2. **恢复**净距。横排包围盒比字列更宽（其宽是文字**长度**而非字高），故其近边会明显更贴近管线
#     —— 对一个长编号，足以横躺在管线上，把「说明它属于谁」的那条引出线一起吞掉。沿背离管线方向
#     推到净距与字列相当时，编号既不压自己的管线，引出线的出现也与翻转严格同步。
static func _gpFlatten(gpPts: PackedVector2Array, gpPl: Dictionary,
		gpTextW: float, gpTextH: float, gpWanted: float) -> Dictionary:
	var gpPos: Vector2 = gpPl.get("pos", Vector2.ZERO)
	var gpRot: float = float(gpPl.get("rot", 0.0))
	# pos is the baseline's start and the baseline runs along the text advance direction, so its
	# midpoint is one half text-width along (cos rot, sin rot).
	# pos 是基线起点，基线沿文字推进方向延伸，故其中点为沿 (cos rot, sin rot) 半个文字宽度处。
	var gpPivot: Vector2 = gpPos + Vector2(cos(gpRot), sin(gpRot)) * (gpTextW * 0.5)
	# Flat about that pivot: glyphs above the baseline, advance along +x, box centred on the pivot's
	# y so the un-rotation does not also shift the number along the pipe.
	# 绕该轴点放平：字形在基线上方、沿 +x 推进，包围盒以轴点 y 居中，使转正不会顺带沿管线方向平移。
	var gpFlat: Dictionary = {
		"pos": gpPivot + Vector2(-gpTextW * 0.5, gpTextH * 0.5),
		"rot": 0.0,
		"vertical": bool(gpPl.get("vertical", false)),
		"anchor": gpPl.get("anchor", Vector2.ZERO),
	}
	# Bounded correction: the first push is an estimate (it assumes a straight nearest feature), so a
	# folded pipe can leave a shortfall. Three passes cannot run away and always terminate.
	# 有界修正：首次推移是估计值（假定最近特征是直的），故折返管线可能仍有欠量。三次上限，不会失控
	# 且必然终止。
	var gpPass: int = 0
	while gpPass < 3:
		var gpHave: float = gpClearance(gpPts, gpFlat, gpTextW, gpTextH)
		if gpHave >= gpWanted:
			break
		var gpCentre: Vector2 = gpBox(gpFlat, gpTextW, gpTextH).get_center()
		var gpAway: Vector2 = gpCentre - gpNearestOnPolyline(gpPts, gpCentre)
		if gpAway.length() < 1e-6:
			break
		var gpDir: Vector2 = gpAway.normalized()
		# Measured from the box CENTRE, minus the box's half-extent along that direction (the
		# support function of the rectangle) — NOT from the deficit gpWanted - gpHave.
		# 自包围盒**中心**量起，再减去包围盒沿该方向的半宽高（即矩形的支撑函数）—— **不是**用
		# gpWanted - gpHave 这个欠量。
		# ⚠️ The deficit form is a trap: it is only valid while the pipe sits OUTSIDE the box. The
		# flat box is a wide one, so a pipe that was clear of the narrow column can end up lying
		# UNDER it, where the edge distance is 0 — every pass then corrects by "0 to 7.5", i.e. by a
		# text half-width less than what is needed, and the box never gets clear. Observed live: a
		# number laid flat with NO leader, its edge 0.5 mm off the pipe.
		# ⚠️ 欠量写法是个陷阱：它仅在管线位于包围盒**之外**时成立。横排包围盒很宽，故原本与窄字列
		# 相隔的管线，可能正好落在它**下方** —— 此时近边距离为 0，每轮都按「0 到 7.5」修正，比实际
		# 所需的少了一个文字半宽，包围盒永远脱不开身。实测曾见：编号已放平却**没有**引出线，其边
		# 距管线仅 0.5mm。
		var gpHalf: float = absf(gpDir.x) * gpTextW * 0.5 + absf(gpDir.y) * gpTextH * 0.5
		var gpPush: float = (gpWanted + gpHalf) - gpAway.length()
		if gpPush <= 1e-6:
			break
		gpFlat["pos"] = (gpFlat["pos"] as Vector2) + gpDir * gpPush
		gpPass += 1
	return gpFlat
