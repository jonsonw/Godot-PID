class_name GPConstants
extends RefCounted
# Copyright © 2026 Jonson Wang
# Single source of truth for geometry / snapping constants shared across core, render
# and ui. They used to be redeclared per module (GP_EPS alone appeared in four files),
# which let them drift apart silently.
# 跨 core / render / ui 共享的几何与吸附常量的单一数据源。此前各模块各自重复声明
# （仅 GP_EPS 就出现在四个文件中），一旦改动便可能静默漂移。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。

# Tolerance for geometry comparisons (degenerate segments, coincidence checks).
# 几何比较容差（退化线段、重合判定）。
const GP_EPS: float = 0.5

# Fallback grid step in world units, matching the grid the overlay actually draws.
# 回退网格步长（世界单位），与覆盖层实际画出的网格一致。
const GP_GRID_STEP: float = 50.0

# Snap radius in SCREEN pixels; divided by zoom so the magnet stays equally forgiving.
# 吸附半径（屏幕像素）；除以 zoom 使缩小后磁力同样宽容。
const GP_SNAP_PX: float = 12.0
