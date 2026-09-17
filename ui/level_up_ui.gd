class_name LevelUpUI
extends CanvasLayer
##
## 升级三选一弹窗。这是整个游戏唯一需要玩家用鼠标的地方。
##
## 三个必须做对的点，少一个就会出现"点了没反应"：
##   1. process_mode = WHEN_PAUSED —— 游戏暂停后，默认 process_mode 的节点
##      收不到任何输入，按钮会完全失灵
##   2. 打开时显示鼠标光标，关闭时隐藏 —— 游戏中光标会挡视线
##   3. 弹窗期间游戏暂停，玩家可以从容看三张卡，不用抢时间
##

signal resolved

const CARD_GAP := 14

var sim: Sim = null

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

	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.02, 0.03, 0.05, 0.72)
	root.add_child(_dim)

	# 640x360 的视口里，卡片区用固定尺寸居中
	_center = Control.new()
	_center.position = Vector2(320, 180)
	root.add_child(_center)

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


func open(s: Sim) -> void:
	sim = s
	_roll()
	show()
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func close() -> void:
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

	var i := 0
	while i < _cards.size():
		var c: Dictionary = choices[i]
		_cards[i].setup(c["def"], int(c["level"]))
		_cards[i].visible = true
		i += 1


func _on_card_picked(card: UpgradeCard) -> void:
	if sim == null:
		return

	var id := str(card.def["id"])
	if id == "_heal":
		sim.apply_heal_pick(30.0)
	else:
		sim.apply_upgrade(id)

	if sim.pending_levelups > 0:
		_roll()          # 连升多级：继续选
	else:
		close()
