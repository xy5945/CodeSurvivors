class_name KnowledgeUI
extends CanvasLayer
##
## 知识卡：右下角弹卡 + Tab 键打开的知识图鉴。
##
## 三条设计约束（改这里之前先读）：
##
## 1. **不打断游戏**。它和升级弹窗最大的区别就在这里 —— 升级要暂停、要点鼠标，
##    知识卡什么都不暂停，玩家一边躲怪一边瞄一眼就够。所以卡片放右上角，
##    顶部与左上角的状态行（血条/Lv/FPS）平齐 —— 那一块在多数时候是空的，
##    也不挡玩家与敌群交火的中轴线（用户 2026-09-17 指定红框区域）。
##    永远不接受鼠标操作 —— 游戏中光标是隐藏的，让孩子去点卡片是找罪受。
##
## 2. **一次只显示一张，其余排队**。开局会同时触发"起始武器 + 变量"两张，
##    6 分钟后精英出场又是一堆。不排队的话角落里会叠成一摞，等于没做。
##
## 3. **同一张卡一局只弹一次**（_seen 兜底）。仿真层自己也记了 seen，
##    但那边的记录服务的是"什么时候 push"，这里服务的是"会不会重复显示"。
##    两处都拦，是因为触发点分散在三个文件里，只靠一处迟早会漏。
##
## 图鉴是整个系统的另一半价值：弹卡是"碰巧看到"，图鉴是"回头复习"。
## 对机构来说，图鉴里那张表才是能直接拿去当课件素材的东西。
##

const CARD_W := 196.0     # 视口只有 640 宽，卡片再大就开始吃交火区了（用户 2026-09-17 反馈）
const CARD_H := 88.0      # 名义高度；实际按文案自适应，见 _fit_height()
const CARD_TOP := 10.0    # 顶部与左上角血条/Lv/FPS 状态行平齐
const CARD_RIGHT := 5.0   # 距右边距：尽量贴边，把中间留给 Boss 血条和战场
const HOLD := 6.0            # 只有一张时停留时长：读完三行中文大概要这么久
const HOLD_QUEUED := 4.0     # 后面还排着队就缩短，否则追不上触发速度
const FADE_IN := 0.22
const FADE_OUT := 0.50
const DELAY_FIRST := 1.2     # 开局先让玩家动起来，别一上来就拿卡片糊脸
const QUEUE_MAX := 6         # 队列上限：极端情况下（Boss 召唤一群新怪）丢弃后来的

const CODEX_COLS := 2
const CODEX_ROWS := 3
const CELL_W := 300.0
const CELL_H := 88.0

# ---- 配色：沿用升级卡的"代码块"观感，但主色换成青，和黄色升级弹窗区分开 ----
const C_HEAD := Color(0.62, 0.78, 0.92, 0.95)
const C_TERM := Color(0.98, 0.86, 0.36, 1.0)
const C_CODE := Color(0.55, 0.80, 0.90, 0.9)
const C_PLAIN := Color(0.94, 0.96, 1.0, 0.96)
const C_USE := Color(0.40, 0.86, 0.78, 0.92)
# 半透明是这个卡的命门：它不暂停游戏，玩家得能透过卡片看见后面的敌人在哪。
# 背景压到 0.5，边框和左侧高亮条也一起压，只留文字保持高不透明 —— 字要看得清，
# 底板要看得穿。所有文字都带 1px 黑描边（UiFont.apply），暗底亮底都啃得动。
const BG := Color(0.05, 0.07, 0.12, 0.50)
const BORDER := Color(0.34, 0.62, 0.78, 0.40)
const ACCENT := Color(0.32, 0.78, 0.88, 0.70)

var _queue: Array[String] = []
var _seen: Dictionary = {}
var _unlocked: Array[String] = []

var _cur := ""
var _timer := 0.0
var _hold := HOLD
var _delay := 0.0

var _card: Panel
var _vb: VBoxContainer
var _head: Label
var _term: Label
var _code: Label
var _plain: Label
var _use: Label

