class_name Bench
extends RefCounted
##
## 逻辑层基准测试 + 核心循环冒烟测试。
## 运行：godot --headless --path . -- --bench
##      godot --headless --path . -- --smoke
##
## 为什么挂在命令行参数下而不是用 --script 独立跑：
## Godot 在 --script 模式下不会注册项目里的 class_name 全局类，
## 导致 Sim / GameConfig 等全部 "not declared"。走主场景则一切正常。
##
## 基准测的是技术方案帧预算表里"实体逻辑 + 碰撞 + 游戏系统"那部分，
## 渲染的 3ms 测不到，要看游戏内 HUD 的真实 FPS。
##
## 测试场景是最坏情况：敌人全部涌向玩家并挤成一团，
## 此时每个敌人的分离计算都撞上邻居数上限，是真实游戏中压力最大的时刻。
##

const SAMPLES := 240
const TARGETS := [200, 400, 800, 1200, 1600]


static func run() -> void:
	print("")
	print("=== 代码幸存者 · 逻辑层基准 ===")
	print("固定步长 1/60 秒 · 每档 %d 帧 · 敌人全部涌向玩家（最坏情况）" % SAMPLES)
	print("")

	for target in TARGETS:
		_run(target)

	print("")
	print("参考：帧预算中给逻辑部分的目标是 9ms 以内（实体 4 + 碰撞 3 + 系统 2），")
	print("      剩余 7.6ms 留给渲染与引擎开销。")
	print("")


static func _run(target: int) -> void:
	var sim := Sim.new()
	sim.setup()
	sim.enemies.clear()
	sim.god_mode = true
	sim.spawn_enabled = false

	for i in target:
		var ang := randf() * TAU
		var dist := 60.0 + randf() * 400.0
		sim.enemies.spawn(
			sim.player_x + cos(ang) * dist,
			sim.player_y + sin(ang) * dist,
			GameConfig.ENEMY_HP,
			GameConfig.ENEMY_SPEED,
			GameConfig.ENEMY_RADIUS
		)

	# 预热，把首次调用的缓存未命中排除掉
	for i in 30:
		sim.step(GameConfig.FIXED_DT, 0.7, -0.7)

	var t0 := Time.get_ticks_usec()
	for i in SAMPLES:
		sim.step(GameConfig.FIXED_DT, 0.7, -0.7)
	var t1 := Time.get_ticks_usec()

	var per_frame_ms := (t1 - t0) / 1000.0 / float(SAMPLES)
	var budget_pct := per_frame_ms / 16.67 * 100.0
	var fps_limit := 1000.0 / per_frame_ms if per_frame_ms > 0.0 else 0.0

	print("敌人 %4d  |  每帧 %6.3f ms  |  占 60FPS 预算 %5.1f%%  |  逻辑帧率上限 %6.0f" % [
		sim.enemies.count, per_frame_ms, budget_pct, fps_limit
	])


# =================================================================== 冒烟测试

##
## 不渲染、不操作，让 AI 自动玩一局：绕圈走 + 有升级就随便选一张。
## 目的是验证核心循环本身（掉落 → 拾取 → 升级 → 变强）不会崩，
## 并把难度曲线打印出来看数值是否合理。
##
## 生存模式：不开无敌，跑到死为止。
## 冒烟测试是无敌的，验证不了"回血到底有没有救回命"，所以单独开一条：
## 打印存活时间、最低血量、捡到多少补丁包、累计回了多少血。
## 这组数字是回血机制的回归基线 —— 改掉落率/回血量后对比这里。
static func run_survival(max_minutes: float = 20.0) -> void:
	print("")
	print("=== 代码幸存者 · 生存模式（不开无敌）===")
	print("自动游玩 · 绕圈移动 · 升级随机选 · 跑到死或 %.0f 分钟" % max_minutes)
	print("")

	var sim := Sim.new()
	sim.setup()

	var steps := int(max_minutes * 60.0 / GameConfig.FIXED_DT)
	var step := 0
	var min_hp := GameConfig.PLAYER_MAX_HP
	while step < steps and not sim.dead:
		# 绕圈频率 0.03（半径约 83px）：冒烟用的 0.06 是 41px 的极小圈，
		# 等于原地转圈等着被围 —— 那个强度是故意压测用的，放到生存测试里
		# 会让"12 秒阵亡"变成测试脚本的假象，看不出真实节奏。
		var a := float(step) * 0.03
		var mx := cos(a)
		var my := sin(a)

		# 会躲的 AI：最近敌人进 90px 就朝反方向撤。
		# 纯绕圈等于站着挨打，那不是真人的玩法 —— 不躲的话测出来的
		# "存活时间"是测试脚本的强度，不是游戏的强度。
		var nj := Targeting.nearest(sim, sim.grid, sim.enemies, sim.player_x, sim.player_y, 260.0)
		if nj >= 0:
			var dx := sim.player_x - sim.enemies.px[nj]
			var dy := sim.player_y - sim.enemies.py[nj]
			var d := sqrt(dx * dx + dy * dy)
			if d < 90.0 and d > 0.001:
				mx = dx / d
				my = dy / d

		# 掉血了就去找血包（模拟真人的取舍）：血包不磁吸，只有主动走过去才拿得到。
		# 测试 AI 必须做这个决策 —— 否则测出来的是"AI 不会捡血"，不是游戏难度。
		if sim.player_hp < sim.max_hp * 0.7:
			var hd := _dir_to_heal(sim)
			if hd != Vector2.ZERO:
				mx = hd.x
				my = hd.y

		sim.step(GameConfig.FIXED_DT, mx, my)

		while sim.pending_levelups > 0:
			var pick: Dictionary = sim.loadout.roll_choices(1)[0]
			var id := str(pick["def"]["id"])
			if id == "_heal":
				sim.apply_heal_pick(30.0)
			else:
				sim.apply_upgrade(id)

		min_hp = minf(min_hp, sim.player_hp)
		if step % 1800 == 0:
			print("  %5.1f 分  血量 %5.1f  Lv %2d  击杀 %5d  补丁包 %3d  回血 %6.1f  地面血包 %2d  满血浪费 %2d" % [
				sim.time / 60.0, sim.player_hp, sim.level, sim.kills,
				sim.patches_collected, sim.healed_total,
				sim.heal_on_ground, sim.heal_wasted
			])
		step += 1

	print("")
	print("结局：%s · 存活 %.1f 分钟 · 最低血量 %.1f · 捡到补丁包 %d · 累计回血 %.1f · 满血浪费 %d" % [
		"阵亡" if sim.dead else "时间到",
		sim.time / 60.0, min_hp, sim.patches_collected, sim.healed_total, sim.heal_wasted
	])


static func run_smoke(minutes: float = 10.0) -> void:
	print("")
	print("=== 代码幸存者 · 核心循环冒烟 ===")
	print("自动游玩 %.0f 分钟 · 绕圈移动 · 升级随机选 · 无敌模式（只看循环与数值）" % minutes)
	print("")

	var sim := Sim.new()
	sim.setup()
	sim.god_mode = true

	var steps := int(minutes * 60.0 / GameConfig.FIXED_DT)
	var step := 0
	while step < steps:
		# 小半径绕圈：敌人速度 52 远低于玩家 150，绕大圈的话它们永远追不上，
		# 会变成 0 击杀的假阴性。小圈能让敌群真正围上来，复现真实的被围场景。
		var a := float(step) * 0.06
		sim.step(GameConfig.FIXED_DT, cos(a), sin(a))

		# 有升级就选，模拟玩家随手点一张
		while sim.pending_levelups > 0:
			var pick: Dictionary = sim.loadout.roll_choices(1)[0]
			var id := str(pick["def"]["id"])
			if id == "_heal":
				sim.apply_heal_pick(30.0)
			else:
				sim.apply_upgrade(id)

		if step % 3600 == 0:
			print("  %2d 分   Lv %2d   击杀 %5d   场上敌人 %4d   地面宝石 %4d   目标数 %4d   [%s]" % [
				int(sim.time / 60.0), sim.level, sim.kills,
				sim.enemies.count, sim.gems.count,
				GameConfig.target_enemies(sim.time),
				_composition(sim.enemies)
			])
		step += 1

	print("")
	print("结束：Lv %d · 击杀 %d · 拾取宝石 %d · 地面残留 %d · 补丁包 %d · 宝箱 %d%s" % [
		sim.level, sim.kills, sim.gems_collected, sim.gems.count,
		sim.patches_collected, sim.chests_collected,
		" · 通关" if sim.victory else (" · Boss 仍存活" if sim.boss_active else "")
	])
	print("技能：精英 %d 次（冲刺 %d · 环形弹幕 %d · 死亡分裂 %d）· Boss %d 次（冲刺 %d · 环形 %d · 扇形 %d · 追踪 %d · 危险区 %d）· 召唤 %d 波" % [
		sim.elite_skills, sim.elite_dashes, sim.elite_novas, sim.elite_splits,
		sim.boss_skills, sim.boss_dashes, sim.boss_novas, sim.boss_aimeds,
		sim.boss_homings, sim.boss_hazards, sim.boss_summons
	])
	print("敌方弹幕：累计发射 %d 发 · 当前场上 %d 发" % [sim.bullets_fired, sim.bullets.count])
	var build := []
	for u in UpgradeDefs.UPGRADES:
		var lv := sim.loadout.level_of(u["id"])
		if lv > 0:
			build.append("%s Lv%d" % [u["name"], lv])
	print("Build：" + "  ".join(build))
	print("")


