class_name GPSymbolGrid
extends Container

# 缩略图网格。最小宽度报 0，使 ScrollContainer 可把网格拉伸到视口宽（按真实宽度
# 自动重排列数）；停靠栏下限由 HSplitContainer 分隔条保证。Godot 的 GridContainer 在
# C++ 层计算最小尺寸、不听 GDScript 重写，故改用普通 Container 手写布局。
# Palette grid whose minimum WIDTH is 0 so the ScrollContainer stretches it to the
# viewport (columns auto-derive from the real width). The dock floor is enforced by
# the HSplitContainer split, not this grid. Godot's GridContainer computes its minimum
# in C++ and ignores GDScript overrides, hence the manual Container layout here.

const GP_MIN_WIDTH: float = 160.0
const GP_CELL: float = 60.0
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
	queue_sort()


# Derive the column count from the explicitly set width, falling back to the
# container's own size, then to the floor width.
# 优先按显式设置宽度推导列数，否则回退到容器自身尺寸，最后回退到下限宽度。
func _gpCols() -> int:
	var gpAvail: float = gpAvailWidth
	if gpAvail <= 0.0:
		gpAvail = maxf(size.x, GP_MIN_WIDTH)
	else:
		gpAvail = maxf(gpAvail, GP_MIN_WIDTH)
	var gpPitched: float = GP_CELL + GP_H_SEP
	return maxi(1, int(floor((gpAvail + GP_H_SEP) / gpPitched)))


# Report a zero minimum WIDTH so the ScrollContainer is free to stretch the grid
# to the full viewport width (auto-rearranging columns). Height stays natural so
# vertical scrolling still works. The floor on the dock width is enforced by the
# HSplitContainer split offset, not by this grid's minimum.
# 最小宽度报 0，使 ScrollContainer 能把网格拉伸到整个视口宽度（自动重排列数）；
# 高度保留自然值以保留纵向滚动。停靠栏下限由 HSplitContainer 分隔条保证，而非本网格最小宽。
func _get_minimum_size() -> Vector2:
	var gpN: int = get_child_count()
	if gpN == 0:
		return Vector2(0.0, 0.0)
	var gpRows: int = ceili(float(gpN) / float(_gpCols()))
	var gpH: float = float(gpRows) * GP_CELL + GP_V_SEP * float(gpRows - 1)
	return Vector2(0.0, gpH)


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
	var gpN: int = get_child_count()
	if gpN == 0:
		return
	var gpCols: int = _gpCols()
	# Use the explicit target width if one was supplied; otherwise fall back to size.
	# 若已提供显式目标宽度则使用它，否则回退到 size。
	var gpAvail: float = gpAvailWidth
	if gpAvail <= 0.0:
		gpAvail = maxf(size.x, GP_MIN_WIDTH)
	else:
		gpAvail = maxf(gpAvail, GP_MIN_WIDTH)
	var gpCw: float = (gpAvail - GP_H_SEP * float(gpCols - 1)) / float(gpCols)
	gpCw = maxf(gpCw, 1.0)
	for gpI in range(gpN):
		var gpChild: Control = get_child(gpI) as Control
		if gpChild == null or not gpChild.visible:
			continue
		var gpCol: int = gpI % gpCols
		var gpRow: int = int(gpI / gpCols)
		var gpX: float = float(gpCol) * (gpCw + GP_H_SEP)
		var gpY: float = float(gpRow) * (GP_CELL + GP_V_SEP)
		fit_child_in_rect(gpChild, Rect2(gpX, gpY, gpCw, GP_CELL))
