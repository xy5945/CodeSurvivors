extends Node2D
##
## 主场景：唯一持有"帧"的地方。
## 职责只有三件：采样输入 → 驱动仿真 → 把数据同步给表现层。
## 所有玩法逻辑都在 core/sim.gd 里，这里不放任何规则。
##

@onready var enemy_renderer: Node2D = $EnemyRenderer
@onready var gem_renderer: Node2D = $GemRenderer
@onready var orbit_renderer: Node2D = $OrbitRenderer
@onready var projectile_renderer: Node2D = $ProjectileRenderer
@onready var enemy_bullet_renderer: Node2D = $EnemyBulletRenderer
@onready var fx_renderer: Node2D = $FxRenderer
@onready var bolt_renderer: Node2D = $BoltRenderer
@onready var whip_arc: Node2D = $WhipArc
@onready var player_view: PlayerView = $PlayerView
@onready var camera: Camera2D = $Camera2D
@onready var hud: HUD = $HUD
@onready var level_up: LevelUpUI = $LevelUpUI
@onready var knowledge: KnowledgeUI = $KnowledgeUI
@onready var vignette: DamageVignette = $DamageVignette

var sim: Sim
var _acc := 0.0
# 截图模式：跑够帧数后把真实画面存盘，用于验证渲染朝向这类 headless 测不到的东西。
# 运行（非 headless）：godot --path . -- --shot
var _shot_countdown := 0
# --nolv：禁止升级弹窗弹出。截图模式专用 —— 弹窗会暂停整棵树，--shot 就废了
var _nolv := false

# ---- 音效的状态跟踪 ----
# 武器开火是"事件队列"（仿真层 push、这里消费），下面这些则是"状态变化"：
# 仿真层只提供了累计计数和状态位，要发声就得自己比前后帧的差值。
var _prev_kills := 0
var _prev_gems := 0
var _prev_patches := 0
var _prev_chests := 0
var _prev_hp := 0.0
var _was_dead := false
var _was_victory := false
var _was_boss := false


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--bench"):
		set_process(false)      # quit() 不会立刻生效，否则 _process 会跑几帧空指针
		Bench.run()
		get_tree().quit()
		return

	if OS.get_cmdline_user_args().has("--wpntest"):
		set_process(false)
		WeaponTest.run()
		get_tree().quit()
		return

	if OS.get_cmdline_user_args().has("--dpstest"):
		set_process(false)
		WeaponTest.run_single()
		get_tree().quit()
		return

	for a in OS.get_cmdline_user_args():
		if a.begins_with("--standtest"):
			set_process(false)
			if a == "--standtest=late":
				Bench.run_stand_late()
			else:
				Bench.run_stand()
			get_tree().quit()
			return

	if OS.get_cmdline_user_args().has("--survival"):
		set_process(false)
		Bench.run_survival(20.0)
		get_tree().quit()
		return

	if OS.get_cmdline_user_args().has("--chesttest"):
		set_process(false)
		Bench.run_chest_test()
		get_tree().quit()
		return

	if OS.get_cmdline_user_args().has("--skilltest"):
		set_process(false)
		Bench.run_skill_test()
		get_tree().quit()
		return

	if OS.get_cmdline_user_args().has("--bosstest"):
		set_process(false)
		Bench.run_boss_test()
		get_tree().quit()
		return

	# --smoke 可带分钟数：--smoke=20（跑到 18 分钟验证 Boss 自然出场）
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--smoke"):
			set_process(false)
			Bench.run_smoke(float(a.split("=")[-1]) if "=" in a else 10.0)
			get_tree().quit()
			return

	# --cardcov：知识卡覆盖率，跑三种典型局看一局能解锁几张卡
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cardcov"):
			set_process(false)
			Bench.run_card_coverage(float(a.split("=")[-1]) if "=" in a else 20.0)
			get_tree().quit()
			return

	randomize()
	# 竞技场外是"虚空"：纯近黑，和场内那块通电的深蓝地板形成色阶。
	# 这一层色差是边界可读性的第一道保险（第二道是 grid_bg 里的霓虹墙）。
	RenderingServer.set_default_clear_color(Color(0.004, 0.006, 0.013))
	# 游戏中隐藏光标：它会挡视线、破坏沉浸感。升级弹窗打开时再显示。
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

	sim = Sim.new()
	sim.setup()

	# --pos=<x>,<y>：把玩家挪到指定坐标再开局，配合 --shot 截特定位置的画面
	#（例如 --pos=1340,0 截边界墙）。只影响开局位置，不参与正式玩法。
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pos="):
			var p := a.substr(6).split(",")
			if p.size() == 2:
				sim.player_x = clampf(float(p[0]), -GameConfig.ARENA_HALF, GameConfig.ARENA_HALF)
				sim.player_y = clampf(float(p[1]), -GameConfig.ARENA_HALF, GameConfig.ARENA_HALF)

	enemy_renderer.setup(GameConfig.MAX_ENEMIES)
	gem_renderer.setup(GameConfig.MAX_GEMS)
	player_view.setup()
	orbit_renderer.setup()
	projectile_renderer.setup(GameConfig.MAX_PROJECTILES)
	enemy_bullet_renderer.setup(GameConfig.MAX_ENEMY_BULLETS)
	fx_renderer.sim = sim
	bolt_renderer.sim = sim
	whip_arc.sim = sim
	level_up.sim = sim
	level_up.resolved.connect(_on_levelup_resolved)

	camera.position = Vector2(sim.player_x, sim.player_y)
	_sync_player(0.0, false)

	# 开局先送两张：起始武器（分支长鞭 → if 分支）和"变量"（经验宝石）。
	# 它们是整局教学的第一课，也是玩家唯一一次"没做任何事就看到"的卡。
	# 起始武器不硬编码 whip —— 以后加了角色系统、起始武器换了，这里自动跟着变。
	for id in sim.loadout.levels:
		if sim.loadout.level_of(id) > 0:
			knowledge.push(id)
	knowledge.push("gem")

	if OS.get_cmdline_user_args().has("--opening"):
		set_process(false)
		Bench.run_opening()
		get_tree().quit()
		return

	if OS.get_cmdline_user_args().has("--cardtest"):
		set_process(false)
		_cardtest()
		get_tree().quit()
		return

	if OS.get_cmdline_user_args().has("--uitest"):
		set_process(false)
		_uitest()
		get_tree().quit()
		return

	# --shot 可带帧数：godot --path . -- --shot=10（截开局空场，适合看玩家本身）
	var shot_arg := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot"):
			shot_arg = a
	if shot_arg != "":
		_shot_countdown = int(shot_arg.split("=")[-1]) if "=" in shot_arg else 300
	if OS.get_cmdline_user_args().has("--nolv"):
		_nolv = true
		# --give=<升级id>：直接把某项拉满，用来截特定武器/特效的画面
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--give="):
				var gid := a.substr(7)
				for u in UpgradeDefs.UPGRADES:
					if str(u["id"]) == gid:
						sim.loadout.levels[gid] = int(u["max"])
				sim.loadout.recompute()
		# --spawn=<敌人id>：在玩家周围摆一圈指定敌人，配合 --shot 验证美术
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--spawn="):
				var ei := EnemyDB.idx_of(a.substr(8))
				if ei >= 0:
					var d: Dictionary = EnemyDB.DEFS[ei]
					for k in 12:
						var ang := TAU * float(k) / 12.0
						sim.enemies.spawn(
							sim.player_x + cos(ang) * 90.0,
							sim.player_y + sin(ang) * 90.0,
							d.hp, 0.0, d.radius, ei
						)


