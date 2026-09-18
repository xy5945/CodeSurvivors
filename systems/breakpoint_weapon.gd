class_name BreakpointWeapon
extends RefCounted
##
## 断点调试 `breakpoint_debug`：让周围敌人原地定住。
##
## 冻结的实现是 enemy_pool.freeze —— 大于 0 时敌人完全跳过移动、分离、
## 技能和接触伤害（见 sim._move_enemies 的 continue）。
##
## 关键设计：**冻结必须附带易伤**（GameConfig.FREEZE_DMG_BONUS = +50%）。
## 只冻不打的控制在幸存者类里是陷阱 —— 玩家会觉得"这把武器没有伤害"，
## 而且冻结期间敌人不掉血，解冻后该围还是围，等于白控 1.8 秒。
## 绑上易伤之后，它变成"开团信号"：冻住的那一瞬间所有武器打得更疼。
##
## 先设 freeze 再结算伤害，这样本次伤害就吃到 +50%（顺序不能反）。
##

const FLASH := 0.14

var enabled := false
var damage := 0.0     # L1~L3 为 0：纯控制，没有伤害
var cd_base := 0.0
var radius := 0.0
var freeze_dur := 0.0
var hit_cap := 0

var cooldown := 0.0


func apply_stats(level: int, lo: Loadout) -> void:
	var s := UpgradeDefs.stats_for("breakpoint", level)
	damage = float(s["dmg"]) * lo.damage_mult
	cd_base = float(s["cd"]) * lo.cooldown_mult
	radius = float(s["radius"])
	freeze_dur = float(s["freeze"])
	hit_cap = int(s["hit_cap"])
	enabled = true


func update(dt: float, sim) -> void:
	if not enabled:
		return
	cooldown -= dt
	if cooldown > 0.0:
		return
	cooldown = cd_base
	_pause(sim)


func _pause(sim) -> void:
	var e: EnemyPool = sim.enemies
	var cx: float = sim.player_x
	var cy: float = sim.player_y
	var r2 := radius * radius

	var n: int = sim.grid.query(cx, cy, radius, hit_cap)
	var hits := 0
	var k := 0
	while k < n and hits < hit_cap:
		var j: int = sim.grid.out[k]
		k += 1
		var dx := e.px[j] - cx
		var dy := e.py[j] - cy
		if dx * dx + dy * dy > r2:
			continue
		# 取最大值：新断点不该缩短上一次的冻结时间
		e.freeze[j] = maxf(e.freeze[j], freeze_dur)
		if damage > 0.0:
			e.hp[j] -= damage * e.dmg_mult(j)
		e.flash[j] = FLASH
		hits += 1

	sim.fx.add_pulse(cx, cy, radius * 0.3, radius, 0.32, 1, false)
	sim.sfx_events.append("ui")
