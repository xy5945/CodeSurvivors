class_name ResultUI
extends CanvasLayer
##
## 一局结束的结算面板：程序崩溃（死亡）与编译成功（通关）共用一套。
##
## 和升级弹窗一样有三条硬约束，少一条就是"点了没反应"：
##   1. process_mode = WHEN_PAUSED —— 暂停后默认节点收不到输入，按钮会失灵
##   2. 打开显示光标、关闭隐藏 —— 游戏中光标挡视线
##   3. 面板期间暂停整棵树，玩家可以从容看数据，不用抢时间
##
## 多一条：重开走"重载场景"而不是手动 reset。手动 reset 要清七八个对象池、
## 空间网格、所有渲染器、知识卡、音效状态，漏一个就是"重开后画面有残留怪"，
## 而且以后每加一个系统都要记得回来补一行。reload_current_scene 最笨也最稳。
##

signal restart_requested
signal quit_requested

## 死亡/通关 → 弹结算之间的间隔：让死亡音、红色渐晕、Boss 爆炸走完再上面板。
## 立刻弹会让玩家觉得"莫名其妙就结束了"，1.4 秒刚好够反应过来发生了什么。
const END_DELAY := 1.4

# ---- 配色 ----
const C_WIN := Color(1.0, 0.88, 0.40, 1.0)
const C_LOSE := Color(1.0, 0.40, 0.42, 1.0)
const C_DIM := Color(0.02, 0.03, 0.05, 0.86)
const C_PANEL := Color(0.06, 0.08, 0.13, 0.97)
const C_BORDER := Color(0.30, 0.44, 0.56, 0.85)
const C_KEY := Color(0.58, 0.70, 0.82, 0.95)
const C_VAL := Color(0.96, 0.98, 1.0, 0.98)
const C_SUB := Color(0.62, 0.74, 0.86, 0.9)

var _dim: ColorRect
var _panel: Panel
var _title: Label
var _sub: Label
var _rows: VBoxContainer
var _build: Label
var _open := false
var _prev_r := false
var _prev_esc := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_build_ui()
	_dim.visible = false


func is_open() -> bool:
	return _open


## 打开结算。win 由 sim.victory 决定，unlocked/total 由知识卡系统给
## （一局解锁了几张卡是这个面板最值得炫耀的数字）。
func open(sim: Sim, unlocked: int, total: int) -> void:
	var win := sim.victory
	_title.text = "BUILD SUCCESSFUL" if win else "FATAL ERROR"
	_title.add_theme_color_override("font_color", C_WIN if win else C_LOSE)
	_sub.text = "编译成功 · 程序跑通了，可以交付了" if win else "程序已崩溃 · 进程被系统终止"
	_fill_rows(sim, unlocked, total)
	_build.text = _build_text(sim)

	_dim.visible = true
	_open = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _fill_rows(sim: Sim, unlocked: int, total: int) -> void:
	for c in _rows.get_children():
		c.free()

	_row("用时", _fmt(sim.time))
	_row("击杀", "%d" % sim.kills)
	_row("等级", "Lv %d" % sim.level)
	_row("经验宝石", "%d" % sim.gems_collected)
	_row("补丁包 / 宝箱", "%d / %d" % [sim.patches_collected, sim.chests_collected])
	_row("知识卡解锁", "%d / %d" % [unlocked, total])


func _build_text(sim: Sim) -> String:
	var parts: Array[String] = []
	for u in UpgradeDefs.UPGRADES:
		var lv := sim.loadout.level_of(str(u["id"]))
		if lv > 0:
			parts.append("%s Lv%d" % [u["name"], lv])
	if parts.is_empty():
		return "Build：无（没拿到任何升级）"
	return "Build：" + "   ".join(parts)


func _fmt(t: float) -> String:
	var s := int(t)
	return "%02d:%02d" % [s / 60, s % 60]


# ---------------------------------------------------------------- 构建

func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = C_DIM
	add_child(_dim)

	# 640x360 的视口：面板 460x278 居中，四周各留 90x41
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.add_child(root)

	_panel = Panel.new()
	_panel.position = Vector2(90.0, 41.0)
	_panel.size = Vector2(460.0, 278.0)
	root.add_child(_panel)

	var sb := StyleBoxFlat.new()
	sb.bg_color = C_PANEL
	sb.set_border_width_all(1)
	sb.border_color = C_BORDER
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	_panel.add_theme_stylebox_override("panel", sb)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 18
	col.offset_right = -18
	col.offset_top = 14
	col.offset_bottom = -14
	col.add_theme_constant_override("separation", 3)
	_panel.add_child(col)

	_title = Label.new()
	_title.text = "BUILD SUCCESSFUL"
	UiFont.apply(_title, 26, C_WIN)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)

	_sub = Label.new()
	UiFont.apply(_sub, 11, C_SUB)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_sub)

	col.add_child(_spacer(8))

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 2)
	col.add_child(_rows)

	col.add_child(_spacer(8))

	_build = Label.new()
	UiFont.apply(_build, 9, C_KEY)
	_build.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_build)

	col.add_child(_spacer(10))

	var btn_box := HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 16)
	col.add_child(btn_box)

	var b_restart := Button.new()
	b_restart.text = "再来一局  (R)"
	b_restart.custom_minimum_size = Vector2(170, 34)
	UiFont.apply(b_restart, 12, C_VAL)
	b_restart.pressed.connect(func() -> void: restart_requested.emit())
	btn_box.add_child(b_restart)

	var b_quit := Button.new()
	b_quit.text = "退出  (Esc)"
	b_quit.custom_minimum_size = Vector2(150, 34)
	UiFont.apply(b_quit, 12, C_KEY)
	b_quit.pressed.connect(func() -> void: quit_requested.emit())
	btn_box.add_child(b_quit)


func _row(key: String, val: String) -> void:
	var hb := HBoxContainer.new()
	_rows.add_child(hb)

	var k := Label.new()
	k.text = key
	UiFont.apply(k, 11, C_KEY)
	k.custom_minimum_size = Vector2(140, 0)
	hb.add_child(k)

	var v := Label.new()
	v.text = val
	UiFont.apply(v, 12, C_VAL)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hb.add_child(v)


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


## 暂停期间 _process 还在跑，键盘只能在这里轮询 + 自己做边沿检测
## （is_action_just_pressed 在暂停时不可靠，直接查物理键位最稳）。
func _process(_delta: float) -> void:
	if not _open:
		return
	var r := Input.is_key_pressed(KEY_R)
	if r and not _prev_r:
		restart_requested.emit()
	_prev_r = r

	var esc := Input.is_key_pressed(KEY_ESCAPE)
	if esc and not _prev_esc:
		quit_requested.emit()
	_prev_esc = esc


# ---------------------------------------------------------------- 测试接口

func debug_reset() -> void:
	_open = false
	_dim.visible = false
	if get_tree().paused:
		get_tree().paused = false