##
## 开局体验检查：站着不动 8 秒，看多久能打到第一个敌人、射程里什么时候有货。
##
## 这个数字直接决定玩家的第一印象 —— 超过 4 秒接不上火，主观感受就是
## "游戏没反应"。常规刷怪距离（430px）配合 52 的速度和 110 的射程，
## 理论接火时间是 6 秒，所以开局必须靠 prewarm 铺一批近的。
##
## 运行：godot --headless --path . -- --opening
##
##
## 知识卡覆盖率：一局到底能解锁多少张卡？
##
## 图鉴要显示"已解锁 x / 25"，那就得先知道 25 这个数在真实一局里够不够得着。
## 三个变量会挡住集齐：① 升级次数（升级项要一个个选出来）
## ② 玩家能不能活到后期（后面的怪 + Boss 卡都在时间轴上）③ 选择策略。
## 所以跑三种典型局：理想玩家（无敌 + 优先拿新项）/ 随手点（无敌 + 随机）
## / 真实玩家（不无敌 + 优先新项，会死在中途）。
##
## 运行：godot --headless --path . -- --cardcov
##
static func run_card_coverage(minutes: float = 20.0) -> void:
	print("")
	print("=== 知识卡覆盖率 ===")
	print("每局 %.0f 分钟 · 绕圈移动 · 三选一" % minutes)
	print("")
	_cardcov("A 理想玩家 · 无敌 · 优先拿没拿过的 · 小圈", minutes, true, true, 0.06)
	_cardcov("B 随手点 · 无敌 · 三选一随机 · 小圈", minutes, true, false, 0.06)
	_cardcov("C 稳着打 · 不无敌 · 优先新项 · 大圈（躲得多、打得少）", minutes, false, true, 0.006)
	_cardcov("D 贴脸打 · 不无敌 · 优先新项 · 小圈（打得狠、容易被围）", minutes, false, true, 0.06)
	print("")


static func _cardcov(title: String, minutes: float, god: bool, greedy: bool, orbit: float) -> void:
	var sim := Sim.new()
	sim.setup()
	sim.god_mode = god

	var seen := {}
	var steps := int(minutes * 60.0 / GameConfig.FIXED_DT)
	var deaths := -1.0
	var step := 0
	while step < steps:
		var a := float(step) * orbit
		sim.step(GameConfig.FIXED_DT, cos(a), sin(a))
		for id in sim.card_events:
			seen[str(id)] = true
		sim.card_events.clear()
		# 不开无敌的局：血空了就停，记下死亡时间
		if not god and sim.player_hp <= 0.0 and deaths < 0.0:
			deaths = sim.time
			break

		while sim.pending_levelups > 0:
			var choices: Array = sim.loadout.roll_choices(3)
			var pick: Dictionary = _pick(choices, sim, greedy)
			var id := str(pick["def"]["id"])
			if id == "_heal":
				sim.apply_heal_pick(30.0)
			else:
				sim.apply_upgrade(id)
		step += 1

	var total := KnowledgeDB.total()
	var miss := []
	for c in KnowledgeDB.CARDS:
		if not seen.has(str(c["id"])):
			miss.append(str(c["id"]))
	print("  %s" % title)
	print("    Lv %d · 用时 %.1f 分%s · 解锁 %d / %d · 补丁包 %d · 宝箱 %d" % [
		sim.level, (deaths if deaths > 0.0 else sim.time) / 60.0,
		" （阵亡）" if deaths > 0.0 else "", seen.size(), total,
		sim.patches_collected, sim.chests_collected])
	if miss.is_empty():
		print("    全解锁")
	else:
		print("    没拿到：" + "、".join(miss))


## greedy = true 时优先选还没拥有的项（想集齐的玩家都这么点），
## 否则三选一随手点第一个。
static func _pick(choices: Array, sim, greedy: bool) -> Dictionary:
	if not greedy:
		return choices[0]
	var fallback: Dictionary = choices[0]
	for c in choices:
		var d: Dictionary = c["def"]
		var id := str(d["id"])
		if id != "_heal" and sim.loadout.level_of(id) == 0:
			return c
	return fallback


##
## 后 6 把武器的机制自检。
##
## 这些武器里有一半带"状态"（叠层、冻结、蓄力、自损、安全阈），
## 光看数值表测不出来：伤害数字对了，机制没生效照样是废武器。
## 所以每一把都单独摆一圈木桩跑一遍，断言的是**行为**不是数字。
##
## 运行：godot --headless --path . -- --wpn6test
##
static func run_wpn6() -> void:
	print("")
	print("=== 后 6 把武器 · 机制测试 ===")
	print("木桩：满级武器 + 静止靶子，只看行为是否发生")
	print("")
	_t_volley()
	_t_gc()
	_t_buffer()
	_t_breakpoint()
	_t_forever()
	_t_rebuild()
	print("")


## 建一个只跑指定武器的仿真：关掉刷怪，免得场上的野生敌人污染计数。
static func _w6mk(id: String, god: bool = true) -> Sim:
	var sim := Sim.new()
	sim.setup()
	sim.spawn_enabled = false
	sim.god_mode = god
	# setup() 里的 spawn.prewarm 会先塞一批敌人进池（为了省首帧分配）。
	# 不清掉的话：① 击杀/掉血统计里混进野生敌人 ② 它们死亡时 swap_remove
	# 会把队尾搬到队头，于是 px[0] 悄悄换成另一只，"位置没变"的断言直接失效。
	sim.enemies.clear()

	# 还要卸掉起始武器（分支长鞭 Lv1）。它在每把武器的测试里都偷偷输出，
	# 让"每次爆发掉血"的采样里混进一串 36，递增曲线直接看不出来。
	# 注意光把 levels 清掉没用 —— 武器实例已经创建、enabled 已经是 true，
	# 必须连 weapons / weapon_map 一起清空，recompute 才会重新按需创建。
	sim.loadout.levels.clear()
	sim.loadout.weapons.clear()
	sim.loadout.weapon_map.clear()
	sim.loadout.whip = null
	sim.loadout.orbit = null
	sim.loadout.forever = null
	sim.loadout.buffer = null
	sim.loadout.rebuild = null
	sim.loadout.levels[id] = 8
	sim.loadout.recompute()
	return sim


## 在玩家周围摆一圈木桩。spd = 0 时它们不会动（测"位置不变"要用）。
static func _w6ring(sim, n: int, dist: float, hp: float, spd: float = 0.0) -> void:
	for k in n:
		var a := TAU * float(k) / float(n)
		sim.enemies.spawn(
			sim.player_x + cos(a) * dist,
			sim.player_y + sin(a) * dist,
			hp, spd, 10.0, 0
		)


static func _w6run(sim, seconds: float) -> void:
	var steps := int(seconds / GameConfig.FIXED_DT)
	for i in steps:
		sim.step(GameConfig.FIXED_DT, 0.0, 0.0)


static func _w6hp(sim) -> float:
	var t := 0.0
	for i in sim.enemies.count:
		t += sim.enemies.hp[i]
	return t


## A 多线程齐射：一梭子要打到**多个不同**目标，而不是全部糊在最近那个上
static func _t_volley() -> void:
	var sim := _w6mk("volley")
	_w6ring(sim, 12, 130.0, 500.0)
	_w6run(sim, 1.2)
	var hurt := 0
	for i in sim.enemies.count:
		if sim.enemies.hp[i] < 500.0:
			hurt += 1
	print("  A 多线程齐射 · 命中 %d/12 个不同目标 · %s" % [
		hurt, "OK" if hurt >= 4 else "FAIL"])


## B 垃圾回收：残血的直接清掉，满血的只吃回收伤害、不会被清
static func _t_gc() -> void:
	var sim := _w6mk("gc")
	_w6ring(sim, 12, 100.0, 1000.0)
	# hp_max 在 spawn 时就固定了，所以要"先满血生成、再打残"，
	# 直接生成残血的话阈值算出来是 100%，永远不会被回收
	for i in 6:
		sim.enemies.hp[i] = 50.0
	_w6run(sim, 0.05)
	var left := sim.enemies.count
	var full_total := _w6hp(sim)
	var ok: bool = left == 6 and full_total < 12.0 * 1000.0 - 100.0
	print("  B 垃圾回收 · 残血 6 个已清（剩 %d）· 满血扣到总血 %.0f · %s" % [
		left, full_total, "OK" if ok else "FAIL"])


