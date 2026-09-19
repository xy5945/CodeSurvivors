class_name HelpUI
extends CanvasLayer
##
## 游戏说明：背景故事 + 操作 + 武器 + 被动/进化 + Bug 图鉴，一共四页。
##
## 内容全部**从数据表现读**（UpgradeDefs / EvolveDefs / EnemyDB），不手写第二份。
## 否则改一次武器数值就要记得同步改说明，漏一次就是"说明里写的和游戏里不一样"，
## 而这种错恰恰只有玩家会看到。
##
## 可以从两个地方进来：标题页的「游戏说明」按钮、暂停界面的「游戏说明」按钮。
## 返回时回到**进来时的那一页**（_from），所以标题页进来回标题、暂停进来回暂停。
##

signal back_requested

# 一页只放得下 4~6 个条目（640x360 的视口，正文区只有 218 像素高）。
# 12 把武器、12 条进化、11 类 Bug 各自拆成两页，宁可翻页也不要滚三屏。
const PAGE_TITLES: Array[String] = [
	"背景与玩法", "武器一览（一）", "武器一览（二）", "被动强化",
	"进化（一）", "进化（二）", "Bug 图鉴（一）", "Bug 图鉴（二）",
]

const C_TITLE := Color(1.0, 0.88, 0.42, 1.0)
const C_HEAD := Color(0.62, 0.94, 1.0, 1.0)
const C_TEXT := Color(0.82, 0.87, 0.95, 1.0)
const C_DIM := Color(0.58, 0.65, 0.77, 1.0)

# 640x360 的视口，四边各留 24，底部 34 给按钮
const PANEL_X := 24.0
const PANEL_Y := 22.0
const PANEL_W := 592.0
const BODY_Y := 70.0
const BODY_H := 218.0
const BTN_Y := 300.0
const BTN_H := 28.0

var _from := ""
var _page := 0
var _is_open := false

var _page_label: Label
var _body: VBoxContainer
var _scroll: ScrollContainer
var _btn_prev: Button
var _btn_next: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_build()
	hide()


func is_open() -> bool:
	return _is_open


## from_id：从哪打开的（"title" / "pause"），返回时还给谁。
func open(from_id: String) -> void:
	_from = from_id
	_page = 0
	_show_page()
	show()
	_is_open = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = true


## 直接跳到第 i 页（截图 / 测试用）
func show_page(i: int) -> void:
	_page = clampi(i, 0, PAGE_TITLES.size() - 1)
	_show_page()


func close() -> void:
	_is_open = false
	hide()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.02, 0.04, 0.94)
	root.add_child(dim)

	var panel := Panel.new()
	panel.position = Vector2(PANEL_X, PANEL_Y)
	panel.size = Vector2(PANEL_W, 316.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.13, 0.98)
	sb.border_color = Color(0.26, 0.32, 0.44, 1.0)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)

	var title := Label.new()
	title.text = "游戏说明"
	UiFont.apply(title, 18, C_TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(PANEL_X + 12.0, PANEL_Y + 8.0)
	title.size = Vector2(PANEL_W - 24.0, 24.0)
	root.add_child(title)

	_page_label = Label.new()
	UiFont.apply(_page_label, 11, C_HEAD)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.position = Vector2(PANEL_X + 12.0, PANEL_Y + 34.0)
	_page_label.size = Vector2(PANEL_W - 24.0, 18.0)
	root.add_child(_page_label)

	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(PANEL_X + 12.0, BODY_Y)
	_scroll.size = Vector2(PANEL_W - 24.0, BODY_H)
	root.add_child(_scroll)

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 3)
	_scroll.add_child(_body)

	_btn_prev = UiFont.make_button("← 上一页", 11)
	_btn_prev.position = Vector2(PANEL_X + 130.0, BTN_Y)
	_btn_prev.size = Vector2(110.0, BTN_H)
	_btn_prev.pressed.connect(_prev_page)
	root.add_child(_btn_prev)

	_btn_next = UiFont.make_button("下一页 →", 11)
	_btn_next.position = Vector2(PANEL_X + 250.0, BTN_Y)
	_btn_next.size = Vector2(110.0, BTN_H)
	_btn_next.pressed.connect(_next_page)
	root.add_child(_btn_next)

	var back := UiFont.make_button("返回上一页", 11, Color(1.0, 0.86, 0.42, 1.0))
	back.position = Vector2(PANEL_X + 370.0, BTN_Y)
	back.size = Vector2(110.0, BTN_H)
	back.pressed.connect(_on_back)
	root.add_child(back)


