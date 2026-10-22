extends GPIPIDAddon
# Fixture (B3): declares the SAME id as the good one — the loader must refuse it rather than let
# two addons fight over one injection point.
# 夹具（B3）：声明了与好插件**相同**的 id —— 加载器必须拒绝它，而不是让两个插件抢一个注入点。

func _gpGetName() -> String:
	return "fixture.good"
