class_name UnitOperationDef
extends Resource

# Chemical unit-operation standard design definition.
# 化工单元操作标准设计定义。
# See Dev Guide §4.5 / §4.6.2.
# 见开发指南 §4.5 / §4.6.2。

var op_type: String = ""        # Operation type, e.g. "centrifugal_pump" / 操作类型，如 "离心泵"
var inputs: Array = []          # Input ports / 输入端口
var outputs: Array = []         # Output ports / 输出端口
var template: PIDGraph = null   # Standard PID fragment template / 标准图片段模板

# Instantiate a PIDGraph fragment from scale params.
# 按规模参数实例化 PIDGraph 片段。
func instantiate(params: Dictionary) -> PIDGraph:
	return PIDGraph.new()
