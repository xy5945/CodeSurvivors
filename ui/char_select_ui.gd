class_name CharSelectUI
extends CanvasLayer
##
## 开局选人。角色 = 起始武器 + 属性修正 + 一条特性（见 core/char_defs.gd）。
##
## 三个必须做对的点，和升级弹窗一样（漏一个就是"点了没反应"）：
##   1. process_mode = WHEN_PAUSED —— 选人时整棵树是暂停的
##   2. 打开时显示光标、选完隐藏 —— 游戏里光标会挡视线
##   3. 布局全部用固定 position/size —— set_anchors_preset 在父节点尚未
##      完成布局时算出来的 offset 是错的（控件会飘出屏幕且零报错）
##
## 信息分两层：卡片上只放"选它要什么代价、得什么好处"，
## 下方的详情条再展开这个编程概念的中文解释。
## 全塞进 118px 宽的卡片里会挤成一团，等于没写。
##

signal selected(char_id: String)
signal back_requested

const CARD_W := 118.0
const CARD_H := 206.0
const CARD_GAP := 9.0
const CARD_TOP := 74.0

const BG := Color(0.07, 0.09, 0.14, 0.97)
const BORDER := Color(0.24, 0.28, 0.38, 1.0)
const BORDER_SEL := Color(1.0, 0.86, 0.36, 1.0)
const C_NAME := Color(0.96, 0.98, 1.0, 1.0)
const C_DIM := Color(0.64, 0.70, 0.82, 1.0)
const C_TRAIT := Color(1.0, 0.86, 0.40, 1.0)

# 记住上一次的选择：换角色重开时默认停在上一个角色上，不用重新找
static var last_id := CharDefs.DEFAULT_ID

var _panels: Array[Panel] = []
var _detail: Label
var _attr: Label
var _sel := 0
var _is_open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_build()
	hide()


func is_open() -> bool:
	return _is_open


## last：默认高亮的角色（重开时传上一局用的）。
func open(last := "") -> void:
	if last != "":
		last_id = last
	_sel = _index_of(last_id)
	_refresh()
	show()
	_is_open = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = true


func _index_of(id: String) -> int:
	for i in CharDefs.CHARACTERS.size():
		if str(CharDefs.CHARACTERS[i]["id"]) == id:
			return i
	return 0


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.02, 0.04, 0.88)
	root.add_child(dim)

	var title := Label.new()
	title.text = "选择你的程序"
	UiFont.apply(title, 20, Color(1.0, 0.88, 0.42, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0.0, 20.0)
	title.size = Vector2(640.0, 28.0)
	root.add_child(title)

	var sub := Label.new()
	sub.text = "鼠标点击卡片 · 数字键 1~5 快速选择 · Enter 开始 · ESC 返回"
	UiFont.apply(sub, 10, C_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.position = Vector2(0.0, 50.0)
	sub.size = Vector2(640.0, 16.0)
	root.add_child(sub)

	var total_w := CARD_W * float(CharDefs.CHARACTERS.size()) + CARD_GAP * float(CharDefs.CHARACTERS.size() - 1)
	var x0 := (640.0 - total_w) * 0.5

	for i in CharDefs.CHARACTERS.size():
		var p := Panel.new()
		p.position = Vector2(x0 + float(i) * (CARD_W + CARD_GAP), CARD_TOP)
		p.size = Vector2(CARD_W, CARD_H)
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		root.add_child(p)
		_panels.append(p)
		_fill_card(p, CharDefs.CHARACTERS[i])
		var idx := i
		p.mouse_entered.connect(func() -> void: _set_sel(idx))
		p.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_confirm())

	_detail = Label.new()
	UiFont.apply(_detail, 11, C_NAME)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.position = Vector2(60.0, CARD_TOP + CARD_H + 12.0)
	_detail.size = Vector2(440.0, 30.0)
	root.add_child(_detail)

	_attr = Label.new()
	UiFont.apply(_attr, 10, C_DIM)
	_attr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_attr.position = Vector2(60.0, CARD_TOP + CARD_H + 42.0)
	_attr.size = Vector2(440.0, 16.0)
	root.add_child(_attr)

	# 返回上一页（标题）。按钮放在详情条右侧，不然 360 高的视口塞不下第二行。
	var back := UiFont.make_button("← 返回", 11)
	back.position = Vector2(524.0, CARD_TOP + CARD_H + 26.0)
	back.size = Vector2(96.0, 30.0)
	back.pressed.connect(func() -> void: _back())
	root.add_child(back)


func _fill_card(p: Panel, d: Dictionary) -> void:
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 3)
	p.add_child(v)
	# 上下留白：贴着边框的文字在暗底上会糊
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 7)
	pad.add_theme_constant_override("margin_right", 7)
	pad.add_theme_constant_override("margin_top", 6)
	pad.add_theme_constant_override("margin_bottom", 6)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(col)

	var code := Label.new()
	code.text = str(d["code"])
	UiFont.apply(code, 15, d["color"])
	code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(code)

	var nm := Label.new()
	nm.text = str(d["name"])
	UiFont.apply(nm, 13, C_NAME)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(nm)

	var term := Label.new()
	term.text = str(d["term"])
	UiFont.apply(term, 10, C_DIM)
	term.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(term)

	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0.0, 5.0)
	col.add_child(sp)

	var start := Label.new()
	var wd := UpgradeDefs.def_of(str(d["start"]))
	start.text = "起始  " + (str(wd["name"]) if not wd.is_empty() else "?")
	UiFont.apply(start, 9, C_DIM)
	start.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(start)

	var sp2 := Control.new()
	sp2.custom_minimum_size = Vector2(0.0, 4.0)
	col.add_child(sp2)

	var tn := Label.new()
	tn.text = str(d["trait_name"])
	UiFont.apply(tn, 11, C_TRAIT)
	tn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tn)

	var td := Label.new()
	td.text = str(d["trait_desc"])
	UiFont.apply(td, 9, C_DIM)
	td.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	td.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	td.custom_minimum_size = Vector2(0.0, 50.0)
	col.add_child(td)


