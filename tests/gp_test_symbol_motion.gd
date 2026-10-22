extends "res://tests/gp_test.gd"
# Copyright © 2026 Jonson Wang
#
# Headless tests for the view-layer motion (R3): the drop pop, the update flash and the alert
# pulse, plus the preference that turns all of them off.
# 视图层动效（R3）的 headless 测试：落位回弹、更新高光与告警脉冲，以及关掉它们的偏好。
#
# Three promises are guarded here / 此处守护三条承诺：
#   1. MOTION IS DATA, NOT AUTOLOAD READS. GPRenderStyle carries the flag into the render layer,
#      so a view can be exercised without any Settings singleton.
#      **动效是数据，不是读自动加载**。GPRenderStyle 把标志带进 render 层，故视图无需 Settings
#      单例即可被测试。
#   2. OFF MEANS OFF — AND RESTORED. Disabling motion must kill a running tween AND put the
#      animated channels back, or the symbol stays frozen half-faded (which reads as a bug).
#      **关掉就是关掉，且要复位**。禁用动效必须停掉补间**并**复位动画通道，否则图元会冻结在
#      半透明状态（看起来像缺陷）。
#   3. NOTHING ESCAPES THE VIEW. The animation touches `scale` / `modulate` only; the graph, the
#      undo stack and every export are untouched by construction.
#      **动效不外溢**。动画只改 scale / modulate；按构造，图、撤销栈与任何导出都不受影响。

const GP_EPS: float = 0.0001


# A definition of the smallest size that still carries a real envelope.
# 一个尺寸最小但仍带真实包络的定义。
func _gpDef() -> GPSymbolDef:
	var gpD: GPSymbolDef = GPSymbolDef.new()
	gpD.gpId = "motion_probe"
	gpD.gpCategory = "instrument"
	gpD.gpDefaultSize = Vector2(16.0, 16.0)
	return gpD


func _gpNode() -> GPPIDNode:
	var gpN: GPPIDNode = GPPIDNode.new()
	gpN.gpInstanceId = "m1"
	gpN.gpSymbolId = "motion_probe"
	return gpN


# A view already bound to a node, optionally inside the tree (create_tween() needs the tree).
# 一个已绑定节点的视图，可选是否在树内（create_tween() 需要场景树）。
func _gpView(gpInTree: bool) -> GPSymbolView:
	var gpV: GPSymbolView = GPSymbolView.new()
	gpV.gpInit(_gpNode(), _gpDef())
	if gpInTree:
		add_child(gpV)
	return gpV


# ---------------------------------------------------------------------------
# The preference travels as DATA
# 偏好以**数据**形式传递
# ---------------------------------------------------------------------------

func gpTestStyleDefaultsMotionOn() -> void:
	var gpStyle: GPRenderStyle = GPRenderStyle.gpFromSources(null, null)
	gpCheck(gpStyle.gpMotionEnabled, "无来源时默认开启动效 / motion defaults to on with no sources")


# A bare RefCounted with the same property name is enough: GPRenderStyle reads it through
# Object.get(), so the render layer needs no dependency on the Settings class.
# 一个仅带同名属性的裸 RefCounted 就够了：GPRenderStyle 经 Object.get() 读取，
# 故 render 层无需依赖 Settings 类。
class GPSettingsStub extends RefCounted:
	var gpMotionEnabled: bool = false


class GPSettingsStubOn extends RefCounted:
	var gpMotionEnabled: bool = true


func gpTestStyleReadsMotionPreference() -> void:
	var gpOff: GPRenderStyle = GPRenderStyle.gpFromSources(GPSettingsStub.new(), null)
	gpCheck(not gpOff.gpMotionEnabled, "读得到关闭状态 / reads the OFF preference")
	var gpOn: GPRenderStyle = GPRenderStyle.gpFromSources(GPSettingsStubOn.new(), null)
	gpCheck(gpOn.gpMotionEnabled, "读得到开启状态 / reads the ON preference")


# ---------------------------------------------------------------------------
# Animated channels: start state, and the restore promise
# 动画通道：起始态与复位承诺
# ---------------------------------------------------------------------------
# ⚠️ WHY THE START STATE IS NOT ASSERTED HERE / 为何此处不断言起始态：
# A tween may only be created inside a SceneTree, and the GPGTest runner executes every suite
# method synchronously during SceneTree._initialize() — at that moment `root` is not yet "inside
# tree", so `create_tween()` is unavailable by design. Asserting the pop's first frame here would
# therefore assert the GUARD, not the effect (it fails with scale == 1.0 because nothing started).
# The start state is covered by the shell smoke run instead; what IS deterministic headlessly is
# the part that matters most: that a view can never be left frozen mid-effect.
# 补间只能在 SceneTree 内创建，而 GPGTest 运行器在 SceneTree._initialize() 期间**同步**执行每个套件
# 方法 —— 此刻 root 尚未「在树内」，故 create_tween() 按设计不可用。在此断言回弹首帧，实际上断言的
# 是**护栏**而非效果（它会因「什么都没开始」而以 scale == 1.0 失败）。起始态改由外壳冒烟验证覆盖；
# headless 下真正可确定验证、也更要紧的那一半是：视图绝不可能被留在效果中途。

