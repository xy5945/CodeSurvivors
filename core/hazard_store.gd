class_name HazardStore
extends RefCounted
##
## 危险区：地面上的预警圈 → 延迟爆炸（Boss"编译锁定"、将来可给别的技能用）。
##
## 为什么要有这个：冲刺是"瞬间的位移威胁"，弹幕是"持续的空间威胁"，
## 两者都靠玩家"看到就躲"。危险区是第三种——**预告式**威胁：
## 地上先亮起来一个圈，1 秒多以后才炸。它考验的是"现在就得离开这里"，
## 而不是"反应快"。Boss 战里它和弹幕叠在一起，才逼得出真正的走位路线选择。
##
## 数据量极小（同屏 ≤ 12 个），用 Dictionary 数组而不是扁平池：
## 可读性优先，这里的开销可以忽略。
##

var hazards := []   # {x,y,r,t,warn,dmg,fired}


func clear() -> void:
	hazards.clear()


## warn = 预警时长（秒）。圈亮起来 warn 秒后爆炸。
func add(x: float, y: float, r: float, warn: float, dmg: float) -> void:
	if hazards.size() >= 24:      # 极端情况兜底，防止长局泄积
		return
	hazards.append({"x": x, "y": y, "r": r, "t": warn, "warn": warn,
		"dmg": dmg, "fired": false})


func update(dt: float, sim) -> void:
	var i := hazards.size() - 1
	while i >= 0:
		var h: Dictionary = hazards[i]
		# 预警圈跟着玩家走？不 —— 锁定就是锁定，圈钉在原地，玩家自己跑出去。
		h["t"] = float(h["t"]) - dt
		if float(h["t"]) <= 0.0:
			_detonate(sim, h)
			hazards.remove_at(i)
		i -= 1


func _detonate(sim, h: Dictionary) -> void:
	var hx := float(h["x"])
	var hy := float(h["y"])
	var hr := float(h["r"])

	# 视觉：直接复用落雷的 16 帧爆炸动画（assets/fx/bolt/）。
	# 编译锁定的爆点就是"被雷劈中"，语义和美术资源都刚好对得上。
	# dmg 传 0 / dps 传 0 = 纯视觉，不会误伤敌人（它是 Boss 的技能）。
	sim.fx.add_bolt(hx, hy, hr, 0.0, GameConfig.BOLT_LIFE, 0.0)

	if sim.dead or sim.god_mode:
		return
	if sim.iframe > 0.0:
		return
	var dx: float = sim.player_x - hx
	var dy: float = sim.player_y - hy
	# 判定半径 + 玩家半径：擦着边站也该算被炸到（视觉上那个圈是"危险范围"）
	var rr := hr + GameConfig.PLAYER_RADIUS
	if dx * dx + dy * dy > rr * rr:
		return
	sim.hurt_player(float(h["dmg"]))
