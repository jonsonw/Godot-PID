class_name Viewport3D
extends SubViewport

# Right 3D placeholder view; rebuilds on graph change.
# 右侧 3D 占位联动视图，监听图变化重建。
# See Dev Guide §4.4.
# 见开发指南 §4.4。

signal graph_rebuilt()  # 3D scene rebuilt / 3D 场景已重建

# TODO: observe PIDGraph.graph_changed -> PID3DBuilder.build()
# TODO：监听 PIDGraph.graph_changed → PID3DBuilder.build()