##
## 升级弹窗的无头验证。UI 是最容易出运行时错误的地方（样式 API、枚举名、
## 字典取值），而它在 headless 下不会被执行到，所以单独开一条测试路径。
## 运行：godot --headless --path . -- --uitest
##
func _uitest() -> void:
	print("")
	print("=== 升级弹窗 · 无头测试 ===")

	sim.pending_levelups = 1
	level_up.open(sim)
	print("打开后 → 可见 %s · 游戏暂停 %s" % [level_up.visible, get_tree().paused])

	for c in level_up._cards:
		var card := c as UpgradeCard
		var levels: Array = card.def["levels"]
		var desc := str(levels[mini(card.target_level, levels.size()) - 1]["desc"])
		print("  卡片 [%s] %s  Lv%d  %s" % [
			card.def["icon"], card.def["name"], card.target_level, desc
		])

	# 模拟用鼠标点第一张卡
	level_up._cards[0].picked.emit(level_up._cards[0])
	print("点第一张 → 剩余升级次数 %d · 暂停 %s · 可见 %s" % [
		sim.pending_levelups, get_tree().paused, level_up.visible
	])

	# 连升两级：验证弹窗会连续刷新而不是直接关闭
	sim.pending_levelups = 2
	level_up.open(sim)
	level_up._cards[0].picked.emit(level_up._cards[0])
	print("连升两级 · 第一次选完 → 剩余 %d · 仍可见 %s" % [
		sim.pending_levelups, level_up.visible
	])
	level_up._cards[0].picked.emit(level_up._cards[0])
	print("第二次选完 → 剩余 %d · 已关闭 %s" % [
		sim.pending_levelups, not level_up.visible
	])

	# 打满所有升级项，验证兜底选项不会出现空卡片
	for u in UpgradeDefs.UPGRADES:
		sim.loadout.levels[u["id"]] = int(u["max"])
	sim.loadout.recompute()
	var last := sim.loadout.roll_choices(3)
	print("全满级后抽 3 张 → %s" % [
		", ".join(last.map(func(c): return str(c["def"]["name"])))
	])
	print("")


