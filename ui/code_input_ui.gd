class_name CodeInputUI
extends CanvasLayer
##
## 升级打码面板：上边显示要照打的代码，下边是输入框，全打对才放行。
##
## 三个必须做对的点（和 LevelUpUI 同源，改这里时一起看）：
##   1. process_mode = WHEN_PAUSED —— 不然暂停后收不到键盘，打了没反应
##   2. layer 要高于升级弹窗，否则会被盖住
##   3. 结束时只 hide、不动 paused —— 解除暂停是 LevelUpUI.close() 的事，
##      这里提前解的话，连升多级时中间那一瞬间游戏会跑起来
##
## 视口只有 640x360，代码区高度是算着给的：标准档最多 7 行，严格档 11 行会滚动。
##

signal solved

const MONO_SIZE := 11

const C_OK := Color(0.60, 0.85, 0.45, 1.0)
const C_BAD := Color(0.95, 0.45, 0.42, 1.0)
const C_DIM := Color(0.68, 0.73, 0.82, 0.9)
const C_TITLE := Color(1.0, 0.88, 0.40, 1.0)
const C_TIP := Color(0.45, 0.82, 0.52, 1.0)

var mode: int = CodeChallenge.Mode.STD

var _dim: ColorRect
var _title: Label
var _tip_l: Label
var _view: RichTextLabel
var _edit: TextEdit
var _status: Label
var _target := ""
var _done_t := -1.0
var _indenting := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	# 必须高于升级弹窗（layer 10）：低于它的后果是升级卡片透上来盖住输入框，
	# 玩家看到的就是「点了卡、升级框不消失、键盘打不了字」
	layer = 20
	_build()
	hide()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.01, 0.02, 0.04, 0.88)
	root.add_child(_dim)

	var center := Control.new()
	center.position = Vector2(320, 180)
	root.add_child(center)

	var col := VBoxContainer.new()
	col.position = Vector2(-290, -168)
	col.size = Vector2(580, 336)
	col.add_theme_constant_override("separation", 4)
	center.add_child(col)

	_title = Label.new()
	_title.text = "LEVEL UP"
	UiFont.apply(_title, 15, C_TITLE)
	col.add_child(_title)

	_tip_l = Label.new()
	UiFont.apply(_tip_l, 11, C_TIP)
	col.add_child(_tip_l)

	col.add_child(_spacer(4))

	# 参考代码：逐字符染色，打对的变暗、当前字符高亮、打错标红
	_view = RichTextLabel.new()
	_view.bbcode_enabled = true
	_view.scroll_active = true
	_view.custom_minimum_size = Vector2(580, 158)
	UiFont.apply_mono(_view, MONO_SIZE, Color(0.82, 0.86, 0.94, 1.0))
	_view.add_theme_color_override("default_color", Color(0.82, 0.86, 0.94, 1.0))
	col.add_child(_view)

	col.add_child(_spacer(2))

	_edit = TextEdit.new()
	_edit.custom_minimum_size = Vector2(580, 88)
	_edit.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	UiFont.apply_mono(_edit, MONO_SIZE, Color(1.0, 1.0, 1.0, 0.95))
	_edit.text_changed.connect(_on_text_changed)
	col.add_child(_edit)

	_status = Label.new()
	_status.text = "照着上面的代码打一遍"
	UiFont.apply(_status, 11, C_DIM)
	col.add_child(_status)

	col.add_child(_spacer(2))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)

	var redo := UiFont.make_button("清空重打", 11)
	redo.pressed.connect(func() -> void:
		Sfx.play("ui")
		_edit.text = ""
		_edit.grab_focus()
		_update()
	)
	row.add_child(redo)


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


# ---------------------------------------------------------------- 生命周期

