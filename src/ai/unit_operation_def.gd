class_name GPUnitOperationDef
extends Resource

# Chemical unit-operation standard design definition.
# 化工单元操作标准设计定义。
# See Dev Guide §4.5 / §4.6.2.
# 见开发指南 §4.5 / §4.6.2。

# Operation type, e.g. "centrifugal_pump"
# 操作类型，如 "离心泵"
var gpOpType: String = ""

# Input ports
# 输入端口
var gpInputs: Array = []

# Output ports
# 输出端口
var gpOutputs: Array = []

# Standard PID fragment template
# 标准图片段模板
var gpTemplate: GPPIDGraph = null


# Instantiate a PIDGraph fragment from scale params.
# 按规模参数实例化 PIDGraph 片段。
func gpInstantiate(gpParams: Dictionary) -> GPPIDGraph:
	return GPPIDGraph.new()