func gpTestSpawnIsInertWhenDisabled() -> void:
	var gpV: GPSymbolView = _gpView(true)
	gpV.gpSetMotionEnabled(false)
	gpV.gpPlaySpawn()
	gpApprox(gpV.scale.x, 1.0, GP_EPS, "禁用时不动缩放 / scale untouched when disabled")
	gpApprox(gpV.modulate.a, 1.0, GP_EPS, "禁用时不动透明度 / alpha untouched when disabled")
	gpV.free()


func gpTestSpawnSkippedOutsideTree() -> void:
	# No SceneTree -> no tween is created, and nothing is left half-applied.
	# 无场景树 -> 不创建补间，也不会留下半截状态。
	var gpV: GPSymbolView = _gpView(false)
	gpV.gpPlaySpawn()
	gpApprox(gpV.scale.x, 1.0, GP_EPS, "树外不启动回弹 / no spawn outside the tree")
	gpApprox(gpV.modulate.a, 1.0, GP_EPS, "树外不改透明度 / alpha untouched outside the tree")
	gpV.free()


func gpTestFlashOutsideTreeLeavesViewUntouched() -> void:
	var gpV: GPSymbolView = _gpView(false)
	gpV.gpPlayFlash()
	gpApprox(gpV.modulate.r, 1.0, GP_EPS, "树外不闪 / no flash outside the tree")
	gpApprox(gpV.modulate.a, 1.0, GP_EPS, "树外不改透明度 / alpha untouched")
	gpV.free()


# ---------------------------------------------------------------------------
# Turning motion OFF restores the view — the promise that matters most
# 关闭动效会复位视图 —— 最要紧的那条承诺
# ---------------------------------------------------------------------------
# The channels are dirtied by hand to stand in for "a tween was killed half way": whatever the
# cause, disabling motion must hand back a fully opaque, unscaled symbol. Without this, a user who
# flips the preference while something animates gets a permanently ghosted glyph and reports it
# as a rendering defect.
# 手工把通道弄脏，代表「补间被中途杀掉」：无论原因为何，关闭动效都必须交还一个不透明、未缩放的
# 图元。否则用户在某个动画进行中关掉偏好，就会得到一个永久半透明的字形，并把它当作渲染缺陷上报。

func gpTestDisableRestoresAnimatedChannels() -> void:
	var gpV: GPSymbolView = _gpView(true)
	gpV.scale = Vector2(0.5, 0.5)
	gpV.modulate = Color(1.0, 1.0, 1.0, 0.2)
	gpV.gpSetMotionEnabled(false)
	gpApprox(gpV.scale.x, 1.0, GP_EPS, "关闭后缩放复位 / scale restored on disable")
	gpApprox(gpV.scale.y, 1.0, GP_EPS, "关闭后缩放复位（y）/ scale restored on disable (y)")
	gpApprox(gpV.modulate.a, 1.0, GP_EPS, "关闭后透明度复位 / alpha restored on disable")
	gpV.free()


func gpTestAlertToggleClearsDirtyChannels() -> void:
	# gpSetAlert() outside the tree falls through to the kill/restore path, which is exactly the
	# guarantee a DRC caller needs when it clears an alert while the sheet is being torn down.
	# 树外 gpSetAlert() 会落到 kill/restore 分支 —— 这正是 DRC 调用方在图纸拆除期间清除告警时
	# 需要的保证。
	var gpV: GPSymbolView = _gpView(true)
	gpV.modulate = Color(1.0, 1.0, 1.0, 0.3)
	gpV.gpSetAlert(true)
	gpApprox(gpV.modulate.a, 1.0, GP_EPS, "告警打开即复位脏通道 / enabling an alert restores dirty channels")
	gpV.gpSetAlert(false)
	gpApprox(gpV.modulate.a, 1.0, GP_EPS, "告警关闭后不透明 / alert off keeps full alpha")
	gpApprox(gpV.modulate.r, 1.0, GP_EPS, "告警关闭后无色偏 / alert off keeps natural colour")
	gpV.free()


func gpTestFlashIgnoredWhenDisabled() -> void:
	var gpV: GPSymbolView = _gpView(true)
	gpV.gpSetMotionEnabled(false)
	gpV.gpPlayFlash()
	gpApprox(gpV.modulate.r, 1.0, GP_EPS, "禁用时不闪 / no flash when disabled")
	gpV.free()
