extends Node
# Fixture (B3): a script that is NOT an addon. Instantiable, but wrong type — must be recorded as
# refused, not crashed on.
# 夹具（B3）：一个**不是插件**的脚本。可实例化但类型不对 —— 必须被记录为拒绝，而不是当场崩。

func _ready() -> void:
	queue_free()
