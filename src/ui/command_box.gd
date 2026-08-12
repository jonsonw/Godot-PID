class_name CommandBox
extends Control

# CAD-style command input: LINE/RECT/TEXT/MOVE/COPY/ZOOM/ROTATE/DELETE + params.
# Equivalent to the toolbar; focuses with Ctrl+`.
# CAD 风格命令框：LINE/RECT/TEXT/MOVE/COPY/ZOOM/ROTATE/DELETE + 参数。
# 与工具栏等价，Ctrl+` 聚焦。
# See Dev Guide §4.4.1.
# 见开发指南 §4.4.1。

signal command_entered(cmd: String)  # A command was entered / 命令输入完成

# TODO: parse command string -> Canvas2D / selection actions
# TODO：解析命令字符串 → Canvas2D / 选择动作
