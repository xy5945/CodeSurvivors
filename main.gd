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
@onready var aura_renderer: Node2D = $AuraRenderer
@onready var bolt_renderer: Node2D = $BoltRenderer
@onready var whip_arc: Node2D = $WhipArc
@onready var player_view: PlayerView = $PlayerView
@onready var camera: Camera2D = $Camera2D
@onready var hud: HUD = $HUD
@onready var level_up: LevelUpUI = $LevelUpUI
@onready var knowledge: KnowledgeUI = $KnowledgeUI
@onready var result: ResultUI = $ResultUI
@onready var char_select: CharSelectUI = $CharSelectUI
@onready var title: TitleUI = $TitleUI
@onready var pause: PauseUI = $PauseUI
@onready var help: HelpUI = $HelpUI
@onready var about: AboutUI = $AboutUI
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
var _prev_self_dmg := 0.0   # 永真力场的自伤累计，用来把"自己掉的血"从受伤音效里剔除
var _was_dead := false
var _was_victory := false
var _was_boss := false
# 一局结束（死亡/通关）到弹结算之间的倒计时；<0 表示还没结束
var _end_delay := -1.0
# 通关解锁：一局只记一次（_update_end 每帧都会被调，不能重复记账）
var _unlock_recorded := false
var _unlock_msg := ""
# 带命令行参数启动的都是测试/截图，不该把解锁进度写进玩家真档
# （--resulttest 会造一个假的通关，不拦住它就会白白解锁一个角色）
var _no_save := false


