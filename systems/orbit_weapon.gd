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

const MAX_ORBITERS := 12

# 数值（由 Loadout.recompute 写入）
var enabled := false
var count := 0
var damage := 0.0
var radius := 0.0
var spin := 0.0
var hit_cd := 0.0

# 运行时状态
var angle := 0.0
var ox := PackedFloat32Array()
var oy := PackedFloat32Array()


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
	enabled = true


func update(dt: float, sim) -> void:
	if not enabled:
		return

	angle += spin * dt
	if angle > TAU:
		angle -= TAU

	var e: EnemyPool = sim.enemies
	var g: SpatialGrid = sim.grid
	var step := TAU / float(count)
	var hit_r := GameConfig.ORBIT_HIT_RADIUS
	var r2 := hit_r * hit_r

	var i := 0
	while i < count:
		var a := angle + i * step
		var x: float = sim.player_x + cos(a) * radius
		var y: float = sim.player_y + sin(a) * radius
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
			e.hp[j] -= damage * e.dmg_mult(j)
			e.flash[j] = GameConfig.ORBIT_FLASH
			e.orb_cd[j] = hit_cd

		i += 1
