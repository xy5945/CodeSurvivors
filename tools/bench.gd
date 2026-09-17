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
	print("技能：精英冲刺 %d · Boss 冲刺 %d · Boss 召唤 %d 波（全程为 0 = 技能没跑起来）" % [
		sim.elite_dashes, sim.boss_dashes, sim.boss_summons
	])
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
	print("技能统计：Boss 冲刺 %d 次 · 召唤 %d 波 · 场上小怪 %d（召唤切后排的验证）" % [
		sim.boss_dashes, sim.boss_summons, sim.enemies.count
	])

	if sim.victory and chests_on_ground + sim.chests_collected >= 3:
		var skills_ok := sim.boss_dashes >= 1 and sim.boss_summons >= 1
		print("PASS：Boss 出场 → 血条数据 → 击杀 → 宝箱掉落 → 通关判定，链路完整"
			+ ("" if skills_ok else "，但技能一次没放（FAIL 项）"))
		if not skills_ok:
			print("FAIL：Boss 冲刺/召唤一次都没触发 —— 技能状态机没跑起来")
			return
		var ok_sec := t > 8.0 and t < 75.0
		print("决战时长 %s（期望 8~75 秒：太短没有压迫感，太长变磨血）" % ("合适" if ok_sec else "需调整血量"))
	else:
		print("FAIL：Boss 链路有断点（没打死或没掉宝箱）")
