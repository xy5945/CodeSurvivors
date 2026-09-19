class_name OrbitWeapon
extends RefCounted
##
## 循环护盾：N 个环绕物绕玩家匀速旋转，碰到的敌人受伤。
##
## 核心约束：每个敌人有独立的受击冷却（orb_cd，存在 EnemyPool 里）。
## 没有它，5 个环绕物叠在一起会把贴脸的敌人瞬间秒掉，武器强度失控。
## 这正好对应 for 循环的语义：不停，但每次只做一次。
##
## 位置写在 ox/oy 里供渲染层读取 —— 表现层不重复算一遍三角函数。
##
## 吸血（lifesteal）：开局唯一的续航手段，随环绕物增多而衰减，满级归零。
##   目的是提高开局存活率 —— 那时只有 2 个环绕物、输出低，被摸两下就很危险；
##   到满级有 6 个环绕物、输出足够，再给吸血就是"站着不动也死不了"。
##   **必须有独立的冷却**：环绕物碰到几个敌人就回几次的话，
##   敌群越密回得越多，反而变成"越危险越安全"的正反馈（长鞭踩过同一个坑）。
##   现在每秒最多回一次，和低等级时的接触伤害（约 15 血/秒）相比只是续命量。
##

const MAX_ORBITERS := 12

# 吸血触发的最小间隔。想调吸血强度请改数据表里的 lifesteal，不要改这个值 ——
# 它只是防止"一帧碰到 8 个敌人回 8 次"的限流器。
const LIFESTEAL_CD := 0.5

# 数值（由 Loadout.recompute 写入）
var enabled := false
var count := 0
var damage := 0.0
var radius := 0.0
var spin := 0.0
var hit_cd := 0.0
var lifesteal := 0.0   # 每次吸血回复的生命（0 = 不吸血）
var evolved := false    # 嵌套循环：内外双层反向环
var draw_count := 0     # 渲染层要画的环绕物总数（进化后是 count 的两倍）

# 运行时状态
var angle := 0.0
var ox := PackedFloat32Array()
var oy := PackedFloat32Array()
var _heal_cd := 0.0


func _init() -> void:
	ox.resize(MAX_ORBITERS)
	oy.resize(MAX_ORBITERS)


func apply_stats(level: int, lo: Loadout) -> void:
	var s := UpgradeDefs.stats_for("orbit", level)
	count = mini(int(s["orbiters"]), MAX_ORBITERS)
	damage = float(s["dmg"]) * lo.damage_mult
	radius = float(s["radius"])
	spin = float(s["spin"])
	hit_cd = float(s["hit_cd"])
	lifesteal = float(s["lifesteal"])
	enabled = true
	evolved = lo.is_evolved("orbit")
	# 嵌套循环：外圈照旧，内圈半径 62%、反向转得更快、伤害 60%。
	# 内圈不是白送的伤害 —— 它转得快所以命中更频繁，但每次更弱，
	# 净效果是"贴身的敌人被磨得更快"，而不是整体 DPS 翻倍。
	# 环绕物上限 12 个：count 满级 6 → 双层正好 12，ox/oy 装得下。
	draw_count = count * (2 if evolved else 1)
	draw_count = mini(draw_count, MAX_ORBITERS)


func update(dt: float, sim) -> void:
	if not enabled:
		return

	if _heal_cd > 0.0:
		_heal_cd = maxf(0.0, _heal_cd - dt)

	angle += spin * dt
	if angle > TAU:
		angle -= TAU

	var e: EnemyPool = sim.enemies
	var g: SpatialGrid = sim.grid
	var step := TAU / float(count)
	var hit_r := GameConfig.ORBIT_HIT_RADIUS
	var r2 := hit_r * hit_r

	var i := 0
	while i < draw_count:
		# 前 count 个是外圈（正向），后 count 个是内圈（反向、更快、更弱）
		var inner := i >= count
		var slot := i - count if inner else i
		var a := angle + slot * step
		var rr := radius
		var dmg := damage
		if inner:
			a = -angle * 1.6 + slot * step
			rr = radius * 0.62
			dmg = damage * 0.6
		var x: float = sim.player_x + cos(a) * rr
		var y: float = sim.player_y + sin(a) * rr
		ox[i] = x
		oy[i] = y

		var n := g.query(x, y, hit_r)
		var k := 0
		while k < n:
			var j := g.out[k]
			k += 1
			if e.orb_cd[j] > 0.0:
				continue
			var dx: float = e.px[j] - x
			var dy: float = e.py[j] - y
			if dx * dx + dy * dy > r2:
				continue
			e.hp[j] -= dmg * e.dmg_mult(j)
			e.flash[j] = GameConfig.ORBIT_FLASH
			e.orb_cd[j] = hit_cd
			if lifesteal > 0.0 and _heal_cd <= 0.0:
				sim.heal_player(lifesteal)
				_heal_cd = LIFESTEAL_CD

		i += 1