# ---- 图鉴 ----
var _codex: Control
var _codex_title: Label
var _codex_page: Label
var _cells: Array[Panel] = []
var _cell_term: Array[Label] = []
var _cell_plain: Array[Label] = []
var _page := 0
var _codex_open := false


func _ready() -> void:
	# 和升级弹窗同一个理由：暂停后默认 process_mode 的节点收不到输入，
	# Tab 键会在图鉴打开后失效（开得了关不掉）。
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_build_card()
	_build_codex()
	_card.visible = false


## 请求弹一张卡。重复请求会被 _seen 吃掉，所以调用方不用自己判重。
func push(id: String) -> void:
	if id == "" or not KnowledgeDB.has_card(id):
		return
	if _seen.has(id):
		return
	_seen[id] = true
	_unlocked.append(id)
	if _queue.size() >= QUEUE_MAX:
		return
	_queue.append(id)
	if _delay <= 0.0 and _cur == "":
		_delay = DELAY_FIRST


## 由 main.gd 每帧驱动。放在表现层而不是自己 _process，
## 是为了保持"main 是唯一持有帧的地方"这条架构线。
func update(delta: float) -> void:
	if _codex_open:
		return
	_update_card(delta)


func _update_card(delta: float) -> void:
	if _cur == "":
		if _queue.is_empty():
			return
		_delay -= delta
		if _delay > 0.0:
			return
		_show_next()
		return

	_timer -= delta
	_apply_fade()
	if _timer <= 0.0:
		_show_next()


func _show_next() -> void:
	if _queue.is_empty():
		_cur = ""
		_card.visible = false
		return

	_cur = _queue.pop_front()
	_hold = HOLD_QUEUED if not _queue.is_empty() else HOLD
	_timer = _hold
	_card.visible = true
	_fill(_cur)
	_apply_fade()


func _apply_fade() -> void:
	var a := 1.0
	if _timer < FADE_OUT:
		a = clampf(_timer / FADE_OUT, 0.0, 1.0)
	else:
		a = clampf((_hold - _timer) / FADE_IN, 0.0, 1.0)
	_card.modulate.a = a
	# 从右边滑进来一点。纯淡入容易看成"闪了一下"，有个位移才像"弹出一张卡"。
	# 注意：这里必须动 offsets 而不是 position —— position 是相对父控件**原点**
	# 的坐标，对右下锚点的控件写 position 会把卡片甩出屏幕（第一版就栽在这）。
	_card.offset_left = -CARD_W - CARD_RIGHT + (1.0 - a) * -14.0
	_card.offset_right = -CARD_RIGHT + (1.0 - a) * -14.0


# ---------------------------------------------------------------- 卡片本体

func _build_card() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	_card = Panel.new()
	# 锚在右上角，顶部与左上角那排状态文字（血条/Lv/FPS 行）平齐。
	# 不用 set_anchors_preset —— 它的 offset 推算依赖调用时的父矩形，
	# _ready 阶段父级还没布局，算出来的锚点会错（实测卡片飘到屏幕外）。
	# 显式写四个 anchors + 四个 offsets，行为完全确定。
	_card.anchor_left = 1.0
	_card.anchor_right = 1.0
	_card.anchor_top = 0.0
	_card.anchor_bottom = 0.0
	_card.offset_left = -CARD_W - CARD_RIGHT
	_card.offset_right = -CARD_RIGHT
	_card.offset_top = CARD_TOP
	_card.offset_bottom = CARD_TOP + CARD_H
	_card.modulate.a = 0.0
	root.add_child(_card)

	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.set_border_width_all(1)
	sb.border_color = BORDER
	# 左边一条竖着的青色高亮：整张卡的"这是一条代码"的观感全靠它
	sb.border_width_left = 2
	sb.border_color = ACCENT
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 9
	sb.content_margin_right = 7
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	_card.add_theme_stylebox_override("panel", sb)

	_vb = VBoxContainer.new()
	_vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vb.offset_left = 9
	_vb.offset_right = -7
	_vb.offset_top = 6
	_vb.offset_bottom = -6
	_vb.add_theme_constant_override("separation", 1)
	_card.add_child(_vb)

	_head = Label.new()
	UiFont.apply(_head, 8, C_HEAD)
	_vb.add_child(_head)

	_term = Label.new()
	UiFont.apply(_term, 13, C_TERM)
	_vb.add_child(_term)

	_code = Label.new()
	UiFont.apply(_code, 9, C_CODE)
	_vb.add_child(_code)

	_vb.add_child(_spacer(2))

	_plain = Label.new()
	UiFont.apply(_plain, 10, C_PLAIN)
	_plain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_vb.add_child(_plain)

	_vb.add_child(_spacer(1))

	_use = Label.new()
	UiFont.apply(_use, 9, C_USE)
	_use.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_vb.add_child(_use)


