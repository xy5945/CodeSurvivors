class_name EnemyAttackSystem
extends RefCounted
##
## 敌方攻击：把"精英/Boss 的技能"翻译成场上的威胁。
##
## 三类威胁，各有各的逼走位方式（机制问题用玩法解决）：
##   环形弹幕 nova   —— 从自身向四周炸开。站在它旁边就是送命，必须先拉开距离。
##   扇形弹幕 aimed —— 朝玩家当前位置打一束。原地不动必吃，得**横向**移动。
##   危险区 hazard  —— 地上先亮圈、延迟爆炸。它封的是**空间**：逼玩家离开当前位置，
##                     而不能只是"躲一下再回来"。
##
## 单独成一个 system 而不是塞进 Sim：
##   Sim 已经有 500 行，而这三件事（发射/移动/结算）互相关联且和玩家受伤耦合，
##   独立出来以后加新技能不用再动 Sim 的状态机。
##

## 环形弹幕。ang0 给一个初始角偏移，避免每次都是"十字对正"的同一个图案。
static func nova(sim, x: float, y: float, n: int, spd: float, dmg: float,
		rad: float, life: float = 3.4, ang0: float = 0.0) -> void:
	var b: EnemyBulletPool = sim.bullets
	for k in n:
		var ang := ang0 + TAU * float(k) / float(n)
		b.spawn(x, y, cos(ang), sin(ang), spd, dmg, rad, life, EnemyBulletPool.KIND_SHARD)


## 扇形弹幕：朝 (dir_x, dir_y) 打一束 n 发，总张角 spread（弧度）。
## 慢速 + 大张角 = 覆盖一片而不是一条线，玩家不能靠"往旁边挪一点"混过去。
static func aimed(sim, x: float, y: float, dir_x: float, dir_y: float, n: int,
		spread: float, spd: float, dmg: float, rad: float,
		life: float = 3.4) -> void:
	var base := atan2(dir_y, dir_x)
	var b: EnemyBulletPool = sim.bullets
	for k in n:
		var off := 0.0 if n <= 1 else (float(k) / float(n - 1) - 0.5) * spread
		var ang := base + off
		b.spawn(x, y, cos(ang), sin(ang), spd, dmg, rad, life, EnemyBulletPool.KIND_SHARD)


## 追踪弹：慢、会拐弯。直线躲开之后它还会咬上来 —— 逼玩家做"绕圈"而不是"后退"。
static func homing(sim, x: float, y: float, dir_x: float, dir_y: float,
		n: int, spd: float, dmg: float, rad: float, turn: float,
		life: float = 4.5) -> void:
	var base := atan2(dir_y, dir_x)
	var b: EnemyBulletPool = sim.bullets
	for k in n:
		var off := 0.0 if n <= 1 else (float(k) / float(n - 1) - 0.5) * 0.7
		var ang := base + off
		b.spawn(x, y, cos(ang), sin(ang), spd, dmg, rad, life,
			EnemyBulletPool.KIND_HOMING, turn)


## 在玩家周围撒 n 个危险区：至少有一个直接落在玩家脚下（必须马上离开），
## 其余散布在附近（封掉"往哪躲"的选项）。
##
## min_d 保证不会全部压在同一个点上 —— 一圈均匀铺开才叫封走位。
static func hazard_around_player(sim, n: int, r: float, warn: float, dmg: float,
		ring_min: float, ring_max: float) -> void:
	var hz: HazardStore = sim.hazards
	hz.add(sim.player_x + randf_range(-r * 0.3, r * 0.3),
		sim.player_y + randf_range(-r * 0.3, r * 0.3), r, warn, dmg)
	for k in n - 1:
		var ang := TAU * float(k) / float(maxi(1, n - 1)) + randf() * 0.6
		var d := randf_range(ring_min, ring_max)
		var hx := clampf(sim.player_x + cos(ang) * d, -GameConfig.ARENA_HALF, GameConfig.ARENA_HALF)
		var hy := clampf(sim.player_y + sin(ang) * d, -GameConfig.ARENA_HALF, GameConfig.ARENA_HALF)
		hz.add(hx, hy, r, warn, dmg)


## 每帧：弹幕移动/追踪/命中玩家，危险区计时/爆炸。
## 必须在 grid.rebuild 之后、_reap 之前调用（它不依赖网格，但受伤结算要早于死亡判定）。
func update(dt: float, sim) -> void:
	_update_bullets(dt, sim)
	sim.hazards.update(dt, sim)


func _update_bullets(dt: float, sim) -> void:
	var b: EnemyBulletPool = sim.bullets
	var lim := GameConfig.ARENA_HALF + 80.0
	var px: float = sim.player_x
	var py: float = sim.player_y
	var pr := GameConfig.PLAYER_RADIUS
	var can_hit: bool = sim.bullet_iframe <= 0.0 and not sim.dead and not sim.god_mode

	var i := b.count - 1
	while i >= 0:
		var life := b.life[i] - dt
		if life <= 0.0:
			b.kill(i)
			i -= 1
			continue
		b.life[i] = life
		b.spin[i] += dt * 4.0

		var x := b.px[i] + b.vx[i] * dt
		var y := b.py[i] + b.vy[i] * dt

		# 追踪：把速度方向朝玩家转过去，转速上限 homing（弧度/秒）。
		# 用"最多转多少度"而不是"直接指向玩家"—— 后者是无解的必中弹。
		var hm := b.homing[i]
		if hm > 0.0:
			var cur := atan2(b.vy[i], b.vx[i])
			var want := atan2(py - y, px - x)
			var diff := wrapf(want - cur, -PI, PI)
			var turn := clampf(diff, -hm * dt, hm * dt)
			var na := cur + turn
			var sp := sqrt(b.vx[i] * b.vx[i] + b.vy[i] * b.vy[i])
			b.vx[i] = cos(na) * sp
			b.vy[i] = sin(na) * sp
			x = b.px[i] + b.vx[i] * dt
			y = b.py[i] + b.vy[i] * dt

		b.px[i] = x
		b.py[i] = y

		# 出界剔除：飞出竞技场就没人能碰到它了，留着只是浪费每帧的遍历
		if absf(x) > lim or absf(y) > lim:
			b.kill(i)
			i -= 1
			continue

		if can_hit:
			var dx := x - px
			var dy := y - py
			var rr := b.r[i] + pr
			if dx * dx + dy * dy <= rr * rr:
				# 弹幕命中即消失：一颗弹只算一次。
				# 不这样的话"站在原地挨一梭子"和"挨一发"没有区别，
				# 弹幕就从"必须躲"退化成"站在里面看血条慢慢掉"。
				sim.hurt_player_bullet(b.dmg[i])
				can_hit = false
				b.kill(i)
				i -= 1
				continue

		i -= 1