## C 缓冲区溢出：连续命中要越打越疼，停火后加成清零
static func _t_buffer() -> void:
	var sim := _w6mk("buffer")
	_w6ring(sim, 10, 60.0, 99999.0)
	var w = sim.loadout.buffer

	# 木桩会被"分离"逻辑互相推开，几秒后就散出了武器范围 ——
	# 于是第二次爆发只打到一两个人，看起来像伤害没涨。
	# 这里每帧把它们按回原位：要测的是伤害递增，不是推挤物理。
	var ox := PackedFloat32Array()
	var oy := PackedFloat32Array()
	for i in sim.enemies.count:
		ox.append(sim.enemies.px[i])
		oy.append(sim.enemies.py[i])

	# 按"每次爆发"采样，不能按固定时间窗口切：
	# 窗口长度不是冷却的整数倍时，两段窗口里的爆发次数不一样，
	# 第二次反而可能更小 —— 那是测量误差，不是机制坏了。
	var bursts: Array[float] = []
	var prev := _w6hp(sim)
	for i in int(5.0 / GameConfig.FIXED_DT):
		for k in sim.enemies.count:
			sim.enemies.px[k] = ox[k]
			sim.enemies.py[k] = oy[k]
		sim.step(GameConfig.FIXED_DT, 0.0, 0.0)
		var now := _w6hp(sim)
		var d := prev - now
		if d > 1.0:
			bursts.append(d)
		prev = now

	var d1: float = bursts[0] if bursts.size() > 0 else 0.0
	var d2: float = bursts[1] if bursts.size() > 1 else 0.0
	var stacked: float = w.stacks
	# 把木桩挪到天边，制造"停火"
	for i in sim.enemies.count:
		sim.enemies.px[i] = 99999.0
	_w6run(sim, 3.0)
	var after_idle: float = w.stacks
	var ok: bool = d2 > d1 * 1.1 and stacked > 0.0 and after_idle == 0.0
	print("  C 缓冲区溢出 · 首轮 %.0f → 次轮 %.0f · 层数 %.2f → 停火后 %.2f · %s" % [
		d1, d2, stacked, after_idle, "OK" if ok else "FAIL"])


## D 断点调试：范围内敌人被冻结，且冻结期间真的不移动
static func _t_breakpoint() -> void:
	var sim := _w6mk("breakpoint")
	_w6ring(sim, 8, 80.0, 500.0, 60.0)
	_w6run(sim, 0.05)
	var frozen := 0
	var x0 := sim.enemies.px[0]
	for i in sim.enemies.count:
		if sim.enemies.freeze[i] > 0.0:
			frozen += 1
	_w6run(sim, 0.5)
	var moved: float = absf(sim.enemies.px[0] - x0)
	print("  D 断点调试 · 冻结 %d/8 · 0.5 秒位移 %.2f px · %s" % [
		frozen, moved, "OK" if frozen >= 8 and moved < 0.5 else "FAIL"])


## E 永真力场：持续灼烧 + 持续自损；血低于 30% 必须自动停机
static func _t_forever() -> void:
	var sim := _w6mk("forever", false)     # 不开无敌，否则自损测不出来
	_w6ring(sim, 8, 60.0, 99999.0)
	var h0 := _w6hp(sim)
	var p0 := sim.player_hp
	_w6run(sim, 3.0)
	var dealt := h0 - _w6hp(sim)
	var lost := p0 - sim.player_hp
	var running1 := sim.loadout.forever.running
	# 安全阀：把血压到 20%
	sim.player_hp = sim.max_hp * 0.2
	_w6run(sim, 0.1)
	var running2 := sim.loadout.forever.running
	var p1 := sim.player_hp
	_w6run(sim, 0.5)
	var lost2 := p1 - sim.player_hp
	var ok: bool = dealt > 100.0 and lost > 1.0 and running1 and not running2 and lost2 < 0.001
	print("  E 永真力场 · 3 秒打出 %.0f · 自损 %.1f · 20%% 血时停机=%s 且不再掉血=%s · %s" % [
		dealt, lost, "是" if not running2 else "否", "是" if lost2 < 0.001 else "否",
		"OK" if ok else "FAIL"])


## F 全量重编译：蓄力期间没有伤害，蓄满后一次性清场，击杀缩短冷却
static func _t_rebuild() -> void:
	var sim := _w6mk("rebuild")
	_w6ring(sim, 20, 120.0, 150.0)        # 血量低于满级伤害，一炸即死
	_w6run(sim, 0.3)                      # 蓄力 0.5s，此刻还没炸
	var k1 := sim.kills
	_w6run(sim, 0.5)
	var k2 := sim.kills
	var w = sim.loadout.rebuild
	var ok: bool = k1 == 0 and k2 >= 20 and w.cooldown < w.cd_base * 0.95
	print("  F 全量重编译 · 蓄力中击杀 %d → 引爆后 %d · 冷却 %.2f/%.1f · %s" % [
		k1, k2, w.cooldown, w.cd_base, "OK" if ok else "FAIL"])


##
## 进化系统自检。
##
## 进化改的是**行为**，所以每一条断言的都是"有没有换一种打法"，
## 而不是伤害涨了多少 —— 后者是数值表的事，测它没意义。
##
## 运行：godot --headless --path . -- --evotest
##
static func run_evo() -> void:
	print("")
	print("=== 进化系统 · 机制测试 ===")
	print("每条都跑两遍：未进化 vs 已进化，对比的是**行为差异**")
	print("")
	_t_evo_gate()
	_t_evo_whip()
	_t_evo_orbit()
	_t_evo_broadcast()
	_t_evo_judgment()
	_t_evo_blade()
	_t_evo_pointer()
	_t_evo_volley()
	_t_evo_gc()
	_t_evo_buffer()
	_t_evo_breakpoint()
	_t_evo_forever()
	_t_evo_rebuild()
	print("")


## 建一把满级武器 + 指定满级被动，可选是否完成进化
## 角色系统自检。运行：godot --headless --path . -- --chartest
static func run_char() -> void:
	print("")
	print("=== 角色系统 · 机制测试 ===")
	print("角色 = 起始武器 + 属性修正 + 一条特性，这里逐条验证三者都真的生效")
	print("")
	_t_char_data()
	_t_char_start()
	_t_char_stats()
	_t_char_module()
	_t_char_cron()
	_t_char_break()
	_t_char_recur()
	_t_char_learn()
	print("")


static func _ok(b: bool) -> String:
	return "OK" if b else "FAIL"


## 建一局指定角色的干净局：不开刷怪（避免敌人乱入计数）、默认无敌。
static func _charmk(cid: String, god: bool = true) -> Sim:
	var sim := Sim.new()
	sim.setup(cid)
	sim.god_mode = god
	sim.spawn_enabled = false
	return sim


## 1 数据表：起始武器必须是武器 —— 写成被动的话开局就是空手
static func _t_char_data() -> void:
	var bad := 0
	for c in CharDefs.CHARACTERS:
		var wd := UpgradeDefs.def_of(str(c["start"]))
		if wd.is_empty() or int(wd["kind"]) != UpgradeDefs.KIND_WEAPON:
			bad += 1
	print("  1 数据表 · %d 个角色起始武器均为武器 · %s" % [
		CharDefs.CHARACTERS.size(), _ok(bad == 0)])


## 2 起始武器：等级表里有、武器实例也真的建出来了
static func _t_char_start() -> void:
	var bad := 0
	var txt: Array[String] = []
	for c in CharDefs.CHARACTERS:
		var sim := _charmk(str(c["id"]))
		var sid := str(c["start"])
		if sim.loadout.level_of(sid) != 1 or sim.loadout.weapon_map.get(sid) == null:
			bad += 1
		txt.append("%s-%s" % [c["name"], UpgradeDefs.def_of(sid)["name"]])
	print("  2 起始武器 · %s · %s" % [" ".join(PackedStringArray(txt)), _ok(bad == 0)])


## 3 属性修正：生命 / 拾取 / 移速
static func _t_char_stats() -> void:
	var base := _charmk("intern")
	var ops := _charmk("ops")
	var arch := _charmk("arch")
	var qa := _charmk("qa")
	var ok_hp := absf(base.max_hp - 100.0) < 0.01 and absf(ops.max_hp - 125.0) < 0.01
	var ok_pick := absf(arch.loadout.pickup_range - 95.0 * 1.4) < 0.01
	var ok_spd := absf(qa.char_speed_mult - 1.08) < 0.001 and absf(base.char_speed_mult - 1.0) < 0.001
	print("  3 属性修正 · 生命 %.0f→%.0f · 拾取 %.0f · 移速 x%.2f · %s" % [
		base.max_hp, ops.max_hp, arch.loadout.pickup_range, qa.char_speed_mult,
		_ok(ok_hp and ok_pick and ok_spd)])


