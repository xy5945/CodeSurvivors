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


func clear() -> void:
	waves.clear()
	bolts.clear()


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
	})


func update(dt: float, sim) -> void:
	_update_waves(dt, sim)
	_update_bolts(dt, sim)


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
		e.hp[j] -= dmg * (1.0 + GameConfig.MARK_BONUS if e.mark[j] > 0.0 else 1.0)
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


## 落雷：落地瞬间结算一次范围伤害，同时留下视觉与（满级时）持续伤害。
## hit_cap = 单道落雷的命中上限（和广播同理：不能让伤害随敌群密度无限涨）。
func strike(sim, x: float, y: float, r: float, dmg: float, dot_dps: float,
		hit_cap: int = 0) -> void:
	_damage_ring(sim, x, y, 0.0, r, dmg, hit_cap if hit_cap > 0 else -1)
	add_bolt(x, y, r, dmg, 0.5 if dot_dps > 0.0 else GameConfig.BOLT_LIFE, dot_dps, hit_cap)
