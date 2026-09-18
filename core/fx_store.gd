class_name FxStore
extends RefCounted
##
## 范围特效：广播冲击波的扩散环 + 随机数审判的落雷。
##
## 数量很小（同时最多几个波、十来道雷），所以用 Array of Dictionary 而不是
## 扁平数组 —— 可读性比极致性能重要，而且这里的开销本来就可以忽略。
##
## 波的命中判定用"环带"而不是"精确半径"，这是它最省的地方：
## 每帧只判断 距离 ∈ [上一帧半径, 这一帧半径] 的敌人，
## 天然保证每个敌人每次广播只挨一次，不需要维护"已命中集合"。
## （敌人索引因 swap_remove 不稳定，用索引集合是错的，这一点很关键。）
##

var waves := []     # {x,y,r,prev,max,spd,dmg,back,phase,bonus}
var bolts := []     # {x,y,r,dmg,life,dps}
# 一次性脉冲：纯视觉的扩散环 + 常驻光环，都由 AuraRenderer 画。
#
# 它们没有伤害逻辑（伤害在生成它们的武器里就结算完了），存在的意义是
# 让玩家"看见"刚才发生了一次范围事件 —— 后 6 把武器里有 4 把是范围型，
# 没有视觉反馈的话玩家根本不知道武器有没有在工作。
# kind 决定颜色：0=回收(青绿) 1=冻结(冰蓝) 2=重编译(橙) 3=溢出(品红)
var pulses := []    # {x,y,r0,r1,life,life0,kind,follow}


func clear() -> void:
	waves.clear()
	bolts.clear()
	pulses.clear()


func add_wave(x: float, y: float, max_r: float, spd: float, dmg: float,
		can_back: bool, back_bonus: float, hit_cap: int = 0) -> void:
	waves.append({
		"x": x, "y": y, "r": 0.0, "prev": 0.0,
		"max": max_r, "spd": spd, "dmg": dmg,
		"back": can_back, "phase": 0, "bonus": back_bonus,
		"cap": hit_cap, "hits": 0,
	})


func add_bolt(x: float, y: float, r: float, dmg: float, life: float, dps: float,
		hit_cap: int = 0) -> void:
	bolts.append({
		"x": x, "y": y, "r": r, "dmg": dmg, "life": life, "dps": dps,
		"cap": hit_cap,
		"life0": life,   # 初始寿命，表现层按 life/life0 换算动画进度
	})


func update(dt: float, sim) -> void:
	_update_waves(dt, sim)
	_update_bolts(dt, sim)
	_update_pulses(dt, sim)


## follow=true 时环跟着玩家走（光环类武器的表现），否则固定在生成点。
func add_pulse(x: float, y: float, r0: float, r1: float, life: float,
		kind: int, follow: bool = false) -> void:
	pulses.append({
		"x": x, "y": y, "r0": r0, "r1": r1,
		"life": life, "life0": life, "kind": kind, "follow": follow,
	})


func _update_pulses(dt: float, sim) -> void:
	var i := pulses.size() - 1
	while i >= 0:
		var p: Dictionary = pulses[i]
		var life: float = float(p["life"]) - dt
		if life <= 0.0:
			pulses.remove_at(i)
		else:
			p["life"] = life
			if bool(p["follow"]):
				p["x"] = sim.player_x
				p["y"] = sim.player_y
		i -= 1


func _update_waves(dt: float, sim) -> void:
	var i := waves.size() - 1
	while i >= 0:
		var w: Dictionary = waves[i]
		w["prev"] = w["r"]

		if int(w["phase"]) == 0:
			w["r"] = float(w["r"]) + float(w["spd"]) * dt
			if float(w["r"]) >= float(w["max"]):
				w["r"] = w["max"]
				if bool(w["back"]):
					w["phase"] = 1          # 回卷：广播并等待
				else:
					waves.remove_at(i)
					i -= 1
					continue
		else:
			# 回卷比扩散快一点，视觉上像"消息被收回"
			w["r"] = float(w["r"]) - float(w["spd"]) * 1.4 * dt
			if float(w["r"]) <= 0.0:
				waves.remove_at(i)
				i -= 1
				continue

		var lo := minf(float(w["prev"]), float(w["r"])) - GameConfig.WAVE_BAND
		var hi := maxf(float(w["prev"]), float(w["r"])) + GameConfig.WAVE_BAND
		var dmg: float = float(w["dmg"]) * (float(w["bonus"]) if int(w["phase"]) == 1 else 1.0)

		# 每波命中上限：整波（扩散 + 回卷）共享一个额度。
		#
		# 没有这个上限时，敌人越密、一波扫到的人越多，总伤害随密度线性上涨 ——
		# 于是"往场上堆怪"反而让玩家更安全（实测站桩 8 分钟一滴血不掉）。
		# 封顶之后，AoE 的价值变成"稳定清掉身周一批"，而不是"人越多我越强"，
		# 多出来的敌人就会真的围上来。这是"必须保持移动"能成立的前提。
		var cap: int = int(w["cap"])
		if cap > 0:
			var left: int = cap - int(w["hits"])
			if left <= 0:
				i -= 1
				continue
			w["hits"] = int(w["hits"]) + _damage_ring(sim, float(w["x"]), float(w["y"]), lo, hi, dmg, left)
		else:
			_damage_ring(sim, float(w["x"]), float(w["y"]), lo, hi, dmg)
		i -= 1


