class_name WeaponTest
extends RefCounted
##
## 单武器满级输出对比。
## 运行：godot --headless --path . -- --wpntest
##
## 存在的理由：武器一多，最容易出的 Bug 是"某把武器看起来在动，其实一次都没打中"。
## 这种 Bug 在混战里根本看不出来，只有单拎出来跑才知道。
##
## 测法：每把武器单独满级，场上恒定维持 200 个敌人（打掉就补），跑 10 秒数击杀。
##
## 敌人血量刻意设成"所有武器满级单发都能一击必杀"（最低的是循环护盾 26）：
## 这样击杀数 ≈ 命中次数，不会被"差一点没打死"的阈值效应污染 ——
## 用 60 血测的时候，飞刃 55 伤害几乎打不出击杀，看起来像坏了，其实是测法问题。
## 它衡量的是命中能力，不等于真实 DPS（真实敌人血厚得多，且有血量成长）。
##

const SECONDS := 10.0
const KEEP_ENEMIES := 200
const ENEMY_HP := 20.0      # 低于所有武器满级单发伤害 → 击杀数 ≈ 命中次数


static func run() -> void:
	print("")
	print("=== 单武器满级输出测试 ===")
	print("每把武器单独满级 · 场上恒定 %d 敌人 · 敌人血量 %.0f（一击必杀）· 跑 %.0f 秒" % [
		KEEP_ENEMIES, ENEMY_HP, SECONDS
	])
	print("击杀数 ≈ 命中次数，衡量的是命中能力，不是真实 DPS")
	print("")

	for u in UpgradeDefs.UPGRADES:
		if int(u["kind"]) != UpgradeDefs.KIND_WEAPON:
			continue
		_measure(u)

	print("")


static func _measure(u: Dictionary) -> void:
	var sim := Sim.new()
	sim.setup()
	sim.enemies.clear()
	sim.gems.clear()
	sim.god_mode = true
	sim.spawn_enabled = false

	# 换一个干净的 Loadout：只装这一把武器，避免起始武器污染数据
	sim.loadout = Loadout.new()
	sim.loadout.levels[str(u["id"])] = int(u["max"])
	sim.loadout.recompute()

	var steps := int(SECONDS * 60.0)
	var s := 0
	while s < steps:
		_refill(sim)
		var a := float(s) * 0.06
		sim.step(GameConfig.FIXED_DT, cos(a), sin(a))
		s += 1

	var kps := float(sim.kills) / SECONDS
	print("  %-8s %-10s 满级 Lv%d  击杀 %5d  约 %5.1f 杀/秒" % [
		u["icon"], u["name"], int(u["max"]), sim.kills, kps
	])


static func _refill(sim) -> void:
	while sim.enemies.count < KEEP_ENEMIES:
		var ang := randf() * TAU
		var dist := 60.0 + randf() * 160.0
		sim.enemies.spawn(
			sim.player_x + cos(ang) * dist,
			sim.player_y + sin(ang) * dist,
			ENEMY_HP,
			GameConfig.ENEMY_SPEED,
			GameConfig.ENEMY_RADIUS
		)


## ------------------------------------------------------------------
## 单体 DPS：贴脸一只超高血量靶子，跑 10 秒看各武器真实输出。
##
## 为什么还要这一项：wpntest 是 200 只 20 血小怪，天然偏袒 AoE
## （一发打中 50 只 = 50 杀）。但精英 150 血、Boss 18000 血，
## 这时候"能打中几只"不重要，"每秒掉多少血"才重要。
## 两个场景分开测，才知道单体武器到底是不是废的。
##
## 运行：godot --headless --path . -- --dpstest
## ------------------------------------------------------------------
const SINGLE_HP := 1000000.0     # 靶子血量高到打不死，纯测输出
const SINGLE_DIST := 96.0        # 护盾满级环绕半径（放在圈内打不到，必须贴着环）
const SINGLE_SECONDS := 10.0


static func run_single() -> void:
	print("")
	print("=== 单体 DPS 测试（对精英 / Boss 的真实价值）===")
	print("每把武器单独满级 · 贴脸 %.0fpx 一只 %.0f 血靶子 · 跑 %.0f 秒" % [
		SINGLE_DIST, SINGLE_HP, SINGLE_SECONDS
	])
	print("")
	var rows := []
	for u in UpgradeDefs.UPGRADES:
		if int(u["kind"]) != UpgradeDefs.KIND_WEAPON:
			continue
		rows.append(_measure_single(u))
	rows.sort_custom(func(a, b): return a[2] > b[2])
	var top: float = rows[0][2]
	for r in rows:
		var bar: String = ""
		var n: int = int(round(r[2] / top * 30.0)) if top > 0.0 else 0
		for _i in n:
			bar += "#"
		print("  %-8s %-10s  DPS %7.1f  %s" % [r[0], r[1], r[2], bar])
	print("")
	print("  最强/最弱 = %.1f 倍" % (top / maxf(rows[rows.size() - 1][2], 0.01)))

	# 满级全家桶 TTK：验证 Boss 18000 血是否合理
	var sim := Sim.new()
	sim.setup()
	sim.enemies.clear()
	sim.gems.clear()
	sim.god_mode = true
	sim.spawn_enabled = false
	sim.loadout = Loadout.new()
	for u in UpgradeDefs.UPGRADES:
		if int(u["kind"]) == UpgradeDefs.KIND_WEAPON:
			sim.loadout.levels[str(u["id"])] = int(u["max"])
	sim.loadout.recompute()
	_spawn_dummy(sim, 18000.0)
	var d0: float = sim.enemies.hp[0]
	var steps := int(SINGLE_SECONDS * 60.0)
	for _i in steps:
		if sim.enemies.count == 0:
			break
		_pinning(sim)
		sim.step(GameConfig.FIXED_DT, 0.0, 0.0)
	if sim.enemies.count > 0:
		var dealt: float = d0 - sim.enemies.hp[0]
		var dps: float = dealt / SINGLE_SECONDS
		print("")
		print("  六武器全满级合计 DPS %.0f → 击杀 Boss(18000) 需 %.1f 秒" % [
			dps, 18000.0 / maxf(dps, 0.01)
		])
	else:
		print("")
		print("  六武器全满级：10 秒内就把 18000 血打光了（Boss 偏软）")


## 靶子会被各种位移效果推走，每帧钉回原位
static func _pinning(sim) -> void:
	if sim.enemies.count == 0:
		return
	sim.enemies.px[0] = sim.player_x + SINGLE_DIST
	sim.enemies.py[0] = sim.player_y


static func _spawn_dummy(sim, hp: float) -> void:
	sim.enemies.spawn(sim.player_x + SINGLE_DIST, sim.player_y, hp, 0.0, 14.0, 0)


static func _measure_single(u: Dictionary) -> Array:
	var sim := Sim.new()
	sim.setup()
	sim.enemies.clear()
	sim.gems.clear()
	sim.god_mode = true
	sim.spawn_enabled = false
	sim.loadout = Loadout.new()
	sim.loadout.levels[str(u["id"])] = int(u["max"])
	sim.loadout.recompute()

	_spawn_dummy(sim, SINGLE_HP)
	var h0: float = sim.enemies.hp[0]
	var steps := int(SINGLE_SECONDS * 60.0)
	for _i in steps:
		if sim.enemies.count == 0:
			break
		_pinning(sim)
		sim.step(GameConfig.FIXED_DT, 0.0, 0.0)
	var dealt: float = h0 - (sim.enemies.hp[0] if sim.enemies.count > 0 else 0.0)
	return [str(u["icon"]), str(u["name"]), dealt / SINGLE_SECONDS]