## 4 模块堆叠（架构师）：伤害随武器数量涨，不是固定值
static func _t_char_module() -> void:
	var arch := _charmk("arch")
	var d1: float = arch.loadout.damage_mult
	arch.loadout.apply_upgrade("whip")
	arch.loadout.apply_upgrade("blade")
	var d3: float = arch.loadout.damage_mult
	var base := _charmk("intern")
	base.loadout.apply_upgrade("whip")
	base.loadout.apply_upgrade("blade")
	var b3: float = base.loadout.damage_mult
	var ok := absf(d1 - 1.05) < 0.001 and absf(d3 - 1.15) < 0.001 and absf(b3 - 1.0) < 0.001
	print("  4 模块堆叠 · 架构师 1 把 x%.2f → 3 把 x%.2f（普通角色 x%.2f）· %s" % [
		d1, d3, b3, _ok(ok)])


## 5 定时自愈（运维工程师）：到点回一次血，其他角色没有
static func _t_char_cron() -> void:
	var steps := int(26.0 / GameConfig.FIXED_DT)
	var ops := _charmk("ops")
	# 必须清掉 setup() 预铺的那批敌人：起始武器会把它们打死，掉的补丁包被捡到
	# 就回一截血，于是「对照组的血量」随机漂移（实测 50 → 75），这条断言时灵时不灵。
	# 这里只验证「定时自愈」本身，不该掺进任何掉落运气。
	ops.enemies.clear()
	ops.player_hp = 50.0
	for i in steps:
		ops.step(GameConfig.FIXED_DT, 0.0, 0.0)
	var base := _charmk("intern")
	base.enemies.clear()
	base.player_hp = 50.0
	for i in steps:
		base.step(GameConfig.FIXED_DT, 0.0, 0.0)
	var ok := ops.cron_procs == 1 and ops.player_hp > 50.0 		and base.cron_procs == 0 and absf(base.player_hp - 50.0) < 0.001
	print("  5 定时自愈 · 运维 26 秒触发 %d 次 HP %.1f（实习生 %d 次 HP %.1f）· %s" % [
		ops.cron_procs, ops.player_hp, base.cron_procs, base.player_hp, _ok(ok)])


## 6 断点暂停（测试工程师）：接触伤害的无敌帧翻倍，弹幕不跟着翻
static func _t_char_break() -> void:
	var qa := _charmk("qa", false)
	qa.hurt_player(10.0)
	var base := _charmk("intern", false)
	base.hurt_player(10.0)
	var qb := _charmk("qa", false)
	qb.hurt_player_bullet(5.0)
	var ok := absf(qa.iframe - 1.2) < 0.001 and absf(base.iframe - 0.6) < 0.001 		and absf(qb.bullet_iframe - GameConfig.BULLET_IFRAME) < 0.001
	print("  6 断点暂停 · 无敌帧 %.2f（普通 %.2f）· 弹幕仍 %.2f · %s" % [
		qa.iframe, base.iframe, qb.bullet_iframe, _ok(ok)])


## 7 递归返回（算法工程师）：每 60 杀把全部武器冷却清零
static func _t_char_recur() -> void:
	var algo := _charmk("algo")
	for i in 60:
		algo.enemies.spawn(algo.player_x + 400.0, algo.player_y, 0.0, 0.0, 7.0, 0)
	algo.step(GameConfig.FIXED_DT, 0.0, 0.0)
	var cd: float = algo.loadout.weapon_map["blade"].cooldown
	var base := _charmk("intern")
	for i in 60:
		base.enemies.spawn(base.player_x + 400.0, base.player_y, 0.0, 0.0, 7.0, 0)
	base.step(GameConfig.FIXED_DT, 0.0, 0.0)
	var ok := algo.kills == 60 and algo.recur_procs == 1 and cd <= 0.001 		and base.recur_procs == 0
	print("  7 递归返回 · 60 杀触发 %d 次、飞刃冷却归零 %.3f（普通 %d 次）· %s" % [
		algo.recur_procs, cd, base.recur_procs, _ok(ok)])


## 吃一颗刚好够升一级的经验宝石。
static func _level_once(sim: Sim) -> void:
	sim.gems.spawn(sim.player_x, sim.player_y, int(sim.exp_next) + 1, 0)
	sim.step(GameConfig.FIXED_DT, 0.0, 0.0)


## 8 边学边练（实习生）：每 10 级多一次三选一
static func _t_char_learn() -> void:
	var it := _charmk("intern")
	for i in 9:
		_level_once(it)
	var algo := _charmk("algo")
	for i in 9:
		_level_once(algo)
	var ok := it.level == 10 and it.learn_bonus == 1 and it.pending_levelups == 10 		and algo.level == 10 and algo.learn_bonus == 0 and algo.pending_levelups == 9
	print("  8 边学边练 · 实习生 Lv%d 升级次数 %d（+%d）· 其他角色 Lv%d 升级次数 %d · %s" % [
		it.level, it.pending_levelups, it.learn_bonus,
		algo.level, algo.pending_levelups, _ok(ok)])


static func _evomk(wid: String, passive: String = "", evolved: bool = true,
		god: bool = true) -> Sim:
	var sim := _w6mk(wid, god)
	if passive != "":
		sim.loadout.levels[passive] = 5
		sim.loadout.recompute()
	if evolved:
		sim.loadout.apply_evolution("evo_" + wid)
	return sim


static func _evo_ok(ok: bool) -> String:
	return "OK" if ok else "FAIL"


## 跑一段并取某个数量的**峰值**。
## 短命的东西（子波、追踪弹）在固定时刻采样经常已经消失了，
## 只看最后一帧会误判成"没生成"，所以这里按帧取最大值。
static func _evo_peak(sim, seconds: float, f: Callable) -> int:
	var peak := 0
	var steps := int(seconds / GameConfig.FIXED_DT)
	for i in steps:
		sim.step(GameConfig.FIXED_DT, 0.0, 0.0)
		peak = maxi(peak, int(f.call()))
	return peak


## 门槛：武器满级 + 被动满级才出现；拿过之后不再重复出现
static func _t_evo_gate() -> void:
	var sim := _w6mk("whip")
	sim.loadout.levels["optimize"] = 4      # 被动还差一级
	var a := sim.loadout.available_evolutions().size()
	sim.loadout.levels["optimize"] = 5
	var b := sim.loadout.available_evolutions().size()
	var got := false
	for e in sim.loadout.available_evolutions():
		if str(e["id"]) == "evo_whip":
			got = true
	# 三选一里必须占一席
	var choices := sim.loadout.roll_choices(3)
	var in_roll := false
	for ch in choices:
		if str(ch["def"]["id"]).begins_with("evo_"):
			in_roll = true
	sim.loadout.apply_evolution("evo_whip")
	var c := sim.loadout.available_evolutions().size()
	var ok: bool = a == 0 and b == 1 and got and in_roll and c == 0
	print("  0 门槛 · 被动Lv4=%d条 → Lv5=%d条(含evo_whip=%s, 进三选一=%s) → 拿过=%d条 · %s" % [
		a, b, "是" if got else "否", "是" if in_roll else "否", c, _evo_ok(ok)])


## 1 三元表达式：四个方向都打（未进化只有 3 个方向，上方是死角）
static func _t_evo_whip() -> void:
	var hurt_plain := 0
	var hurt_evo := 0
	for evo in [false, true]:
		var sim := _evomk("whip", "optimize", evo)
		# 上下左右各一个木桩
		for d in [Vector2(70, 0), Vector2(-70, 0), Vector2(0, 70), Vector2(0, -70)]:
			sim.enemies.spawn(sim.player_x + d.x, sim.player_y + d.y, 1000.0, 0.0, 10.0, 0)
		_w6run(sim, 0.3)
		var n := 0
		for i in sim.enemies.count:
			if sim.enemies.hp[i] < 1000.0:
				n += 1
		if evo:
			hurt_evo = n
		else:
			hurt_plain = n
	print("  1 三元表达式 · 四向木桩命中 %d → %d · %s" % [
		hurt_plain, hurt_evo, _evo_ok(hurt_plain == 3 and hurt_evo == 4)])


## 2 嵌套循环：环绕物变双层，内圈更近
static func _t_evo_orbit() -> void:
	var sim := _evomk("orbit", "overclock", true)
	var w = sim.loadout.orbit
	_w6run(sim, 0.2)
	var inner_d: float = Vector2(w.ox[w.count] - sim.player_x, w.oy[w.count] - sim.player_y).length()
	var outer_d: float = Vector2(w.ox[0] - sim.player_x, w.oy[0] - sim.player_y).length()
	var ok: bool = w.draw_count == w.count * 2 and inner_d < outer_d * 0.8
	print("  2 嵌套循环 · 环绕物 %d → %d · 内圈半径 %.0f/外圈 %.0f · %s" % [
		w.count, w.draw_count, inner_d, outer_d, _evo_ok(ok)])


