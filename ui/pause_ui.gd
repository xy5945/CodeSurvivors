class_name PauseUI
extends CanvasLayer
##
## 游戏内暂停（ESC 呼出）：返回游戏 / 游戏说明 / 退出游戏。
##
## 「退出游戏」= 放弃这一局、回到标题页，**不是关掉程序**（main._on_pause_quit）。
## 玩家点它的意思是"这局不想玩了"，直接退出进程会把所有进度一并带走，
## 而且标题页没有退出入口的话，还以为是把游戏关了。
##
## 三个必须做对的地方，和升级弹窗、结算面板同一套：
##   1. process_mode = WHEN_PAUSED —— 整棵树都暂停了，默认收不到输入
##   2. 打开显示光标、关闭隐藏 —— 游戏里光标挡视线
##   3. 固定 position/size，不用 set_anchors_preset（父节点没布局完时 offset 会算错）
##
## 说明页从这里打开时，返回要回到**这里**而不是标题页，
## 所以 HelpUI.open() 要带来源标识，见 HelpUI._from。
##

signal resume_requested
signal help_requested
signal quit_requested

const C_TITLE := Color(1.0, 0.88, 0.42, 1.0)
const C_DIM := Color(0.60, 0.66, 0.78, 1.0)
const C_QUIT := Color(1.0, 0.55, 0.52, 1.0)

const PANEL_W := 260.0
const PANEL_H := 196.0
const BTN_W := 200.0
const BTN_H := 30.0

var _is_open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_build()
	hide()


func is_open() -> bool:
	return _is_open


func open() -> void:
	show()
	_is_open = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = true


func close() -> void:
	_is_open = false
	hide()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.02, 0.04, 0.82)
	root.add_child(dim)

	var px := (640.0 - PANEL_W) * 0.5
	var py := (360.0 - PANEL_H) * 0.5

	var panel := Panel.new()
	panel.position = Vector2(px, py)
	panel.size = Vector2(PANEL_W, PANEL_H)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.13, 0.98)
	sb.border_color = Color(0.30, 0.38, 0.52, 1.0)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)

	var title := Label.new()
	title.text = "已暂停"
	UiFont.apply(title, 20, C_TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(px, py + 12.0)
	title.size = Vector2(PANEL_W, 26.0)
	root.add_child(title)

	var hint := Label.new()
	hint.text = "ESC 继续游戏"
	UiFont.apply(hint, 9, C_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.position = Vector2(px, py + 38.0)
	hint.size = Vector2(PANEL_W, 14.0)
	root.add_child(hint)

	var bx := px + (PANEL_W - BTN_W) * 0.5
	var resume := UiFont.make_button("返回游戏", 12, Color(0.72, 1.0, 0.72, 1.0))
	resume.position = Vector2(bx, py + 60.0)
	resume.size = Vector2(BTN_W, BTN_H)
	resume.pressed.connect(func() -> void: _resume())
	root.add_child(resume)

	var help := UiFont.make_button("游戏说明", 12)
	help.position = Vector2(bx, py + 96.0)
	help.size = Vector2(BTN_W, BTN_H)
	help.pressed.connect(func() -> void: _help())
	root.add_child(help)

	var quit := UiFont.make_button("退出游戏", 12, C_QUIT)
	quit.position = Vector2(bx, py + 132.0)
	quit.size = Vector2(BTN_W, BTN_H)
	quit.pressed.connect(func() -> void: _quit())
	root.add_child(quit)


func _resume() -> void:
	if not _is_open:
		return
	close()
	resume_requested.emit()


func _help() -> void:
	if not _is_open:
		return
	# 先把自己藏起来，但**不恢复暂停** —— 说明页也要暂停着看
	hide()
	_is_open = false
	help_requested.emit()


func _quit() -> void:
	if not _is_open:
		return
	close()
	get_tree().paused = false
	quit_requested.emit()