func _prev_page() -> void:
	if _page > 0:
		_page -= 1
		_show_page()


func _next_page() -> void:
	if _page < PAGE_TITLES.size() - 1:
		_page += 1
		_show_page()


func _on_back() -> void:
	if not _is_open:
		return
	close()
	back_requested.emit(_from)


func _show_page() -> void:
	for c in _body.get_children():
		c.queue_free()

	_page_label.text = "%d / %d　%s" % [_page + 1, PAGE_TITLES.size(), PAGE_TITLES[_page]]
	_btn_prev.disabled = _page == 0
	_btn_next.disabled = _page == PAGE_TITLES.size() - 1

	match _page:
		0: _page_story()
		1, 2: _page_weapons(_page - 1)
		3: _page_passives()
		4, 5: _page_evolutions(_page - 4)
		6, 7: _page_bugs(_page - 6)

	# 换了页要回到顶部，否则从第 4 页翻回第 1 页时停在半空
	_scroll.scroll_vertical = 0


# ---------------- 第 1 页：背景与玩法 ----------------

func _page_story() -> void:
	_add_head("你是一段程序")
	_add_para("你刚被写出来，还没跑通，就被丢进了一个满是 Bug 的系统里。四面八方涌过来的报错、弹窗、死循环都想让你的进程崩溃。")
	_add_para("撑住 18 分钟，等编译器把最后一行代码编译完 —— 看到 BUILD SUCCESSFUL，你就赢了。")

	_add_head("怎么变强")
	_add_para("每消灭一个 Bug 会掉出经验宝石，捡够就升级。每次升级从三张卡里选一张：拿新武器、给武器升段、或者加被动。")
	_add_para("一局最多能带 6 把武器 + 5 个被动，所以选什么就是在决定这一局你是什么打法。")
	_add_para("武器和它对应的被动都升到满级时，会出现金色的「进化」卡：武器的机制直接改变，不是加数字那么简单。")

	_add_head("操作")
	_add_para("WASD 移动　·　鼠标点击升级卡　·　Tab 查看已解锁的知识卡　·　ESC 暂停")

	_add_head("角色与难度")
	_add_para("一开始只有「实习生」可以用。用他通关一次（撑满 18 分钟、看到 BUILD SUCCESSFUL），才会解锁下一个角色 —— 每个新角色都得靠前一个通关换来。")
	_add_para("越靠后的角色，敌人的血量越厚：实习生 ×0.8 → 测试工程师 ×0.9 → 算法工程师 ×1.0 → 全栈工程师 ×1.1 → 架构师 ×1.2。解锁进度会自动保存。")

	_add_head("知识卡")
	_add_para("每把武器、每个 Bug 都对应一个真实的编程概念。第一次遇到时会弹出知识卡，讲它是什么、代码里怎么用。Tab 可以随时翻看已经解锁的。")
	_add_note("提示：站着不动是活不下来的 —— 这一作的核心就是走位。")


# ---------------- 第 2 页：武器 ----------------

## half：0 = 前 6 把，1 = 后 6 把
func _page_weapons(half: int) -> void:
	if half == 0:
		_add_head("12 把武器（开局自带一把，其余靠升级获得）")
	for u in _weapons_slice(half):
		var lv: Dictionary = (u["levels"] as Array)[0]
		var wname := str(u["name"])
		# 专属武器标出归属角色：5 把起始武器各自只属于一个角色，
		# 其他角色在升级三选一里根本看不到它 —— 选角色就是在选开局打法。
		var owner := UpgradeDefs.owner_of(str(u["id"]))
		if owner != "":
			wname += "（%s 专属）" % CharDefs.def_of(owner).get("name", owner)
		_add_item("[%s] %s" % [str(u["icon"]), wname], str(lv["desc"]))
		_add_sub(str(u["sub"]))
	if half == 1:
		_add_note("武器满 8 级后，配合对应被动满级即可进化（见进化页）。")
		_add_note("带「专属」的 5 把武器是各个角色的起始武器，其他角色拿不到 —— 所以开局选谁，直接决定了这一局能凑出什么 build。")


func _weapons_slice(half: int) -> Array:
	var ws: Array = []
	for u in UpgradeDefs.UPGRADES:
		if int(u["kind"]) == UpgradeDefs.KIND_WEAPON:
			ws.append(u)
	return ws.slice(half * 6, half * 6 + 6)


