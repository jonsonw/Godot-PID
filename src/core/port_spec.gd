class_name GPPortSpec
extends RefCounted

# Copyright © 2026 Jonson Wang
# Build GPPort primitives from an array of port dicts (legacy / gpToDict output).
# 由端口字典数组（历史格式 / gpToDict 输出）构建 GPPort 原语。
# Centralized so GPSymbolDef, the pack builder and any importer share one mapping.
# 集中于此，使 GPSymbolDef、图元包构建器与任何导入器共用同一映射。

static func gpFromDicts(gpArr: Array) -> Array[GPPort]:
	var gpOut: Array[GPPort] = []
	for gpD in gpArr:
		var gpP: GPPort = GPPort.new()
		gpP.gpFromDict(gpD as Dictionary)
		gpOut.append(gpP)
	return gpOut


# Serialize an array of GPPort back to an array of dictionaries (for the normalizer's
# round-trip math, which still reasons about ports as dicts). Inverse of gpFromDicts.
# 把 GPPort 数组序列化回字典数组（供归一化器的往返数学使用，其仍以字典方式推理端口）。
# gpFromDicts 的逆操作。
static func gpToDicts(gpPorts: Array[GPPort]) -> Array:
	var gpOut: Array = []
	for gpP in gpPorts:
		gpOut.append(gpP.gpToDict())
	return gpOut