func _ready() -> void:
	# 读存档：解锁到第几个角色。必须在最前面 —— 选人界面和结算都依赖它，
	# 而它是 static 的，重载场景（重开 / 退出回标题）不会自己重置。
	SaveData.load_game()
	# 只要带了参数就是测试/截图流程，解锁一律不落盘
	_no_save = not OS.get_cmdline_user_args().is_empty()

	if OS.get_cmdline_user_args().has("--bench"):
		set_process(false)      # quit() 不会立刻生效，否则 _process 会跑几帧空指针
		Bench.run()
		get_tree().quit()
		return

	if OS.get_cmdline_user_args().has("--dmgtab"):
		set_process(false)
		Bench.run_dmg_table()
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

	if OS.get_cmdline_user_args().has("--diagboss"):
		set_process(false)
		Bench.run_diag_boss()
		get_tree().quit()
		return

	# --smoke 可带分钟数：--smoke=20（跑到 18 分钟验证 Boss 自然出场）
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--smoke"):
			set_process(false)
			Bench.run_smoke(float(a.split("=")[-1]) if "=" in a else 10.0, _cmd_char())
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
	sim.setup(_cmd_char())

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
	player_view.setup(sim.char_def["color"])
	orbit_renderer.setup()
	projectile_renderer.setup(GameConfig.MAX_PROJECTILES)
	enemy_bullet_renderer.setup(GameConfig.MAX_ENEMY_BULLETS)
	fx_renderer.sim = sim
	aura_renderer.sim = sim
	bolt_renderer.sim = sim
	whip_arc.sim = sim
	level_up.sim = sim
	level_up.resolved.connect(_on_levelup_resolved)
	result.restart_requested.connect(_on_restart)
	result.quit_requested.connect(_on_quit)
	char_select.selected.connect(_on_char_selected)
	char_select.back_requested.connect(_on_char_back)
	title.start_requested.connect(_on_title_start)
	title.help_requested.connect(_on_title_help)
	title.about_requested.connect(_on_title_about)
	pause.resume_requested.connect(_on_pause_resume)
	pause.help_requested.connect(_on_pause_help)
	pause.quit_requested.connect(_on_pause_quit)
	help.back_requested.connect(_on_help_back)
	# about 的返回语义和 help 完全一样：从哪来回哪去
	about.back_requested.connect(_on_help_back)

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

	if OS.get_cmdline_user_args().has("--resulttest"):
		set_process(false)
		_resulttest()
		get_tree().quit()
		return

	# --resultlayout：开面板后**等两帧**再量真实布局。
	# 同步量到的只是"最小尺寸"，排版要等容器真正 sort 过才算数 ——
	# 玩家看到的是等过帧之后的那一版，所以必须单独验一次。
	if OS.get_cmdline_user_args().has("--resultlayout"):
		_set_gameplay_ui(false)
		for case in [["满配+解锁", true, "测试工程师", true],
				["满配无解锁", true, "", true], ["空 Build", false, "", false]]:
			for u in UpgradeDefs.UPGRADES:
				sim.loadout.levels[str(u["id"])] = int(u["max"]) if bool(case[3]) else 0
			sim.loadout.recompute()
			sim.victory = bool(case[1])
			sim.dead = not bool(case[1])
			result.debug_reset()
			result.open(sim, knowledge.unlocked_count(), KnowledgeDB.total(), str(case[2]))
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var lay2: Dictionary = result.debug_layout()
			var pr2: Rect2 = lay2["panel"]
			var br2: Rect2 = lay2["buttons"]
			var lr2: Rect2 = lay2["build"]
			var ok2: bool = (br2.end.y <= pr2.end.y + 0.6 and lr2.end.y <= pr2.end.y + 0.6
				and pr2.position.y >= -0.6 and pr2.end.y <= 360.6)
			print("[layout] %s · 面板 y=%.1f h=%.1f · 按钮底 %.1f / 面板底 %.1f%s · %s" % [
				case[0], pr2.position.y, pr2.size.y, br2.end.y, pr2.end.y,
				" · 紧凑" if bool(lay2["compact"]) else "", "OK" if ok2 else "FAIL"])
		get_tree().quit()
		return

	# --resultshot=win|lose：直接开结算面板截图（结算会暂停整棵树，
	# --shot 的倒计时在暂停时跑不动，所以单独给一条路径）
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--resultshot"):
			var win := a != "--resultshot=lose"
			sim.time = 1103.0 if win else 407.0
			sim.kills = 4821 if win else 936
			sim.level = 58 if win else 19
			sim.gems_collected = 3200 if win else 640
			sim.patches_collected = 11
			sim.chests_collected = 4 if win else 1
			sim.victory = win
			sim.dead = not win
			# 满配 Build：结算面板的 Build 行会换行，截图要能看到换行后的排版
			for u in UpgradeDefs.UPGRADES:
				sim.loadout.levels[str(u["id"])] = int(u["max"])
			sim.loadout.recompute()
			for id in sim.loadout.levels:
				if sim.loadout.level_of(id) > 0:
					knowledge.push(id)
			knowledge.push("gem")
			knowledge.push("whip")
			result.open(sim, knowledge.unlocked_count(), KnowledgeDB.total(),
				"测试工程师" if win else "")
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			_save_shot()
			get_tree().quit()
			return

	# --charshot[=解锁数]：选人界面截图。默认解锁 1 个，=3 就能看到
	# 2 张锁着的卡片（灰底 + 未解锁 + 解锁条件）长什么样
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--charshot"):
			_set_gameplay_ui(false)
			var n := int(a.split("=")[-1]) if "=" in a else 1
			n = clampi(n, 1, CharDefs.CHARACTERS.size())
			SaveData.loaded = false
			SaveData.test_path = "user://_shot_save.cfg"
			SaveData.reset_all()
			for i in n - 1:
				SaveData.mark_cleared(str(CharDefs.CHARACTERS[i]["id"]))
			char_select.open()
			SaveData.test_path = ""
			SaveData.loaded = false
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			_save_shot()
			get_tree().quit()
			return

	# --titleshot：开标题画面截图
	if OS.get_cmdline_user_args().has("--titleshot"):
		_set_gameplay_ui(false)
		title.open()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		_save_shot()
		get_tree().quit()
		return

	# --aboutshot：品牌页（关于本作品）截图。落款、版权声明的排版只能靠眼睛看
	if OS.get_cmdline_user_args().has("--aboutshot"):
		_set_gameplay_ui(false)
		about.open("title")
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		_save_shot()
		get_tree().quit()
		return

	# --helpshot=<页号 0~3>：游戏说明截图。排版只能靠眼睛看，headless 测不出来
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--helpshot"):
			var pno := int(a.split("=")[-1]) if "=" in a else 0
			_set_gameplay_ui(false)
			help.open("title")
			help.show_page(pno)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			_save_shot()
			get_tree().quit()
			return

	# --lvshot[=<武器id>]：升级弹窗截图。卡面排版（含"专属"角标会不会撑破卡片）
	# 只能靠眼睛看。不传 id 就随机抽，传了就强制第一张卡是该武器。
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lvshot"):
			var wid := a.split("=")[-1] if "=" in a else ""
			sim.pending_levelups = 1
			level_up.open(sim)
			if wid != "":
				level_up._cards[0].setup(UpgradeDefs.def_of(wid), 2)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			_save_shot()
			get_tree().quit()
			return

	# --pauseshot：暂停界面截图
	if OS.get_cmdline_user_args().has("--pauseshot"):
		pause.open()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		_save_shot()
		get_tree().quit()
		return

	# --charshot[=<角色id>]：开选人界面截图（选人会暂停整棵树，
	# --shot 的倒计时跑不动，所以和结算一样单独给一条路径）
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--charshot"):
			var cid := a.split("=")[-1] if "=" in a else ""
			char_select.open(cid)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			_save_shot()
			get_tree().quit()
			return

	if OS.get_cmdline_user_args().has("--evotest"):
		set_process(false)
		Bench.run_evo()
		get_tree().quit()
		return

	if OS.get_cmdline_user_args().has("--chartest"):
		set_process(false)
		Bench.run_char()
		get_tree().quit()
		return

	if OS.get_cmdline_user_args().has("--wpn6test"):
		set_process(false)
		Bench.run_wpn6()
		get_tree().quit()
		return

	# --savetest：角色解锁链 + 难度系数自检（用临时存档，不碰玩家真档）
	if OS.get_cmdline_user_args().has("--savetest"):
		set_process(false)
		Bench.run_save()
		get_tree().quit()
		return

	# --unlockall / --resetunlock：开发用。想直接看后面的角色时不用重打一遍。
	if OS.get_cmdline_user_args().has("--unlockall"):
		SaveData.load_game()
		SaveData.unlock_all()
		print("[SaveData] 已全解锁 %d/%d 个角色" % [SaveData.unlocked_count(), CharDefs.CHARACTERS.size()])
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--resetunlock"):
		SaveData.load_game()
		SaveData.reset_all()
		print("[SaveData] 已清档，回到只解锁第 1 个角色")
		get_tree().quit()
		return

	if OS.get_cmdline_user_args().has("--uitest"):
		set_process(false)
		_uitest()
		get_tree().quit()
		return

	if OS.get_cmdline_user_args().has("--tunetest"):
		set_process(false)
		Bench.run_tune()
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
				if EvolveDefs.is_evo_id(gid):
					# 直接给进化：进化要先把武器/被动刷满，手点太慢
					var ed := EvolveDefs.def_of(gid)
					if not ed.is_empty():
						sim.loadout.levels[str(ed["base"])] = 							int(UpgradeDefs.def_of(str(ed["base"]))["max"])
						sim.loadout.levels[str(ed["passive"])] = 							int(UpgradeDefs.def_of(str(ed["passive"]))["max"])
				else:
					for u in UpgradeDefs.UPGRADES:
						if str(u["id"]) == gid:
							sim.loadout.levels[gid] = int(u["max"])
				sim.loadout.recompute()
				if EvolveDefs.is_evo_id(gid):
					sim.loadout.apply_evolution(gid)
		# --dropchest：在玩家旁边摆一个宝箱，配合 --shot 验证宝箱美术
	#（宝箱只能靠击杀精英获得，手点太慢，截图需要一条直达路径）
	if OS.get_cmdline_user_args().has("--dropchest"):
		sim.gems.spawn_chest(sim.player_x + 70.0, sim.player_y)

	# --spawn=<敌人id>：在玩家周围摆一圈指定敌人，配合 --shot 验证美术。
	# 缩进教训：这个 for 曾经多缩进一层，被解析进上面 --dropchest 的分支体里，
	# 结果 --spawn 单独传时静默无效（一圈敌人一个都不出来），必须两个参数一起传才行。
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

	# 正常开局（一个命令行参数都没有）→ 标题 → 选角色 → 开打。
	# 带参数的启动一律直接开局：headless 测试和截图流程不能被弹窗挡住。
	if OS.get_cmdline_user_args().is_empty():
		# 血条、武器栏、受击红光都是"对局中"的东西，标题和选人阶段不该露出来
		# （之前标题页左上角一直挂着一条空血条，像渲染残影）。
		_set_gameplay_ui(false)
		title.open()


