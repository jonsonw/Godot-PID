extends "res://tests/gp_test.gd"
# 钉住「render 层不读 autoload」这条闭合路径。
# pin the closed path "the render layer never reads an autoload".
#
# 这套测试把依赖注入机制钉死，专门针对最危险的失败模式——「切换语言 / 字号后，
# 旧视图的 style 没被更新，于是图上残留旧字号 / 旧文字」。四个断言分别覆盖：
#   1. GPRenderStyle 值对象正确携带纯数据（不依赖 autoload）；
#   2. GPGraphBinder.gpApplyStyle 把新快照重注入所有已有视图（钉住「忘记重注入」）；
#   3. 装配时新建的视图拿到注入的 style（钉住创建路径的注入无遗漏）；
#   4. 画布在 autoload 缺失（headless）时回落安全默认快照。
#
# This suite pins the dependency-injection mechanism, aimed squarely at the worst failure
# mode — a locale / font change that forgets to re-push the style into existing views, leaving
# stale labels on screen. The four asserts cover: (1) the value object carries data, (2) the
# binder re-injects on gpApplyStyle, (3) newly created views receive the injected style, (4) the
# canvas falls back to safe defaults when the autoloads are absent.

# 1. 值对象：纯数据，不依赖 autoload。
# Value object: pure data, no autoload dependency.
func gpTestValueObjectCarriesData() -> void:
	var gpF: Font = ThemeDB.fallback_font
	var gpS: GPRenderStyle = GPRenderStyle.gpFrom(gpF, 20, "en", true, 14, true)
	gpCheck(gpS != null, "gpFrom 返回非空 / gpFrom returns non-null")
	gpEq(gpS.gpSymbolFontSize, 20.0, "字号透传 / font size passed")
	gpEq(gpS.gpLocale, "en", "语言透传 / locale passed")
	gpCheck(gpS.gpScreenConstantWidth, "屏幕恒定线宽透传 / screen-constant width passed")
	gpEq(gpS.gpPipeTagFontSize, 14, "位号字号透传 / pipe-tag size passed")
	gpCheck(gpS.gpPipeTagRotate, "位号旋转透传 / pipe-tag rotate passed")
	gpEq(gpS.gpSymbolFont, gpF, "字体透传 / font passed")


# 2. 重注入（关键钉）：切换语言 / 字号后，所有已有视图的 style 必须更新。
# Re-injection (the critical pin): after a locale / font change, every existing view's style
# must update.
func gpTestBinderReinjectOnApplyStyle() -> void:
	var gpBinder: GPGraphBinder = GPGraphBinder.new()
	var gpRoot: Node2D = Node2D.new()
	gpBinder.gpWorldRoot = gpRoot
	var gpSymV: GPSymbolView = GPSymbolView.new()
	var gpEdgeV: GPEdgeView = GPEdgeView.new()
	gpRoot.add_child(gpSymV)
	gpRoot.add_child(gpEdgeV)
	# 直接登记到绑定器的内部缓存（与 gpSync 创建分支写入的是同一个字典）。
	# Register straight into the binder's internal caches (the same dicts gpSync's create
	# branch writes into).
	gpBinder._gpSymbolViews["s1"] = gpSymV
	gpBinder._gpEdgeViews["e1"] = gpEdgeV

	var gpA: GPRenderStyle = GPRenderStyle.gpFrom(null, 16, "zh_CN", false, 0, false)
	var gpB: GPRenderStyle = GPRenderStyle.gpFrom(null, 22, "en", true, 18, true)
	gpBinder.gpStyle = gpA
	# Simulate views that already carry style A (as if created via gpSync with style A).
	# 模拟「已带着 style A 的视图」（如同经 gpSync 以 style A 创建）。
	gpSymV.gpStyle = gpA
	gpEdgeV.gpStyle = gpA
	gpCheck(gpSymV.gpStyle == gpA, "注入前符号视图 style == A / symbol view starts at A")
	# 切换语言 / 字号：重建快照并重推。
	# Locale / font switch: rebuild the snapshot and re-push it.
	gpBinder.gpApplyStyle(gpB)
	gpEq(gpSymV.gpStyle, gpB, "重注入后符号视图 style == B / symbol view re-injected to B")
	gpEq(gpEdgeV.gpStyle, gpB, "重注入后连线视图 style == B / edge view re-injected to B")
	gpEq(gpBinder.gpStyle, gpB, "绑定器自身 style 已更新 / binder style updated")
	gpBinder.free()
	gpRoot.free()


