class_name GPIPIDAddon
extends Resource

# Open-Core plugin contract: Pro / commercial peripheral features mount to the core
# by extending this class, without modifying core code.
# Open-Core 插件契约：Pro / 商业外围功能通过继承此类挂载到核心，核心代码不改动。
# An addon loader scans the addons/ directory and instantiates discovered addons.
# 插件加载器扫描 addons/ 目录并实例化发现的插件。

# Return the addon display name.
# 返回插件显示名。
func _gpGetName() -> String:
	return "unnamed"

# Return toolbar extension config (buttons / menu items).
# 返回工具栏扩展配置（按钮/菜单项）。
func _gpGetTools() -> Array:
	return []

# Return side-panel scene paths to inject, e.g. ["res://addons/foo/panel.tscn"].
# 返回要在侧边栏注入的面板场景路径（String 数组，如 ["res://addons/foo/panel.tscn"]）。
func _gpGetPanels() -> Array:
	return []

# Called when the graph changes; a Pro module may trigger HAZOP recompute, rule checks, etc.
# 图发生变化时的回调；Pro 模块可在此触发 HAZOP 重算、规则检查等。
func _gpOnGraphChanged(_gpGraph: GPPIDGraph) -> void:
	pass

# Register exporters (e.g. dwg / excel) — see Dev Guide §4.6.1.
# 注册导出器（如 dwg/excel），见开发指南 §4.6.1。
func _gpRegisterExporters() -> Array:
	return []

# Register symbol packs (e.g. paid industry packs); coexists with directory-dropped SymbolPacks.
# 注册图元包（如收费行业包）；与目录外挂的 SymbolPack 并存。
func _gpRegisterSymbolPacks() -> Array:
	return []

# Auth / permission init hook (collaboration · Pro) — see Dev Guide §4.11.
# 鉴权 / 权限初始化钩子（协同·Pro 实现），见开发指南 §4.11。
func _gpOnLoad(gpCtx: Dictionary) -> void:
	pass

# Receive a remote operation (collaboration · Pro) — see Dev Guide §4.11.
# 接收远端操作（协同·Pro 实现），见开发指南 §4.11。
func _gpOnSync(gpOp: Dictionary) -> void:
	pass
