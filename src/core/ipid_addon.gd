class_name IPIDAddon
extends Resource

## Open-Core 插件契约：Pro / 商业外围功能通过继承此类挂载到核心。
## 核心代码不改动，仅通过 addon  loader 扫描 addons/ 目录并实例化。


## 返回要在工具栏注入的按钮/菜单项配置。
func _get_tools() -> Array:
	return []


## 返回要在侧边栏注入的面板场景路径（String 数组，如 ["res://addons/foo/panel.tscn"]）。
func _get_panels() -> Array:
	return []


## 图发生变化时的回调；Pro 模块可在此触发 HAZOP 重算、规则检查等。
func _on_graph_changed(_graph: PIDGraph) -> void:
	pass
