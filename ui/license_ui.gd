class_name LicenseUI
extends CanvasLayer
##
## 输入激活码的弹窗：本机申请码 + 一个输入框。
##
## 流程是「学生报码 → 作者算码 → 学生填码」，所以这一页的主角不是输入框，
## **是那串申请码** —— 学生要照着它念给你、或者打字发给你。字号给到 20，
## 位置放在最显眼的第二行。
##
## 错误提示要分得清"有字符抄错了"和"这是别人机器的码"：
## 两者在学生那里都表现为"用不了"，但在你这里一个是重发、一个是重新发码，
## 分不清就只能靠电话来回猜。
##
## 暂停/布局规则与标题页、说明页一致：WHEN_PAUSED + 固定 position/size
## （set_anchors_preset 在父节点没布局完时会算错 offset，这个是踩过的坑）。
##

signal closed

const C_TITLE := Color(0.72, 0.95, 1.0, 1.0)
const C_DIM := Color(0.60, 0.70, 0.82, 1.0)
const C_CODE := Color(1.0, 0.86, 0.42, 1.0)
const C_ERR := Color(1.0, 0.48, 0.44, 1.0)
const C_OK := Color(0.48, 0.95, 0.58, 1.0)

const PANEL_POS := Vector2(100.0, 75.0)
const PANEL_SIZE := Vector2(440.0, 210.0)
const CARD_W := 360.0

var _panel: Control
var _code_label: Label
var _edit: LineEdit
var _msg: Label
var _ok_btn: Button
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
	_edit.text = ""
	_refresh()
	_edit.grab_focus()


## 关窗时**不解除暂停**：本窗口只从标题页打开，而标题页是 WHEN_PAUSED ——
## 一 unpause 它就收不到输入了。返回后的状态由 main 那侧接管（与说明页同一套路）。
func close() -> void:
	if not _is_open:
		return
	_is_open = false
	hide()
	closed.emit()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.80)
	root.add_child(dim)

	_panel = Control.new()
	_panel.position = PANEL_POS
	_panel.size = PANEL_SIZE
	root.add_child(_panel)

	var frame := Panel.new()
	frame.position = Vector2.ZERO
	frame.size = PANEL_SIZE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.11, 0.99)
	sb.border_color = Color(0.30, 0.58, 0.85, 1.0)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	frame.add_theme_stylebox_override("panel", sb)
	_panel.add_child(frame)

	var title := Label.new()
	title.text = "输入激活码"
	UiFont.apply(title, 14, C_TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0.0, 14.0)
	title.size = Vector2(PANEL_SIZE.x, 22.0)
	_panel.add_child(title)

	var hint := Label.new()
	hint.text = "把下面这串申请码发给作者，换取激活码"
	UiFont.apply(hint, 11, C_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.position = Vector2(0.0, 40.0)
	hint.size = Vector2(PANEL_SIZE.x, 16.0)
	_panel.add_child(hint)

	_code_label = Label.new()
	_code_label.text = "----"
	UiFont.apply(_code_label, 20, C_CODE)
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_label.position = Vector2(0.0, 60.0)
	_code_label.size = Vector2(PANEL_SIZE.x, 30.0)
	_panel.add_child(_code_label)

	_edit = LineEdit.new()
	_edit.placeholder_text = "XXXX-XXXX-XXXX-XXXX-XXXX"
	UiFont.apply(_edit, 13, Color(0.90, 0.94, 1.0, 1.0))
	_edit.position = Vector2(40.0, 100.0)
	_edit.size = Vector2(CARD_W, 30.0)
	_edit.max_length = 40
	_edit.add_theme_color_override("font_placeholder_color", Color(0.42, 0.52, 0.64, 1.0))
	_edit.add_theme_color_override("caret_color", C_CODE)
	var eb := StyleBoxFlat.new()
	eb.bg_color = Color(0.09, 0.12, 0.18, 1.0)
	eb.border_color = Color(0.34, 0.46, 0.62, 1.0)
	eb.set_border_width_all(1)
	eb.set_corner_radius_all(3)
	eb.content_margin_left = 8.0
	eb.content_margin_right = 8.0
	_edit.add_theme_stylebox_override("normal", eb)
	var ef := eb.duplicate() as StyleBoxFlat
	ef.border_color = C_CODE
	_edit.add_theme_stylebox_override("focus", ef)
	_edit.text_submitted.connect(func(_t: String) -> void: _submit())
	_panel.add_child(_edit)

	_msg = Label.new()
	UiFont.apply(_msg, 11, C_DIM)
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.position = Vector2(0.0, 138.0)
	_msg.size = Vector2(PANEL_SIZE.x, 16.0)
	_panel.add_child(_msg)

	var cancel := UiFont.make_button("取消", 12)
	cancel.position = Vector2(88.0, 164.0)
	cancel.size = Vector2(120.0, 30.0)
	cancel.pressed.connect(close)
	_panel.add_child(cancel)

	_ok_btn = UiFont.make_button("立即激活", 12, C_CODE)
	_ok_btn.position = Vector2(232.0, 164.0)
	_ok_btn.size = Vector2(120.0, 30.0)
	_ok_btn.pressed.connect(_submit)
	_panel.add_child(_ok_btn)


func _refresh() -> void:
	_code_label.text = License.machine_code()
	if not License.has_secret():
		_set_msg("本机没有配置激活密钥，请联系作者", C_ERR)
		_edit.editable = false
		_ok_btn.disabled = true
		return
	_edit.editable = true
	_ok_btn.disabled = false
	_set_msg(SaveData.status_text(), C_DIM)


func _set_msg(text: String, color: Color) -> void:
	_msg.text = text
	_msg.add_theme_color_override("font_color", color)


func _submit() -> void:
	if not License.has_secret():
		return
	var raw := _edit.text
	var n := License.clean(raw).length()
	if n != License.CODE_CHARS:
		_set_msg("激活码应该是 20 个字符，现在填了 %d 个" % n, C_ERR)
		return
	var r := License.verify(raw)
	if not bool(r["ok"]):
		_set_msg(str(r["reason"]), C_ERR)
		return
	var days := int(r["days"])
	License.apply(days)
	if bool(r["permanent"]):
		_set_msg("激活成功：已永久授权", C_OK)
	else:
		_set_msg("激活成功：可使用 %d 天" % days, C_OK)
	_edit.text = ""
	# paused 状态下 timer 要显式 process_always，否则永远不触发
	get_tree().create_timer(1.1, true).timeout.connect(close)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()
