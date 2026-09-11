extends SceneTree
# Headless reproduction + verification for the gpSetEdgeSelection signal-type crash:
#   "Cannot convert argument 1 from Array to Array" when emitting gpSelectionChanged([]).
# The crash only fires at RUNTIME (signal emit), not at compile time, so it needs a real
# emit. GPCanvas2D's dependency chain references the I18n / Settings autoloads as globals;
# under `--script` those singletons are absent, so we register lightweight stand-ins via
# Engine.register_singleton BEFORE loading the canvas, letting its whole script graph compile.
# 复现并验证 gpSetEdgeSelection 的信号类型崩溃（向 gpSelectionChanged 传裸 [] 报
# "Array -> Array[String]" 转换错误）。该错误只在运行时（信号发射）触发，不在编译期，
# 故需真实发射。GPCanvas2D 依赖链把 I18n / Settings 自动加载当作全局引用；`--script` 下
# 它们缺失，故在加载画布前先用 Engine.register_singleton 注册轻量占位，使其整条脚本图可编译。
#
# Run: Godot --headless --path . --script res://tests/smoke_selection_emit.gd
# 运行：Godot --headless --path . --script res://tests/smoke_selection_emit.gd

func _initialize() -> void:
	# Register the autoloads the canvas depends on so its script graph compiles headlessly.
	# We only need the global identifiers to RESOLVE at compile time; gpSetEdgeSelection
	# does not call I18n/Settings methods at runtime (the canvas guards missing autoloads),
	# so plain Node stand-ins are enough.
	# 注册画布依赖的自动加载单例，使其脚本图在无界面下可编译。只需全局标识符在编译期可解析；
	# gpSetEdgeSelection 运行时不调用 I18n/Settings 方法（画布对缺失自动加载有护栏），故普通 Node 占位即可。
	Engine.register_singleton("I18n", Node.new())
	Engine.register_singleton("Settings", Node.new())

	var CanvasCls := load("res://src/ui/canvas/canvas_2d.gd")
	var canvas = CanvasCls.new()
	root.add_child(canvas)  # triggers _ready (autoloads guarded -> uses fallback bus)
	var got: Array[String] = []
	var count_arr := [0]  # Array wrapper: GDScript lambda capture of an int does not write back.
	canvas.gpEvents.gpSelectionChanged.connect(func(ids: Array[String]) -> void:
		got.clear()
		got.append_array(ids)  # mutate (not reassign) so the captured Array writes back
		count_arr[0] += 1
	)
	# P3 path: select an edge -> emits selection-changed (was crashing at this call).
	# 用与真实调用方相同形态的具类型数组变量（select_tool 传 [gpEdgeHit]，由 String 变量推断为
	# Array[String]），而非裸字面量（裸字面量在 --script 下不推断类型，会触发另一处同类报错）。
	# P3 路径：选中边 -> 发射选择变更（此前此处崩溃）。
	var e1: Array[String] = ["E1"]
	canvas.gpSetEdgeSelection(e1)
	# Clearing path: empty edge selection -> emits empty node selection (the crash line).
	# 清空路径：空边选择 -> 发射空节点选择（即报错那一行）。
	var empty: Array[String] = []
	canvas.gpSetEdgeSelection(empty)
	# A non-empty node selection also routes through the same typed emit (gpSetSelection).
	# 非空节点选择同样经同一有类型 emit 路径（gpSetSelection）。
	var n1: Array[String] = ["N1"]
	canvas.gpSetSelection(n1)
	print("SMOKE_SELECTION_OK count=", count_arr[0], " last_ids_size=", got.size())
	quit(0)
