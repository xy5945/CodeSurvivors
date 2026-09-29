class_name RescueUI
extends CanvasLayer
##
## 血量归零后的「救我一命」面板 —— 失败界面之前的那道选择题。
##
## 设计意图（用户原话）：孩子打不过不该立刻判死，给三次「做题换命」的机会。
## 题目是满级小题（最难的那一档），做对才复活，做错可以一直重来 ——
## 但如果他不想做，必须有一个明确的出口（投降认输），不能把人卡死在面板里。
##
## 三个和暂停/结算面板同一套的硬要求：
##   1. process_mode = WHEN_PAUSED —— 整棵树都暂停着，默认收不到输入
##   2. 打开显示光标、关闭隐藏 —— 游戏里光标挡视线
##   3. 固定 position/size，不用 set_anchors_preset（父节点没布局完时 offset 会算错）
##
## 层叠：本面板 18 < 打码面板 20。点「救我一命」后自己 hide，让打码面板上来。
##

signal rescue_requested
signal give_up_requested

const C_TITLE := Color(1.0, 0.62, 0.36, 1.0)
const C_DIM := Color(0.72, 0.78, 0.88, 1.0)
const C_WARN := Color(1.0, 0.85, 0.45, 1.0)
const C_LIVE := Color(0.72, 1.0, 0.72, 1.0)
const C_QUIT := Color(1.0, 0.55, 0.52, 1.0)

const PANEL_W := 300.0
const PANEL_H := 180.0
const BTN_W := 240.0
const BTN_H := 32.0

var _is_open := false
var _live_btn: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	layer = 18
	_build()
	hide()


func is_open() -> bool:
	return _is_open


func open(remain: int) -> void:
	_live_btn.text = "救我一命（剩 %d 次）" % remain
	_live_btn.disabled = remain <= 0
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
	dim.color = Color(0.03, 0.01, 0.02, 0.84)
	root.add_child(dim)

	var px := (640.0 - PANEL_W) * 0.5
	var py := (360.0 - PANEL_H) * 0.5

	var panel := Panel.new()
	panel.position = Vector2(px, py)
	panel.size = Vector2(PANEL_W, PANEL_H)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.06, 0.09, 0.98)
	sb.border_color = Color(0.55, 0.32, 0.30, 1.0)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)

	var title := Label.new()
	title.text = "生命值归零"
	UiFont.apply(title, 20, C_TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(px, py + 10.0)
	title.size = Vector2(PANEL_W, 26.0)
	root.add_child(title)

	# 规则必须写清楚：做什么题、换来什么。含糊的话孩子会以为点了就复活。
	var hint := Label.new()
	hint.text = "打对一道满级小题 → 恢复 100 点生命"
	UiFont.apply(hint, 10, C_WARN)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.position = Vector2(px, py + 40.0)
	hint.size = Vector2(PANEL_W, 16.0)
	root.add_child(hint)

	var hint2 := Label.new()
	hint2.text = "机会用完就只能投降认输了"
	UiFont.apply(hint2, 9, C_DIM)
	hint2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint2.position = Vector2(px, py + 58.0)
	hint2.size = Vector2(PANEL_W, 14.0)
	root.add_child(hint2)

	var bx := px + (PANEL_W - BTN_W) * 0.5

	_live_btn = UiFont.make_button("救我一命", 13, C_LIVE)
	_live_btn.position = Vector2(bx, py + 84.0)
	_live_btn.size = Vector2(BTN_W, BTN_H)
	_live_btn.pressed.connect(func() -> void: _rescue())
	root.add_child(_live_btn)

	var give := UiFont.make_button("投降认输", 13, C_QUIT)
	give.position = Vector2(bx, py + 124.0)
	give.size = Vector2(BTN_W, BTN_H)
	give.pressed.connect(func() -> void: _give_up())
	root.add_child(give)


func _rescue() -> void:
	if not _is_open:
		return
	close()     # 让位给打码面板；游戏保持暂停
	rescue_requested.emit()


func _give_up() -> void:
	if not _is_open:
		return
	close()
	give_up_requested.emit()