func _set_sel(i: int) -> void:
	if i == _sel:
		return
	_sel = i
	_refresh()


func _refresh() -> void:
	for i in _panels.size():
		var sb := StyleBoxFlat.new()
		sb.bg_color = BG
		sb.border_color = BORDER_SEL if i == _sel else BORDER
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(4)
		_panels[i].add_theme_stylebox_override("panel", sb)

	var d: Dictionary = CharDefs.CHARACTERS[_sel]
	_detail.text = "「%s」%s —— %s" % [d["term"], d["code"], d["plain"]]
	_attr.text = _attr_text(d)


## 只列和基准不一样的项。全列一遍的话 5 个角色看起来都差不多，
## 差异反而被淹没了 —— 玩家读的是"这个角色特殊在哪"。
func _attr_text(d: Dictionary) -> String:
	var parts: Array[String] = []
	if absf(float(d["hp_mult"]) - 1.0) > 0.001:
		parts.append("生命 ×%s" % _fmt(float(d["hp_mult"])))
	if absf(float(d["speed_mult"]) - 1.0) > 0.001:
		parts.append("移速 ×%s" % _fmt(float(d["speed_mult"])))
	if absf(float(d["dmg_mult"]) - 1.0) > 0.001:
		parts.append("伤害 ×%s" % _fmt(float(d["dmg_mult"])))
	if absf(float(d["cd_mult"]) - 1.0) > 0.001:
		parts.append("冷却 ×%s" % _fmt(float(d["cd_mult"])))
	if absf(float(d["pickup_mult"]) - 1.0) > 0.001:
		parts.append("拾取 ×%s" % _fmt(float(d["pickup_mult"])))
	if parts.is_empty():
		return "属性：标准配置（无修正）"
	return "属性  " + "  ".join(PackedStringArray(parts))


func _fmt(v: float) -> String:
	return ("%.2f" % v).trim_suffix("0").trim_suffix("0")


func _confirm() -> void:
	if not _is_open:
		return
	last_id = str(CharDefs.CHARACTERS[_sel]["id"])
	_is_open = false
	hide()
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	get_tree().paused = false
	selected.emit(last_id)


## 返回标题页。注意**不恢复暂停** —— 标题页自己也是暂停的，
## 由 main 决定接下来打开谁。
func _back() -> void:
	if not _is_open:
		return
	_is_open = false
	hide()
	back_requested.emit()


func _input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k >= KEY_1 and k <= KEY_9:
			var i := k - KEY_1
			if i < CharDefs.CHARACTERS.size():
				_set_sel(i)
				_confirm()
				get_viewport().set_input_as_handled()
		elif k == KEY_RIGHT or k == KEY_D:
			_set_sel((_sel + 1) % CharDefs.CHARACTERS.size())
			get_viewport().set_input_as_handled()
		elif k == KEY_LEFT or k == KEY_A:
			_set_sel((_sel - 1 + CharDefs.CHARACTERS.size()) % CharDefs.CHARACTERS.size())
			get_viewport().set_input_as_handled()
		elif k == KEY_ENTER or k == KEY_SPACE:
			_confirm()
			get_viewport().set_input_as_handled()
		elif k == KEY_ESCAPE:
			_back()
			get_viewport().set_input_as_handled()
