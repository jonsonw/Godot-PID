extends "res://tests/gp_test.gd"
# Headless regression tests for the two new connection features (endpoint-to-endpoint + auto-route
# + crossing break rendering). Pure static modules are exercised directly; the canvas wiring is
# covered by the integration suite. These guards lock the drafting RULES so a future edit cannot
# silently flip which line breaks at a crossing or which endpoints may be joined.
# 连线新功能（端点对端点 + 自动布线 + 交叉断线渲染）的 headless 回归测试。纯静态模块直接驱动；
# 画布接线由集成套件覆盖。此处守护「制图规则」，使日后改动无法静默翻转交叉处哪条线断、或哪两端可连。

const GP_EPS: float = 0.5


# ============================ GPPortAnchor：连接合法性 ============================

func gpTestWishFor() -> void:
	gpEq(GPPortAnchor.gpWishFor(GPPort.GP_NOZZLE), "pipe", "nozzle wants a pipe")
	gpEq(GPPortAnchor.gpWishFor(GPPort.GP_SIGNAL), "signal", "signal end wants a signal line")
	gpEq(GPPortAnchor.gpWishFor(GPPort.GP_TERMINAL), "any", "terminal accepts either kind")


func gpTestConnectKindFor() -> void:
	gpEq(GPPortAnchor.gpConnectKindFor(GPPort.GP_NOZZLE, GPPort.GP_NOZZLE), GPPIDEdge.GP_PROCESS,
		"nozzle + nozzle -> PROCESS")
	gpEq(GPPortAnchor.gpConnectKindFor(GPPort.GP_SIGNAL, GPPort.GP_ACTUATOR), GPPIDEdge.GP_SIGNAL,
		"signal + actuator -> SIGNAL")
	# A pipe and a signal line may NEVER be joined. / 管道与信号线绝不相连。
	gpEq(GPPortAnchor.gpConnectKindFor(GPPort.GP_NOZZLE, GPPort.GP_SIGNAL), "",
		"nozzle + signal -> illegal (empty kind)")


func gpTestValidatePair() -> void:
	var gpA: Dictionary = GPPortAnchor.gpMakeAnchor("n1", "p1", Vector2.ZERO, Vector2.RIGHT, GPPort.GP_NOZZLE)
	var gpB: Dictionary = GPPortAnchor.gpMakeAnchor("n2", "p2", Vector2(100, 0), Vector2.LEFT, GPPort.GP_NOZZLE)
	var gpC: Dictionary = GPPortAnchor.gpMakeAnchor("n1", "p1", Vector2.ZERO, Vector2.RIGHT, GPPort.GP_NOZZLE)
	gpEq(GPPortAnchor.gpValidatePair(gpA, gpB), GPPortAnchor.GP_REFUSAL_NONE, "two compatible ends are legal")
	gpEq(GPPortAnchor.gpValidatePair(gpA, gpC), GPPortAnchor.GP_REFUSAL_SELF_LOOP, "the same port is a self-loop")
	var gpSig: Dictionary = GPPortAnchor.gpMakeAnchor("n3", "s1", Vector2.ZERO, Vector2.UP, GPPort.GP_SIGNAL)
	gpEq(GPPortAnchor.gpValidatePair(gpA, gpSig), GPPortAnchor.GP_REFUSAL_TYPE, "nozzle + signal is a type mismatch")


# ============================ GPEdgeCrossing：断线优先级 ============================

func _gpLine(gpId: String, gpKind: String, gpA: Vector2, gpB: Vector2) -> Dictionary:
	return {"id": gpId, "kind": gpKind, "pts": PackedVector2Array([gpA, gpB])}


# Rule a: PROCESS vs PROCESS -> the VERTICAL run breaks, the horizontal stays whole.
# 规则 a：主工艺对主工艺 -> 竖向断，横向连续。
func gpTestProcessVsProcessVerticalBreaks() -> void:
	var gpH: Dictionary = _gpLine("H", GPPIDEdge.GP_PROCESS, Vector2(0, 0), Vector2(100, 0))
	var gpV: Dictionary = _gpLine("V", GPPIDEdge.GP_PROCESS, Vector2(50, -50), Vector2(50, 50))
	var gpCross: Array[Dictionary] = GPEdgeCrossing.gpFindCrossings([gpV, gpH])
	gpEq(gpCross.size(), 1, "exactly one crossing is detected")
	gpEq(str(gpCross[0].get("broken")), "V", "the vertical process line breaks")


