extends SceneTree

# Generate docs/samples/blank_a3.pid.json — a clean A3 starting sheet (frame on, bilingual
# title block pre-populated empty, DEXPI library available) for 1:1 tracing reproduction.
# 生成空白 A3 模板：干净的 A3 起点图纸（图框开、双语标题栏预置空、DEXPI 图元库可用），
# 供 1:1 追踪复刻使用。
# Run: Godot --headless --script res://tools/make_blank_a3.gd
# 运行：Godot --headless --script res://tools/make_blank_a3.gd

func _initialize() -> void:
	var gpSheet: GPSheet = GPSheet.gpNew("sheet-1", "", 0)
	gpSheet.gpWidthMM = 420.0
	gpSheet.gpHeightMM = 297.0
	gpSheet.gpFrameOn = true
	gpSheet.gpLabelMode = GPSheet.GP_LABEL_BOTH
	var gpPath: String = "res://docs/samples/blank_a3.pid.json"
	var gpErr: int = GPProjectIO.gpWriteSheets([gpSheet], gpPath)
	if gpErr != OK:
		printerr("ERROR: write failed, code ", gpErr)
		quit(1)
		print("WROTE: ", gpPath)
	# Read it back to prove the round-trip, then print the dict shape.
	# 读回以验证往返，并打印字典形态。
	var gpRead: GPIOResult = GPProjectIO.gpReadSheets(gpPath)
	if not gpRead.gpIsOk():
		printerr("ERROR: read-back failed")
		quit(1)
	var gpSheets: Array = gpRead.gpPayload as Array
	var gpS: GPSheet = gpSheets[0] as GPSheet
	print("OK sheets=%d size=%s x %s frame=%s mode=%d" % [
		gpSheets.size(), gpS.gpWidthMM, gpS.gpHeightMM, gpS.gpFrameOn, gpS.gpLabelMode])
	quit()