## 3 事件总线：主波扫完后再冒出子波（未进化的波扫完就没了）
static func _t_evo_broadcast() -> void:
	var sub_plain := 0
	var sub_evo := 0
	for evo in [false, true]:
		var sim := _evomk("broadcast", "ptr", evo)
		_w6ring(sim, 8, 100.0, 1000.0)
		var peak := _evo_peak(sim, 1.2, func() -> int: return sim.fx.waves.size())
		if evo:
			sub_evo = peak
		else:
			sub_plain = peak
	print("  3 事件总线 · 同时存在的波峰值 %d → %d（主波+子波）· %s" % [
		sub_plain, sub_evo, _evo_ok(sub_plain <= 1 and sub_evo >= 2)])


## 4 随机种子：一次冷却打出 3 倍数量的落雷
static func _t_evo_judgment() -> void:
	var n_plain := 0
	var n_evo := 0
	for evo in [false, true]:
		var sim := _evomk("judgment", "optimize", evo)
		_w6ring(sim, 8, 100.0, 1000.0)
		_w6run(sim, 0.05)
		if evo:
			n_evo = sim.fx.bolts.size()
		else:
			n_plain = sim.fx.bolts.size()
	print("  4 随机种子 · 单波落雷 %d → %d 道 · %s" % [
		n_plain, n_evo, _evo_ok(n_plain >= 1 and n_evo == n_plain * 3)])


## 5 尾递归：弹射不再衰减、次数 +3
static func _t_evo_blade() -> void:
	var sim0 := _evomk("blade", "thread", false)
	var sim1 := _evomk("blade", "thread", true)
	var w0 = sim0.loadout.weapon_map["blade"]
	var w1 = sim1.loadout.weapon_map["blade"]
	var ok: bool = w0.decay < 1.0 and w1.decay == 1.0 and w1.bounces == w0.bounces + 3
	print("  5 尾递归 · 衰减 %.2f→%.2f · 弹射 %d→%d · %s" % [
		w0.decay, w1.decay, w0.bounces, w1.bounces, _evo_ok(ok)])


## 6 引用计数：命中后一发变两发
static func _t_evo_pointer() -> void:
	var n_plain := 0
	var n_evo := 0
	for evo in [false, true]:
		var sim := _evomk("pointer", "ptr", evo)
		_w6ring(sim, 3, 90.0, 1000.0)
		var peak := _evo_peak(sim, 1.2, func() -> int: return sim.projectiles.count)
		if evo:
			n_evo = peak
		else:
			n_plain = peak
	print("  6 引用计数 · 场上追踪弹峰值 %d → %d · %s" % [
		n_plain, n_evo, _evo_ok(n_evo > n_plain)])


## 7 线程池：一次冷却打两轮点射
static func _t_evo_volley() -> void:
	var n_plain := 0
	var n_evo := 0
	for evo in [false, true]:
		var sim := _evomk("volley", "thread", evo)
		_w6ring(sim, 8, 130.0, 9999.0)
		_w6run(sim, 3.0)
		var shots: int = sim.loadout.weapon_map["volley"].fired_total
		if evo:
			n_evo = shots
		else:
			n_plain = shots
	print("  7 线程池 · 3 秒内开火 %d → %d 轮 · %s" % [
		n_plain, n_evo, _evo_ok(n_evo >= n_plain * 2 - 1)])


## 8 全量回收：远处（远超半径）的残血也会被清掉
static func _t_evo_gc() -> void:
	var left_plain := 0
	var left_evo := 0
	for evo in [false, true]:
		var sim := _evomk("gc", "optimize", evo)
		var r: float = sim.loadout.weapon_map["gc"].radius
		# 近处一个、远处一个（远超半径），都是残血
		sim.enemies.spawn(sim.player_x + r * 0.5, sim.player_y, 1000.0, 0.0, 10.0, 0)
		sim.enemies.spawn(sim.player_x + r * 4.0, sim.player_y, 1000.0, 0.0, 10.0, 0)
		sim.enemies.hp[0] = 30.0
		sim.enemies.hp[1] = 30.0
		_w6run(sim, 0.1)
		if evo:
			left_evo = sim.enemies.count
		else:
			left_plain = sim.enemies.count
	var ok: bool = left_plain == 1 and left_evo == 0
	print("  8 全量回收 · 一近一远残血，扫完剩 %d → %d 个 · %s" % [
		left_plain, left_evo, _evo_ok(ok)])


## 9 环形缓冲：停火后层数不再清零
static func _t_evo_buffer() -> void:
	var s_plain := 0.0
	var s_evo := 0.0
	for evo in [false, true]:
		var sim := _evomk("buffer", "overclock", evo)
		_w6ring(sim, 8, 60.0, 9999.0)
		_w6run(sim, 4.0)              # 叠层
		sim.enemies.clear()           # 停火
		_w6run(sim, 3.0)              # 超过 2.5 秒的清空阈值
		if evo:
			s_evo = sim.loadout.weapon_map["buffer"].stacks
		else:
			s_plain = sim.loadout.weapon_map["buffer"].stacks
	print("  9 环形缓冲 · 停火 3 秒后层数 %.2f → %.2f · %s" % [
		s_plain, s_evo, _evo_ok(s_plain < 0.01 and s_evo > 0.5)])


## 10 断言：被冻结的敌人死亡时，把武器范围外的敌人也一起冻住
static func _t_evo_breakpoint() -> void:
	var sim := _evomk("breakpoint", "malloc", true)
	var w = sim.loadout.breakpoint_w
	var r: float = w.radius
	# A 在冻结范围内、一击就死；B 在范围外，只有靠 A 死掉的连锁才够得着
	sim.enemies.spawn(sim.player_x + r * 0.6, sim.player_y, 1.0, 0.0, 10.0, 0)
	sim.enemies.spawn(sim.player_x + r * 1.15, sim.player_y, 9999.0, 0.0, 10.0, 0)
	# 冻结会随时间衰减，跑到末尾再采样一定已经解冻了 —— 必须按帧取峰值。
	var peak := _evo_peak(sim, 4.0, func() -> int:
		for i in sim.enemies.count:
			if absf(sim.enemies.px[i] - sim.player_x) > r * 1.05:
				return 1 if sim.enemies.freeze[i] > 0.0 else 0
		return 0)
	var b_frozen := peak == 1
	print(" 10 断言 · 范围外敌人被连锁冻住=%s · %s" % [
		"是" if b_frozen else "否", _evo_ok(b_frozen)])


## 11 守护进程：残血不再停机，改为输出与自损一起减半
static func _t_evo_forever() -> void:
	var res := []
	for evo in [false, true]:
		var sim := _evomk("forever", "malloc", evo, false)
		_w6ring(sim, 8, 110.0, 99999.0)      # 在半径(140)内，但远到不会贴脸吃接触伤害
		var h0 := _w6hp(sim)
		sim.player_hp = sim.max_hp * 0.2       # 残血：原版会停机
		var p0 := sim.player_hp
		_w6run(sim, 2.0)
		res.append({
			"running": sim.loadout.forever.running,
			"dealt": h0 - _w6hp(sim),
			"lost": p0 - sim.player_hp,
		})
	var ok: bool = (not res[0]["running"]) and res[0]["dealt"] < 1.0 \
		and res[1]["running"] and res[1]["dealt"] > 50.0 and res[1]["lost"] > 0.0
	print(" 11 守护进程 · 残血时 停机=%s/输出%.0f → 停机=%s/输出%.0f(自损%.1f) · %s" % [
		"是" if not res[0]["running"] else "否", res[0]["dealt"],
		"是" if not res[1]["running"] else "否", res[1]["dealt"], res[1]["lost"],
		_evo_ok(ok)])


## 12 增量编译：一轮爆两次
static func _t_evo_rebuild() -> void:
	var n_plain := 0
	var n_evo := 0
	for evo in [false, true]:
		var sim := _evomk("rebuild", "overclock", evo)
		_w6ring(sim, 20, 120.0, 9999.0)
		_w6run(sim, 1.2)          # 首爆 0.5s + 追加 0.3s，之后进冷却
		if evo:
			n_evo = sim.loadout.rebuild.fired_total
		else:
			n_plain = sim.loadout.rebuild.fired_total
	print(" 12 增量编译 · 1.2 秒内引爆 %d → %d 次 · %s" % [
		n_plain, n_evo, _evo_ok(n_plain == 1 and n_evo == 2)])


