class_name TitleUI
extends CanvasLayer
##
## 开场标题画面。游戏现在有角色、有成长、有结算，但启动后直接进选人 ——
## 缺一个"这是一个完整游戏"的门面，这是补齐的那块。
##
## 和选人/结算同一套规则：暂停整棵树 + process_mode = WHEN_PAUSED +
## 固定 position/size（set_anchors_preset 在父节点没布局完时会算出错误 offset）。
##
## 美术全部代码画：标题是文字，背景是程序化网格 + 漂浮的 0/1。
## 这游戏的视觉语言本来就是"程序世界"，画一张 Logo 图反而和场内的
## 电路板底图对不上。
##

signal start_requested
signal help_requested
signal about_requested
signal license_requested

const C_TITLE := Color(0.62, 0.94, 1.0, 1.0)      # 青白：和场内电路板同色系
const C_SUB := Color(1.0, 0.86, 0.42, 1.0)        # 金色：升级/进化的"奖励色"
const C_DIM := Color(0.60, 0.72, 0.86, 1.0)
const C_FOOTER := Color(0.52, 0.46, 0.34, 1.0)   # 落款：压暗的金，不抢标题

const TITLE_TEXT := "代码幸存者"
const SUB_TEXT := "CODE  SURVIVORS"
const DESC_TEXT := "你是一段程序 —— 在 Bug 的海洋里活到编译成功"
# 落款：和塔防《守护稚码王国》主菜单同一条，品牌只在这一行露面，
# 不抢标题的注意力（字号最小、放在最底）
const FOOTER_TEXT := "稚码园机器人编程　原创作品　v1.0.0"

var _bg: Node2D
var _code_btn: Button
var _status: Label
var _start_btn: Button
var _lic_btn: Button
var _is_open := false
var _t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_build()
	hide()


func is_open() -> bool:
	return _is_open


## 打开说明页时把标题页"挂起"：它还显示着（当背景），但不再响应 Enter。
## 不挂起的话，在说明页里按 Enter 会穿透到标题页直接开局。
func set_active(b: bool) -> void:
	_is_open = b


func open() -> void:
	show()
	_is_open = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = true
	refresh_status()

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.02, 0.04, 0.92)
	root.add_child(dim)

	# 背景装饰单独挂一个 Node2D 自己画（网格 + 漂浮的 0/1）
	_bg = _TitleBg.new()
	root.add_child(_bg)

	var title := Label.new()
	title.text = TITLE_TEXT
	UiFont.apply(title, 40, C_TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0.0, 46.0)
	title.size = Vector2(640.0, 56.0)
	root.add_child(title)

	var sub := Label.new()
	sub.text = SUB_TEXT
	UiFont.apply(sub, 13, C_SUB)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.position = Vector2(0.0, 102.0)
	sub.size = Vector2(640.0, 20.0)
	root.add_child(sub)

	var desc := Label.new()
	desc.text = DESC_TEXT
	UiFont.apply(desc, 12, C_DIM)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.position = Vector2(0.0, 128.0)
	desc.size = Vector2(640.0, 18.0)
	root.add_child(desc)

	# 授权状态单独占一行：常驻但不抢眼。它既是「还剩几天」的提醒，
	# 也是到期后的提示 —— 玩家不该某天突然被锁，事先看得见才不觉得被骗。
	_status = Label.new()
	UiFont.apply(_status, 10, C_DIM)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.position = Vector2(0.0, 154.0)
	_status.size = Vector2(640.0, 16.0)
	root.add_child(_status)

	# 三个明确按钮取代原来的「点屏幕任意处开始」：后者玩家不知道点哪，
	# 而且说明页没有入口 —— 想看武器表只能先开一局。
	# 「关于本作品」放后面：它是品牌页，不是玩法入口，点了会离开这条主线。
	_start_btn = UiFont.make_button("开始游戏", 14, Color(1.0, 0.94, 0.72, 1.0))
	_start_btn.position = Vector2(240.0, 180.0)
	_start_btn.size = Vector2(160.0, 30.0)
	_start_btn.pressed.connect(func() -> void: _confirm())
	_style_disabled(_start_btn)
	root.add_child(_start_btn)

	var help_btn := UiFont.make_button("游戏说明", 12)
	help_btn.position = Vector2(240.0, 218.0)
	help_btn.size = Vector2(160.0, 24.0)
	help_btn.pressed.connect(func() -> void: help_requested.emit())
	root.add_child(help_btn)

	# 打码难度开关。放在「游戏说明」右侧：它属于玩法设置，
	# 不该混进下方的授权/落款区，也不该抢「开始游戏」的位置。
	_code_btn = UiFont.make_button("代码挑战：标准", 12)
	_code_btn.position = Vector2(412.0, 218.0)
	_code_btn.size = Vector2(150.0, 24.0)
	_code_btn.pressed.connect(_on_code_mode)
	root.add_child(_code_btn)
	_refresh_code_btn()

	var about_btn := UiFont.make_button("关于本作品", 12)
	about_btn.position = Vector2(240.0, 250.0)
	about_btn.size = Vector2(160.0, 24.0)
	about_btn.pressed.connect(func() -> void: about_requested.emit())
	root.add_child(about_btn)

	# 激活入口常驻但做得最小最暗：平时不打扰，到期时学生自己就能找到。
	# 藏起来的话，每个到期的人都要打电话问一句"怎么续"。
	_lic_btn = UiFont.make_button("输入激活码", 11, Color(0.72, 0.80, 0.90, 1.0))
	_lic_btn.position = Vector2(240.0, 282.0)
	_lic_btn.size = Vector2(160.0, 22.0)
	_lic_btn.pressed.connect(func() -> void: license_requested.emit())
	root.add_child(_lic_btn)

	# 落款是"签名"，不是正文：和按钮区隔开、离视口底留一点余量，
	# 贴着按钮会被当成最后一个按钮的说明文字。
	var footer := Label.new()
	footer.text = FOOTER_TEXT
	UiFont.apply(footer, 9, C_FOOTER)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.position = Vector2(0.0, 328.0)
	footer.size = Vector2(640.0, 14.0)
	root.add_child(footer)

	refresh_status()


