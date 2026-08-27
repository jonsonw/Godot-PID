extends SceneTree

func _init() -> void:
	var gpPath: String = "res://src/ui/main_window.gd"
	print("Loading script: ", gpPath)
	var gpScript: GDScript = load(gpPath)
	if gpScript == null:
		print("FAILED: load returned null")
	else:
		print("OK: script loaded")
	quit()
