extends "res://tests/gp_test.gd"
# 架构优化 §4.2：钉住「render 层不读 autoload」这条闭合路径。
# Architecture §4.2: pin the closed path "the render layer never reads an autoload".
#
# 这套测试把 §4.2 的依赖注入机制钉死，专门针对最危险的失败模式——「切换语言 / 字号后，
# 旧视图的 style 没被更新，于是图上残留旧字号 / 旧文字」。四个断言分别覆盖：
#   1. GPRenderStyle 值对象正确携带纯数据（不依赖 autoload）；
#   2. GPGraphBinder.gpApplyStyle 把新快照重注入所有已有视图（钉住「忘记重注入」）；
#   3. 装配时新建的视图拿到注入的 style（钉住创建路径的注入无遗漏）；
#   4. 画布在 autoload 缺失（headless）时回落安全默认快照。
#
# This suite pins the §4.2 dependency-injection mechanism, aimed squarely at the worst failure
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
	gpEq(gpS.gpSymbolFontSize, 20, "字号透传 / font size passed")
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
	var gpS: GPRenderStyle = gpCv._gpBuildRenderStyle()
	gpCheck(gpS != null, "默认快照非空 / default snapshot non-null")
	gpEq(gpS.gpLocale, "zh_CN", "autoload 缺失时回落 zh_CN / falls back to zh_CN without autoload")
	gpEq(gpS.gpSymbolFontSize, 16, "autoload 缺失时回落 16 / falls back to 16")
	gpCv.free()
