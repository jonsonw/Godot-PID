class_name GPFrameEditor
extends Control

# Frame editor: visually adjust sheet size / border / title block / revision table;
# writes back to the active PIDDocument.frame.
# 图框编辑器：可视化调幅面/边框/标题栏/版次表；写回当前 PIDDocument.frame。
# See Dev Guide §4.4.2.
# 见开发指南 §4.4.2。

# Frame was edited
# 图框被编辑
signal gpFrameChanged(gpFrame)

# TODO: bind UI controls to FrameDef fields, emit frame_changed
# TODO：将 UI 控件绑定到 FrameDef 字段，发出 frame_changed
