extends "res://tests/gp_test.gd"
# Headless tests for the autosave POLICY state machine (ADR-9).
# 自动保存**策略**状态机（ADR-9）的 headless 测试。
# WHY / 为何要这些测试：
# the arming rule ("only after the first successful save") and the two cadences are the whole
# contract of this feature. They are pure state, so they can be pinned here without a Timer,
# a real clock, or a scene tree — and a careless refactor that flips "dirty -> 1 min" into
# "dirty -> 5 min" is exactly the kind of regression no screenshot would ever reveal.
# 启用规则（「仅在首次保存成功后」）与两档节拍就是本功能的全部契约。它们是纯状态，
# 因此可在此无 Timer、无真实时钟、无场景树地钉住 —— 而把「脏 -> 1 分钟」粗心改成
# 「脏 -> 5 分钟」这类回归，正是任何截图都永远看不出来的。


# Fresh service starts DISARMED: a never-saved document has no path worth protecting.
# 全新服务默认**关闭**：从未保存过的文档没有值得保护的路径。
func gpTestAutosaveStartsDisarmed() -> void:
	var gpSvc: GPAutoSaveService = GPAutoSaveService.new()
	gpCheck(not gpSvc.gpIsArmed(), "autosave must start disarmed until the first save")


# Defaults match ADR-9: 1 minute while dirty, 5 minutes while idle.
# 默认值符合 ADR-9：脏时 1 分钟，空闲时 5 分钟。
func gpTestAutosaveDefaultCadences() -> void:
	var gpSvc: GPAutoSaveService = GPAutoSaveService.new()
	gpApprox(gpSvc.gpActiveInterval(), 60.0, 1e-6, "dirty cadence defaults to 60s")
	gpApprox(gpSvc.gpIdleInterval(), 300.0, 1e-6, "idle cadence defaults to 300s")
	gpApprox(GPAutoSaveService.GP_ACTIVE_INTERVAL_SEC, 60.0, 1e-6, "active constant is 60s")
	gpApprox(GPAutoSaveService.GP_IDLE_INTERVAL_SEC, 300.0, 1e-6, "idle constant is 300s")


# The interval tracks the dirty flag: dirty picks the short cadence, clean the long one.
# 间隔跟随脏标记：脏取短节拍，干净取长节拍。
func gpTestAutosaveIntervalFollowsDirty() -> void:
	var gpSvc: GPAutoSaveService = GPAutoSaveService.new()
	gpApprox(gpSvc.gpIntervalFor(true), 60.0, 1e-6, "a dirty document waits 60s")
	gpApprox(gpSvc.gpIntervalFor(false), 300.0, 1e-6, "a clean document waits 300s")


# Arming is a one-way latch for the session; disarming is available but not used by the flow.
# 启用是本会话内的单向闩锁；关闭虽可用但流程中未使用。
func gpTestAutosaveArmDisarm() -> void:
	var gpSvc: GPAutoSaveService = GPAutoSaveService.new()
	gpSvc.gpArm()
	gpCheck(gpSvc.gpIsArmed(), "gpArm() must arm autosave")
	gpSvc.gpDisarm()
	gpCheck(not gpSvc.gpIsArmed(), "gpDisarm() must disarm autosave")


# gpConfigure overrides the cadences and clamps garbage (zero / negative) to a 1s floor.
# gpConfigure 覆盖节拍，并把垃圾值（0 / 负数）夹到 1 秒下限。
func gpTestAutosaveConfigureClamps() -> void:
	var gpSvc: GPAutoSaveService = GPAutoSaveService.new()
	gpSvc.gpConfigure(30.0, 120.0)
	gpApprox(gpSvc.gpIntervalFor(true), 30.0, 1e-6, "configured active cadence wins")
	gpApprox(gpSvc.gpIntervalFor(false), 120.0, 1e-6, "configured idle cadence wins")
	gpSvc.gpConfigure(-5.0, 0.0)
	gpApprox(gpSvc.gpIntervalFor(true), 1.0, 1e-6, "a non-positive active cadence clamps to 1s")
	gpApprox(gpSvc.gpIntervalFor(false), 1.0, 1e-6, "a non-positive idle cadence clamps to 1s")
