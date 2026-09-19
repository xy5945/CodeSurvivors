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

# ---- 面板尺寸 ----
# 高度不再是写死的公式：内容填完后让 VBox 自己报最小高度，面板照着撑
# （见 _relayout）。原因写在 _relayout 上方 —— 估行数那套会把按钮挤出面板。
const PANEL_W := 460.0
const PANEL_MIN_H := 258.0
const PANEL_MAX_H := 330.0  # 视口 360，上下各留 15
const PAD_X := 18.0
const PAD_TOP := 14.0
const PAD_BOTTOM := 16.0
# 三段留白：标题下 / 数据表下 / Build 与按钮之间
const SPACER_H: Array[float] = [8.0, 8.0, 12.0]

# ---- 配色 ----
const C_WIN := Color(1.0, 0.88, 0.40, 1.0)
const C_LOSE := Color(1.0, 0.40, 0.42, 1.0)
const C_DIM := Color(0.02, 0.03, 0.05, 0.86)
const C_PANEL := Color(0.06, 0.08, 0.13, 0.97)
const C_BORDER := Color(0.30, 0.44, 0.56, 0.85)
const C_KEY := Color(0.58, 0.70, 0.82, 0.95)
const C_VAL := Color(0.96, 0.98, 1.0, 0.98)
const C_SUB := Color(0.62, 0.74, 0.86, 0.9)
const C_UNLOCK := Color(1.0, 0.86, 0.40, 1.0)

var _dim: ColorRect
var _panel: Panel
var _col: VBoxContainer
var _title: Label
var _sub: Label
var _unlock: Label
var _unlock_box: PanelContainer
var _rows: VBoxContainer
var _build: Label
var _btn_box: HBoxContainer
var _spacers: Array[Control] = []
var _compact := false
# 开面板后再量几帧：第一次量的时候 Label 还没按新文本重新分行，
# 报出来的高度是错的（实测空 Build 都能报 193）。面板暂停时 _process 照样跑，
# 补两帧就能收口，玩家看不到这 30ms 的变化。
var _relayout_ticks := 0
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
## unlock_msg：这一局通关解锁的新角色名，空串表示没解锁（死亡或已解锁过）。
func open(sim: Sim, unlocked: int, total: int, unlock_msg := "") -> void:
	var win := sim.victory
	_title.text = "BUILD SUCCESSFUL" if win else "FATAL ERROR"
	_title.add_theme_color_override("font_color", C_WIN if win else C_LOSE)
	_sub.text = "编译成功，程序全部跑通，可以交付了" if win else "程序已崩溃 · 进程被系统终止"
	# 解锁提示单独占一条：它是"这一局最大的收获"，混在副标题里会被一眼略过。
	_unlock.text = ("新角色解锁　" + unlock_msg) if unlock_msg != "" else ""
	_unlock_box.visible = unlock_msg != ""
	_fill_rows(sim, unlocked, total)
	_build.text = _build_text(sim)
	# 内容都填完了才量高度 —— 顺序反了量到的是上一局的高度
	_relayout(_build.text)
	_relayout_ticks = 2

	_dim.visible = true
	_open = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _fill_rows(sim: Sim, unlocked: int, total: int) -> void:
	for c in _rows.get_children():
		c.free()

	_row("角色", _char_text(sim))
	_row("用时", _fmt(sim.time))
	_row("消灭 Bug", "%d 个" % sim.kills)
	_row("等级", "Lv %d" % sim.level)
	_row("变量", "%d" % sim.gems_collected)
	_row("补丁包 / 宝箱", "%d / %d" % [sim.patches_collected, sim.chests_collected])
	_row("知识卡解锁", "%d / %d" % [unlocked, total])


