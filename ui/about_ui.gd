class_name AboutUI
extends CanvasLayer
##
## 关于本作品：稚码园的品牌形象页 —— 作品信息 / 关于稚码园 / 创作理念 / 版权声明。
##
## 和《守护稚码王国》（塔防）是同一套门面：主菜单一个「关于本作品」按钮进来，
## 返回按钮固定在底部不动，正文可滚动。谁来问"这游戏是谁做的、能不能拿去用"，
## 答案都在这页上，不用翻 README。
##
## 内容量（角色/武器/进化/Bug/知识卡）全部**从数据表现读**，不写第二份数字。
## 只有"版本"和"代码量"是手写常量 —— 那两个数没有对应的数据表可查，
## 改的时候记得连这里一起改。
##
## 配色沿用塔防那套金：标题金 + 正文白 + 声明灰。本作的 UI 主色是青白，
## 但品牌页要"稳重、正式"，金色更像落款。
##

signal back_requested

# 手写常量（改代码结构时要回来改这两个）
const VERSION := "v1.0.0"
const CODE_LINE_HINT := "13,000+ 行 GDScript（64 个脚本）"

const C_TITLE := Color(1.0, 0.88, 0.42, 1.0)
const C_GOLD := Color(0.86, 0.72, 0.32, 1.0)
const C_HEAD := Color(0.62, 0.94, 1.0, 1.0)
const C_TEXT := Color(0.86, 0.89, 0.95, 1.0)
const C_DIM := Color(0.60, 0.66, 0.78, 1.0)
const C_NOTE := Color(1.0, 0.86, 0.42, 1.0)

# 640x360 视口：面板上下各留 16，底部 30 给返回按钮
const PANEL_X := 24.0
const PANEL_Y := 16.0
const PANEL_W := 592.0
const PANEL_H := 328.0
const BODY_Y := 78.0
const BODY_H := 218.0
const BTN_Y := 306.0
const BTN_H := 30.0

var _from := ""
var _is_open := false
var _body: VBoxContainer
var _scroll: ScrollContainer
var _title_label: Label
var _sub_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_build()
	hide()


## 把正文拼成一个字符串交出去，测试端用来断言"该写的都写了"。
## 品牌页的价值全在文案上，headless 测不了排版，但能测有没有漏写。
func debug_text() -> String:
	# 标题和副标题不在 _body 里（它们是固定位置，不随正文滚动），一并交出去
	var parts: Array[String] = [_title_label.text, _sub_label.text]
	for c in _body.get_children():
		if c is Label:
			parts.append((c as Label).text)
		elif c is HBoxContainer:
			for cc in (c as HBoxContainer).get_children():
				if cc is Label:
					parts.append((cc as Label).text)
	return "\n".join(parts)


func is_open() -> bool:
	return _is_open


## from_id：从哪打开的（"title" / "pause"），返回时还给谁。
func open(from_id: String) -> void:
	_from = from_id
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
	dim.color = Color(0.01, 0.02, 0.04, 0.94)
	root.add_child(dim)

	var panel := Panel.new()
	panel.position = Vector2(PANEL_X, PANEL_Y)
	panel.size = Vector2(PANEL_W, PANEL_H)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.11, 0.98)
	sb.border_color = Color(0.34, 0.28, 0.14, 1.0)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)

	_title_label = Label.new()
	_title_label.text = "关于本作品"
	UiFont.apply(_title_label, 18, C_TITLE)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.position = Vector2(PANEL_X + 12.0, PANEL_Y + 8.0)
	_title_label.size = Vector2(PANEL_W - 24.0, 24.0)
	root.add_child(_title_label)

	# 装饰线 + 副标题：塔防那页有这两条金线，落款感就来自它们
	var line := ColorRect.new()
	line.color = Color(0.62, 0.52, 0.22, 1.0)
	line.position = Vector2(PANEL_X + 12.0, PANEL_Y + 38.0)
	line.size = Vector2(PANEL_W - 24.0, 1.0)
	root.add_child(line)

	_sub_label = Label.new()
	_sub_label.text = "代码幸存者　CODE  SURVIVORS"
	UiFont.apply(_sub_label, 11, C_GOLD)
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_label.position = Vector2(PANEL_X + 12.0, PANEL_Y + 44.0)
	_sub_label.size = Vector2(PANEL_W - 24.0, 18.0)
	root.add_child(_sub_label)

	var body_w: float = PANEL_W - 36.0
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(PANEL_X + 18.0, BODY_Y)
	_scroll.size = Vector2(body_w, BODY_H)
	root.add_child(_scroll)

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 钉住宽度：不钉的话 autowrap Label 的最小宽度只有 1px，会按 1 字/行换行
	_body.custom_minimum_size = Vector2(body_w - 12.0, 0.0)
	_body.add_theme_constant_override("separation", 2)
	_scroll.add_child(_body)

	_fill()

	var back := UiFont.make_button("返回上一页", 11, Color(1.0, 0.86, 0.42, 1.0))
	back.position = Vector2(320.0 - 80.0, BTN_Y)
	back.size = Vector2(160.0, BTN_H)
	back.pressed.connect(_on_back)
	root.add_child(back)


