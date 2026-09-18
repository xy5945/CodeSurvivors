class_name GcWeapon
extends RefCounted
##
## 垃圾回收 `gc_sweep`：周期性回收范围内血量低于阈值的敌人。
##
## 它是全场唯一"直接删除实体"的武器 —— 不造成常规伤害，而是把 hp 归零，
## 交给 sim._reap 走正常死亡流程（掉宝石、计击杀、精英照样分裂）。
## 这一点很关键：如果绕过 _reap 直接 kill，经验曲线和掉落都会被打乱。
##
## 设计上它是一把"越到后期越强"的武器。前期敌人血量低、数量少，
## 它看起来几乎没用；后期杂兵血量涨到几百，玩家打残一片却收不掉，
## 它能一次性清空 —— 这是它存在的唯一理由，也是它不该在前期就强的原因。
##
## 低等级没有回收伤害（只回收残血），第 4 级起附带范围伤害，
## 于是它在"清残血"之外还有点自己的输出。
##

const FLASH := 0.12

var enabled := false
var cd_base := 0.0
var thr := 0.0          # 回收阈值（血量比例）
var radius := 0.0
var damage := 0.0       # 回收时附带的范围伤害（L1~L3 为 0）
var hit_cap := 0
var reset_n := 0        # 每回收这么多个，冷却立即重置（L8）

var cooldown := 0.0
var recycled_total := 0   # 本局累计回收数（结算与测试用）
var _since_reset := 0


func apply_stats(level: int, lo: Loadout) -> void:
	var s := UpgradeDefs.stats_for("gc", level)
	cd_base = float(s["cd"]) * lo.cooldown_mult
	thr = float(s["thr"])
	radius = float(s["radius"])
	# 回收伤害吃全局伤害加成 —— 它是实打实的伤害，不是斩杀效果
	damage = float(s["dmg"]) * lo.damage_mult
	hit_cap = int(s["hit_cap"])
	reset_n = int(s["reset_n"])
	enabled = true


func update(dt: float, sim) -> void:
	if not enabled:
		return
	cooldown -= dt
	if cooldown > 0.0:
		return
	cooldown = cd_base
	_sweep(sim)


func _sweep(sim) -> void:
	var e: EnemyPool = sim.enemies
	var cx: float = sim.player_x
	var cy: float = sim.player_y
	var r2 := radius * radius

	var n: int = sim.grid.query(cx, cy, radius, hit_cap)
	var hits := 0
	var recycled := 0
	var k := 0
	while k < n and hits < hit_cap:
		var j: int = sim.grid.out[k]
		k += 1
		var dx := e.px[j] - cx
		var dy := e.py[j] - cy
		if dx * dx + dy * dy > r2:
			continue

		# hp_max 可能是 0（不该发生，但除零会让阈值判定变成 NaN），兜一下
		var frac: float = e.hp[j] / maxf(e.hp_max[j], 1.0)
		if frac <= thr:
			e.hp[j] = 0.0      # 直接回收；掉落与击杀由 _reap 处理
			recycled += 1
		elif damage > 0.0:
			e.hp[j] -= damage * e.dmg_mult(j)
		e.flash[j] = FLASH
		hits += 1

	# 寿命 0.7s：24 帧序列按 ~34fps 播完（pulse 纯视觉，不影响结算）。
	sim.fx.add_pulse(cx, cy, radius * 0.2, radius, 0.7, 0, false)
	sim.sfx_events.append("wave")

	recycled_total += recycled
	if reset_n > 0 and recycled > 0:
		_since_reset += recycled
		if _since_reset >= reset_n:
			_since_reset -= reset_n
			cooldown = 0.0     # 立刻再来一次：滚起来的 GC 是停不下来的