## 面板排版的唯一入口：先让 Build 那行报出真实换行高度，再让 VBox 报出
## 内容总高，面板照着撑，最后居中。
##
## 之前用的是"单行宽度 ÷ 可用宽度 = 行数"的估算，中文英文混排时经常少算一行
## （少十几像素），而 VBox 超出的部分 Godot 既不裁剪也不报错 ——
## 结果就是最底下的「再来一局 / 退出」被顶到面板外沿上，看着像两块 UI 重叠。
## 换成 get_multiline_string_size + get_combined_minimum_size，两边都由引擎
## 自己算，不会再对不上。
func _relayout(_text: String) -> void:
	# 先把 Build 的宽度钉成可用宽度。autowrap Label 的"最小宽度"只有一个字宽，
	# 不钉住的话它按 1 字/行去换行，硬生生报出 200+ px 的最小高度
	# （实测空 Build 都报 235），面板被撑爆，最底下的按钮就被顶到面板外面 ——
	# 玩家看到的就是"按钮压在面板上"。钉住宽度后它才按真实行数算高度。
	var avail: float = PANEL_W - PAD_X * 2.0
	_build.custom_minimum_size = Vector2(avail, 0.0)
	# 光设 custom_minimum_size 不够：Label 要等下一次排版才按新宽度重新分行，
	# 这里同步设一次 size.x，让它当场按可用宽度排版 —— 量到的才是真行数。
	_build.size.x = avail

	# 顺序不能反：先按正常间距量一次，塞不下才切紧凑并**重新量**。
	# 只切不重量的话，面板拿到的是紧凑态的高度，实际排的却是正常间距 ——
	# 差出来的十几像素正好把底部按钮顶出面板（实测溢出 13px）。
	_set_compact(false)
	var h := _content_height() + PAD_TOP + PAD_BOTTOM
	if h > PANEL_MAX_H:
		_set_compact(true)
		h = _content_height() + PAD_TOP + PAD_BOTTOM
	h = clampf(h, PANEL_MIN_H, PANEL_MAX_H)
	_panel.size = Vector2(PANEL_W, h)
	_panel.position = Vector2((640.0 - PANEL_W) * 0.5, (360.0 - h) * 0.5)


## 逐块报最小高度，只给排查排版用（哪个块撑爆了一眼就看出来）
func _part_sizes() -> Array:
	var out: Array = []
	for c in _col.get_children():
		out.append("%s:%.0f" % [c.get_class(), c.get_combined_minimum_size().y])
	return out


func _content_height() -> float:
	return _col.get_combined_minimum_size().y


## 紧凑模式：只在内容真的装不下时开。省出来的十几像素换来的是
## "按钮还在面板里"，比留白好看重要得多。
func _set_compact(on: bool) -> void:
	if _compact == on:
		return
	_compact = on
	_col.add_theme_constant_override("separation", 2 if on else 3)
	_rows.add_theme_constant_override("separation", 1 if on else 2)
	for i in _spacers.size():
		_spacers[i].custom_minimum_size.y = SPACER_H[i] * (0.6 if on else 1.0)


func _build_text(sim: Sim) -> String:
	var parts: Array[String] = []
	for u in UpgradeDefs.UPGRADES:
		var lv := sim.loadout.level_of(str(u["id"]))
		if lv > 0:
			# 进化过的标一颗 ★ —— 这是这局最难达成的东西，结算里必须看得见
			var star := "★" if sim.loadout.is_evolved(str(u["id"])) else ""
			parts.append("%s%s Lv%d" % [u["name"], star, lv])
	if parts.is_empty():
		return "Build：无（没拿到任何升级）"
	return "Build：" + "   ".join(parts)


## 角色 + 它的编程概念。结算里留这一行，是因为不同角色的成绩不该直接横向比 ——
## 运维的续航和测试的容错，本来就不是同一种打法。
func _char_text(sim: Sim) -> String:
	if sim.char_def.is_empty():
		return "—"
	return "%s（%s）" % [sim.char_def["name"], sim.char_def["term"]]


func _fmt(t: float) -> String:
	var s := int(t)
	return "%02d:%02d" % [s / 60, s % 60]


# ---------------------------------------------------------------- 构建

