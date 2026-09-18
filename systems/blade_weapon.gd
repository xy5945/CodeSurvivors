class_name BladeWeapon
extends RefCounted
##
## 递归飞刃 `recursive_blade`：命中后分裂出一个更弱的自己，继续飞向下一个目标。
##
## 每一次弹射就是一次"自我调用"，伤害按 decay 衰减、速度按 spd_bonus 递增 ——
## 递归的代价（越来越弱）和递归的终止条件（bounces 用尽）都是显式的。
##

const FIRE_SEEK := 320.0        # 发射时找目标的范围

# 数值（由 Loadout.recompute 写入）
var enabled := false
var damage := 0.0
var cd_base := 0.0
var proj_speed := 0.0
var bounces := 0
var decay := 1.0
var spd_bonus := 0.0
var evolved := false    # 尾递归：弹射不衰减、次数 +3

var cooldown := 0.0


func apply_stats(level: int, lo: Loadout) -> void:
	var s := UpgradeDefs.stats_for("blade", level)
	damage = float(s["dmg"]) * lo.damage_mult
	cd_base = float(s["cd"]) * lo.cooldown_mult
	proj_speed = float(s["pspeed"])
	bounces = int(s["bounces"])
	decay = float(s["decay"])
	spd_bonus = float(s["spd_bonus"])
	enabled = true
	evolved = lo.is_evolved("blade")
	if evolved:
		# 尾递归：每次弹射不再衰减（decay = 1），弹射次数 +3。
		# 普通递归越递归越弱，是"栈要一层层还回去"的代价；
		# 尾递归没有这个代价，所以能一直递归下去 —— 数值上就是不再衰减。
		decay = 1.0
		bounces += 3


func update(dt: float, sim) -> void:
	if not enabled:
		return
	cooldown -= dt
	if cooldown > 0.0:
		return
	cooldown = cd_base
	sim.sfx_events.append("shoot")
	_fire(sim)


func _fire(sim) -> void:
	var e: EnemyPool = sim.enemies
	var dx: float = sim.facing_x
	var dy: float = sim.facing_y

	var tj := Targeting.nearest(sim, sim.grid, e, sim.player_x, sim.player_y, FIRE_SEEK)
	if tj >= 0:
		dx = e.px[tj] - sim.player_x
		dy = e.py[tj] - sim.player_y
		var d := sqrt(dx * dx + dy * dy)
		if d > 0.001:
			dx /= d
			dy /= d
		else:
			dx = sim.facing_x
			dy = sim.facing_y

	sim.projectiles.spawn_blade(
		sim.player_x, sim.player_y,
		dx * proj_speed, dy * proj_speed,
		damage, bounces, decay, spd_bonus
	)