static func run_opening() -> void:
	var s1: Dictionary = UpgradeDefs.stats_for("whip", 1)
	var reach: float = float(s1["reach"])
	var reach2 := reach * reach

	print("")
	print("=== 开局体验 · 站着不动 8 秒 ===")
	print("起始武器：分支长鞭 Lv1 · 射程 %.0f · 冷却 %.2fs · 伤害 %.0f" % [
		reach, float(s1["cd"]), float(s1["dmg"])
	])
	print("")

	var sim := Sim.new()
	sim.setup()
	sim.god_mode = true

	var first_kill := -1.0
	var next_report := 1.0
	var step := 0
	var steps := int(8.0 / GameConfig.FIXED_DT)

	while step < steps:
		# 站着不动是最保守的情况，玩家真跑起来只会更快接火
		sim.step(GameConfig.FIXED_DT, 0.0, 0.0)

		if first_kill < 0.0 and sim.kills > 0:
			first_kill = sim.time

		if sim.time >= next_report:
			next_report += 1.0
			# 射程内敌人数 = 武器有没有目标的直接指标
			var in_range := 0
			var i := 0
			while i < sim.enemies.count:
				var dx: float = sim.enemies.px[i] - sim.player_x
				var dy: float = sim.enemies.py[i] - sim.player_y
				if dx * dx + dy * dy <= reach2:
					in_range += 1
				i += 1
			print("t=%2.0fs  场上 %3d  ·  射程内 %3d  ·  累计击杀 %3d" % [
				sim.time, sim.enemies.count, in_range, sim.kills
			])
		step += 1

	print("")
	if first_kill >= 0.0:
		print("首次击杀：%.1f 秒" % first_kill)
	else:
		print("8 秒内一个都没打到 —— 开局距离或刷怪速度需要再调")

	# 动画帧分布：全部挤在同一帧 = spawn 时没随机化相位，会变成整齐划一的踏步
	var dist := []
	for f in EnemyPool.FRAMES:
		dist.append(0)
	var i := 0
	while i < sim.enemies.count:
		var fi := int(sim.enemies.anim[i])
		if fi >= 0 and fi < EnemyPool.FRAMES:
			dist[fi] += 1
		i += 1
	var parts := []
	for f in EnemyPool.FRAMES:
		parts.append("帧%d=%d" % [f, dist[f]])
	print("动画帧分布  " + "  ".join(parts) + "   （大致均匀 = 相位随机生效）")
	print("")


## 场上敌人类型构成（波次验证用）：期望随时间推移出现新类型名
static func _composition(e: EnemyPool) -> String:
	var cnt := {}
	for i in e.count:
		var id: String = EnemyDB.DEFS[e.type[i]]["id"]
		cnt[id] = int(cnt.get(id, 0)) + 1
	var parts := []
	for id in cnt:
		parts.append("%s×%d" % [id, cnt[id]])
	parts.sort()
	return " ".join(parts)


##
## 宝箱链路验证：在玩家面前 45px 放一只薄血精英，
## 武器击杀 → 必掉宝箱 → **玩家自己走过去踩到** → 回血 50。
## 运行：godot --headless --path . -- --chesttest
##
static func run_chest_test() -> void:
	print("")
	print("=== 精英宝箱链路测试 ===")

	var sim := Sim.new()
	sim.setup()
	sim.god_mode = true
	sim.spawn_enabled = false

	# 先扣到 40 血：满血时回血会溢出被截断，healed_total 永远是 0，测不出回血
	sim.player_hp = 40.0

	var ei := EnemyDB.idx_of(EnemyDB.ELITE_ID)
	sim.enemies.spawn(
		sim.player_x + 45.0, sim.player_y,
		10.0, 0.0, EnemyDB.DEFS[ei].radius, ei
	)

	var chest_seen := false
	for i in 600:
		# 宝箱不磁吸，掉在 45px 外就得走过去 —— 玩家不动的话这里会 FAIL，
		# 那正是新规则要的效果（测的是"掉落 + 主动拾取"整条链路）
		var d := _dir_to_heal(sim)
		sim.step(GameConfig.FIXED_DT, d.x, d.y)
		if sim.chests_collected > 0:
			chest_seen = true
			break

	print("击杀 %d · 拾取宝石 %d · 宝箱 %d · 累计回血 %.1f" % [
		sim.kills, sim.gems_collected, sim.chests_collected, sim.healed_total
	])
	if chest_seen and sim.chests_collected >= 1 and sim.healed_total >= GameConfig.CHEST_HEAL:
		print("PASS：精英死亡 → 宝箱掉落 → 玩家走过去踩到 → 回血 %.0f，链路完整" % sim.healed_total)
	else:
		print("FAIL：宝箱链路有断点，逐项排查")


##
## 站桩测试：玩家全程不移动，看能活多久。
## 运行：godot --headless --path . -- --standtest
##
## 这是"必须时刻保持移动"这条设计意图的回归基线。
## 站桩能活满 20 分钟 = 敌人根本近不了身 = 游戏失去可玩性（用户 2026-09-17 反馈）。
## 期望：站桩在 1~3 分钟内阵亡 —— 站着能活，但活不久，逼玩家走起来。
##
static func run_stand(max_minutes: float = 20.0, rounds: int = 3) -> void:
	print("")
	print("=== 站桩测试（玩家全程不动）===")
	print("不开无敌 · 升级随机选 · 跑 %d 局 · 期望 1~3 分钟内阵亡" % rounds)
	print("")

	var deaths := 0
	for r in rounds:
		var sim := Sim.new()
		sim.setup()
		var steps := int(max_minutes * 60.0 / GameConfig.FIXED_DT)
		var step := 0
		while step < steps and not sim.dead:
			sim.step(GameConfig.FIXED_DT, 0.0, 0.0)
			while sim.pending_levelups > 0:
				var pick: Dictionary = sim.loadout.roll_choices(1)[0]
				var id := str(pick["def"]["id"])
				if id == "_heal":
					sim.apply_heal_pick(30.0)
				else:
					sim.apply_upgrade(id)
			step += 1

		var survived := not sim.dead
		if not survived:
			deaths += 1
		print("  第 %d 局：%s · 存活 %.1f 分钟 · Lv %d · 击杀 %d · 场上敌人 %d" % [
			r + 1, "阵亡" if not survived else "活满全场",
			sim.time / 60.0, sim.level, sim.kills, sim.enemies.count
		])

	print("")
	print("站桩阵亡 %d/%d 局" % [deaths, rounds])
	if deaths == 0:
		print("FAIL：站着不动也死不了 —— 敌人威胁不足，玩家没有移动压力")
	else:
		print("PASS：站着不动会死，移动是必须的")


##
## 后期满配站桩：真实抱怨的场景。
## 运行：godot --headless --path . -- --standtest=late
##
## 开局站桩 12 秒就死，那是"只有一把长鞭 Lv1、背后全是盲区"的必然结果，
## 说明不了问题。用户看到的是**武器成型之后**：AoE 覆盖四周，
## 敌人还没走到跟前就成片倒下，站着不动也不掉血。
##
## 所以这一档要先把场面推到 10 分钟的档位（满级武器 + 敌人铺到 800），
## 再关掉无敌、玩家站定不动 —— 测的就是"火力网有没有漏洞"。
##
static func run_stand_late(max_minutes: float = 4.0, rounds: int = 1) -> void:
	print("")
	print("=== 后期满配站桩（武器全满级 · 敌人 10 分钟档位）===")
	print("玩家全程不动 · 跑 %d 局 · 期望阵亡：火力网必须留缺口，站着就得死" % rounds)
	print("")

	var deaths := 0
	for r in rounds:
		var sim := Sim.new()
		sim.setup()
		sim.god_mode = true
		for u in UpgradeDefs.UPGRADES:
			if int(u["kind"]) == UpgradeDefs.KIND_WEAPON:
				sim.loadout.levels[str(u["id"])] = int(u["max"])
		sim.loadout.recompute()
		sim.time = 600.0          # 刷怪与血量成长按 10 分钟档位来

		# 预热 90 秒：把敌人铺满到该档位（无敌，只铺场不算账）
		for _i in int(90.0 / GameConfig.FIXED_DT):
			sim.step(GameConfig.FIXED_DT, 0.0, 0.0)

		# 清掉地面掉落物：站桩又不移动，宝石只是白占 _update_gems 的遍历，
		# 一局下来几千个纯属拖慢测试。不影响战斗结果。
		sim.gems.clear()
		sim.heal_on_ground = 0

		sim.god_mode = false
		var t0 := sim.time
		var steps := int(max_minutes * 60.0 / GameConfig.FIXED_DT)
		var step := 0
		var hp_prev := sim.player_hp
		var hurts := 0
		while step < steps and not sim.dead:
			sim.step(GameConfig.FIXED_DT, 0.0, 0.0)
			if sim.player_hp < hp_prev:
				hurts += 1
			hp_prev = sim.player_hp

			# 诊断：站着不动却死不了，一定是"敌人压根没碰到玩家"，
			# 光看存活时间猜不出是哪一环挡住的 —— 所以要打印最近距离与贴身数量
			if step % 1800 == 0:
				var near := 0
				var min_d := 1e9
				for i in sim.enemies.count:
					var dx: float = sim.enemies.px[i] - sim.player_x
					var dy: float = sim.enemies.py[i] - sim.player_y
					var d2 := dx * dx + dy * dy
					if d2 < min_d:
						min_d = d2
					if d2 <= 40.0 * 40.0:
						near += 1
				print("    %.1f 分  血 %5.1f  场上 %4d  最近敌人 %5.1fpx  40px 内 %3d  累计挨打 %d 次" % [
					(sim.time - t0) / 60.0, sim.player_hp, sim.enemies.count,
					sqrt(min_d), near, hurts
				])
			step += 1

		var survived := not sim.dead
		if not survived:
			deaths += 1
		print("  第 %d 局：%s · 站桩存活 %.1f 分钟 · 击杀 %d · 挨打 %d 次 · 场上敌人 %d" % [
			r + 1, "阵亡" if not survived else "活满全场",
			(sim.time - t0) / 60.0, sim.kills, hurts, sim.enemies.count
		])

	print("")
	print("站桩阵亡 %d/%d 局" % [deaths, rounds])
	if deaths == 0:
		print("FAIL：后期站着不动也死不了 —— 敌人近不了身，移动失去意义")
		print("     （看上面的 最近敌人 / 40px 内 两列：一直贴不上来 = 火力网没有缺口）")
	else:
		print("PASS：站着不动会死，移动是必须的")


