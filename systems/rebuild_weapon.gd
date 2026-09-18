class_name RebuildWeapon
extends RefCounted
##
## 全量重编译 `full_rebuild`：蓄力之后来一发覆盖半个屏幕的爆发。
##
## 蓄力是有意的代价：它让这把武器有"节奏" —— 玩家要提前判断
## "现在这一炸值不值"，而不是冷却一到就无脑放。
## 蓄力期间玩家仍可自由移动，爆炸落在放手那一刻的位置。
##
## 伤害一次性结算（fx.blast），不走扩散波：
## 波是分帧按环带扫的等它扫完，玩家早不知道这一发打死了几个 ——
## 而"每次击杀减少剩余冷却"必须当帧拿到战果。
##
## 滚雪球：每个击杀减少**剩余**冷却的 3%（连乘，不是加算）。
## 敌群越密，冷却缩得越狠，但永远缩不到 0 ——
## 用减法的话十几杀就能把冷却清零，那会变成永动机。
##

var enabled := false
var damage := 0.0
var cd_base := 0.0
var radius := 0.0
var charge_time := 0.0
var hit_cap := 0
var cd_kill := 0.0      # 每个击杀减少的剩余冷却比例（L8 才有）

var cooldown := 0.0
var charging := false
var charge_left := 0.0
var fired_total := 0    # 本局引爆次数
var kills_total := 0    # 本局由爆炸直接造成的击杀
var evolved := false    # 增量编译：一轮两炸
var _chained := false   # 本轮是否已经追加过第二发


func apply_stats(level: int, lo: Loadout) -> void:
	var s := UpgradeDefs.stats_for("rebuild", level)
	damage = float(s["dmg"]) * lo.damage_mult
	cd_base = float(s["cd"]) * lo.cooldown_mult
	radius = float(s["radius"])
	charge_time = float(s["charge"])
	hit_cap = int(s["hit_cap"])
	cd_kill = float(s["cd_kill"])
	enabled = true
	evolved = lo.is_evolved("rebuild")


func update(dt: float, sim) -> void:
	if not enabled:
		return

	if charging:
		charge_left -= dt
		if charge_left <= 0.0:
			_detonate(sim)
		return

	cooldown -= dt
	if cooldown > 0.0:
		return
	charging = true
	charge_left = charge_time


## 蓄力进度 0~1，渲染层画读秒环用。
func charge_ratio() -> float:
	if charge_time <= 0.0:
		return 0.0
	return clampf(1.0 - charge_left / charge_time, 0.0, 1.0)


func _detonate(sim) -> void:
	charging = false
	fired_total += 1

	var kills: int = sim.fx.blast(
		sim, sim.player_x, sim.player_y, radius, damage, hit_cap, 2, 0.5
	)
	kills_total += kills
	sim.sfx_events.append("bolt")

	# 增量编译（进化）：引爆后立刻追加一发，蓄力只要 60%。
	# 一轮两炸，但每轮仍然只走一次冷却 —— 它换来的是"节奏变快"，
	# 而不是"冷却砍半"。第二发打完后照样进冷却，所以不会滚成连发。
	if evolved and not _chained:
		_chained = true
		charging = true
		charge_left = charge_time * 0.6
		return

	_chained = false
	cooldown = cd_base
	if cd_kill > 0.0 and kills > 0:
		# 连乘：剩余冷却 × (1-3%)^击杀数。永远不会归零，
		# 但二十杀之后能砍掉将近一半，敌群越密越明显
		cooldown *= pow(1.0 - cd_kill, float(kills))
