class_name LevelUpUI
extends CanvasLayer
##
## 升级三选一弹窗。这是整个游戏唯一需要玩家用鼠标的地方。
##
## 四个必须做对的点，少一个就会出现"点了没反应"：
##   1. process_mode = WHEN_PAUSED —— 游戏暂停后，默认 process_mode 的节点
##      收不到任何输入，按钮会完全失灵
##   2. 打开时显示鼠标光标，关闭时隐藏 —— 游戏中光标会挡视线
##   3. 弹窗期间游戏暂停，玩家可以从容看三张卡，不用抢时间
##   4. 打码面板的 layer 必须比本弹窗高，且点开打码前本弹窗要先 hide
##      —— 否则打码面板会被盖在下面，看起来就是"升级框不消失、打不了字"
##
## 收尾还要留 1 秒「准备时间」：打完代码手还在键盘上，直接恢复游戏会挨打。
## 这一秒内游戏仍然暂停，只是不再显示卡片。
##

signal resolved

const CARD_GAP := 14
## 打完代码后回到游戏的缓冲（秒）
const READY_SEC := 1.0

var sim: Sim = null
## 打码面板，由 main.gd 接进来。null 时退回「点了直接升级」。
var code_input: CodeInputUI = null
## 难度档位（CodeChallenge.Mode）。OFF 时点卡直接生效。
var code_mode: int = CodeChallenge.Mode.STD
var _pending_id := ""

var _panel: Control          # 选卡那一套（遮罩 + 卡片）
var _ready_layer: Control    # 收尾那 1 秒的「准备」提示
var _ready_t := -1.0         # < 0 表示不在准备期
var _need_ready := false     # 只有走过打码的那一轮才需要缓冲

var _dim: ColorRect
var _center: Control
var _title: Label
var _hint: Label
var _card_box: HBoxContainer
var _cards: Array[UpgradeCard] = []


func _ready() -> void:
	# 关键：没有这一行，暂停后按钮收不到鼠标事件
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_build()
	hide()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_panel)

	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.02, 0.03, 0.05, 0.72)
	_panel.add_child(_dim)

	# 640x360 的视口里，卡片区用固定尺寸居中
	_center = Control.new()
	_center.position = Vector2(320, 180)
	_panel.add_child(_center)

	var col := VBoxContainer.new()
	col.position = Vector2(-300, -155)
	col.size = Vector2(600, 310)
	_center.add_child(col)

	_title = Label.new()
	_title.text = "LEVEL UP"
	UiFont.apply(_title, 22, Color(1.0, 0.88, 0.4, 1.0))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)

	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 8)
	col.add_child(sp)

	_card_box = HBoxContainer.new()
	_card_box.custom_minimum_size = Vector2(600, 236)
	_card_box.add_theme_constant_override("separation", CARD_GAP)
	_card_box.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_card_box)

	_hint = Label.new()
	_hint.text = "用鼠标点一张卡 · 游戏已暂停，不用着急"
	UiFont.apply(_hint, 11, Color(0.7, 0.75, 0.85, 0.85))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_hint)

	for i in 3:
		var card := UpgradeCard.new()
		card.picked.connect(_on_card_picked)
		_card_box.add_child(card)
		_cards.append(card)

	_build_ready(root)


## 「准备」提示层：和卡片层是兄弟，关卡片时不关它
func _build_ready(root: Control) -> void:
	_ready_layer = Control.new()
	_ready_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ready_layer.visible = false
	root.add_child(_ready_layer)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.05, 0.35)
	_ready_layer.add_child(dim)

	# 右下/底部锚定的坑见踩坑 13：这里用中心 + 固定坐标，不做锚定动画
	var box := VBoxContainer.new()
	box.position = Vector2(-160, -46)
	box.size = Vector2(320, 92)
	var c := Control.new()
	c.position = Vector2(320, 180)
	_ready_layer.add_child(c)
	c.add_child(box)

	var big := Label.new()
	big.text = "准备…"
	UiFont.apply(big, 30, Color(1.0, 0.88, 0.4, 1.0))
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(big)

	var small := Label.new()
	small.text = "手放回 WASD · 马上继续"
	UiFont.apply(small, 12, Color(0.78, 0.82, 0.9, 0.9))
	small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(small)


