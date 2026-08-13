class_name GPPID3DBuilder
extends RefCounted

# Build / rebuild a 3D scene (Node3D) from a PIDGraph; listens to graph_changed.
# 从 PIDGraph 构建/重建 3D 场景（Node3D）；监听 graph_changed。
# See Dev Guide §4.5.
# 见开发指南 §4.5。

# Build a 3D scene from the graph.
# 从图构建 3D 场景。
func gpBuild(gpGraph: GPPIDGraph) -> Node3D:
	return Node3D.new()
