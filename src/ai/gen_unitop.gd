class_name GenUnitOp
extends RefCounted

# Generate chemical unit-operation standard designs: rule templates -> PIDGraph fragment.
# 生成化工单元操作标准设计：规则模板 → PIDGraph 片段。
# See Dev Guide §4.6.2.
# 见开发指南 §4.6.2。

# Generate a standard PID fragment from a unit-op definition and params.
# 按单元操作定义与参数生成标准图片段。
func generate_unit_op(def: UnitOperationDef, params: Dictionary) -> PIDGraph:
	return PIDGraph.new()
