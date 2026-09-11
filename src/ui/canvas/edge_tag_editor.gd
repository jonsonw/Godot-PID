class_name GPEdgeTagEditor
extends RefCounted

# In-place line-number editor for a P&ID edge (P3-4). A floating LineEdit is shown over the
# selected edge's midpoint; typing a new tag and pressing Enter (or clicking away) commits it
# through the canvas edit port, so the rename is ONE undo step. While the editor is open the
# canvas freezes pan/zoom so the field cannot drift off the pipe.
# 一条边的就地管线号编辑器（P3-4）。一个浮层 LineEdit 显示在该边中点的上方；输入新位号并回车
# （或点击别处）即经画布编辑端口提交，使重命名成为一个撤销步。编辑器打开期间画布冻结平移/缩放，
# 字段不会偏离管线。
#
# Why a canvas delegate (not a free module) / 为何是画布委托：
#   it owns a UI node (a LineEdit) that must live in the canvas tree and must reach the model
#   through the same edit ports as every other interaction. Mirrors GPAnnotationEditor's
#   "holds the canvas reference" shape.
#   它持有一个 UI 节点（LineEdit），必须挂在画布子树中，并须经与其它交互相同的编辑端口触达模型。
#   与 GPAnnotationEditor「持有画布引用」的形状一致。

# The canvas that owns the live graph + the edit ports. / 持有实时图与编辑端口的画布。
var gpCv: GPCanvas2D

# The LineEdit overlay (created lazily on first open so headless import stays node-free).
# 浮层 LineEdit（首次打开时惰性创建，使无界面导入不引入节点）。
var _gpEdit: LineEdit = null

# Edge id currently being edited ("" = none). / 当前正在编辑的边 id（"" 表示无）。
var _gpEdgeId: String = ""

# True while the field is open and capturing input. / 字段打开并接收输入时为真。
var _gpActive: bool = false


func _init(gpCanvas: GPCanvas2D) -> void:
	gpCv = gpCanvas


# Is the in-place editor open? The canvas polls this to freeze pan/zoom.
# 就地编辑器是否打开？画布据此冻结平移/缩放。
func gpIsEditing() -> bool:
	return _gpActive


# Lazily build the LineEdit and parent it to the canvas.
# 惰性构建 LineEdit 并挂到画布。
func _gpEnsureEdit() -> LineEdit:
	if _gpEdit != null:
		return _gpEdit
	var gpEdit: LineEdit = LineEdit.new()
	gpEdit.focus_mode = Control.FOCUS_CLICK
	gpEdit.size = Vector2(120.0, 26.0)
	gpEdit.max_length = 24
	# Commit on Enter; close+commit when focus leaves (clicking another edge, the canvas, etc.).
	# 回车提交；焦点离开（点另一条边、点画布等）时关闭并提交。
	gpEdit.text_submitted.connect(_gpOnSubmitted)
	gpEdit.focus_exited.connect(_gpOnFocusExited)
	gpCv.add_child(gpEdit)
	_gpEdit = gpEdit
	return gpEdit


# Open the editor for gpEdgeId, pre-filled with its current tag, and grab focus.
# 为 gpEdgeId 打开编辑器，预填当前位号，并夺取焦点。
func gpOpen(gpEdgeId: String) -> void:
	if gpCv.gpGraph == null:
		return
	var gpE: GPPIDEdge = gpCv.gpGraph.gpGetEdge(gpEdgeId)
	if gpE == null:
		return
	_gpEdgeId = gpEdgeId
	var gpEdit: LineEdit = _gpEnsureEdit()
	gpEdit.text = gpE.gpTag
	gpEdit.editable = true
	gpCv.gpSetEdgeSelection([gpEdgeId])
	_gpReposition()
	gpEdit.show()
	gpEdit.grab_focus()
	gpEdit.select_all()
	_gpActive = true
	gpCv.queue_redraw()


# Close the editor without committing (ESC path). / 不提交而关闭编辑器（ESC 路径）。
func gpClose() -> void:
	_gpActive = false
	_gpEdgeId = ""
	if _gpEdit != null:
		_gpEdit.release_focus()
		_gpEdit.hide()
	gpCv.queue_redraw()


# Reposition the field over the edge midpoint in screen coordinates (canvas-local, since the
# LineEdit is a child of the canvas). Called on open; pan/zoom is frozen while editing, so the
# midpoint never moves underneath it.
# 把字段定位在该边中点的屏幕坐标处（画布局部，因 LineEdit 是画布子节点）。打开时调用；编辑期间
# 平移/缩放被冻结，故中点不会移动到它下面。
func _gpReposition() -> void:
	if _gpEdit == null:
		return
	var gpMid: Vector2 = gpCv.gpEdgeGrips.gpEdgeMidpointWorld(_gpEdgeId)
	if gpMid == Vector2.INF:
		return
	var gpS: Vector2 = gpCv.gpScreenFromWorld(gpMid)
	_gpEdit.position = gpS - _gpEdit.size * 0.5


# Enter commits. / 回车提交。
func _gpOnSubmitted(_gpText: String) -> void:
	_gpCommit()


# Focus lost: commit (the field is closing anyway). Guarded so an explicit gpClose() that also
# releases focus does not double-commit.
# 焦点离开：提交（字段本就要关闭）。加护栏，使显式 gpClose() 释放焦点时不会重复提交。
func _gpOnFocusExited() -> void:
	if _gpActive:
		_gpCommit()


# Write the typed tag through the canvas port (one undo step) and close.
# 经画布端口写入键入的位号（一个撤销步）并关闭。
func _gpCommit() -> void:
	var gpId: String = _gpEdgeId
	var gpText: String = ""
	if _gpEdit != null:
		gpText = _gpEdit.text
	_gpActive = false
	_gpEdgeId = ""
	# A duplicate / manual tag is accepted; the command flags tag_manual so a future renumber
	# skips it. Failure here means the edge vanished mid-edit — just close.
	# 重复 / 手工位号被接受；命令会打 tag_manual 标记，使今后的重编号跳过它。
	# 此处失败说明边在编辑期间被删除 —— 直接关闭。
	if gpCv.gpGraph != null and gpCv.gpGraph.gpGetEdge(gpId) != null:
		gpCv.gpRequestSetEdgeTag(gpId, gpText)
	gpCv.gpEmitStatus()
	if _gpEdit != null:
		_gpEdit.hide()
	gpCv.queue_redraw()
