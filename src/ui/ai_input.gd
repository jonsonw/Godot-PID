class_name AIInputBox
extends Control

# AI input box: natural language -> parse intent -> generate unit-op / symbol preview.
# v1.0 uses a rule engine (no cloud). See Dev Guide §4.4.1 / §4.6.2.
# AI 输入框：自然语言 → 解析意图 → 生成单元操作/图元预览。v1.0 走规则引擎（不接云端）。
# 见开发指南 §4.4.1 / §4.6.2。

signal submit(text: String)         # User submitted text / 用户提交文本
signal preview_ready(frag)          # A preview fragment is ready / 预览片段就绪

# TODO: parse text -> UnitOperationDef.instantiate(params)
# TODO：解析文本 → UnitOperationDef.instantiate(params)
