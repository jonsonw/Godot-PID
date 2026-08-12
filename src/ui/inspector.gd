class_name Inspector
extends ScrollContainer

# Property panel: edit the selected node's attrs.
# 属性面板：编辑选中节点的 attrs。
# See Dev Guide §4.4.
# 见开发指南 §4.4。

signal attr_changed(id: String, key: String, val)  # An attribute was edited / 属性被编辑

# TODO: build form from SymbolDef.attrs_schema of the selected node
# TODO：按选中节点 SymbolDef.attrs_schema 生成表单