# 3. 创建路径注入：gpSync 新建的视图必须拿到注入的 style，不能依赖 render 自读 autoload。
# Create-path injection: views gpSync creates must receive the injected style, never read the
# autoload themselves.
func gpTestBinderInjectsOnCreate() -> void:
	var gpBinder: GPGraphBinder = GPGraphBinder.new()
	var gpRoot: Node2D = Node2D.new()
	gpBinder.gpWorldRoot = gpRoot
	var gpG: GPPIDGraph = GPPIDGraph.new()
	gpG.gpAddNode(gpG.gpNewNode("N1", "pump", "P-101", Vector2(100.0, 100.0)))
	gpG.gpAddNode(gpG.gpNewNode("N2", "valve", "V-201", Vector2(300.0, 100.0)))
	gpG.gpAddEdge(gpG.gpNewEdge("E1", "N1", "N2"))
	var gpDef: GPSymbolDef = GPSymbolDef.new()
	gpDef.gpId = "pump"
	gpDef.gpCategory = "general"
	var gpStyle: GPRenderStyle = GPRenderStyle.gpFrom(null, 18, "en", false, 0, false)
	gpBinder.gpStyle = gpStyle
	gpBinder.gpSync(gpG, [gpDef], [], "", 1.0)
	var gpSymV: GPSymbolView = gpBinder.gpGetSymbolView("N1")
	gpCheck(gpSymV != null, "符号视图已创建 / symbol view created")
	gpEq(gpSymV.gpStyle, gpStyle, "新建符号视图拿到注入的 style / new symbol view got injected style")
	var gpEdgeV: GPEdgeView = gpBinder.gpGetEdgeView("E1")
	gpCheck(gpEdgeV != null, "连线视图已创建 / edge view created")
	gpEq(gpEdgeV.gpStyle, gpStyle, "新建连线视图拿到注入的 style / new edge view got injected style")
	gpBinder.free()
	gpRoot.free()


# 4. headless 回落：autoload 缺失时，画布构造的快照必须用安全默认值（不崩溃、不读全局）。
# Headless fallback: with no autoloads, the snapshot the canvas builds must use safe defaults
# (no crash, no global reads).
func gpTestCanvasBuildsDefaultHeadless() -> void:
	var gpCv: GPCanvas2D = GPCanvas2D.new()
	var gpS: GPRenderStyle = gpCv.gpBuildRenderStyle()
	gpCheck(gpS != null, "默认快照非空 / default snapshot non-null")
	gpEq(gpS.gpLocale, "zh_CN", "autoload 缺失时回落 zh_CN / falls back to zh_CN without autoload")
	gpEq(gpS.gpSymbolFontSize, 3.0, "autoload 缺失时回落 3.0（mm）/ falls back to 3.0 (mm)")
	gpCv.free()


# 5. 快照必须真的「读到」来源，而不是悄悄用回落值。
# The snapshot must actually READ its sources rather than quietly falling back.
#
# 这是本套件最关键的一条。Godot 4 中 autoload 是 /root 下的节点、**不是** Engine 单例，故
# `Engine.has_singleton("Settings")` 恒为假；一旦据此取值，快照里**每一项**都会退化成默认值 ——
# 用户看到的症状正是「竖管位号不旋转，而 settings.cfg 里明明写着 tag_rotate=true」，且当时整套
# 测试全绿。
# 故此处刻意取**与回落值不同**的数值，使「读到了」与「没读到」可被区分；若只断言「等于默认值」，
# 无论有没有缺陷都会通过。
# The fixture's values are deliberately DISTINCT from the fallbacks, so "read it" and "fell back"
# cannot be confused — asserting against the default would pass either way.
func gpTestSnapshotReadsItsSources() -> void:
	var gpSettings: Node = load("res://src/autoload/settings.gd").new()
	var gpI18n: Node = load("res://src/autoload/i18n.gd").new()
	gpSettings.gpSymbolFontSize = 7.25
	gpSettings.gpPipeTagFontSize = 9
	gpSettings.gpPipeTagRotate = false
	gpSettings.gpScreenConstantWidth = true
	gpI18n.gpLocale = "en"
	var gpS: GPRenderStyle = GPRenderStyle.gpFromSources(gpSettings, gpI18n)
	gpEq(gpS.gpSymbolFontSize, 7.25, "图元字号取自设置 / font size read from settings")
	gpEq(gpS.gpPipeTagFontSize, 9, "位号字号取自设置 / tag size read from settings")
	gpCheck(not gpS.gpPipeTagRotate, "位号旋转取自设置（与回落值相反）/ rotate read, not defaulted")
	gpCheck(gpS.gpScreenConstantWidth, "屏幕恒定线宽取自设置 / const width read from settings")
	gpEq(gpS.gpLocale, "en", "语言取自 I18n / locale read from I18n")
	gpSettings.free()
	gpI18n.free()


