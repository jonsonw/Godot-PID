extends GPIPIDAddon
# Fixture (B4): a contract-v2 addon — chat panel, tool definitions, validation hooks. It exists so
# the tests can prove the three new mount points are collected AND validated, and that a v1 addon
# (fx_addon_good.gd) still loads beside it untouched.
# 夹具（B4）：契约 v2 插件 —— 对话面板、工具定义、校验钩子。它让测试能证明三个新挂载点会被收集
# **并**校验，同时 v1 插件（fx_addon_good.gd）仍原样加载。

func _gpGetName() -> String:
	return "fixture.v2"


func _gpGetChatPanel() -> String:
	return "res://tests/fixtures/addons/fx_chat_panel.tscn"


func _gpGetToolDefs() -> Array:
	return [{
		"id": "fixture.echo",
		"description": "Echo the argument back",
		"args": {"text": "string"},
		"handler": "gpEcho",
	}]


func _gpGetValidationHooks() -> Array:
	return [{
		"id": "fixture.hook",
		"description": "Always reports nothing",
		"severity": "info",
		"handler": "gpNoFindings",
	}]