func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = C_DIM
	add_child(_dim)

	# 640x360 的视口：面板 460 宽居中，高度由 _relayout 按内容定（先给个中间值）
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.add_child(root)

	_panel = Panel.new()
	_panel.position = Vector2((640.0 - PANEL_W) * 0.5, (360.0 - PANEL_MIN_H) * 0.5)
	_panel.size = Vector2(PANEL_W, PANEL_MIN_H)
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

	_col = VBoxContainer.new()
	# 关键：offsets 显式写四对。set_anchors_preset 在 _ready 阶段父节点还没布局，
	# 算出来的 offset 是错的（表现为内容整体飘出面板，而且零报错）。
	_col.set_anchors_preset(Control.PRESET_FULL_RECT)
	_col.offset_left = PAD_X
	_col.offset_right = -PAD_X
	_col.offset_top = PAD_TOP
	_col.offset_bottom = -PAD_BOTTOM
	_col.add_theme_constant_override("separation", 3)
	_panel.add_child(_col)
	var col := _col

	_title = Label.new()
	_title.text = "BUILD SUCCESSFUL"
	UiFont.apply(_title, 26, C_WIN)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)

	_sub = Label.new()
	UiFont.apply(_sub, 11, C_SUB)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_sub)

	# 解锁提示做成一条金边高亮条：裸文字夹在副标题和数据表之间太容易被略过，
	# 而它是一局里最值得看见的东西。
	_unlock_box = PanelContainer.new()
	_unlock_box.visible = false
	_unlock_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var usb := StyleBoxFlat.new()
	usb.bg_color = Color(1.0, 0.86, 0.40, 0.12)
	usb.set_border_width_all(1)
	usb.border_color = Color(1.0, 0.86, 0.40, 0.60)
	usb.set_corner_radius_all(3)
	usb.content_margin_left = 10
	usb.content_margin_right = 10
	usb.content_margin_top = 4
	usb.content_margin_bottom = 4
	_unlock_box.add_theme_stylebox_override("panel", usb)
	col.add_child(_unlock_box)

	_unlock = Label.new()
	UiFont.apply(_unlock, 12, C_UNLOCK)
	_unlock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_unlock_box.add_child(_unlock)

	col.add_child(_spacer(0))

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 2)
	col.add_child(_rows)

	col.add_child(_spacer(1))

	_build = Label.new()
	UiFont.apply(_build, 9, C_KEY)
	_build.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_build)

	col.add_child(_spacer(2))

	_btn_box = HBoxContainer.new()
	_btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_btn_box.add_theme_constant_override("separation", 16)
	col.add_child(_btn_box)

	# 走 UiFont.make_button：标题页/选人/暂停用的是同一套，这里自己 new 一个
	# Button 会拿到 Godot 默认的那块灰底，和暗色面板完全不是一套。
	var b_restart := UiFont.make_button("再来一局  (R)", 12, C_VAL)
	b_restart.custom_minimum_size = Vector2(170, 32)
	b_restart.pressed.connect(func() -> void: restart_requested.emit())
	_btn_box.add_child(b_restart)

	var b_quit := UiFont.make_button("退出  (Esc)", 12, C_KEY)
	b_quit.custom_minimum_size = Vector2(150, 32)
	b_quit.pressed.connect(func() -> void: quit_requested.emit())
	_btn_box.add_child(b_quit)


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


## 留白按 SPACER_H 的索引取高度，并登记进 _spacers —— 紧凑模式要统一压它们。
func _spacer(i: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, SPACER_H[i])
	_spacers.append(c)
	return c


## 暂停期间 _process 还在跑，键盘只能在这里轮询 + 自己做边沿检测
## （is_action_just_pressed 在暂停时不可靠，直接查物理键位最稳）。
func _process(_delta: float) -> void:
	if not _open:
		return

	if _relayout_ticks > 0:
		_relayout(_build.text)
		_relayout_ticks -= 1

	var r := Input.is_key_pressed(KEY_R)
	if r and not _prev_r:
		restart_requested.emit()
	_prev_r = r

	var esc := Input.is_key_pressed(KEY_ESCAPE)
	if esc and not _prev_esc:
		quit_requested.emit()
	_prev_esc = esc


# ---------------------------------------------------------------- 测试接口

## 布局体检：把面板矩形和各块的实际位置交出去，测试端判断有没有溢出。
## 结算面板是纯手工排的（没有锚定系统兜底），内容一多就会溢出面板底边，
## 而 Godot 不会裁剪也不会报错 —— 只能靠量数字发现，肉眼看截图很容易漏。
func debug_layout() -> Dictionary:
	var pr := _panel.get_global_rect()
	var br := _btn_box.get_global_rect()
	var lr := _build.get_global_rect()
	return {
		"panel": pr,
		"buttons": br,
		"build": lr,
		"content": _content_height(),
		"parts": _part_sizes(),
		"compact": _compact,
		"unlock_visible": _unlock_box.visible,
	}


func debug_reset() -> void:
	_open = false
	_dim.visible = false
	if get_tree().paused:
		get_tree().paused = false