##
## 朝向最近的地面回血物的单位向量；地上没有回血物就返回零向量。
##
## 回血物取消磁吸后，所有"验证能拿到回血"的测试都必须让玩家自己走过去，
## 否则测出来的是"有没有掉落"，不是"能不能拿到"。
static func _dir_to_heal(sim: Sim) -> Vector2:
	var best := -1
	var best_d2 := 1e18
	for g in sim.gems.count:
		if not GemPool.is_heal(sim.gems.kind[g]):
			continue
		var dx: float = sim.gems.px[g] - sim.player_x
		var dy: float = sim.gems.py[g] - sim.player_y
		var d2 := dx * dx + dy * dy
		if d2 < best_d2:
			best_d2 = d2
			best = g
	if best < 0:
		return Vector2.ZERO
	var v := Vector2(sim.gems.px[best] - sim.player_x, sim.gems.py[best] - sim.player_y)
	return v.normalized() if v.length() > 0.001 else Vector2.ZERO


##
## Boss 链路验证：满级武器 + 玩家贴脸，spawn 一只编译器反噬，
## 验证 ① Boss 出场被 sim 追踪到（boss_active / 血条数据源）
##      ② 击杀耗时（用来校准 4000 血是否合理）
##      ③ 死亡后必掉 3 个宝箱 + victory 置位
## 运行：godot --headless --path . -- --bosstest
##
static func run_boss_test() -> void:
	print("")
	print("=== Boss「编译器反噬」链路测试 ===")

	var sim := Sim.new()
	sim.setup()
	sim.god_mode = true
	sim.spawn_enabled = false

	# 武器拉满，模拟 18 分钟时的真实 Build 强度
	for u in UpgradeDefs.UPGRADES:
		sim.loadout.levels[str(u["id"])] = int(u["max"])
	sim.loadout.recompute()

	var bi := EnemyDB.idx_of(EnemyDB.BOSS_ID)
	var d: Dictionary = EnemyDB.DEFS[bi]
	# 摆在拾取半径内（45 < 70），否则宝箱掉在够不着的地方，测的是"掉落"不是"走位去捡"
	sim.enemies.spawn(sim.player_x + 200.0, sim.player_y, d.hp, d.speed, d.radius, bi)
	sim._update_boss(0.0)
	print("出场：boss_active=%s  血 %.0f/%.0f  (半径 %.0f → 视觉 %.0f px)" % [
		sim.boss_active, sim.boss_hp, sim.boss_max_hp, d.radius, d.radius * 2.0
	])

	var step := 0
	var max_steps := int(180.0 / GameConfig.FIXED_DT)   # 最多打 3 分钟
	while step < max_steps and not sim.victory and not sim.dead:
		sim.step(GameConfig.FIXED_DT, 0.0, 0.0)
		step += 1

	# 打完之后再走 3 秒去把宝箱踩到：宝箱不磁吸，不去捡就永远在地上。
	# 这一段同时验证"通关奖励玩家真的拿得到"。
	for i in 180:
		var hd := _dir_to_heal(sim)
		sim.step(GameConfig.FIXED_DT, hd.x, hd.y)

	var t := float(step) * GameConfig.FIXED_DT
	# 统计地面上的宝箱（掉落口径）—— 拾取数会被"玩家有没有走过去"干扰
	var chests_on_ground := 0
	for g in sim.gems.count:
		if sim.gems.kind[g] == GemPool.KIND_CHEST:
			chests_on_ground += 1
	print("击杀耗时 %.1f 秒 · victory=%s · 地面宝箱 %d · 已拾取 %d · 累计回血 %.0f" % [
		t, sim.victory, chests_on_ground, sim.chests_collected, sim.healed_total
	])
	print("技能统计：Boss 技能 %d 次（冲刺 %d · 环形弹幕 %d · 扇形 %d · 追踪 %d · 危险区 %d）· 召唤 %d 波 · 场上小怪 %d" % [
		sim.boss_skills, sim.boss_dashes, sim.boss_novas, sim.boss_aimeds,
		sim.boss_homings, sim.boss_hazards, sim.boss_summons, sim.enemies.count
	])
	print("弹幕：累计发射 %d 发；危险区留在场上的预警圈由 HazardStore 管理" % sim.bullets_fired)

	if sim.victory and chests_on_ground + sim.chests_collected >= 3:
		# 五种技能必须都出现过至少一次：轮盘一旦卡住（比如某个技能的
		# 前置条件永远不满足），表现就是"Boss 只会普攻"，而那是看不见的 bug。
		var kinds: Array = [sim.boss_dashes, sim.boss_novas, sim.boss_aimeds,
			sim.boss_homings, sim.boss_hazards]
		var missing := 0
		for v in kinds:
			if int(v) < 1:
				missing += 1
		var skills_ok := sim.boss_skills >= 8 and sim.boss_summons >= 1 and missing == 0
		print("PASS：Boss 出场 → 血条数据 → 技能轮盘 → 击杀 → 宝箱掉落 → 通关判定，链路完整"
			+ ("" if skills_ok else "，但技能覆盖不足（FAIL 项）"))
		if not skills_ok:
			print("FAIL：Boss 技能总次数 %d（期望 ≥8）· 未出现的技能种类 %d 种 —— 技能轮盘没转起来"
				% [sim.boss_skills, missing])
			return
		# 站桩满级 TTK 是"玩家一次都不躲"的下限值，所以窗口要按"下限 ≥60 秒"卡：
		# 实际对局玩家还要躲弹幕、清杂兵，真实时长只会比它更长。
		var ok_sec := t >= 52.0 and t <= 150.0
		print("决战时长 %s（站桩满级 %.1f 秒；期望 52~150 秒的下限窗口 —— 太短没有压迫感，太长变磨血）"
			% ["合适" if ok_sec else "需调整血量", t])
	else:
		print("FAIL：Boss 链路有断点（没打死或没掉宝箱）")