## limit >= 0 时最多命中 limit 个，返回实际命中数（供调用方累计额度）。
## limit < 0 = 不限。
func _damage_ring(sim, cx: float, cy: float, lo: float, hi: float, dmg: float,
		limit: int = -1) -> int:
	var e: EnemyPool = sim.enemies
	var lo2 := lo * lo
	var hi2 := hi * hi
	var hits := 0

	var n: int = sim.grid.query(cx, cy, hi)
	var k := 0
	while k < n:
		if limit >= 0 and hits >= limit:
			break
		var j: int = sim.grid.out[k]
		k += 1
		var dx := e.px[j] - cx
		var dy := e.py[j] - cy
		var d2 := dx * dx + dy * dy
		if d2 < lo2 or d2 > hi2:
			continue
		e.hp[j] -= dmg * e.dmg_mult(j)
		e.flash[j] = GameConfig.WAVE_FLASH
		hits += 1
	return hits


func _update_bolts(dt: float, sim) -> void:
	var i := bolts.size() - 1
	while i >= 0:
		var b: Dictionary = bolts[i]
		var life: float = float(b["life"]) - dt

		if float(b["dps"]) > 0.0:
			# 电痕（随机数审判 L8）：落地后持续一小段时间的范围伤害。
			# 它每帧都结算一次，所以同样要卡命中上限 —— 否则它变成
			# "范围里有多少人打多少人、还每帧都打"的无限 AoE，
			# 把刚加的上限从后门绕过去了。
			_damage_ring(sim, float(b["x"]), float(b["y"]), 0.0, float(b["r"]),
				float(b["dps"]) * dt, int(b["cap"]) if int(b["cap"]) > 0 else -1)

		if life <= 0.0:
			bolts.remove_at(i)
		else:
			b["life"] = life
		i -= 1


## 全量重编译：一次性全范围爆发。
##
## 不用 wave（扩散环）来打伤害：波的伤害是分帧按环带结算的，等它扫到边缘时
## 玩家早就不知道"这一发打死了几个" —— 而"每次击杀减少冷却"需要**立刻**
## 拿到击杀数。所以伤害一次性结算完，环只负责好看。
## 返回本次造成的击杀数（由调用方换算成冷却缩减）。
func blast(sim, x: float, y: float, r: float, dmg: float, hit_cap: int,
		pulse_kind: int, pulse_life: float) -> int:
	# 死的判定在 sim._reap（本帧稍后），所以这里数"血量已 <=0 但还没被回收"的
	# 敌人数，前后各数一次取差。用 sim.kills 是错的 —— 那是整局累计击杀，
	# 和本次爆炸的战果不是一回事，两者相减会得到一个离谱的负数或大数。
	var before := _dying_count(sim)
	_damage_ring(sim, x, y, 0.0, r, dmg, hit_cap if hit_cap > 0 else -1)
	add_pulse(x, y, r * 0.25, r, pulse_life, pulse_kind, false)
	return maxi(0, _dying_count(sim) - before)


## 场上已濒死（hp<=0、等待 _reap 回收）的敌人数。
## 只统计濒死差值，别的武器打死的敌人就不会算进重编译的战果里。
func _dying_count(sim) -> int:
	var e: EnemyPool = sim.enemies
	var k := 0
	for i in e.count:
		if e.hp[i] <= 0.0:
			k += 1
	return k


## 落雷：落地瞬间结算一次范围伤害，同时留下视觉与（满级时）持续伤害。
## hit_cap = 单道落雷的命中上限（和广播同理：不能让伤害随敌群密度无限涨）。
func strike(sim, x: float, y: float, r: float, dmg: float, dot_dps: float,
		hit_cap: int = 0) -> void:
	_damage_ring(sim, x, y, 0.0, r, dmg, hit_cap if hit_cap > 0 else -1)
	add_bolt(x, y, r, dmg, 0.5 if dot_dps > 0.0 else GameConfig.BOLT_LIFE, dot_dps, hit_cap)
