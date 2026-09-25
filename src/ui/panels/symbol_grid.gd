class_name GPSymbolGrid
extends Container

# 缩略图网格。最小宽度报 0，使 ScrollContainer 可把网格拉伸到视口宽（按真实宽度
# 自动重排列数）；停靠栏下限由 HSplitContainer 分隔条保证。Godot 的 GridContainer 在
# C++ 层计算最小尺寸、不听 GDScript 重写，故改用普通 Container 手写布局。
# Palette grid whose minimum WIDTH is 0 so the ScrollContainer stretches it to the
# viewport (columns auto-derive from the real width). The dock floor is enforced by
# the HSplitContainer split, not this grid. Godot's GridContainer computes its minimum
# in C++ and ignores GDScript overrides, hence the manual Container layout here.

# Floor width (pixels) the grid is allowed to shrink to when deriving columns.
# Fed from the left dock's GP_LEFT_MIN so the grid floor and the dock floor stay
# in sync (see toolbar.gd / main_window.gd). 160 matches the left dock's minimum.
# 网格推导列数时允许收缩到的下限宽（像素）。由左停靠栏的 GP_LEFT_MIN 注入，使网格
# 下限与停靠栏下限保持一致（见 toolbar.gd / main_window.gd）。160 与左停靠栏最小宽一致。
var gpMinWidth: float = 160.0

# Horizontal / vertical gap between cells in pixels.
# 单元格之间的横向 / 纵向间距（像素）。
const GP_H_SEP: float = 4.0
const GP_V_SEP: float = 4.0

# Target width explicitly supplied by the owning toolbar during a dock resize.
# 停靠栏缩放时由所属工具栏显式传入的目标宽度。
# Relying on size.x inside NOTIFICATION_SORT_CHILDREN is unreliable because the
# grid may be sorted before its parent has allocated the new width. Setting this
# value lets _gpCols() / _gpSort() use the real dock width directly.
# 在 NOTIFICATION_SORT_CHILDREN 中依赖 size.x 不可靠，因为网格可能在父节点分配新宽度前
# 就被排序。设置此值后，_gpCols() / _gpSort() 可直接使用真实停靠栏宽度。
var gpAvailWidth: float = 0.0


# Tell the grid which width it should layout for.
# 告诉网格应以哪个宽度进行布局。
func gpSetAvailWidth(gpW: float) -> void:
	gpAvailWidth = gpW
	# CRITICAL: recompute the MINIMUM SIZE as well, not just the layout. The column count derives
	# from the available width, so a width change changes the row count and therefore the height
	# the grid must report to its parent VBox. Calling only queue_sort() left the parent with the
	# height of the OLD column count — the grid then laid its cells out over more rows than the
	# space it had been given, and every following category's header was drawn on top of the
	# previous category's last row (the reported "categories overlap" defect).
	# 关键：不仅要重排，还要重算「最小尺寸」。列数由可用宽度推导，故宽度变化会改变行数，进而改变
	# 网格必须上报给父 VBox 的高度。此前只调 queue_sort()，父级仍持有**旧列数**对应的高度 —— 网格
	# 于是按多于所分配空间的行数摆放单元格，后续每个类目的标题都画在了上一个类目最后一行的上面
	#（即用户报告的「分类重叠」缺陷）。
	update_minimum_size()
	queue_sort()


# Cell height, taken from the SINGLE metric owner (GPSymbolPaletteItem). The grid must never
# re-derive it: while it derived its own value from gpFontSize and the item reserved space from
# gpSymbolFontSize, the two disagreed and categories overlapped.
# 单元格高度取自**唯一的度量拥有者**（GPSymbolPaletteItem）。网格绝不自行推导：此前它按
# gpFontSize 自行推导、而条目按 gpSymbolFontSize 预留空间，二者不一致，导致类目重叠。
func _gpCellSize() -> float:
	return GPSymbolPaletteItem.gpCellHeight(Settings.gpFontSize)


# Re-layout the grid when the symbol font size changes (no need to recreate items).
# 图元字号变化时重排网格（无需重建条目）。
func _ready() -> void:
	Settings.gpSymbolStyleChanged.connect(_gpOnSymbolStyleChanged)