# 6. 来源缺失时的回落 —— 其中「竖管旋转」回落为**真**，因为它是制图约定而非偏好。
# Fallbacks when a source is absent — rotate falls back to TRUE, being a drafting convention rather
# than a preference. Settings / GPRenderStyle / GPEdgeView 三处必须写法一致，否则任何一条漏掉注入
# 的路径都会静默翻转这条约定（这正是旧代码 `else false` 的后果）。
func gpTestSnapshotFallbackKeepsTheConvention() -> void:
	var gpS: GPRenderStyle = GPRenderStyle.gpFromSources(null, null)
	gpCheck(gpS.gpPipeTagRotate, "无来源时竖管仍旋转 / vertical runs still rotate with no source")
	gpEq(gpS.gpSymbolFontSize, 3.0, "无来源时回落 3.0mm / falls back to 3.0 mm")
	gpEq(gpS.gpLocale, "zh_CN", "无来源时回落图纸默认语种 / falls back to the drawing default locale")


# 7. autoload 解析的**树外护栏**（缺陷现场的另一半）。
# The out-of-tree guard of the autoload resolution — the other half of the defect's site.
#
# ⚠️ 为何不「挂一个假 autoload 再解析」：本运行器是 `--script` 模式下的 SceneTree，其中 `add_child`
# 不会完成入树传播 —— 实测把假节点挂到 root 下后，`/root/<名字>` 仍解析不到（返回 null 正说明入树
# 未完成：若完成则该路径必然可解析）。那样的断言测到的是运行器环境而非被测代码。
# Why not fake an autoload and resolve it: in this `--script` SceneTree runner `add_child` does not
# complete the enter-tree propagation — measured: after adding a fake node under root, `/root/<name>`
# still resolves to null (which PROVES the propagation did not finish; had it finished, that path
# would necessarily resolve). Such an assertion would test the runner, not the code under test.
# 真实路径的端到端证据由「跑真正的主场景 main.tscn 并打印快照」承担（设置确实生效）；此处只钉住
# 画布脱离场景树时不得触发无树可解析的绝对路径查找。
# End-to-end evidence for the real path comes from running the real main.tscn and printing the
# snapshot; this test only pins that an out-of-tree canvas must not trip an absolute-path lookup.
func gpTestAutoloadGuardForOutOfTreeHosts() -> void:
	var gpLoose: Node = Node.new()
	gpEq(GPCanvas2D.gpResolveAutoload(gpLoose, "Settings"), null,
		"未入树的宿主返回 null / an out-of-tree host resolves to null")
	gpLoose.free()
	gpEq(GPCanvas2D.gpResolveAutoload(null, "Settings"), null,
		"无宿主返回 null / a null host resolves to null")
	# 裸 new 出的画布（headless 测试路径）必须安全回落，且回落后仍遵守制图约定。
	# A bare canvas (the headless test path) must fall back safely — and still honour the convention.
	var gpCv: GPCanvas2D = GPCanvas2D.new()
	var gpS: GPRenderStyle = gpCv.gpBuildRenderStyle()
	gpCheck(gpS != null, "树外画布仍产出快照 / an out-of-tree canvas still yields a snapshot")
	gpCheck(gpS.gpPipeTagRotate, "树外回落后仍旋转竖管编号 / still rotates vertical numbers")
	gpCv.free()


# 8. 源码级护栏：快照构建不得再用 Engine.has_singleton / Engine.get_singleton 解析 autoload。
# Source guard: the snapshot builder must not resolve autoloads via Engine.has_singleton again.
# 为何必须读源码：Godot 4 中该查找**恒为空**且失败无声，而其症状仅表现为「设置里改了没反应」。
# 更糟的是，若回落值恰好等于期望值（旋转的回落值**正是** true），上面任何行为断言都抓不到它 ——
# 只有钉住实现手段本身才能防它复发。
# Why source-level: that lookup is ALWAYS empty in Godot 4 and fails silently; its only symptom is
# "a setting in the dialog does nothing". Worse, where the fallback equals the wished-for value (the
# rotate fallback IS true) no behavioural assertion above can catch a relapse — only pinning the
# mechanism can.
func gpTestSnapshotBuilderResolvesThroughTreeNotEngine() -> void:
	var gpSrc: String = FileAccess.get_file_as_string("res://src/ui/canvas/canvas_2d.gd")
	gpCheck(not gpSrc.contains("Engine.has_singleton("),
		"不再用 Engine.has_singleton 解析 autoload / no Engine.has_singleton lookup")
	gpCheck(not gpSrc.contains("Engine.get_singleton("),
		"不再用 Engine.get_singleton 取值 / no Engine.get_singleton lookup")
	var gpAt: int = gpSrc.find("func gpBuildRenderStyle")
	gpCheck(gpAt >= 0, "快照构建函数在场 / the snapshot builder is present")
	var gpBody: String = gpSrc.substr(gpAt, 300)
	gpCheck(gpBody.contains("\"Settings\""), "按名解析 Settings / resolves Settings by name")
	gpCheck(gpBody.contains("\"I18n\""), "按名解析 I18n / resolves I18n by name")
