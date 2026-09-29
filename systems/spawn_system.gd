class_name SpawnSystem
extends RefCounted
##
## 刷怪：在玩家周围的环形区域（屏幕外）生成敌人，场上数量追随时间曲线。
##
## 数量曲线见 GameConfig.target_enemies()：开局 30 只，第 9 分半爬到 950 上限。
## 前两个角色乘一个 <1 的数量系数（见 CharDefs.density），场上会略少一点。
## 敌人血量也随时间成长，否则后期一刀一片、难度曲线是平的。
##
## 分化投放（M3）：
##   - 普通怪按时间档位 + 权重选类型（EnemyDB.pick_type）：
##     0 分钟只有报错红字/弹窗 → 45 秒垃圾文件 → 2 分钟木马 → … 越贵的怪越晚来。
##   - 精英不走权重（权重 0），走独立定时器：6 分钟起每 40 秒出一只，同屏上限 3。
##     精英必掉宝箱（D 方案），是"值得单体武器点名"的目标。
##

const ELITE_FIRST_AT := 360.0    # 6 分钟出第一只精英
const ELITE_INTERVAL := 40.0     # 之后每 40 秒补充一只
const ELITE_MAX_ALIVE := 3       # 同屏精英上限：多了就不是"点名目标"而是"围殴"
const BOSS_AT := 1080.0          # 18 分钟终局：编译器反噬

var timer := 0.0
var elite_timer := 0.0
var boss_spawned := false


## 开局预铺。用比常规更近的距离（见 GameConfig.SPAWN_START_* 的注释）。
## 预铺固定是最弱杂兵 —— 开局正反馈（一刀一个）靠它保证。
func prewarm(sim) -> void:
	for i in GameConfig.START_ENEMIES:
		_spawn_one(sim, 0.0, GameConfig.SPAWN_START_MIN, GameConfig.SPAWN_START_MAX, EnemyDB.BASIC_IDX)


func update(dt: float, sim) -> void:
	timer -= dt
	while timer <= 0.0:
		timer += GameConfig.spawn_interval(sim.time)
		_spawn_one(sim, sim.time)
	_update_elite(dt, sim)
	_update_boss(sim)


func _update_elite(dt: float, sim) -> void:
	if sim.time < ELITE_FIRST_AT:
		return
	elite_timer -= dt
	if elite_timer > 0.0:
		return
	elite_timer = ELITE_INTERVAL
	if EnemyDB.elite_alive(sim.enemies) >= ELITE_MAX_ALIVE:
		return

	var ei := EnemyDB.idx_of(EnemyDB.ELITE_ID)
	if ei < 0:
		return
	_spawn_one(sim, sim.time, GameConfig.SPAWN_MIN_DIST, GameConfig.SPAWN_MAX_DIST, ei)
	sim.sfx_events.append("elite")


## Boss：一局只出一只，不受"场上敌人上限"约束（否则会被杂兵挤掉），
## 血量固定不乘成长曲线 —— 它是设计好的一场决战，数值要可预期。
func _update_boss(sim) -> void:
	if boss_spawned or sim.time < BOSS_AT:
		return
	var bi := EnemyDB.idx_of(EnemyDB.BOSS_ID)
	if bi < 0:
		return
	boss_spawned = true
	_spawn_one(sim, sim.time, GameConfig.SPAWN_MIN_DIST, GameConfig.SPAWN_MIN_DIST + 60.0,
		bi, true, EnemyDB.DEFS[bi].hp)


func _spawn_one(sim, t: float, d_min: float = GameConfig.SPAWN_MIN_DIST,
		d_max: float = GameConfig.SPAWN_MAX_DIST, type_i: int = -1,
		force := false, fixed_hp := 0.0) -> void:
	var e: EnemyPool = sim.enemies
	var cap := GameConfig.target_enemies(t, sim.density)
	# Boss 战期间"挂起其他进程"：场上目标数压到 45%。
	# 不压的话 950 只杂兵把 AoE 的命中上限（hit_cap）全部吃掉，
	# Boss 分到的伤害不到六分之一，决战变成磨血马拉松（--smoke=20 实测 2 分钟打不死）。
	if sim.boss_active:
		cap = int(cap * 0.45)
	if not force and e.count >= cap:
		return

	if type_i < 0:
		type_i = EnemyDB.pick_type(t)
	var d: Dictionary = EnemyDB.DEFS[type_i]

	var ang: float = randf() * TAU
	var dist: float = d_min + randf() * (d_max - d_min)
	var x: float = sim.player_x + cos(ang) * dist
	var y: float = sim.player_y + sin(ang) * dist
	# 速度随机化跟难度无关：难度只改血量，改速度会让"这局难在哪"变得说不清。
	var spd: float = d.speed * (0.85 + randf() * 0.3)
	# 普通怪：基础血量 × 时间成长 × 角色难度（0.6~1.2，见 char_defs.diff）。
	# Boss：血量固定、不吃时间成长（它是设计好的一场决战），难度照样要乘 ——
	# 但系数 <1 时按 1 算：Boss 是设计好的一场决战，血量不该低于 80000，
	# 否则实习生那档会出现"站桩也能过"的决战，决战感直接没了。
	var hp: float = (fixed_hp * maxf(1.0, sim.difficulty)) if fixed_hp > 0.0 else sim.enemy_hp(d.hp, t)

	if e.spawn(x, y, hp, spd, d.radius, type_i, t):
		sim._note_enemy_type(type_i)