func _on_back() -> void:
	if not _is_open:
		return
	close()
	back_requested.emit(_from)


# ---------------- 正文 ----------------

func _fill() -> void:
	_add_head("◆ 作品信息")
	_add_kv("版本", VERSION)
	_add_kv("引擎", "Godot 4 · GDScript")
	_add_kv("代码量", CODE_LINE_HINT)
	_add_kv("角色", "%d 名（逐个通关解锁）" % CharDefs.CHARACTERS.size())
	_add_kv("武器", "%d 把　·　被动 %d 个　·　进化 %d 条" % [
		_count_kind(UpgradeDefs.KIND_WEAPON), _count_kind(UpgradeDefs.KIND_PASSIVE),
		EvolveDefs.EVOLUTIONS.size()])
	_add_kv("敌人", "%d 类 Bug + 编译器反噬（Boss）" % EnemyDB.DEFS.size())
	_add_kv("知识卡", "%d 张（随进度解锁）" % KnowledgeDB.total())
	_sp(4)

	_add_head("◆ 关于稚码园")
	_add_para("稚码园机器人编程，用游戏点燃孩子的代码梦想。")
	_add_para("我们相信每个孩子都能创造自己的世界。")
	_add_para("编程不是枯燥的代码，而是创造的工具。")
	_add_para("「我们不教孩子背代码，我们让孩子在创造里用熟它。」")
	_sp(4)

	_add_head("◆ 边玩边练：游戏里的代码训练")
	_add_para("升级不是点一下按钮就完事：三选一之后，要照着屏幕把一段真实的 C++ 代码打出来，全打对了才升级。救我一命也是 —— 想续命，就打一道完整小题。")
	_add_para("题库全部取自 C++ 入门到进阶最常用的写法，覆盖 GESP C++ 一至四级的高频关键字和标准语句：变量与输入输出、分支 if / else / switch、循环 for / while / do-while、数组与二维数组、指针与 new / delete……")
	_add_para("孩子为了变强会一遍遍亲手打这些代码 —— 手熟了，代码就不再是拦路虎。玩得开心，代码熟练度不知不觉就上去了。")
	_sp(4)

	_add_head("◆ 姊妹作品")
	_add_para("《守护稚码王国》：pygame 开发的暗黑魔幻塔防，每波清完同样要打一段 C++ 代码领补给，与本作共用同一套题库。")
	_sp(4)

	_add_head("◆ 创作理念")
	_add_para("这是一本能“玩懂”的编程启蒙游戏。")
	_add_para("每把武器、每只 Bug 都对应一个真实的编程概念：分支、循环、指针、递归、垃圾回收、断点调试……你在游戏里用它们打架，知识卡再告诉你它是什么、代码里怎么写。")
	_add_para("先有直觉，再有概念 —— 比先背定义再做题更容易记住，也不容易忘。")
	_add_para("所以我们把数值压在“能玩”这一侧：机制优先于数值，好玩优先于难。")
	_sp(4)

	_add_head("◆ 版权声明")
	_add_note2("本作品由稚码园机器人编程团队独立设计开发。")
	_add_note2("游戏中全部代码、美术、音效均为原创或经合法授权。")
	_add_note2("稚码园机器人编程　保留所有权利。")
	_add_note2("未经授权不得复制、修改或用于商业目的。")
	_sp(4)

	_add_note("感谢每一位玩家 —— 你的每一次通关，都是孩子眼里的一段代码。")


func _count_kind(kind: int) -> int:
	var n := 0
	for u in UpgradeDefs.UPGRADES:
		if int(u["kind"]) == kind:
			n += 1
	return n


# ---------------- 排版小工具 ----------------

func _add_head(text: String) -> void:
	var l := Label.new()
	l.text = text
	UiFont.apply(l, 12, C_HEAD)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(l)
	_sp(2)


func _add_para(text: String) -> void:
	var l := Label.new()
	l.text = "　" + text
	UiFont.apply(l, 10, C_TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(l)
	_sp(2)


## 左标签右值：作品信息那张表用（仿塔防的 info_lines，值右对齐更好扫）
func _add_kv(label: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(row)

	var k := Label.new()
	k.text = label
	UiFont.apply(k, 10, C_DIM)
	k.custom_minimum_size = Vector2(64.0, 0.0)
	row.add_child(k)

	var v := Label.new()
	v.text = value
	UiFont.apply(v, 10, C_TEXT)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(v)
	_sp(2)


func _add_note2(text: String) -> void:
	var l := Label.new()
	l.text = "　" + text
	UiFont.apply(l, 9, C_DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(l)
	_sp(1)


func _add_note(text: String) -> void:
	var l := Label.new()
	l.text = text
	UiFont.apply(l, 9, C_NOTE)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			_on_back()
			get_viewport().set_input_as_handled()