##
## 知识卡无头测试。运行：godot --headless --path . -- --cardtest
##
## 查五件事，任何一项挂掉都算没做完：
##   A 完整性 —— 每把武器/被动、每种敌人都配了卡。忘了配 = 这块内容永远不教学
##   B 长度   —— 超长文案会撑爆 250x130 的卡片排版（这个尺寸是算过的）
##   C 引号   —— 文案里出现 ASCII 双引号，将来导出 markdown 会错位
##   D 去重   —— 同一张卡反复触发只弹一次
##   E 队列   —— 连着触发多张时逐张播放，不叠成一摞、也不丢
##
func _cardtest() -> void:
	print("")
	print("=== 知识卡 · 无头测试 ===")
	print("卡片总数 %d" % KnowledgeDB.total())

	# ---- A 完整性 ----
	var missing := KnowledgeDB.missing_cards()
	if missing.size() > 0:
		print("  [A 缺卡] %s" % ", ".join(missing))
	else:
		print("  A 完整性 OK · %d 升级项 + %d 敌人 全部配了卡" % [
			UpgradeDefs.UPGRADES.size(), EnemyDB.DEFS.size()
		])

	# ---- B / C 逐张检查文案 ----
	var long_plain := 0
	var long_use := 0
	var bad_quote := 0
	for c in KnowledgeDB.CARDS:
		if str(c["plain"]).length() > 20:
			long_plain += 1
			print("    [B 过长] %s · plain %d 字" % [c["term"], str(c["plain"]).length()])
		if str(c["use"]).length() > 24:
			long_use += 1
			print("    [B 过长] %s · use %d 字" % [c["term"], str(c["use"]).length()])
		for k in ["term", "code", "plain", "use"]:
			if str(c[k]).contains("\""):
				bad_quote += 1
				print("    [C 引号] %s · %s 含 ASCII 双引号" % [c["term"], k])
	if long_plain + long_use == 0:
		print("  B 长度 OK · 全部在卡片容量内")
	if bad_quote == 0:
		print("  C 引号 OK · 无 ASCII 双引号")

	# ---- D 去重 ----
	knowledge.debug_reset()
	knowledge.push("whip")
	knowledge.push("whip")
	knowledge.push("whip")
	var dup: int = knowledge.debug_snapshot()["unlocked"]
	print("  D 去重 %s · 同一张 push 3 次 → 解锁 %d 张" % [
		"OK" if dup == 1 else "FAIL", dup
	])

	# ---- E 队列与停留时长 ----
	knowledge.debug_reset()
	for id in ["whip", "orbit", "gem", "virus", "boss_compiler"]:
		knowledge.push(id)
	var last := ""
	var t := 0.0
	var t_show := 0.0
	var lines: Array[String] = []
	for _f in 60 * 60:
		knowledge.update(1.0 / 60.0)
		t += 1.0 / 60.0
		var cur: String = str(knowledge.debug_snapshot()["cur"])
		if cur == last:
			continue
		if last != "":
			lines.append("      %-14s 显示 %.1f 秒" % [last, t - t_show])
		if cur == "":
			break
		t_show = t
		last = cur
	print("  E 队列 · 连开 5 张（首张延迟 1.2 秒，让玩家先动起来）：")
	for l in lines:
		print(l)

	# ---- F 图鉴：开/关与暂停状态 ----
	knowledge.debug_reset()
	for id in ["whip", "gem", "error_red"]:
		knowledge.push(id)
	knowledge._open_codex()
	var f1: bool = get_tree().paused and knowledge._codex.visible
	knowledge._page = 1
	knowledge._refresh_codex()
	knowledge._close_codex()
	var f2: bool = not get_tree().paused and not knowledge._codex.visible
	print("  F 图鉴 %s · 打开暂停=%s 关闭恢复=%s" % [
		"OK" if f1 and f2 else "FAIL", f1, f2
	])

	# ---- 导出（这套文案要能直接拿去做课件，所以落到工作区根目录而不是 user://）----
	var out := "res://../知识卡-课件表.md"
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		out = "user://knowledge_cards.md"      # 上一条被拒时（导出后的包里）退回用户目录
		f = FileAccess.open(out, FileAccess.WRITE)
	if f != null:
		f.store_string(KnowledgeDB.to_markdown())
		f.close()
		print("  已导出课件表: " + ProjectSettings.globalize_path(out))
	print("")