# ---------------- 第 3 页：强化与进化 ----------------

func _page_passives() -> void:
	_add_head("被动强化（最多同时带 5 个）")
	_add_para("被动不和武器绑定，任何 build 都能拿。但每把武器进化时，都指定了一个「必须满级的被动」。")
	for u in UpgradeDefs.UPGRADES:
		if int(u["kind"]) != UpgradeDefs.KIND_PASSIVE:
			continue
		var lv: Dictionary = (u["levels"] as Array)[0]
		_add_item("· %s" % str(u["name"]), str(lv["desc"]))


## half：0 = 前 6 条，1 = 后 6 条
func _page_evolutions(half: int) -> void:
	if half == 0:
		_add_head("进化（武器机制质变）")
		_add_para("触发条件：某把武器升到满级 + 它指定的那个被动也升到满级。满足后进化卡会直接出现在三选一里，必占一席。")
	var es: Array = EvolveDefs.EVOLUTIONS.slice(half * 6, half * 6 + 6)
	for e in es:
		var elv: Dictionary = (e["levels"] as Array)[0]
		_add_item("★ %s" % str(e["name"]), str(elv["desc"]))
		_add_sub(str(e["sub"]))


# ---------------- 第 4 页：Bug 图鉴 ----------------

## half：0 = 前期杂兵，1 = 后期杂兵 + 精英 / Boss 详解
func _page_bugs(half: int) -> void:
	if half == 0:
		_add_head("Bug 图鉴（一）· 前期（按时间档位陆续投放）")
		for d in EnemyDB.DEFS.slice(0, 5):
			_add_item("%s　%s" % [str(d["name"]), _when(d)], str(d["desc"]))
	else:
		_add_head("Bug 图鉴（二）· 后期")
		for d in EnemyDB.DEFS.slice(5):
			_add_item("%s　%s" % [str(d["name"]), _when(d)], str(d["desc"]))
		_add_head("两种特殊敌人")
		_add_item("精英怪", "6 分钟起每 40 秒来一只，会冲刺、会放环形弹幕，打死还会分裂出小怪 —— 但必掉一个宝箱，回 50 点血。")
		_add_item("编译器反噬（Boss）", "18 分钟准时出场。五种技能轮流放：冲刺、环形弹幕、扇形弹幕、追踪弹、地面危险区，还会召唤小怪堵你的走位。")
		_add_note("注意：Boss 对冻结有很强的抗性 —— 想靠控制把它锁住是行不通的，得靠走位躲技能。")


func _when(d: Dictionary) -> String:
	if bool(d.get("boss", false)):
		return "18 分钟终局"
	if bool(d.get("elite", false)):
		return "6 分钟起"
	var fs: float = float(d["from_sec"])
	if fs <= 0.0:
		return "开局就有"
	return "%d 分起" % int(fs / 60.0)


# ---------------- 排版小工具 ----------------

func _add_head(text: String) -> void:
	var l := Label.new()
	l.text = text
	UiFont.apply(l, 12, C_HEAD)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(l)
	_sp(3)


func _add_para(text: String) -> void:
	var l := Label.new()
	l.text = text
	UiFont.apply(l, 10, C_TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(l)
	_sp(4)


## 一条目：head 是主行（亮），sub 是说明（暗）
func _add_item(head: String, sub: String) -> void:
	var l := Label.new()
	l.text = head
	UiFont.apply(l, 10, C_TITLE)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(l)

	var s := Label.new()
	s.text = "　　" + sub
	UiFont.apply(s, 9, C_TEXT)
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(s)
	_sp(3)


func _add_sub(text: String) -> void:
	var l := Label.new()
	l.text = "　　　" + text
	UiFont.apply(l, 9, C_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(l)
	_sp(3)


func _add_note(text: String) -> void:
	var l := Label.new()
	l.text = text
	UiFont.apply(l, 9, Color(1.0, 0.86, 0.42, 1.0))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(l)


func _sp(h: int) -> void:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0.0, float(h))
	_body.add_child(c)


func _input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_LEFT or k == KEY_A:
			_prev_page()
			get_viewport().set_input_as_handled()
		elif k == KEY_RIGHT or k == KEY_D:
			_next_page()
			get_viewport().set_input_as_handled()
		elif k == KEY_ESCAPE:
			_on_back()
			get_viewport().set_input_as_handled()