func _process(delta: float) -> void:
	if _ready_t < 0.0:
		return
	_ready_t += delta
	if _ready_t >= READY_SEC:
		_ready_t = -1.0
		_finish_resume()


func open(s: Sim) -> void:
	sim = s
	_ready_t = -1.0
	_need_ready = false
	_ready_layer.visible = false
	_panel.visible = true
	_roll()
	show()
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


## 真正解除暂停并收尾
func _finish_resume() -> void:
	_ready_layer.visible = false
	hide()
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	resolved.emit()


## 打出「准备…」并计时。游戏仍然是暂停的，只是卡片收起来了。
func _begin_resume() -> void:
	_ready_t = 0.0
	_panel.visible = false
	_ready_layer.visible = true
	show()
	# 光标提前收：准备层只有一行提示，光标留着只会挡视线
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)


## 兼容外部直接调用：不带缓冲地关掉
func close() -> void:
	_ready_t = -1.0
	_ready_layer.visible = false
	_panel.visible = true
	hide()
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	resolved.emit()


func _roll() -> void:
	var choices := sim.loadout.roll_choices(3)
	_title.text = "LEVEL UP  →  Lv %d" % sim.level
	if sim.pending_levelups > 1:
		_hint.text = "还有 %d 次选择 · 用鼠标点一张卡" % (sim.pending_levelups - 1)
	else:
		_hint.text = "用鼠标点一张卡 · 游戏已暂停，不用着急"

	# 选项可能不足 3 个（武器和被动全满级时，兜底只给一张紧急补丁）。
	# 以前这里直接 choices[i]，少一个就数组越界 —— 多出来的卡位藏起来就行，
	# HBoxContainer 是居中对齐的，剩一张时它会自己在中间。
	var i := 0
	while i < _cards.size():
		if i < choices.size():
			var c: Dictionary = choices[i]
			_cards[i].setup(c["def"], int(c["level"]))
			_cards[i].visible = true
		else:
			_cards[i].visible = false
		i += 1


func _on_card_picked(card: UpgradeCard) -> void:
	Sfx.play("ui")
	if sim == null:
		return

	var id := str(card.def["id"])

	# 紧急补丁是保底选项（武器被动全满时只剩它），不该被题目卡住；
	# 关掉打码或没接面板时，退回原来的「点了直接升级」。
	if id == "_heal" or code_mode == CodeChallenge.Mode.OFF or code_input == null:
		_apply(id, false)
		return

	var head := "★ 进化" if card.is_evo else (
		"新获得" if card.target_level == 1 else "Lv %d → %d" % [card.target_level - 1, card.target_level])
	_pending_id = id
	_need_ready = true
	# 先把自己收起来：打码面板在自己的 CanvasLayer 上，层更高，
	# 但遮罩是半透明的，不 hide 的话卡片会透上来盖住输入框
	hide()
	code_input.open("%s　%s" % [str(card.def["name"]), head],
		id, card.target_level, card.is_evo, code_mode)


func _on_code_solved() -> void:
	_apply(_pending_id, true)


## 真正写入升级。打码通过后才轮到这里。
## with_ready：这一轮走过打码，收尾要多留 1 秒
func _apply(id: String, with_ready: bool = false) -> void:
	if id == "_heal":
		sim.apply_heal_pick(30.0)
	else:
		sim.apply_upgrade(id)

	if sim.pending_levelups > 0:
		show()          # 连升多级：卡片层回来继续选
		_roll()
		return

	if with_ready or _need_ready:
		_need_ready = false
		_begin_resume()
	else:
		_finish_resume()


## 由 main.gd 调一次，把打码面板接上
func bind_code_input(ci: CodeInputUI) -> void:
	code_input = ci
	ci.solved.connect(_on_code_solved)