## 游戏内常驻 UI（血条 / 武器栏 / 受击红光）的统一开关。
## 只在"标题 ↔ 对局"两个状态间切换，暂停和弹窗不动它们 ——
## 暂停时玩家正要盯着血条决定要不要喝口药。
func _set_gameplay_ui(on: bool) -> void:
	hud.visible = on
	vignette.visible = on


## 标题画面点掉之后进选人。
func _on_title_start() -> void:
	char_select.open()


## --char=<角色id>：跳过选人直接开局（测试与截图用）。
func _cmd_char() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--char="):
			return a.substr(7)
	return CharDefs.DEFAULT_ID


## 换角色后重建一局。只有真的换了角色才需要重建 ——
## 选人界面默认就停在上一局那个角色上，直接确认时什么都不用做。
func _on_char_selected(cid: String) -> void:
	_set_gameplay_ui(true)
	if cid == sim.char_id:
		return
	sim = Sim.new()
	sim.setup(cid)
	fx_renderer.sim = sim
	aura_renderer.sim = sim
	bolt_renderer.sim = sim
	whip_arc.sim = sim
	level_up.sim = sim
	player_view.setup(sim.char_def["color"])
	knowledge.debug_reset()
	for id in sim.loadout.levels:
		if sim.loadout.level_of(id) > 0:
			knowledge.push(id)
	knowledge.push("gem")
	camera.position = Vector2(sim.player_x, sim.player_y)
	_sync_player(0.0, false)


