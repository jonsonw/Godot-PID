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


# Contract version this addon was written against (2 = chat panel + tool defs + validation hooks).
# 本插件编写时所对的契约版本（2 = 对话面板 + 工具定义 + 校验钩子）。
# The loader never refuses an addon for an OLD version — every v1 hook has a default — and never
# pretends to support a NEWER one silently; it reports the mismatch instead.
# 加载器不会因插件版本**旧**而拒绝它（v1 的钩子都有默认实现），也不会默默假装支持**更新**的版本；
# 它会把不匹配报告出来。
const GP_CONTRACT_VERSION: int = 2


# Chat-panel mount point (v2): a scene path the shell may dock, or "" for none.
# 对话面板挂载点（v2）：外壳可停靠的场景路径，无则空串。
# WHY A PATH AND NOT A NODE / 为何给路径而非节点：
# an addon must not hand the shell a live node it still owns; the shell instantiates, owns and
# frees the scene, so one addon cannot keep a handle on a window that has been closed.
# 插件不得把自己仍然持有的活节点交给外壳；由外壳实例化、持有并释放该场景，
# 这样一个插件就无法继续握着一个已经关闭的窗口。
func _gpGetChatPanel() -> String:
	return ""


# Tool definitions (v2), shared verbatim with the MCP / local tool list: each entry is
# {id, description, args, handler}. `handler` is a METHOD NAME on the tool dispatcher, never a
# Callable — a Callable cannot be serialised, reviewed or diffed, and this contract must be
# readable as data.
# 工具定义（v2），与 MCP / 本地工具清单**逐字共用**：每条为 {id, description, args, handler}。
# `handler` 是工具分发器上的**方法名**，绝不是 Callable —— Callable 无法序列化、评审或 diff，
# 而本契约必须能以数据形式被读懂。
func _gpGetToolDefs() -> Array:
	return []


# Validation hooks (v2): rule descriptors the DRC pack may run after the built-in seven.
# 校验钩子（v2）：DRC 规则包在内置七条之后可运行的规则描述。
# Entries are {id, description, severity, handler} with the same shape rules everywhere, so a
# plugin rule cannot be a special case in the report.
# 条目为 {id, description, severity, handler}，与其它规则同形，使插件规则在报告里不成为特例。
func _gpGetValidationHooks() -> Array:
	return []


# Auth / permission init hook (collaboration · Pro) — see Dev Guide §4.11.
# 鉴权 / 权限初始化钩子（协同·Pro 实现），见开发指南 §4.11。
func _gpOnLoad(gpCtx: Dictionary) -> void:
	pass


# Receive a remote operation (collaboration · Pro) — see Dev Guide §4.11.
# 接收远端操作（协同·Pro 实现），见开发指南 §4.11。
func _gpOnSync(gpOp: Dictionary) -> void:
	pass