## 灰掉的按钮要自己补样式：make_button 只定义了正常/hover/pressed/focus，
## 漏掉 disabled 的话，到期后那个按钮会退回 Godot 默认灰块，和整套 UI 不是一路。
func _style_disabled(b: Button) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.12, 0.92)
	sb.border_color = Color(0.24, 0.27, 0.33, 1.0)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	b.add_theme_stylebox_override("disabled", sb)
	b.add_theme_color_override("font_disabled_color", Color(0.44, 0.47, 0.54, 1.0))


## 刷新授权状态。到期后把「开始游戏」灰掉并换文案 ——
## 只锁入口、不弹窗赶人：已经开局的那一局必须能打完。
func refresh_status() -> void:
	if _status == null or _start_btn == null:
		return
	_status.text = SaveData.status_text()
	var c := C_DIM
	if SaveData.is_permanent():
		c = Color(1.0, 0.86, 0.42, 1.0)
	elif SaveData.is_expired():
		c = Color(1.0, 0.46, 0.42, 1.0)
	elif SaveData.days_left() <= 2:
		c = Color(1.0, 0.72, 0.35, 1.0)
	_status.add_theme_color_override("font_color", c)
	# 按钮只负责"灰掉"，「为什么不能进」交给上面那行状态文字说 ——
	# 两处都写「试用已结束」会变成两个并列的提示，反而看不出哪个是原因。
	_start_btn.disabled = SaveData.is_expired()

func _process(dt: float) -> void:
	if not _is_open:
		return
	# 背景的 0/1 自己在飘（见 _TitleBg），标题页本身不再做别的动画
	_t += dt


func _confirm() -> void:
	if not _is_open:
		return
	# 到期后 Enter 不该还能开局：直接引到激活窗，省得玩家按了没反应
	if SaveData.is_expired():
		license_requested.emit()
		return
	_is_open = false
	hide()
	get_tree().paused = false
	start_requested.emit()

func _input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_ENTER or k == KEY_SPACE:
			_confirm()
			get_viewport().set_input_as_handled()
	# 鼠标不再"点哪都开始"：有按钮之后这个行为会变成误触


##
## 标题背景：程序化网格 + 向下漂浮的 0/1。
## 内嵌在这里而不是单独建文件 —— 只服务于这一个画面，拆出去反而要到处找。
##
class _TitleBg extends Node2D:
	const CELL := 40.0
	const N_CHARS := 26

	var _t := 0.0
	var _chars: Array[Dictionary] = []


	func _ready() -> void:
		for i in N_CHARS:
			_chars.append({
				"x": randf() * 640.0,
				"y": randf() * 360.0,
				"v": 12.0 + randf() * 26.0,
				"c": "1" if randf() < 0.5 else "0",
			})


	func _process(dt: float) -> void:
		_t += dt
		for d in _chars:
			d["y"] = float(d["y"]) + float(d["v"]) * dt
			if float(d["y"]) > 370.0:
				d["y"] = -10.0
				d["x"] = randf() * 640.0
		queue_redraw()


	func _draw() -> void:
		# 网格：和场内电路板底图同一语言，慢速右移制造"程序在跑"的感觉
		var off := _t * 6.0
		var x := -fmod(off, CELL)
		while x < 640.0:
			draw_line(Vector2(x, 0.0), Vector2(x, 360.0), Color(0.25, 0.75, 0.95, 0.05), 1.0)
			x += CELL
		var y := 0.0
		while y < 360.0:
			draw_line(Vector2(0.0, y), Vector2(640.0, y), Color(0.25, 0.75, 0.95, 0.05), 1.0)
			y += CELL

		# 漂浮的 0/1：用默认字体画（数字不需要中文字体）
		var f := ThemeDB.fallback_font
		for d in _chars:
			draw_string(f, Vector2(float(d["x"]), float(d["y"])), str(d["c"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(0.35, 0.85, 1.0, 0.20))

## 循环切换打码难度：不打码 -> 轻松 -> 标准 -> 严格。
## 存进存档而不是只留在内存里：体验课要关掉、常规课要标准，
## 每次进来重选一遍太烦，而且孩子自己开机时不会去改。
func _on_code_mode() -> void:
	Sfx.play("ui")
	SaveData.code_mode = (SaveData.code_mode + 1) % 4
	SaveData.save_game()
	_refresh_code_btn()


func _refresh_code_btn() -> void:
	if _code_btn == null:
		return
	var m := SaveData.code_mode
	_code_btn.text = "代码挑战：" + str(CodeChallenge.MODE_NAMES[m])