##
## 升级弹窗的无头验证。UI 是最容易出运行时错误的地方（样式 API、枚举名、
## 字典取值），而它在 headless 下不会被执行到，所以单独开一条测试路径。
## 运行：godot --headless --path . -- --uitest
##
## 结算界面自检：结算是这个游戏"能拿给别人玩"的最后一块，
## 死在这里最尴尬 —— 玩家打完一局看到的是静止画面，不知道自己赢了没有。
##
## 运行：godot --headless --path . -- --resulttest
func _resulttest() -> void:
	print("")
	print("=== 结算界面 ===")

	# A 死亡流程：结束后不该同帧弹面板（死亡音和红光要看得到）
	sim.time = 275.0
	sim.kills = 1234
	sim.level = 21
	sim.gems_collected = 890
	sim.patches_collected = 7
	sim.chests_collected = 2
	knowledge.push("whip")
	knowledge.push("gem")
	sim.dead = true
	_update_end(0.016)
	var same_frame := result.is_open()
	_update_end(1.0)
	_update_end(1.0)
	print("  A 死亡 · 同帧不弹=%s · 1.4 秒后打开=%s · 暂停=%s" % [
		"OK" if not same_frame else "FAIL",
		"OK" if result.is_open() else "FAIL",
		"OK" if get_tree().paused else "FAIL"])
	print("     标题 %s" % result._title.text)
	print("     %s" % _row_texts())

	# B 通关流程：同一套面板，标题和数据要跟着变
	result.debug_reset()
	sim.dead = false
	sim.victory = true
	_end_delay = -1.0
	_update_end(0.016)
	_update_end(1.0)
	_update_end(1.0)
	print("  B 通关 · 打开=%s · 标题 %s" % [
		"OK" if result.is_open() else "FAIL", result._title.text])

	# C 两个按钮的信号（暂停时点得到，是结算能不能用的前提）
	# 先摘掉 main 自己的两个槽：在 _ready 里真的 reload 场景 / quit 会炸，
	# 这里只验证"按钮按下去信号能出来"，真正的重开逻辑靠实机验证。
	result.restart_requested.disconnect(_on_restart)
	result.quit_requested.disconnect(_on_quit)
	var hits := [false, false]
	result.restart_requested.connect(func() -> void: hits[0] = true, CONNECT_ONE_SHOT)
	result.quit_requested.connect(func() -> void: hits[1] = true, CONNECT_ONE_SHOT)
	_click_button(0)
	_click_button(1)
	print("  C 按钮 · 再来一局=%s · 退出=%s" % [
		"OK" if hits[0] else "FAIL", "OK" if hits[1] else "FAIL"])

	# E 布局：内容不能溢出面板 —— 面板是手工排的，Godot 对溢出既不裁剪也不报错，
	# 只能量数字。重点看最底下的按钮行：它一旦被顶出面板底边，
	# 玩家看到的就是"按钮和面板重叠"。
	for case in [["满配+解锁", true, "测试工程师", true], ["满配无解锁", true, "", true], ["空 Build", false, "", false]]:
		result.debug_reset()
		sim.victory = bool(case[1])
		sim.dead = not bool(case[1])
		# Build 那行是面板里唯一会换行的块，也是最容易被撑爆的 ——
		# 必须真的把 6 武器 5 被动全点满，否则测的是"空 Build"，量不出问题
		for u in UpgradeDefs.UPGRADES:
			sim.loadout.levels[str(u["id"])] = int(u["max"]) if bool(case[3]) else 0
		sim.loadout.recompute()
		_end_delay = -1.0
		_update_end(0.016)
		_update_end(1.0)
		_update_end(1.0)
		if str(case[2]) != "":
			result.open(sim, knowledge.unlocked_count(), KnowledgeDB.total(), str(case[2]))
		var lay: Dictionary = result.debug_layout()
		var pr: Rect2 = lay["panel"]
		var br: Rect2 = lay["buttons"]
		var lr: Rect2 = lay["build"]
		var over_btn: float = maxf(0.0, br.end.y - pr.end.y)
		var over_build: float = maxf(0.0, lr.end.y - pr.end.y)
		var ok: bool = over_btn < 0.6 and over_build < 0.6 and pr.end.y <= 360.0
		print("     块高 %s" % " ".join(PackedStringArray(lay["parts"])))
		print("  E 布局 · %s · 面板 %.0f 高（内容 %.0f%s）· 按钮溢出 %.1f · %s" % [
			case[0], pr.size.y, float(lay["content"]),
			" · 紧凑" if bool(lay["compact"]) else "", over_btn,
			"OK" if ok else "FAIL (Build 溢出 %.1f)" % over_build])

	# D 关闭后恢复
	result.debug_reset()
	print("  D 关闭 · 打开=%s · 暂停已恢复=%s" % [
		"OK" if not result.is_open() else "FAIL",
		"OK" if not get_tree().paused else "FAIL"])
	print("")