# React to symbol font / size changes: recompute the cell size and re-layout.
# 响应图元字体/字号变化：重算单元格尺寸并重排。
func _gpOnSymbolStyleChanged() -> void:
	update_minimum_size()
	queue_sort()


# Derive the column count from the explicitly set width, falling back to the
# container's own size, then to the floor width.
# 优先按显式设置宽度推导列数，否则回退到容器自身尺寸，最后回退到下限宽度。
func _gpCols() -> int:
	var gpAvail: float = gpAvailWidth
	if gpAvail <= 0.0:
		gpAvail = maxf(size.x, gpMinWidth)
	else:
		gpAvail = maxf(gpAvail, gpMinWidth)
	var gpPitched: float = _gpCellSize() + GP_H_SEP
	return maxi(1, int(floor((gpAvail + GP_H_SEP) / gpPitched)))


# Report a zero minimum WIDTH so the ScrollContainer is free to stretch the grid
# to the full viewport width (auto-rearranging columns). Height stays natural so
# vertical scrolling still works. The floor on the dock width is enforced by the
# HSplitContainer split offset, not by this grid's minimum.
# 最小宽度报 0，使 ScrollContainer 能把网格拉伸到整个视口宽度（自动重排列数）；
# 高度保留自然值以保留纵向滚动。停靠栏下限由 HSplitContainer 分隔条保证，而非本网格最小宽。
func _get_minimum_size() -> Vector2:
	var gpVisible: Array[Control] = _gpVisibleChildren()
	if gpVisible.is_empty():
		return Vector2(0.0, 0.0)
	var gpRows: int = ceili(float(gpVisible.size()) / float(_gpCols()))
	var gpH: float = float(gpRows) * _gpCellSize() + GP_V_SEP * float(gpRows - 1)
	return Vector2(0.0, gpH)


# Only VISIBLE children participate in the grid. The palette-visibility gear menu hides
# individual symbols by toggling child visibility; counting hidden children would leave
# empty holes and phantom rows.
# 网格只排布**可见**子项。图元库可见性齿轮菜单通过切换子项可见性来隐藏单个图元；
# 若把隐藏子项计入，会留下空洞与幻影行。
func _gpVisibleChildren() -> Array[Control]:
	var gpOut: Array[Control] = []
	for gpC in get_children():
		var gpChild: Control = gpC as Control
		if gpChild != null and gpChild.visible:
			gpOut.append(gpChild)
	return gpOut


# Re-layout children whenever the container is sorted by the engine.
# 容器被引擎重排时重新布局子项。
func _notification(gpWhat: int) -> void:
	if gpWhat == NOTIFICATION_SORT_CHILDREN:
		_gpSort()


# Place every visible child on a column-major grid, stretching each cell to fill
# the available width evenly. Cells always span the full width (no right gap) and
# never overlap because pitch > cell size.
# 把每个可见子项按列优先网格定位，并把每格均分铺满可用宽度：右侧无空隙、
# 因「步距 > 格宽」而永不重叠。
func _gpSort() -> void:
	var gpVisible: Array[Control] = _gpVisibleChildren()
	var gpN: int = gpVisible.size()
	if gpN == 0:
		return
	var gpCols: int = _gpCols()
	# Use the explicit target width if one was supplied; otherwise fall back to size.
	# 若已提供显式目标宽度则使用它，否则回退到 size。
	var gpAvail: float = gpAvailWidth
	if gpAvail <= 0.0:
		gpAvail = maxf(size.x, gpMinWidth)
	else:
		gpAvail = maxf(gpAvail, gpMinWidth)
	var gpCw: float = (gpAvail - GP_H_SEP * float(gpCols - 1)) / float(gpCols)
	gpCw = maxf(gpCw, 1.0)
	for gpI in range(gpN):
		var gpChild: Control = gpVisible[gpI]
		var gpCol: int = gpI % gpCols
		var gpRow: int = int(gpI / gpCols)
		var gpX: float = float(gpCol) * (gpCw + GP_H_SEP)
		var gpY: float = float(gpRow) * (_gpCellSize() + GP_V_SEP)
		fit_child_in_rect(gpChild, Rect2(gpX, gpY, gpCw, _gpCellSize()))