func _process(delta: float) -> void:
	# Input.get_vector 自带对角线归一化，斜向不会比直线快 1.41 倍。
	# 参数顺序是 (neg_x, pos_x, neg_y, pos_y) = (left, right, up, down)，写反了方向会全乱。
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")

	_acc += minf(delta, 0.25)
	var steps := 0
	while _acc >= GameConfig.FIXED_DT and steps < GameConfig.MAX_STEPS_PER_FRAME:
		sim.step(GameConfig.FIXED_DT, dir.x, dir.y)
		# 必须紧跟 step 消费：下一个 step 开头会清空队列
		_drain_sfx()
		_drain_cards()
		_acc -= GameConfig.FIXED_DT
		steps += 1
	if steps >= GameConfig.MAX_STEPS_PER_FRAME:
		_acc = 0.0      # 追不上就丢弃，避免死亡螺旋

	enemy_renderer.sync(sim.enemies, sim.player_x)
	gem_renderer.sync(sim.gems, delta)
	orbit_renderer.sync(sim.loadout.orbit)
	projectile_renderer.sync(sim.projectiles)
	enemy_bullet_renderer.sync(sim.bullets)
	_sync_player(delta, dir.length_squared() > 0.0)
	camera.position = Vector2(sim.player_x, sim.player_y)
	hud.update_stats(delta, sim)
	vignette.update_fx(delta, sim)
	knowledge.update(delta)
	_sync_audio()

	# 升级弹窗：放在最后，本帧的仿真已经跑完。
	# --nolv：截图模式专用。弹窗一开游戏就暂停，--shot 永远等不到目标帧。
	if not _nolv and not sim.dead and sim.pending_levelups > 0 and not level_up.visible:
		level_up.open(sim)
		Sfx.play("levelup")

	if _shot_countdown > 0:
		_shot_countdown -= 1
		if _shot_countdown == 0:
			var path := "user://shot.png"
			get_viewport().get_texture().get_image().save_png(path)
			print("截已保存: " + ProjectSettings.globalize_path(path))
			get_tree().quit()


func _sync_player(dt: float, moving: bool) -> void:
	var p := Vector2(sim.player_x, sim.player_y)
	player_view.position = p
	player_view.update_view(dt, moving, sim.facing_x, sim.iframe)
	# WhipArc 的 _draw 以本地原点为中心画扇形，必须跟着玩家走。
	# 忘了这一行的话：开局第一刀可见（玩家还在原点），一移动就再也看不到。
	whip_arc.position = p


## 消费仿真层这一帧攒下的音效事件（武器开火、Boss 召唤）。
## 仿真层只给事件名，这里负责交给 Sfx —— 仿真层永远不碰 AudioServer。
func _drain_sfx() -> void:
	for evt in sim.sfx_events:
		Sfx.play(evt)
	sim.sfx_events.clear()


## 知识卡事件：仿真层只说"这一帧首次遇到了什么"，排队和显示交给 KnowledgeUI。
## 队列由**这里**清空，不在 sim.step 里清 —— 升级弹窗里点出来的事件发生在 step
## 之后，step 一清就丢了（武器卡曾经全部弹不出来，就是栽在这）。
func _drain_cards() -> void:
	if sim.card_events.is_empty():
		return
	for id in sim.card_events:
		knowledge.push(id)
	sim.card_events.clear()


## 状态变化类音效：靠比前后帧的累计计数和状态位来发现。
## 一帧杀 40 个敌人也只请求一次 —— 密集触发由 Sfx 内部的节流兜底，
## 这里每类事件每帧最多一次，免得同一帧堆出几十个播放请求抢声道。
func _sync_audio() -> void:
	if sim.kills > _prev_kills:
		Sfx.play("kill")
	if sim.gems_collected > _prev_gems:
		Sfx.play("pickup")
	if sim.patches_collected > _prev_patches:
		Sfx.play("heal")
		knowledge.push("patch")
	if sim.chests_collected > _prev_chests:
		Sfx.play("chest")
		knowledge.push("chest")
	if sim.player_hp < _prev_hp - 0.001:
		Sfx.play("hurt")

	_prev_kills = sim.kills
	_prev_gems = sim.gems_collected
	_prev_patches = sim.patches_collected
	_prev_chests = sim.chests_collected
	_prev_hp = sim.player_hp

	# 三个一次性事件：只在状态从"没发生"跳到"发生"的那一帧响
	if sim.boss_active and not _was_boss:
		Sfx.play("boss")
		Sfx.set_boss_mode(true)
	if sim.victory and not _was_victory:
		Sfx.play("victory")
	if sim.dead and not _was_dead:
		Sfx.play("death")
		Sfx.stop_bgm()

	_was_boss = sim.boss_active
	_was_victory = sim.victory
	_was_dead = sim.dead


## 弹窗关闭后清掉累积时间，否则暂停期间攒下的 delta 会让仿真瞬间连跑好几步
func _on_levelup_resolved() -> void:
	_acc = 0.0
