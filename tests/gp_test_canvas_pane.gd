extends "res://tests/gp_test.gd"
# Headless tests for the PANE canvas attach contract (multi-view, ADR-44 / D05).
# 多视图窗格画布挂载契约（ADR-44 / D05）的 headless 测试。
#
# Godot's add_child() ERRORS on a node that already has a parent — it never auto-reparents.
# gpAttachCanvas therefore owns EXPLICIT reparent semantics, verified here without a scene
# tree (the pane is driven with a bare host Control; the hint label stays null, which the
# null guards tolerate).
# Godot 的 add_child() 对已有父节点的节点直接报错 —— 绝不自动 reparent。因此
# gpAttachCanvas 持有**显式** reparent 语义，此处无场景树验证（窗格由裸 host Control
# 驱动；提示标签保持 null，空护栏可以容忍）。
#
# Three promises are guarded here / 此处守护三条承诺：
#   1. IDEMPOTENT AT HOME. Re-attaching the SAME canvas to the SAME pane never re-adds it
#      (the pane picker re-fires _gpAttachAllPanes even when nothing changed — the
#      "already has a parent (same host)" console error the user hit).
#      **在家中时幂等**。同一画布重挂同一窗格绝不重复添加（窗格选择器即使什么都没变也会
#      重发 _gpAttachAllPanes —— 用户撞上的「已有父节点（同一承载区）」控制台报错）。
#   2. A SWAP MOVES, NEVER STEALS BLINDLY. Attaching a canvas that still lives in another
#      host takes it out of that host first — both panes end up holding exactly one canvas.
#      **交换是搬移、不是盲抢**。挂载仍住在另一承载区的画布时先把它从那带走 —— 两个窗格
#      最终各恰持一个画布。
#   3. DETACH PHYSICALLY LEAVES. Detach returns the canvas with a null parent (layout
#      switches queue_free the pane tree — a canvas left inside would die with it), and a
#      second detach is a harmless null.
#      **摘出即物理离开**。摘出交回的画布父节点为 null（切换布局会 queue_free 窗格树 ——
#      留在里面的画布会随之死亡），二次摘出是无害的 null。


func gpTestAttachIdempotentAtHome() -> void:
	var gpPane: GPCanvasPane = GPCanvasPane.new()
	gpPane.gpHost = Control.new()
	var gpCv: GPCanvas2D = GPCanvas2D.new()
	gpPane.gpAttachCanvas(gpCv)
	gpEq(gpCv.get_parent(), gpPane.gpHost, "首挂应进入承载区")
	gpEq(gpPane.gpHost.get_child_count(), 1, "承载区应恰有一个画布")
	# The re-attach that used to throw "already has a parent (same host)":
	# 曾经抛「已有父节点（同一承载区）」的那次重挂：
	gpPane.gpAttachCanvas(gpCv)
	gpEq(gpCv.get_parent(), gpPane.gpHost, "重挂同画布应幂等")
	gpEq(gpPane.gpHost.get_child_count(), 1, "重挂后承载区仍应恰有一个画布")
	gpEq(gpPane.gpCanvas(), gpCv, "gpCanvas 应交回该画布")


func gpTestAttachMovesFromOtherHost() -> void:
	var gpPaneA: GPCanvasPane = GPCanvasPane.new()
	var gpPaneB: GPCanvasPane = GPCanvasPane.new()
	gpPaneA.gpHost = Control.new()
	gpPaneB.gpHost = Control.new()
	var gpCvB: GPCanvas2D = GPCanvas2D.new()
	var gpCvA: GPCanvas2D = GPCanvas2D.new()
	gpPaneA.gpAttachCanvas(gpCvA)
	gpPaneB.gpAttachCanvas(gpCvB)
	# The swap: A takes B's canvas (which still lives in B's host) and B takes A's —
	# exactly what _gpAttachAllPanes does after a picker swap.
	# 交换：A 拿走 B 的画布（它还住在 B 的承载区里）、B 拿走 A 的 —— 正是选择器交换后
	# _gpAttachAllPanes 所做的事。
	gpPaneA.gpAttachCanvas(gpCvB)
	gpPaneB.gpAttachCanvas(gpCvA)
	gpEq(gpCvB.get_parent(), gpPaneA.gpHost, "B 的画布应搬到 A 的承载区")
	gpEq(gpCvA.get_parent(), gpPaneB.gpHost, "A 的画布应搬到 B 的承载区")
	gpEq(gpPaneA.gpHost.get_child_count(), 1, "A 承载区应恰有一个画布")
	gpEq(gpPaneB.gpHost.get_child_count(), 1, "B 承载区应恰有一个画布")
	gpEq(gpPaneA.gpCanvas(), gpCvB, "A 的登记应跟随搬移")
	gpEq(gpPaneB.gpCanvas(), gpCvA, "B 的登记应跟随搬移")


func gpTestDetachPhysicallyLeaves() -> void:
	var gpPane: GPCanvasPane = GPCanvasPane.new()
	gpPane.gpHost = Control.new()
	var gpCv: GPCanvas2D = GPCanvas2D.new()
	gpPane.gpAttachCanvas(gpCv)
	var gpOut: GPCanvas2D = gpPane.gpDetachCanvas()
	gpEq(gpOut, gpCv, "摘出应交回画布")
	gpEq(gpCv.get_parent(), null, "摘出后画布应物理离开（父为空）")
	gpEq(gpPane.gpCanvas(), null, "摘出后窗格应遗忘画布")
	gpEq(gpPane.gpDetachCanvas(), null, "二次摘出应无害交回空")
	# A null attach is safe at any time (placeholder mode).
	# 任意时刻传 null 挂载都安全（占位模式）。
	gpPane.gpAttachCanvas(null)
	gpEq(gpPane.gpCanvas(), null, "空挂载后仍应无画布")