func open(title_text: String, upgrade_id: String, target_level: int, is_evo: bool, m: int, variant: int = -1) -> void:
	mode = m
	var ch := CodeChallenge.build(upgrade_id, target_level, is_evo, m, variant)
	_target = str(ch["text"])
	_title.text = title_text
	_tip_l.text = "· " + str(ch["tip"]) + "　（%s·%s）" % [
		CodeChallenge.MODE_NAMES[m], "Lv %d" % int(ch["level"])]
	_edit.text = ""
	_done_t = -1.0
	show()
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_edit.grab_focus()
	_update()


func _finish() -> void:
	_done_t = -1.0
	hide()
	# 还回到升级弹窗，光标不能收
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	solved.emit()


func _process(delta: float) -> void:
	if not visible:
		return
	if _done_t >= 0.0:
		_done_t += delta
		if _done_t >= 0.45:
			_finish()


# ---------------------------------------------------------------- 校验与染色

func _update() -> void:
	var st := CodeChallenge.match_state(_target, _edit.text)
	var tpos := int(st["tpos"])
	var err := bool(st["err"])
	var done := bool(st["done"])
	_render(tpos, err)

	if done:
		_status.text = "全对！正在升级…"
		_status.add_theme_color_override("font_color", C_OK)
		if _done_t < 0.0:
			_done_t = 0.0
			Sfx.play("victory")
		return

	_done_t = -1.0
	if err:
		if tpos >= _target.length():
			_status.text = "打多了 · 把多出来的部分删掉就能升级"
		else:
			var lc := CodeChallenge.pos_to_line_col(_target, tpos)
			_status.text = "第 %d 行第 %d 个字符不对 · 改对就能升级" % [lc.x, lc.y]
		_status.add_theme_color_override("font_color", C_BAD)
	else:
		_status.text = "已打 %d / %d 字符 · 打错不会扣任何东西" % [tpos, _target.length()]
		_status.add_theme_color_override("font_color", C_DIM)


func _render(tpos: int, err: bool) -> void:
	var bb := ""
	if tpos > 0:
		bb += "[color=#3f6b39]" + _esc(_target.substr(0, tpos)) + "[/color]"
	if tpos < _target.length():
		var ch := _esc(_target.substr(tpos, 1))
		bb += "[bgcolor=#6b4a10][color=#ffe9a8]" + ch + "[/color][/bgcolor]" if not err \
			else "[bgcolor=#7a2020][color=#ffdada]" + ch + "[/color][/bgcolor]"
		if tpos + 1 < _target.length():
			bb += "[color=#c2cbd8]" + _esc(_target.substr(tpos + 1)) + "[/color]"
	_view.parse_bbcode(bb)


## bbcode 的特殊字符是方括号，不是尖括号 —— C++ 的 << 和 & 原样写就行。
## 一开始照 HTML 的习惯转义成 &lt; 结果显示成字面量，白转了。
func _esc(s: String) -> String:
	return s.replace("[", "[lb]").replace("]", "[rb]")


# ---------------------------------------------------------------- 输入

func _on_text_changed() -> void:
	if _indenting:
		return
	# 回车后自动补缩进：上一行以 { 结尾就多缩进一层。
	# 不打缩进也能过的话，这块就练不到 —— 但打多打少不追究（校验那边宽容）。
	if _edit.text.ends_with("\n"):
		var lines := _edit.text.split("\n")
		var prev := ""
		if lines.size() >= 2:
			prev = str(lines[lines.size() - 2])
		var ind := _leading_spaces(prev)
		if prev.strip_edges().ends_with("{"):
			ind += 4
		if ind > 0:
			_indenting = true
			_edit.insert_text_at_caret(" ".repeat(ind))
			_indenting = false
	_update()


func _leading_spaces(s: String) -> int:
	var n := 0
	while n < s.length() and s.substr(n, 1) == " ":
		n += 1
	return n


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and k.keycode == KEY_TAB:
			# Tab 默认会跳焦点，这里改成插入四个空格
			get_viewport().set_input_as_handled()
			_edit.insert_text_at_caret("    ")
		elif k.pressed and k.keycode == KEY_ESCAPE:
			# 严格模式没有「跳过」这条路，Esc 也不给过
			get_viewport().set_input_as_handled()
