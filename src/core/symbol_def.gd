class_name SymbolDef
extends Resource

## 图元定义：数据驱动，避免为每个符号建一个类。
## 符号库用 SymbolDef 数组即可；渲染层按 category + id 匹配绘制。

@export var id: String = ""
@export var display_name: String = ""
@export var category: String = "general"  ## general / valve / tank / pump / instrument ...
@export var icon_path: String = ""        ## res://assets/symbols/xxx.svg
@export var default_size: Vector2 = Vector2(64, 64)
@export var ports: Array[Dictionary] = []  ## [{"name":"in","pos":[-32,0]},{"name":"out","pos":[32,0]}]
@export var attrs_schema: Dictionary = {}  ## 可填写的属性模板


func to_dict() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"category": category,
		"icon_path": icon_path,
		"default_size": [default_size.x, default_size.y],
		"ports": ports.duplicate(),
		"attrs_schema": attrs_schema.duplicate(),
	}
