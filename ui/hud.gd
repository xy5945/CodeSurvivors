class_name HUD
extends CanvasLayer
##
## 顶部经验条 + 左上状态 + 底部 Build 摘要。
##
## 经验条是这一版新增的核心反馈：升级三选一是整个游戏的节奏点，
## 玩家必须随时能看到"还差多少能升级"，否则滚雪球的爽感会断掉。
##

var _exp_fill: ColorRect
var _hp_fill: ColorRect
var _lv_label: Label
var _info: Label
var _build_label: Label
# Boss 血条：顶部中央，只在 Boss 在场时显示。
# 48px 的大块头 + 4000 血，玩家必须能一眼看到"还剩多久打完"。
var _boss_root: Control
var _boss_fill: ColorRect
var _boss_label: Label

var _frames := 0
var _acc := 0.0
var _fps := 0.0
var _slow_acc := 0.0    # 低频更新的计时（Build 摘要不需要每帧刷）


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# ---- 顶部经验条 ----
	var exp_bg := ColorRect.new()
	exp_bg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	exp_bg.offset_bottom = 9
	exp_bg.color = Color(0.10, 0.13, 0.18, 0.9)
	root.add_child(exp_bg)

	_exp_fill = ColorRect.new()
	_exp_fill.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_exp_fill.size = Vector2(0, 9)
	_exp_fill.color = Color(0.32, 0.92, 0.85, 0.95)
	root.add_child(_exp_fill)

	# ---- 血条 ----
	var hp_bg := ColorRect.new()
	hp_bg.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hp_bg.position = Vector2(10, 15)
	hp_bg.size = Vector2(200, 8)
	hp_bg.color = Color(0.18, 0.08, 0.08, 0.9)
	root.add_child(hp_bg)

	_hp_fill = ColorRect.new()
	_hp_fill.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_hp_fill.position = Vector2(10, 15)
	_hp_fill.size = Vector2(200, 8)
	_hp_fill.color = Color(0.85, 0.22, 0.22, 0.95)
	root.add_child(_hp_fill)

	# ---- 文本 ----
	_lv_label = Label.new()
	_lv_label.position = Vector2(11, 28)
	UiFont.apply(_lv_label, 16, Color(0.32, 0.92, 0.85, 1.0))
	root.add_child(_lv_label)

	_info = Label.new()
	_info.position = Vector2(11, 50)
	UiFont.apply(_info, 12, Color(0.9, 0.92, 0.96, 0.92))
	root.add_child(_info)

	_build_label = Label.new()
	_build_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_build_label.position = Vector2(11, -30)
	UiFont.apply(_build_label, 12, Color(0.75, 0.8, 0.9, 0.85))
	root.add_child(_build_label)

	_boss_bar(root)


func _boss_bar(root: Control) -> void:
	_boss_root = Control.new()
	_boss_root.set_anchors_preset(Control.PRESET_CENTER_TOP)
	# 视口宽 640，血条 200 宽居中；y=46 在左上 info 行（y50 起）之上、经验条之下
	_boss_root.position = Vector2(-100, 46)
	_boss_root.visible = false
	root.add_child(_boss_root)

	var bg := ColorRect.new()
	bg.size = Vector2(200, 10)
	bg.color = Color(0.22, 0.05, 0.06, 0.92)
	_boss_root.add_child(bg)

	_boss_fill = ColorRect.new()
	_boss_fill.size = Vector2(200, 10)
	_boss_fill.color = Color(0.92, 0.18, 0.16, 0.95)
	_boss_root.add_child(_boss_fill)

	_boss_label = Label.new()
	_boss_label.position = Vector2(64, -15)
	UiFont.apply(_boss_label, 12, Color(1.0, 0.72, 0.68, 0.95))
	_boss_label.text = "编译器反噬"
	_boss_root.add_child(_boss_label)


func update_stats(delta: float, sim: Sim) -> void:
	_acc += delta
	_frames += 1
	_slow_acc += delta

	# 经验条每帧更新：它是连续的，降频会有肉眼可见的跳动
	_exp_fill.size.x = float(_exp_fill.get_parent().size.x) * _exp_ratio(sim)
	if sim.max_hp > 0.0:
		_hp_fill.size.x = 200.0 * clampf(sim.player_hp / sim.max_hp, 0.0, 1.0)

	# Boss 血条：每帧更新（血量连续变化，降频会跳）
	_boss_root.visible = sim.boss_active
	if sim.boss_active and sim.boss_max_hp > 0.0:
		_boss_fill.size.x = 200.0 * clampf(sim.boss_hp / sim.boss_max_hp, 0.0, 1.0)

	if _frames < 6:
		return
	_fps = _frames / _acc if _acc > 0.0 else 0.0
	_frames = 0
	_acc = 0.0

	_lv_label.text = "Lv %d" % sim.level

	if sim.dead:
		_info.text = "FPS %d  消灭Bug %d  存活 %s\n程序已崩溃 (Fatal Error)" % [
			int(_fps), sim.kills, _fmt_time(sim.time)
		]
	elif sim.victory:
		_info.text = "FPS %d  消灭Bug %d  通关用时 %s\nBUILD SUCCESSFUL · 编译成功" % [
			int(_fps), sim.kills, _fmt_time(sim.time)
		]
	else:
		_info.text = "FPS %d  敌人 %d  消灭Bug %d  HP %d/%d  %s%s" % [
			int(_fps), sim.enemies.count, sim.kills,
			int(sim.player_hp), int(sim.max_hp), _fmt_time(sim.time),
			"  [静音 · M]" if Sfx.is_muted() else ""
		]

	# Build 摘要每秒刷一次就够
	if _slow_acc >= 1.0:
		_slow_acc = 0.0
		_build_label.text = _build_text(sim)


func _exp_ratio(sim: Sim) -> float:
	if sim.exp_next <= 0:
		return 0.0
	return clampf(float(sim.exp_cur) / float(sim.exp_next), 0.0, 1.0)


func _build_text(sim: Sim) -> String:
	# 满配 6 武器 + 6 被动 = 12 项，写全名会超出 640 宽的视口。
	# 缩写成"符号+等级"：认识符号的人一眼看懂，不认识的去看升级卡片。
	var parts := []
	for u in UpgradeDefs.UPGRADES:
		var lv := sim.loadout.level_of(u["id"])
		if lv > 0:
			parts.append("%s%d" % [u["icon"], lv])
	return "  ".join(parts) if parts.size() > 0 else "WASD 移动 · 朝向即攻击方向 · M 静音"


func _fmt_time(t: float) -> String:
	var m := int(t) / 60
	var s := int(t) % 60
	return "%d:%02d" % [m, s]