func _fill(id: String) -> void:
	var c := KnowledgeDB.card_of(id)
	if c.size() == 0:
		return
	var n := KnowledgeDB.index_of(id) + 1
	_head.text = "知识卡  %d / %d" % [n, KnowledgeDB.total()]
	_term.text = str(c["term"])
	_code.text = str(c["code"])
	_plain.text = str(c["plain"])
	_use.text = str(c["use"])
	_fit_height()


## 高度自适应：文案长短不一（窄卡下白话/用处会折成两行），写死高度不是挤爆
## 文案就是底下空一大块。Label 的换行结果要等一次布局才准，这里直接用字体量：
## 单行宽度 / 可用宽度 向上取整就是行数，再乘行高。略偏保守（多几像素），
## 多出来的空间落在 VBox 底部，不会把字挤掉。
func _fit_height() -> void:
	var inner: float = CARD_W - 9.0 - 7.0
	var h: float = 6.0 + 6.0  # 上下 content margin
	h += _text_h(_head, inner)
	h += _text_h(_term, inner)
	h += _text_h(_code, inner)
	h += _text_h(_plain, inner)
	h += _text_h(_use, inner)
	h += 2.0 * 1.0 + 3.0    # 两个 spacer + separation 余量
	_card.offset_bottom = CARD_TOP + clampf(h, 66.0, 128.0)


func _text_h(lab: Label, inner: float) -> float:
	var f := lab.get_theme_font("font")
	var fs := lab.get_theme_font_size("font_size")
	if f == null:
		return float(fs) + 3.0
	var w: float = f.get_string_size(lab.text, fs).x
	var n := maxi(1, ceili(w / maxf(inner, 1.0)))
	return f.get_height(fs) * float(n) + 1.0


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


# ---------------------------------------------------------------- 图鉴

func _build_codex() -> void:
	_codex = Control.new()
	_codex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_codex.visible = false
	add_child(_codex)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.05, 0.93)
	_codex.add_child(dim)

	_codex_title = Label.new()
	_codex_title.position = Vector2(20, 14)
	UiFont.apply(_codex_title, 18, C_TERM)
	_codex.add_child(_codex_title)

	var hint := Label.new()
	hint.position = Vector2(20, 40)
	hint.text = "A / D 翻页  ·  Tab 或 Esc 关闭"
	UiFont.apply(hint, 11, C_HEAD)
	_codex.add_child(hint)

	_codex_page = Label.new()
	_codex_page.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_codex_page.position = Vector2(-140, -22)
	_codex_page.size = Vector2(120, 16)
	_codex_page.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiFont.apply(_codex_page, 11, C_HEAD)
	_codex.add_child(_codex_page)

	for r in CODEX_ROWS:
		for c in CODEX_COLS:
			_cell(Vector2(20.0 + c * (CELL_W + 12.0), 62.0 + r * (CELL_H + 8.0)))