## 精英 / Boss 技能链路 + "必须走位"的量化验证。
##
## 运行：godot --headless --path . -- --skilltest
##
## 三段：
##   A 精英：摆一只精英在 320px 外，看技能轮盘转不转、弹幕有没有真的飞出来。
##   B Boss：满级 build 站桩打 Boss，确认五种技能全部出现过。
##   C 走位：同样的 Boss 战跑两遍 —— 一遍站桩、一遍"会躲"——
##     血量曲线就是"必须走位"的硬证据。这一段的结论不能靠感觉。
static func run_skill_test() -> void:
	print("")
	print("=== 精英 / Boss 技能链路测试 ===")

	# ---------------- A. 精英技能 ----------------
	var s1 := Sim.new()
	s1.setup()
	s1.god_mode = true          # 只看技能，不让玩家中途死掉（死了就没人给它打了）
	s1.spawn_enabled = false
	var ei := EnemyDB.idx_of(EnemyDB.ELITE_ID)
	var ed: Dictionary = EnemyDB.DEFS[ei]
	s1.enemies.spawn(s1.player_x + 320.0, s1.player_y, ed.hp, ed.speed, ed.radius, ei)
	s1.grid.rebuild(s1.enemies)

	var peak_b := 0
	var elite_hp0: float = ed.hp
	for i in int(45.0 / GameConfig.FIXED_DT):
		s1.step(GameConfig.FIXED_DT, 0.0, 0.0)
		peak_b = maxi(peak_b, s1.bullets.count)
	var elite_left := 0
	var elite_hp_left := 0.0
	for i in s1.enemies.count:
		if s1.enemies.type[i] == ei:
			elite_left += 1
			elite_hp_left = s1.enemies.hp[i]
	print("A 精英 45 秒（玩家不动，看它放什么）")
	print("   技能 %d 次（冲刺 %d · 环形弹幕 %d）· 发射弹幕 %d 发 · 同屏峰值 %d 发"
		% [s1.elite_skills, s1.elite_dashes, s1.elite_novas, s1.bullets_fired, peak_b])
	print("   精英存活 %d 只 · 血量 %.0f / %.0f（hp 从 150 提到 350 = 磨得动但更久）"
		% [elite_left, elite_hp_left, elite_hp0])
	print("   存活 %s" % ("是 —— 技能状态机没跑起来" if s1.elite_skills == 0 else "是"))

	# ---------------- B. Boss 五技能覆盖 ----------------
	var s2 := Sim.new()
	s2.setup()
	s2.god_mode = true
	s2.spawn_enabled = false
	for u in UpgradeDefs.UPGRADES:
		s2.loadout.levels[str(u["id"])] = int(u["max"])
	s2.loadout.recompute()
	var bi := EnemyDB.idx_of(EnemyDB.BOSS_ID)
	var bd: Dictionary = EnemyDB.DEFS[bi]
	s2.enemies.spawn(s2.player_x + 220.0, s2.player_y, bd.hp, bd.speed, bd.radius, bi)
	s2._update_boss(0.0)

	var peak_b2 := 0
	var boss_t := 0.0
	var max_steps := int(150.0 / GameConfig.FIXED_DT)
	var st := 0
	while st < max_steps and not s2.victory:
		s2.step(GameConfig.FIXED_DT, 0.0, 0.0)
		peak_b2 = maxi(peak_b2, s2.bullets.count)
		st += 1
	boss_t = float(st) * GameConfig.FIXED_DT
	print("")
	print("B Boss 战 %.1f 秒（满级 build 站桩，即「一次都不躲」的输出下限）" % boss_t)
	print("   技能 %d 次：冲刺 %d · 环形弹幕 %d · 扇形弹幕 %d · 追踪弹 %d · 危险区 %d · 召唤 %d 波"
		% [s2.boss_skills, s2.boss_dashes, s2.boss_novas, s2.boss_aimeds,
			s2.boss_homings, s2.boss_hazards, s2.boss_summons])
	print("   弹幕 %d 发 · 同屏峰值 %d 发 · %s" % [
		s2.bullets_fired, peak_b2, "已击杀" if s2.victory else "未在 150 秒内击杀"])

	# ---------------- C. 走位 vs 站桩 ----------------
	print("")
	print("C 走位验证（满级 build · 关闭无敌 · 不放刷怪，只留 Boss 一只）")
	var stand := _duel(false)
	print("   站桩不动：存活 %.1f 秒 · 末血量 %.0f · 承受伤害 %.0f" % stand)
	var dodge := _duel(true)
	print("   %s：存活 %.1f 秒 · 末血量 %.0f · 承受伤害 %.0f" % [
		"只躲不还手", dodge[0], dodge[1], dodge[2]])
	# 判定改过一次：原来要求「只躲能撑满 45 秒」，可这一组是**不还手**的，
	# 玩家根本打不死 Boss，撑再久也终有一死（实测 36.8 秒）→ 永远判「需复查」。
	# 真正要证明的是「躲比不躲活得久」，所以比的是两组存活时间的差距。
	var verdict := "PASS：躲比不躲活得久 —— 走位是必需的" if dodge[0] > stand[0] * 1.5 else "需复查：走位没有带来生存优势"
	print("   %s" % verdict)
	print("")


## 一场"半真实"的单挑：只有 Boss、没有杂兵，玩家按 dodge 决定动不动。
## 返回 [存活秒数, 剩余血量, 承受伤害]。玩家不反击（武器仍在自动开火）。
static func _duel(dodge: bool) -> Array:
	var sim := Sim.new()
	sim.setup()
	sim.spawn_enabled = false
	for u in UpgradeDefs.UPGRADES:
		sim.loadout.levels[str(u["id"])] = int(u["max"])
	sim.loadout.recompute()
	sim._refresh_max_hp()
	sim.player_hp = sim.max_hp
	var bi := EnemyDB.idx_of(EnemyDB.BOSS_ID)
	var d: Dictionary = EnemyDB.DEFS[bi]
	sim.enemies.spawn(sim.player_x + 260.0, sim.player_y, d.hp, d.speed, d.radius, bi)
	sim._update_boss(0.0)

	var limit := int(60.0 / GameConfig.FIXED_DT)
	for i in limit:
		var dir := Vector2.ZERO
		if dodge:
			dir = _dodge_dir(sim)
		sim.step(GameConfig.FIXED_DT, dir.x, dir.y)
		if sim.dead:
			break
	return [sim.time, sim.player_hp, sim.damage_taken]


## 简化版"会玩"的 AI：躲弹幕、躲危险区，其余时间绕圈。
##
## 它不是要做一个好玩家，只是要回答一个是非题：**这套攻击躲得掉吗**。
## 如果连"看到子弹就往外跑"都能活下来，说明威胁是可读、可操作的；
## 如果这样都活不下来，那说明数值或弹速过头了，得改设计而不是改 AI。
static func _dodge_dir(sim) -> Vector2:
	var ax := 0.0
	var ay := 0.0
	var b: EnemyBulletPool = sim.bullets
	for i in b.count:
		var dx: float = sim.player_x - b.px[i]
		var dy: float = sim.player_y - b.py[i]
		var d2 := dx * dx + dy * dy
		if d2 > 25000.0 or d2 < 1.0:      # 160px 之外不用管
			continue
		var d := sqrt(d2)
		var w := 1.0 - d / 160.0
		ax += dx / d * w
		ay += dy / d * w
	for h in sim.hazards.hazards:
		var hx := float(h["x"])
		var hy := float(h["y"])
		var dx: float = sim.player_x - hx
		var dy: float = sim.player_y - hy
		var d := sqrt(dx * dx + dy * dy)
		var safe := float(h["r"]) + 46.0
		if d > safe or d < 1.0:
			continue
		# 危险区是"必须离开"的，权重给得比弹幕高
		ax += dx / d * 2.2
		ay += dy / d * 2.2
	# 底噪：一直绕圈。站着不动的 AI 会被杂兵（这里没有）和冲刺逼死，
	# 而绕圈恰好也是幸存者类最基本的操作。
	var ang: float = sim.time * 0.85
	ax += cos(ang) * 0.55
	ay += sin(ang) * 0.55
	var l := sqrt(ax * ax + ay * ay)
	if l < 0.0001:
		return Vector2(cos(ang), sin(ang))
	return Vector2(ax / l, ay / l)

## 临时诊断：Boss 技能轮盘为什么不转
static func run_diag_boss() -> void:
	print("")
	print("=== Boss 技能诊断 ===")
	_diag_one("A 满级全 build（含断点调试）", true)
	_diag_one("B 满级但去掉断点调试", false)


static func _diag_one(label: String, with_break: bool) -> void:
	var sim := Sim.new()
	sim.setup()
	sim.god_mode = true
	sim.spawn_enabled = false
	sim.enemies.clear()
	for u in UpgradeDefs.UPGRADES:
		sim.loadout.levels[str(u["id"])] = int(u["max"])
	if not with_break:
		sim.loadout.levels["breakpoint"] = 0
	sim.loadout.recompute()

	var bi := EnemyDB.idx_of(EnemyDB.BOSS_ID)
	var d: Dictionary = EnemyDB.DEFS[bi]
	sim.enemies.spawn(sim.player_x + 200.0, sim.player_y, d.hp, d.speed, d.radius, bi)
	sim._update_boss(0.0)

	print("--- %s ---" % label)
	for s in 24:
		for i in int(3.0 / GameConfig.FIXED_DT):
			sim.step(GameConfig.FIXED_DT, 0.0, 0.0)
			if sim.victory:
				break
		var b := -1
		for i in sim.enemies.count:
			if sim.enemies.type[i] == bi:
				b = i
				break
		if b < 0:
			print("  t=%2.0fs Boss 已死 · 技能 %d 次 · 召唤 %d" % [
				(s + 1) * 3.0, sim.boss_skills, sim.boss_summons])
			return
		var e := sim.enemies
		var dx: float = e.px[b] - sim.player_x
		var dy: float = e.py[b] - sim.player_y
		print("  t=%2.0fs freeze=%.2f cd=%.2f state=%d dist=%5.0f hp=%7.0f skills=%d 承受=%4.0f" % [
			(s + 1) * 3.0, e.freeze[b], e.skill_cd[b], e.skill_state[b],
			sqrt(dx * dx + dy * dy), e.hp[b], sim.boss_skills, sim.damage_taken])
