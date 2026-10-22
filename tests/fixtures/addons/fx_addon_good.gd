extends GPIPIDAddon
# Fixture (B3): a minimal, well-formed addon. It exists only so the loader tests can prove that
# "a good addon is loaded, named and collected" — never scanned at application startup.
# 夹具（B3）：最小且格式正确的插件。它只用于让加载器测试证明「好插件会被加载、命名、收集」，
# 应用启动时绝不会扫描这里。

func _gpGetName() -> String:
	return "fixture.good"


func _gpGetTools() -> Array:
	return [{"action": "fixture_hello", "label": "Hello"}]


func _gpGetPanels() -> Array:
	return ["res://tests/fixtures/addons/fx_panel.tscn"]