func _cell(pos: Vector2) -> void:
	var p := Panel.new()
	p.position = pos
	p.size = Vector2(CELL_W, CELL_H)
	_codex.add_child(p)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.10, 0.15, 0.95)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.20, 0.26, 0.34, 1.0)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 10
	vb.offset_right = -10
	vb.offset_top = 6
	vb.offset_bottom = -6
	vb.add_theme_constant_override("separation", 2)
	p.add_child(vb)

	var head := Label.new()
	UiFont.apply(head, 10, C_CODE)
	vb.add_child(head)

	var term := Label.new()
	UiFont.apply(term, 15, C_TERM)
	vb.add_child(term)

	var plain := Label.new()
	UiFont.apply(plain, 11, C_PLAIN)
	plain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(plain)

	var use := Label.new()
	UiFont.apply(use, 10, C_USE)
	use.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(use)

	_cells.append(p)
	_cell_term.append(term)
	_cell_plain.append(plain)
	# head / use 两个 Label 挂在格子里但没存引用 —— 放进数组要四个数组，
	# 不如直接按索引从格子树里取。这里存两个最常用的就够。
	p.set_meta("head", head)
	p.set_meta("use", use)


func _open_codex() -> void:
	_codex_open = true
	_page = 0
	_codex.visible = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_refresh_codex()


func _close_codex() -> void:
	_codex_open = false
	_codex.visible = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)


func _refresh_codex() -> void:
	var per := CODEX_COLS * CODEX_ROWS
	var pages := maxi(1, ceili(float(KnowledgeDB.total()) / float(per)))
	_page = clampi(_page, 0, pages - 1)

	_codex_title.text = "知识图鉴    已解锁 %d / %d" % [_unlocked.size(), KnowledgeDB.total()]
	_codex_page.text = "第 %d / %d 页" % [_page + 1, pages]

	var i := 0
	while i < _cells.size():
		var idx := _page * per + i
		var p := _cells[i]
		var head := p.get_meta("head") as Label
		var use := p.get_meta("use") as Label
		if idx >= KnowledgeDB.CARDS.size():
			p.visible = false
			i += 1
			continue
		p.visible = true

		var c: Dictionary = KnowledgeDB.CARDS[idx]
		var got := _seen.has(str(c["id"]))
		if got:
			head.text = "%s   %s" % [KnowledgeDB.KIND_NAMES[int(c["kind"])], c["code"]]
			_cell_term[i].text = str(c["term"])
			_cell_plain[i].text = str(c["plain"])
			use.text = str(c["use"])
			p.modulate.a = 1.0
		else:
			head.text = KnowledgeDB.KIND_NAMES[int(c["kind"])]
			_cell_term[i].text = "？ ？ ？"
			_cell_plain[i].text = "还没遇到，继续玩就能解锁"
			use.text = ""
			p.modulate.a = 0.42
		i += 1


## 只有这里用 _process：Tab 键必须在暂停时也能按（否则图鉴开得了关不掉），
## 而 main.gd 的 _process 在暂停时是不跑的。除了这一处，全部由 main 驱动。
func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("build_panel"):
		if _codex_open:
			_close_codex()
		# 升级弹窗开着时不要抢它的暂停状态，否则关掉图鉴会把游戏直接放出来
		elif not get_tree().paused:
			_open_codex()
		return

	if not _codex_open:
		return

	if Input.is_action_just_pressed("ui_cancel"):
		_close_codex()
		return

	var per := CODEX_COLS * CODEX_ROWS
	var pages := maxi(1, ceili(float(KnowledgeDB.total()) / float(per)))
	if Input.is_action_just_pressed("move_left") and _page > 0:
		_page -= 1
		_refresh_codex()
	elif Input.is_action_just_pressed("move_right") and _page < pages - 1:
		_page += 1
		_refresh_codex()


# ---------------------------------------------------------------- 测试接口

## 无头测试用：把队列和当前卡清空成指定状态。
func debug_reset() -> void:
	_queue.clear()
	_seen.clear()
	_unlocked.clear()
	_cur = ""
	_timer = 0.0
	_delay = 0.0
	_card.visible = false


## 结算面板要显示"本局解锁了几张卡"，这个数字只有这里知道。
func unlocked_count() -> int:
	return _unlocked.size()


func debug_snapshot() -> Dictionary:
	return {
		"cur": _cur, "queue": _queue.size(),
		"unlocked": _unlocked.size(), "visible": _card.visible,
	}
