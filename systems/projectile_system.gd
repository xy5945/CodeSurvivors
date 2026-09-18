class_name ProjectileSystem
extends RefCounted
##
## 投射物的移动、追踪与碰撞。递归飞刃和指针追踪共用一套逻辑，
## 只在命中时用 kind 分叉 —— 它们 90% 的行为（飞、找目标、结算伤害）是一样的。
##
## 倒序遍历 + swap_remove：新生成的投射物（递归分裂）追加在数组末尾，
## 索引一定大于当前 i，本轮循环不会再碰到它，天然安全。
##

const HOMING_TURN := 6.0        # 追踪弹每秒朝目标偏转的比例
const BLADE_SEEK_R := 180.0     # 飞刃弹射时寻找下一个目标的范围
const PROJ_FLASH := 0.10


func update(dt: float, sim) -> void:
	var p: ProjectilePool = sim.projectiles
	var e: EnemyPool = sim.enemies
	var g: SpatialGrid = sim.grid

	var i := p.count - 1
	while i >= 0:
		if p.cd[i] > 0.0:
			p.cd[i] -= dt

		if p.kind[i] == ProjectilePool.KIND_POINTER:
			_homing(i, sim, p, e, g, dt)

		p.px[i] += p.vx[i] * dt
		p.py[i] += p.vy[i] * dt
		p.life[i] -= dt
		p.ang[i] = atan2(p.vy[i], p.vx[i])

		var done := false
		if p.cd[i] <= 0.0:
			done = _collide(i, sim, p, e, g)

		if done or p.life[i] <= 0.0:
			p.remove_at(i)
		i -= 1


func _homing(i: int, sim, p: ProjectilePool, e: EnemyPool, g: SpatialGrid, dt: float) -> void:
	var tj := Targeting.nearest(sim, g, e, p.px[i], p.py[i], p.seek[i])
	if tj < 0:
		return

	var dx := e.px[tj] - p.px[i]
	var dy := e.py[tj] - p.py[i]
	var d2 := dx * dx + dy * dy
	if d2 < 1.0:
		return

	var d := sqrt(d2)
	var spd := sqrt(p.vx[i] * p.vx[i] + p.vy[i] * p.vy[i])
	var want_x := (dx / d) * spd
	var want_y := (dy / d) * spd

	var k := clampf(HOMING_TURN * dt, 0.0, 1.0)
	p.vx[i] = lerpf(p.vx[i], want_x, k)
	p.vy[i] = lerpf(p.vy[i], want_y, k)

	# 插值会改变速度大小，重新归一到原速，否则追踪弹越转越慢
	var nl := sqrt(p.vx[i] * p.vx[i] + p.vy[i] * p.vy[i])
	if nl > 0.001:
		p.vx[i] = (p.vx[i] / nl) * spd
		p.vy[i] = (p.vy[i] / nl) * spd


func _collide(i: int, sim, p: ProjectilePool, e: EnemyPool, g: SpatialGrid) -> bool:
	var x: float = p.px[i]
	var y: float = p.py[i]
	var r: float = p.radius[i]
	var r2 := r * r

	var n := g.query(x, y, r)
	var k := 0
	while k < n:
		var j := g.out[k]
		k += 1
		var dx := e.px[j] - x
		var dy := e.py[j] - y
		if dx * dx + dy * dy > r2:
			continue

		e.hp[j] -= p.dmg[i] * e.dmg_mult(j)
		e.flash[j] = PROJ_FLASH
		if p.mark[i] == 1:
			e.mark[j] = GameConfig.MARK_DURATION

		if p.kind[i] == ProjectilePool.KIND_BLADE:
			_bounce(i, sim, p, e, g, j)
			return true

		# 指针追踪：满级可穿透 1 个目标，但要留命中冷却，
		# 否则同一敌人会在连续帧里被同一发子弹反复结算
		#
		# 引用计数（指针进化）：命中后分裂成两发，各自继续追下一个目标。
		# 分裂出来的两发 split=0，所以只会裂一次 —— 允许再裂就是 2^n，
		# 一发弹能把屏幕清空，那是失控不是进化。
		if p.kind[i] == ProjectilePool.KIND_POINTER and p.bounces[i] > 0:
			_split_pointer(i, sim, p, e, g, j)
			return true

		if p.pierce[i] > 0:
			p.pierce[i] -= 1
			p.cd[i] = GameConfig.PROJ_HIT_CD
			return false
		return true

	return false


## 引用计数（指针进化）：一发变两发，朝左右各偏 25° 飞出去，
## 之后由 _homing 各自重新锁定目标 —— 所以它们会奔向不同的敌人。
func _split_pointer(i: int, sim, p: ProjectilePool, e: EnemyPool,
		g: SpatialGrid, hit_j: int) -> void:
	var spd := sqrt(p.vx[i] * p.vx[i] + p.vy[i] * p.vy[i])
	var base_a := atan2(p.vy[i], p.vx[i])
	var dmg := p.dmg[i] * 0.6

	for k in 2:
		var a := base_a + (-1.0 if k == 0 else 1.0) * 0.44
		p.spawn_pointer(
			p.px[i], p.py[i],
			cos(a) * spd, sin(a) * spd,
			dmg, p.seek[i], 0, p.mark[i] == 1, 0
		)


## 递归：命中后分裂出一个更弱的自己，朝下一个最近目标飞去。
## 伤害按 decay 衰减、速度按 spd_bonus 递增 —— 每一次弹射都是一次"自我调用"。
func _bounce(i: int, sim, p: ProjectilePool, e: EnemyPool, g: SpatialGrid, hit_j: int) -> void:
	if p.bounces[i] <= 0:
		return

	var nj := Targeting.nearest(sim, g, e, p.px[i], p.py[i], BLADE_SEEK_R, hit_j)
	if nj < 0:
		return

	var dx := e.px[nj] - p.px[i]
	var dy := e.py[nj] - p.py[i]
	var d2 := dx * dx + dy * dy
	if d2 < 1.0:
		return

	var d := sqrt(d2)
	var spd := sqrt(p.vx[i] * p.vx[i] + p.vy[i] * p.vy[i]) * (1.0 + p.spd_bonus[i])

	p.spawn_blade(
		p.px[i], p.py[i],
		(dx / d) * spd, (dy / d) * spd,
		p.dmg[i] * p.decay[i],
		p.bounces[i] - 1,
		p.decay[i],
		p.spd_bonus[i]
	)