func _row_texts() -> String:
	var out: Array[String] = []
	for hb in result._rows.get_children():
		var labels := hb.get_children()
		if labels.size() >= 2:
			out.append("%s %s" % [labels[0].text, labels[1].text])
	return " · ".join(out)


## 递归找 Button —— 面板是代码搭的，没存按钮引用，测试里按序取更省事
func _click_button(idx: int) -> void:
	var btns: Array[Button] = []
	_collect_buttons(result._panel, btns)
	if idx < btns.size():
		btns[idx].pressed.emit()


func _collect_buttons(n: Node, out: Array[Button]) -> void:
	if n is Button:
		out.append(n)
	for c in n.get_children():
		_collect_buttons(c, out)


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

	# 中文字体：内嵌字体没加载上的话 headless 里看不出任何异常，
	# 到了没装中文字体的机器上就是整屏方框 —— 所以这里必须显式断言。
	var f := UiFont.cjk()
	print("  中文字体 · %s · %s" % [
		f.resource_path if f != null else "未加载", "OK" if f != null else "FAIL"])
	print("")

	# ---- 品牌页（关于本作品）----
	# 排版只能靠眼睛看，但"该写的有没有写"必须能测：
	# 品牌、著作权、创作理念三块，漏任何一块这页就白做了。
	print("")
	print("=== 关于本作品 · 无头测试 ===")
	about.open("title")
	var atxt := about.debug_text()
	var need: Array[String] = [
		"稚码园机器人编程", "保留所有权利", "关于本作品",
		"创作理念", "版权声明", "作品信息",
	]
	var miss: Array[String] = []
	for w in need:
		if not atxt.contains(w):
			miss.append(w)
	# 内容量必须和数据表一致：写死的数字迟早和游戏对不上
	var cnt_ok: bool = atxt.contains("%d 名" % CharDefs.CHARACTERS.size()) \
		and atxt.contains("%d 类 Bug" % EnemyDB.DEFS.size())
	print("  打开=%s · 暂停=%s" % [about.is_open(), get_tree().paused])
	print("  必备文案 %s%s" % ["OK" if miss.is_empty() else "FAIL",
		"" if miss.is_empty() else "（缺：" + "、".join(miss) + "）"])
	print("  内容量取自数据表 · 角色 %d / Bug %d · %s" % [
		CharDefs.CHARACTERS.size(), EnemyDB.DEFS.size(), "OK" if cnt_ok else "FAIL"])
	about.close()
	print("  返回后 · 打开=%s · %s" % [about.is_open(),
		"OK" if not about.is_open() else "FAIL"])
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


## ESC：游戏中开暂停，暂停中再按一次继续。
## 说明页自己处理 ESC（返回上一页），这里必须先让开，否则一次按键穿透两层。
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var ke := event as InputEventKey
	if ke.keycode != KEY_ESCAPE or not ke.pressed or ke.echo:
		return
	if help.is_open() or about.is_open():
		return
	_toggle_pause()
	get_viewport().set_input_as_handled()


