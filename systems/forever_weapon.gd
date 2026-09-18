class_name ForeverWeapon
extends RefCounted
##
## 永真力场 `forever_loop`：while(true) —— 一直烧，一直掉血，直到没电。
##
## 全场唯一会伤害玩家的武器。它的代价必须看得见但**不吵闹**：
## 自伤走 sim.self_damage（不置无敌帧、不触发受击红光与音效），
## 否则每秒让屏幕红一次，没人敢拿这把武器。
##
## 安全阀：血量低于 30% 自动停机，回升到 42% 才重新启动。
## 两个阈值不一样是为了防抖 —— 单阈值会在 30% 附近疯狂开关，
## 表现是光环闪烁 + 血量锯齿，玩家根本搞不清它在干嘛。
##
## 设计意图（来自武器文档）：它是"用血量换输出"的极端选项。
## 和"异常捕获"类免疫效果配合会质变，那是有意留的隐藏组合。
##

const SHUTOFF_HP_FRAC := 0.30
const RESTART_HP_FRAC := 0.42
const TICK_FLASH := 0.08

var enabled := false
var dps := 0.0
var radius := 0.0
var self_dps := 0.0
var hit_cap := 0

var running := false      # 安全阀状态（渲染层要读它，停机时画暗环）
var drained_total := 0.0  # 本局自损总量（测试用）


func apply_stats(level: int, lo: Loadout) -> void:
	var s := UpgradeDefs.stats_for("forever", level)
	dps = float(s["dps"]) * lo.damage_mult
	radius = float(s["radius"])
	self_dps = float(s["self_dps"])
	hit_cap = int(s["hit_cap"])
	enabled = true


func update(dt: float, sim) -> void:
	if not enabled or sim.dead:
		return

	var frac: float = sim.player_hp / maxf(sim.max_hp, 1.0)
	if running:
		if frac <= SHUTOFF_HP_FRAC:
			running = false
	else:
		if frac >= RESTART_HP_FRAC:
			running = true
	if not running:
		return

	sim.self_damage(self_dps * dt)
	drained_total += self_dps * dt

	var e: EnemyPool = sim.enemies
	var cx: float = sim.player_x
	var cy: float = sim.player_y
	var r2 := radius * radius
	var dmg: float = dps * dt

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
		e.hp[j] -= dmg * e.dmg_mult(j)
		e.flash[j] = TICK_FLASH
		hits += 1
