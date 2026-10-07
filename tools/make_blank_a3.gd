extends SceneTree

# Generate a clean A3 starting sheet (frame on, bilingual title block pre-populated empty,
# DEXPI library available) for 1:1 tracing reproduction.
# 生成一张干净的 A3 起点图纸（图框开、双语标题栏预置空、DEXPI 图元库可用），供 1:1 追踪复刻。
#
# Output / 落点：默认写到 `user://blank_a3.pid.json`（**不落进仓库** —— 仓库不再分发样例工程，
# 2026-10-07 起）。需要指定位置时追加参数：
#   Godot --headless --script res://tools/make_blank_a3.gd -- /path/to/my_a3.pid.json
# The absolute path is printed so you can find the file immediately.
# 运行完会打印**绝对路径**，便于直接找到该文件。

func _initialize() -> void:
	var gpOutUser: PackedStringArray = OS.get_cmdline_user_args()
	var gpPath: String = "user://blank_a3.pid.json"
	if gpOutUser.size() > 0 and not str(gpOutUser[0]).is_empty():
		gpPath = str(gpOutUser[0])
	var gpSheet: GPSheet = GPSheet.gpNew("sheet-1", "", 0)
	gpSheet.gpWidthMM = 420.0
	gpSheet.gpHeightMM = 297.0
	gpSheet.gpFrameOn = true
	gpSheet.gpLabelMode = GPSheet.GP_LABEL_BOTH
	var gpErr: int = GPProjectIO.gpWriteSheets([gpSheet], gpPath)
	if gpErr != OK:
		printerr("ERROR: write failed, code ", gpErr)
		quit(1)
		return
	print("WROTE: ", gpPath, "  (abs: ", ProjectSettings.globalize_path(gpPath), ")")
	# Read it back to prove the round-trip, then print the dict shape.
	# 读回以验证往返，并打印字典形态。
	var gpRead: GPIOResult = GPProjectIO.gpReadSheets(gpPath)
	if not gpRead.gpIsOk():
		printerr("ERROR: read-back failed")
		quit(1)
		return
	var gpSheets: Array = gpRead.gpPayload as Array
	var gpS: GPSheet = gpSheets[0] as GPSheet
	print("OK sheets=%d size=%s x %s frame=%s mode=%d" % [
		gpSheets.size(), gpS.gpWidthMM, gpS.gpHeightMM, gpS.gpFrameOn, gpS.gpLabelMode])
	quit()