# Rule b: UTILITY vs any PROCESS -> the UTILITY line always breaks.
# 规则 b：次要管线对任意主工艺 -> 次要管线恒断。
func gpTestUtilityYieldsToProcess() -> void:
	var gpV: Dictionary = _gpLine("U", GPPIDEdge.GP_UTILITY, Vector2(50, -50), Vector2(50, 50))
	var gpH: Dictionary = _gpLine("P", GPPIDEdge.GP_PROCESS, Vector2(0, 0), Vector2(100, 0))
	var gpCross: Array[Dictionary] = GPEdgeCrossing.gpFindCrossings([gpH, gpV])
	gpEq(str(gpCross[0].get("broken")), "U", "the utility line breaks against a process line")


# Rule c: SIGNAL vs any PROCESS -> the SIGNAL line always breaks.
# 规则 c：信号线对任意主工艺 -> 信号线恒断。
func gpTestSignalYieldsToProcess() -> void:
	var gpV: Dictionary = _gpLine("S", GPPIDEdge.GP_SIGNAL, Vector2(50, -50), Vector2(50, 50))
	var gpH: Dictionary = _gpLine("P", GPPIDEdge.GP_PROCESS, Vector2(0, 0), Vector2(100, 0))
	var gpCross: Array[Dictionary] = GPEdgeCrossing.gpFindCrossings([gpH, gpV])
	gpEq(str(gpCross[0].get("broken")), "S", "the signal line breaks against a process line")


# Two lines that share an endpoint (a tee onto one port) must NOT count as a crossing.
# 共用端点（同一端口上的两支）不算交叉。
func gpTestSharedEndpointIsNotACrossing() -> void:
	var gpA: Dictionary = _gpLine("A", GPPIDEdge.GP_PROCESS, Vector2(0, 0), Vector2(100, 0))
	var gpB: Dictionary = _gpLine("B", GPPIDEdge.GP_PROCESS, Vector2(100, 0), Vector2(100, 100))
	var gpCross: Array[Dictionary] = GPEdgeCrossing.gpFindCrossings([gpA, gpB])
	gpEq(gpCross.size(), 0, "touching at a shared endpoint is not a crossing")


# ============================ GPEdgeAutoRoute：正交避障 ============================

func gpTestAutoRouteAvoidsObstacle() -> void:
	# A -> B straight across is blocked by a box right in the middle. / A→B 直线被中央方框挡住。
	var gpFrom: Dictionary = {"pos": Vector2(0, 0), "dir": Vector2(1, 0), "bound": true}
	var gpTo: Dictionary = {"pos": Vector2(200, 0), "dir": Vector2(-1, 0), "bound": true}
	var gpObs: Array[Rect2] = [Rect2(80, -20, 40, 40)]  # x 80..120, y -20..20
	var gpPath: PackedVector2Array = GPEdgeAutoRoute.gpRouteAuto(gpFrom, gpTo, gpObs, [])
	gpCheck(gpPath.size() >= 4, "an obstacle forces a detour (more bends than a straight line)")

	# Every leg is axis-aligned. / 每段轴对齐。
	for gpI in range(gpPath.size() - 1):
		var gpDx: float = absf(gpPath[gpI].x - gpPath[gpI + 1].x)
		var gpDy: float = absf(gpPath[gpI].y - gpPath[gpI + 1].y)
		gpCheck(gpDx < GP_EPS or gpDy < GP_EPS, "leg %d is axis-aligned" % gpI)

	# No leg midpoint sits strictly inside the blocker. / 没有任一段中点落在障碍物内部。
	for gpI in range(gpPath.size() - 1):
		var gpMid: Vector2 = (gpPath[gpI] + gpPath[gpI + 1]) * 0.5
		for gpR in gpObs:
			var gpInside: bool = gpMid.x > gpR.position.x + GP_EPS and gpMid.x < gpR.position.x + gpR.size.x - GP_EPS \
				and gpMid.y > gpR.position.y + GP_EPS and gpMid.y < gpR.position.y + gpR.size.y - GP_EPS
			gpCheck(not gpInside, "leg %d clears the obstacle" % gpI)