func _toggle_pause() -> void:
	# 这些界面各有各的 ESC 语义（或根本不该被暂停打断），让它们自己处理
	if title.is_open() or char_select.is_open() or level_up.visible or result.is_open() \
			or about.is_open():
		return
	if pause.is_open():
		pause.close()
		_resume_game()
	else:
		pause.open()


func _resume_game() -> void:
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)


func _on_pause_resume() -> void:
	_resume_game()


## 暂停里的「退出游戏」= 放弃这一局、回到标题页，**不是关掉程序**。
## 走重载场景而不是手工 reset：手清要动七八个对象池 + 空间网格 + 所有渲染器
## + 知识卡 + 音效，漏一个就是"标题页背后还跑着上一局的怪"。
## 重载后 _ready 会重新建一局并打开标题页，和刚启动时的状态完全一致。
func _on_pause_quit() -> void:
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	Sfx.restart_bgm()
	get_tree().reload_current_scene()


func _on_pause_help() -> void:
	help.open("pause")


## 品牌页：从标题页进来，返回时把标题页重新激活（同 help）
func _on_title_about() -> void:
	title.set_active(false)
	about.open("title")


func _on_title_help() -> void:
	title.set_active(false)
	help.open("title")


## 说明页返回：从暂停进来回暂停；从标题进来时标题页本来就在下面显示着，
## 只要把它重新激活（恢复 Enter 响应和呼吸动画）。
func _on_help_back(from: String) -> void:
	if from == "pause":
		pause.open()
	else:
		title.set_active(true)


func _on_char_back() -> void:
	_set_gameplay_ui(false)
	title.open()


func _process(delta: float) -> void:
	_update_end(delta)

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
	if not _nolv and not sim.dead and not sim.victory and sim.pending_levelups > 0 and not level_up.visible:
		level_up.open(sim)
		Sfx.play("levelup")

	if _shot_countdown > 0:
		_shot_countdown -= 1
		if _shot_countdown == 0:
			_save_shot()
			get_tree().quit()


## 一局结束 → 结算面板。
## 不立刻弹：死亡音、红色渐晕、Boss 的爆炸都要时间走完，玩家也需要
## 一两秒反应"啊我死了/啊打赢了"。结算面板本身会暂停整棵树，所以这里
## 只是倒计时，暂停的活儿交给 ResultUI.open。
func _update_end(delta: float) -> void:
	if not (sim.dead or sim.victory):
		return
	if result.is_open():
		return
	if _end_delay < 0.0:
		_end_delay = ResultUI.END_DELAY
		return
	_end_delay -= delta
	if _end_delay <= 0.0:
		# 通关才记账：用第 n 个角色赢了，才开第 n+1 个。
		# 记在开面板之前 —— 面板上要直接写"解锁了谁"。
		if sim.victory and not _unlock_recorded and not _no_save:
			_unlock_recorded = true
			_unlock_msg = SaveData.mark_cleared(sim.char_id)
		result.open(sim, knowledge.unlocked_count(), KnowledgeDB.total(), _unlock_msg)


## 重开：直接重载场景。手动 reset 要清七八个对象池 + 空间网格 + 所有渲染器
## + 知识卡 + 音效状态，漏一个就是"重开后画面有残留"，以后每加系统还得回来补。
func _on_restart() -> void:
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	Sfx.restart_bgm()
	get_tree().reload_current_scene()


func _on_quit() -> void:
	get_tree().paused = false
	get_tree().quit()


## 截图存档。渲染相关的检查（朝向、卡片位置、面板排版）headless 测不出来，
## 只能真跑一帧把画面存下来看。
func _save_shot() -> void:
	var path := "user://shot.png"
	get_viewport().get_texture().get_image().save_png(path)
	print("截已保存: " + ProjectSettings.globalize_path(path))


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
	# 只有"被敌人打掉的血"才响受伤音。永真力场每帧自伤，
	# 不扣掉它的话这把武器一开就是持续不断的噪音（实测全程响，听不下去）。
	var hp_loss := _prev_hp - sim.player_hp
	var self_loss := sim.self_dmg_total - _prev_self_dmg
	if hp_loss > self_loss + 0.001:
		Sfx.play("hurt")
	_prev_self_dmg = sim.self_dmg_total

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
