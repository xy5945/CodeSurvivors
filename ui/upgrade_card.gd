class_name UpgradeCard
extends Panel
##
## 升级三选一里的一张卡。
##
## 刻意做成"代码块"的样子：语法符号在上、名称在中、注释风格的一句话在下。
## 那句 // 注释是整个 UI 里最能体现编程主题的地方，比任何美术都管用。
##

signal picked(card: UpgradeCard)

const WIDTH := 188.0
const HEIGHT := 236.0

const C_ICON := Color(0.98, 0.86, 0.36, 1.0)
const C_NAME := Color(1.0, 1.0, 1.0, 0.96)
const C_SUB := Color(0.45, 0.82, 0.52, 1.0)     # 注释绿
const C_DESC := Color(0.85, 0.88, 0.95, 0.9)
const C_LV := Color(0.35, 0.72, 0.95, 1.0)

const BG := Color(0.09, 0.11, 0.16, 0.97)
const BORDER := Color(0.22, 0.26, 0.36, 1.0)
const BORDER_HOVER := Color(0.98, 0.86, 0.36, 1.0)
# 进化卡：整张卡描金边，和普通升级卡一眼分开。
# 它是这局最难拿到的东西（武器满级 + 被动满级），必须看起来"值得"。
const BG_EVO := Color(0.16, 0.13, 0.06, 0.98)
const BORDER_EVO := Color(1.0, 0.82, 0.30, 1.0)
const C_LV_EVO := Color(1.0, 0.82, 0.30, 1.0)

var def: Dictionary
var target_level := 1
var is_evo := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(WIDTH, HEIGHT)


func setup(d: Dictionary, lv: int) -> void:
	def = d
	target_level = lv
	is_evo = EvolveDefs.is_evo_id(str(d.get("id", "")))
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()

	_apply_style(BORDER_EVO if is_evo else BORDER)

	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 12
	vb.offset_right = -12
	vb.offset_top = 10
	vb.offset_bottom = -12
	add_child(vb)

	# 语法符号
	var icon := Label.new()
	icon.text = str(def["icon"])
	UiFont.apply(icon, 30, C_ICON)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(icon)

	# 名称
	var name_l := Label.new()
	name_l.text = str(def["name"])
	UiFont.apply(name_l, 17, C_NAME)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(name_l)

	# 等级变化（进化卡这里是"★ 进化"，因为它不吃等级）
	var lv_l := Label.new()
	lv_l.text = "★ 进化" if is_evo else ("新获得" if target_level == 1 else "Lv %d → %d" % [target_level - 1, target_level])
	# 角色专属武器标出来：玩家看到这一行才知道"这把只有我这局的角色能拿"，
	# 也顺便解释了为什么别人的专属武器从来没在三选一里出现过。
	if not is_evo and UpgradeDefs.is_exclusive(str(def.get("id", ""))):
		lv_l.text += "　·　专属"
	UiFont.apply(lv_l, 12, C_LV_EVO if is_evo else C_LV)
	lv_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(lv_l)

	vb.add_child(_spacer(6))

	# 代码注释风格的一句话
	var sub := Label.new()
	sub.text = str(def["sub"])
	UiFont.apply(sub, 11, C_SUB)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(sub)

	vb.add_child(_spacer(6))

	# 本级具体效果
	var desc := Label.new()
	var levels: Array = def["levels"]
	desc.text = str(levels[mini(target_level, levels.size()) - 1]["desc"])
	UiFont.apply(desc, 13, C_DESC)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(desc)


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _apply_style(border: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_EVO if is_evo else BG
	sb.border_color = border
	sb.set_border_width_all(3 if is_evo else 2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	add_theme_stylebox_override("panel", sb)


# ---------------------------------------------------------------- 交互

func _ready() -> void:
	mouse_entered.connect(func() -> void: _apply_style(BORDER_HOVER))
	mouse_exited.connect(func() -> void: _apply_style(BORDER_EVO if is_evo else BORDER))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			picked.emit(self)
