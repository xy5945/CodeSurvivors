class_name Sim
extends RefCounted
##
## 仿真核心：纯数据层，没有节点、没有信号、没有 _process。
## 由 main.gd 以固定步长驱动，每帧调用一次 step()。
##
## 这条界线是性能的前提：逻辑层可以脱离 Godot 场景树独立跑，
## 所以能用 headless 模式做基准测试（见 tools/bench.gd）。
##

var enemies: EnemyPool
var gems: GemPool
var grid: SpatialGrid
var spawn: SpawnSystem
var loadout: Loadout

# 投射物（递归飞刃 / 指针追踪共用）与范围特效（广播波 / 落雷）
var projectiles: ProjectilePool
var proj_sys: ProjectileSystem
var fx: FxStore

# 敌方威胁：弹幕（精英/Boss 发射，玩家躲）与危险区（地面预警圈 → 延迟爆炸）。
# 和玩家的 projectiles 完全分开：那边的目标是敌人，这边的目标是玩家。
var bullets: EnemyBulletPool
var hazards: HazardStore
var attack: EnemyAttackSystem

# ---- 玩家 ----
var player_x := 0.0
var player_y := 0.0
var facing_x := 1.0      # 开局默认面向右侧
var facing_y := 0.0
var player_hp := GameConfig.PLAYER_MAX_HP
var max_hp := GameConfig.PLAYER_MAX_HP
var iframe := 0.0          # 接触伤害/危险区爆炸的无敌帧
# 弹幕用**独立的**无敌帧：和接触伤害共用的话，挨一发弹幕就能白穿一整面弹幕墙，
# "弹幕必须躲"这条设计立刻失效（实测每 0.6 秒才掉一次血 = 站在弹幕里散步）。
var bullet_iframe := 0.0
var dead := false
var damage_taken := 0.0    # 累计承受伤害（平衡回归用，god_mode 下不计）

# ---- 经验与升级 ----
var level := 1
var exp_cur := 0
var exp_next := 0
var pending_levelups := 0     # UI 轮询这个：>0 就弹三选一

# ---- 统计 ----
# ---- Boss / 终局 ----
# Boss 血量不走成长曲线，所以这里直接按类型表取值即可。
# 不存敌人索引：池用 swap_remove，索引跨帧不可靠，每帧扫描更省心（O(n)，无所谓）。
var boss_active := false
var boss_hp := 0.0
var boss_max_hp := 0.0
var victory := false       # Boss 被击杀 → 通关

# 技能统计（测试断言用：精英/Boss 技能是否真的在放）
var elite_dashes := 0
var boss_dashes := 0
var boss_summons := 0
var elite_skills := 0      # 精英技能总次数（含冲刺与弹幕）
var elite_novas := 0
var elite_splits := 0      # 精英死亡分裂次数
var boss_skills := 0
var boss_novas := 0
var boss_aimeds := 0
var boss_homings := 0
var boss_hazards := 0
var bullets_fired := 0     # 累计发射的弹幕数（含精英）
var boss_summon_cd := 4.0  # Boss 落地后 4 秒先召第一波

var kills := 0
# 音效事件队列：仿真层只记录"这一帧发生了什么"，由表现层决定发不发声、怎么发声。
# 每个 step 开头清空（见 step），headless 自动化测试不消费它也不会无限增长。
var sfx_events: Array[String] = []
# 知识卡事件队列：和 sfx_events 完全同一套路 —— 仿真层只记"这一帧首次遇到了什么"，
# 显示、排队、去重全归表现层。同样每个 step 开头清空，headless 不消费也不会涨。
var card_events: Array[String] = []
# 已经记过一次的敌人类型（按 EnemyDB.DEFS 下标）。
# 不记的话每刷一只怪就 push 一次，一秒钟能塞进几十张同内容的卡。
var seen_enemy_types: Array[bool] = []
var gems_collected := 0
var patches_collected := 0
var chests_collected := 0
var healed_total := 0.0          # 累计实际回血量（溢出部分不算），用于平衡回归
var heal_on_ground := 0          # 地面上回血物数量（不磁吸，只能靠拾取减少）
var heal_wasted := 0             # 满血时吃掉、回血全溢出的次数（玩家自己浪费掉的）
var time := 0.0

# 供 headless 基准测试使用：关掉刷怪与玩家受伤，才能稳定测出指定敌人数下的耗时
var spawn_enabled := true
var god_mode := false


func setup() -> void:
	enemies = EnemyPool.new(GameConfig.MAX_ENEMIES)
	gems = GemPool.new(GameConfig.MAX_GEMS)
	grid = SpatialGrid.new()
	grid.setup(GameConfig.CELL_SIZE, GameConfig.ARENA_HALF, GameConfig.MAX_ENEMIES)
	spawn = SpawnSystem.new()
	loadout = Loadout.new()
	projectiles = ProjectilePool.new(GameConfig.MAX_PROJECTILES)
	proj_sys = ProjectileSystem.new()
	fx = FxStore.new()
	bullets = EnemyBulletPool.new(GameConfig.MAX_ENEMY_BULLETS)
	hazards = HazardStore.new()
	attack = EnemyAttackSystem.new()

	loadout.setup()
	_refresh_max_hp()
	player_hp = max_hp
	exp_next = UpgradeDefs.exp_to_next(1)
	seen_enemy_types.resize(EnemyDB.DEFS.size())
	seen_enemy_types.fill(false)
	spawn.prewarm(self)


func step(dt: float, dir_x: float, dir_y: float) -> void:
	if dead:
		return
	time += dt
	sfx_events.clear()
	# card_events **不能**在这里清。它和 sfx_events 不一样：音效事件全部产生于
	# step 内部，同一帧就消费完；而"首次获得武器/被动"的事件产生于玩家在升级
	# 弹窗里点卡片的那一刻 —— 那是 step 之后、下一帧之前。这里一清，武器卡的
	# 事件就被下一帧的 step 吞掉，玩家永远看不到武器知识卡（2026-09-17 实测）。
	# 所以它是一条靠消费方清空的队列，见 KnowledgeUI 的投递处。
	if card_events.size() > 64:
		card_events.clear()

	_move_player(dt, dir_x, dir_y)
	if spawn_enabled:
		spawn.update(dt, self)
	grid.rebuild(enemies)
	_move_enemies(dt)

	# 武器 → 投射物 → 范围特效 → 统一回收。
	# _reap 必须排在所有伤害来源之后，否则死在特效里的敌人不会掉宝石。
	for w in loadout.weapons:
		w.update(dt, self)
	proj_sys.update(dt, self)
	# 敌方攻击放在 _reap 之前：本帧造成的伤害必须先结算，否则死在弹幕里的玩家
	# 会以"已经死亡的 sim"再跑一遍回收逻辑。
	attack.update(dt, self)
	fx.update(dt, self)

	_reap()
	_update_gems(dt)
	_update_boss(dt)


# ---------------------------------------------------------------- 玩家

func _move_player(dt: float, dir_x: float, dir_y: float) -> void:
	if iframe > 0.0:
		iframe -= dt
	if bullet_iframe > 0.0:
		bullet_iframe -= dt

	var len_sq := dir_x * dir_x + dir_y * dir_y
	if len_sq > 0.0001:
		# 只有真正有输入时才更新朝向 —— 这就是"静止时保持最后朝向"的实现点
		var inv := 1.0 / sqrt(len_sq)
		facing_x = dir_x * inv
		facing_y = dir_y * inv
		var spd := GameConfig.PLAYER_SPEED * loadout.move_speed_mult * dt
		player_x += facing_x * spd
		player_y += facing_y * spd

	var lim := GameConfig.ARENA_HALF
	player_x = clampf(player_x, -lim, lim)
	player_y = clampf(player_y, -lim, lim)


## 统一受伤入口。所有对玩家的伤害都必须走这两个函数之一 ——
## 之前只有"敌人接触"一种伤害源，判定内联在 _move_enemies 里就够了；
## 现在多了弹幕和危险区，各自扣血的话无敌帧、死亡判定、受伤统计会到处漏。
## 返回是否真的造成了伤害（供测试断言"这一下有没有打中"）。
func hurt_player(v: float) -> bool:
	if dead or god_mode or iframe > 0.0:
		return false
	_apply_player_damage(v)
	iframe = GameConfig.PLAYER_IFRAME
	return true


## 弹幕专用的受伤入口（走更短、独立的无敌帧）。
func hurt_player_bullet(v: float) -> bool:
	if dead or god_mode or bullet_iframe > 0.0:
		return false
	_apply_player_damage(v)
	bullet_iframe = GameConfig.BULLET_IFRAME
	return true


func _apply_player_damage(v: float) -> void:
	player_hp -= v
	damage_taken += v
	if player_hp <= 0.0:
		player_hp = 0.0
		dead = true


func heal_player(v: float) -> void:
	if dead:
		return
	var before := player_hp
	player_hp = minf(player_hp + v, max_hp)
	healed_total += player_hp - before


## 升级入口。UI 选中一张卡后调用这里。
## 注意：加"生命上限"时同时补等量血 —— 否则玩家点了加血却看不到血条变化，
## 会觉得这个选项没用（这是幸存者类游戏的通用做法）。
func apply_upgrade(id: String) -> void:
	var before := max_hp
	loadout.apply_upgrade(id)
	_refresh_max_hp()
	if max_hp > before:
		player_hp += max_hp - before
	player_hp = minf(player_hp, max_hp)

	if pending_levelups > 0:
		pending_levelups -= 1

	# 首次拿到这把武器/这个被动 → 弹它的知识卡。
	# 判断放在 apply 之后：此刻 levels[id] 已经是新等级，等于 1 说明是刚拿到的。
	if loadout.level_of(id) == 1:
		card_events.append(id)


## 兜底选项"紧急补丁"：不占等级、不进 loadout。
func apply_heal_pick(amount: float) -> void:
	heal_player(amount)
	if pending_levelups > 0:
		pending_levelups -= 1


func _refresh_max_hp() -> void:
	max_hp = GameConfig.PLAYER_MAX_HP + loadout.max_hp_bonus


## 记一张"首次遇到这种敌人"的知识卡。
##
## 三个刷怪入口都必须调（常规刷怪 / 精英死亡分裂 / Boss 召唤），
## 漏一个的话那种敌人永远弹不出卡 —— 而它恰好可能是唯一一次出现（比如 Boss）。
## 重复调用是安全的：seen_enemy_types 会挡住。
func _note_enemy_type(ti: int) -> void:
	if ti < 0 or ti >= seen_enemy_types.size():
		return
	if seen_enemy_types[ti]:
		return
	seen_enemy_types[ti] = true
	card_events.append(str(EnemyDB.DEFS[ti]["id"]))


# ---------------------------------------------------------------- 敌人

func _move_enemies(dt: float) -> void:
	var e := enemies
	var g := grid
	var sep_range := GameConfig.SEP_RANGE
	var sep_range_sq := sep_range * sep_range
	var max_n := GameConfig.SEP_MAX_NEIGHBORS
	var touch := GameConfig.PLAYER_RADIUS
	var elite_i := EnemyDB.idx_of(EnemyDB.ELITE_ID)
	var boss_i := EnemyDB.idx_of(EnemyDB.BOSS_ID)

	var i := 0
	while i < e.count:
		var x := e.px[i]
		var y := e.py[i]
		var ti := e.type[i]

		if e.flash[i] > 0.0:
			e.flash[i] -= dt
		if e.orb_cd[i] > 0.0:
			e.orb_cd[i] -= dt
		if e.mark[i] > 0.0:
			e.mark[i] -= dt

		# 行走动画相位。必须取模而不是一直累加 —— 一局 20 分钟，
		# 累加到几千之后 float32 精度不够，帧号会卡住不动。
		var a := e.anim[i] + dt * EnemyPool.ANIM_RATE
		if a >= float(EnemyPool.FRAMES):
			a -= float(EnemyPool.FRAMES)
		e.anim[i] = a

		# 朝玩家
		var dx := player_x - x
		var dy := player_y - y
		var d2 := dx * dx + dy * dy
		if d2 > 1.0:
			var inv := 1.0 / sqrt(d2)
			dx *= inv
			dy *= inv
		else:
			dx = 0.0
			dy = 0.0

		# 精英 / Boss 冲刺技能。返回移速倍率；冲刺中还会改写移动方向。
		var spd_mul := 1.0
		if ti == elite_i or ti == boss_i:
			spd_mul = _skill_tick(i, e, dt, dx, dy, sqrt(d2), ti, boss_i)
			if e.skill_state[i] == 2:
				dx = e.skill_dx[i]
				dy = e.skill_dy[i]

		var vx := dx * e.speed[i] * spd_mul
		var vy := dy * e.speed[i] * spd_mul

		# 分离：候选数与推力数双重上限（这是保帧率的关键，见 GameConfig 注释）
		var sx := 0.0
		var sy := 0.0
		var n := g.query(x, y, sep_range, GameConfig.SEP_MAX_CHECKS)
		var k := 0
		var checked := 0
		var processed := 0
		while k < n and checked < GameConfig.SEP_MAX_CHECKS and processed < max_n:
			var j := g.out[k]
			k += 1
			checked += 1
			if j == i:
				continue
			var ox := x - e.px[j]
			var oy := y - e.py[j]
			var od2 := ox * ox + oy * oy
			if od2 >= sep_range_sq or od2 <= 0.0001:
				continue
			var min_d := e.radius[i] + e.radius[j]
			if od2 >= min_d * min_d:
				continue
			var od := sqrt(od2)
			var push := (min_d - od) / min_d
			sx += (ox / od) * push
			sy += (oy / od) * push
			processed += 1

		e.px[i] = x + (vx + sx * GameConfig.SEP_FORCE) * dt
		e.py[i] = y + (vy + sy * GameConfig.SEP_FORCE) * dt

		# 接触伤害（带无敌帧，否则贴脸瞬间掉光血）。伤害按敌人类型走，
		# 大块头撞一下必须比小杂兵疼，不然血量厚度没有意义
		if iframe <= 0.0 and not god_mode:
			var tx := e.px[i] - player_x
			var ty := e.py[i] - player_y
			var tr := e.radius[i] + touch
			if tx * tx + ty * ty <= tr * tr:
				hurt_player(EnemyDB.DEFS[e.type[i]].damage)

		i += 1


## 精英 / Boss 的技能状态机（每帧只对精英和 Boss 调用，全屏 ≤ 5 个）。
##
## 三态 + 技能轮盘：
##   0 待机 —— 技能间隔倒计时；归零且玩家在射程内 → 抽下一个技能，进入蓄力
##   1 蓄力 —— 白闪（渲染层把 flash>0 的实例画成放大的白剪影）+ 移速压到 25%，
##              结束时按技能类型走 _cast
##   2 冲刺 —— 沿锁定方向以数倍速度突进（唯一有"持续态"的技能）
##
## 技能由 GameConfig.BOSS_SKILLS / ELITE_SKILLS 顺序轮转，不是各自独立冷却：
## 节奏因此可预期（冲刺 → 环形弹幕 → 扇形弹幕 → 危险区 → 追踪弹 → 循环），
## 玩家能学会"接下来该防什么"。随机放招会让同一场战斗忽难忽易，读不出规律。
##
## 设计意图（机制问题用玩法解决）：五种技能封的是不同的走位方式 ——
## 冲刺逼你横向让开、弹幕逼你离开那条线、危险区逼你离开那片地。
## 全靠"跑得比它快"是不成立的，必须看招换方向。
func _skill_tick(i: int, e: EnemyPool, dt: float,
		dx: float, dy: float, dist: float, ti: int, boss_i: int) -> float:
	var is_boss := ti == boss_i
	var rot: Array = GameConfig.BOSS_SKILLS if is_boss else GameConfig.ELITE_SKILLS
	var cd: float = GameConfig.BOSS_SKILL_CD if is_boss else GameConfig.ELITE_SKILL_CD
	var rng: float = GameConfig.BOSS_SKILL_RANGE if is_boss else GameConfig.ELITE_SKILL_RANGE
	var enraged: bool = is_boss and e.hp[i] < EnemyDB.DEFS[boss_i].hp * GameConfig.BOSS_ENRAGE_HP_FRAC
	if enraged:
		cd *= GameConfig.BOSS_ENRAGE_CD_MULT

	match e.skill_state[i]:
		0:
			e.skill_cd[i] -= dt
			if e.skill_cd[i] > 0.0:
				return 1.0
			# 只排除"太远"（技能够不着，放了也是浪费前摇）。
			#
			# 这里**不能**再排除"太近"：曾经有一条 dist <= 40 的门槛，本意是
			# "贴脸了就不必冲刺"，实际效果是玩家一贴身打输出，精英和 Boss
			# 就再也不放技能了 —— 而近战武器的玩家本来就一直贴着打，
			# 于是"精英/Boss 有技能"在实战里等于不存在（--bosstest 实测 0 次）。
			# 贴身时放环形弹幕恰恰是最危险的，那正是我们想要的。
			if dist > rng:
				e.skill_cd[i] = 0.8
				return 1.0
			e.skill_seq[i] = (e.skill_seq[i] + 1) % rot.size()
			e.skill_state[i] = 1
			e.skill_t[i] = _windup_of(str(rot[e.skill_seq[i]]), is_boss)
			return 1.0
		1:
			# 持续白闪当蓄力提示（flash 同时被渲染层放大 1.4 倍，"蓄力鼓胀"）
			e.flash[i] = maxf(e.flash[i], 0.12)
			e.skill_t[i] -= dt
			if e.skill_t[i] > 0.0:
				return GameConfig.SKILL_WINDUP_MULT
			return _cast(i, e, is_boss, str(rot[e.skill_seq[i]]))
		_:
			e.skill_t[i] -= dt
			if e.skill_t[i] <= 0.0:
				e.skill_state[i] = 0
				e.skill_cd[i] = cd * (0.9 + randf() * 0.2)
				return 1.0
			return GameConfig.BOSS_DASH_MULT if is_boss else GameConfig.ELITE_DASH_MULT


static func _windup_of(skill: String, is_boss: bool) -> float:
	match skill:
		"dash":
			return GameConfig.BOSS_DASH_WINDUP if is_boss else GameConfig.ELITE_DASH_WINDUP
		"nova":
			return 0.62
		"aimed":
			return 0.50
		"hazard":
			return 0.45
		_:
			return 0.55


## 蓄力结束，真正放出技能。返回本帧的移速倍率。
##
## 方向在**这一刻**才取，而不是蓄力开始时锁定 —— 玩家看到白闪就走开，招就落空。
## 蓄力开始就锁方向的话，前摇只是个动画，玩家没有可操作的空间。
func _cast(i: int, e: EnemyPool, is_boss: bool, skill: String) -> float:
	var ex := e.px[i]
	var ey := e.py[i]
	var tdx := player_x - ex
	var tdy := player_y - ey
	var d := sqrt(tdx * tdx + tdy * tdy)
	if d > 1.0:
		tdx /= d
		tdy /= d
	else:
		tdx = 1.0
		tdy = 0.0

	var boss_hp_full: float = EnemyDB.DEFS[EnemyDB.idx_of(EnemyDB.BOSS_ID)].hp
	var enraged: bool = is_boss and e.hp[i] < boss_hp_full * GameConfig.BOSS_ENRAGE_HP_FRAC
	var cmul := GameConfig.BOSS_ENRAGE_COUNT_MULT if enraged else 1.0

	match skill:
		"dash":
			e.skill_state[i] = 2
			e.skill_t[i] = GameConfig.BOSS_DASH_TIME if is_boss else GameConfig.ELITE_DASH_TIME
			e.skill_dx[i] = tdx
			e.skill_dy[i] = tdy
			if is_boss:
				boss_dashes += 1
			else:
				elite_dashes += 1
			_count_skill(is_boss, "dash")
			return GameConfig.BOSS_DASH_MULT if is_boss else GameConfig.ELITE_DASH_MULT
		"nova":
			var n := int((GameConfig.BOSS_NOVA_N if is_boss else GameConfig.ELITE_NOVA_N) * cmul)
			EnemyAttackSystem.nova(self, ex, ey, n,
				GameConfig.BOSS_NOVA_SPD if is_boss else GameConfig.ELITE_NOVA_SPD,
				GameConfig.BOSS_NOVA_DMG if is_boss else GameConfig.ELITE_NOVA_DMG,
				GameConfig.BULLET_SHARD_RADIUS, GameConfig.BULLET_LIFE, randf() * TAU)
			bullets_fired += n
			_count_skill(is_boss, "nova")
		"aimed":
			EnemyAttackSystem.aimed(self, ex, ey, tdx, tdy,
				GameConfig.BOSS_AIMED_N, GameConfig.BOSS_AIMED_SPREAD,
				GameConfig.BOSS_AIMED_SPD, GameConfig.BOSS_AIMED_DMG,
				GameConfig.BULLET_SHARD_RADIUS)
			bullets_fired += GameConfig.BOSS_AIMED_N
			_count_skill(true, "aimed")
		"homing":
			EnemyAttackSystem.homing(self, ex, ey, tdx, tdy,
				GameConfig.BOSS_HOMING_N, GameConfig.BOSS_HOMING_SPD,
				GameConfig.BOSS_HOMING_DMG, GameConfig.BULLET_HOMING_RADIUS,
				GameConfig.BOSS_HOMING_TURN)
			bullets_fired += GameConfig.BOSS_HOMING_N
			_count_skill(true, "homing")
		"hazard":
			# 复用"精英出场"的三声警报当预警音：弹幕可能被屏幕外的发射者挡住视线，
			# 但危险区是往玩家脚下放的，必须有个听觉提示 —— 玩家听到警报
			# 就该低头看脚下。爆炸声不需要额外事件，爆炸走的是落雷视觉，
			# 到时候玩家自己会看到。
			sfx_events.append("elite")
			EnemyAttackSystem.hazard_around_player(self,
				int(GameConfig.BOSS_HAZARD_N * cmul), GameConfig.BOSS_HAZARD_R,
				GameConfig.BOSS_HAZARD_WARN, GameConfig.BOSS_HAZARD_DMG,
				GameConfig.BOSS_HAZARD_RING_MIN, GameConfig.BOSS_HAZARD_RING_MAX)
			_count_skill(true, "hazard")

	e.skill_state[i] = 0
	e.skill_cd[i] = (GameConfig.BOSS_SKILL_CD if is_boss else GameConfig.ELITE_SKILL_CD) \
		* (0.9 + randf() * 0.2)
	return 1.0


func _count_skill(is_boss: bool, name: String) -> void:
	if is_boss:
		boss_skills += 1
		match name:
			"nova": boss_novas += 1
			"aimed": boss_aimeds += 1
			"homing": boss_homings += 1
			"hazard": boss_hazards += 1
	else:
		elite_skills += 1
		if name == "nova":
			elite_novas += 1


## 每帧扫一遍场上有没有 Boss（n ≤ 2048，且已经有多次 O(n) 遍历，不敏感）。
## 顺手驱动 Boss 的召唤技能 —— 反正这一帧已经找到 Boss 的位置了。
func _update_boss(dt: float) -> void:
	if boss_active:
		var bi := EnemyDB.idx_of(EnemyDB.BOSS_ID)
		var found := false
		for i in enemies.count:
			if enemies.type[i] == bi:
				boss_hp = enemies.hp[i]
				found = true
				_boss_summon_tick(dt, i, bi)
				break
		if not found:
			# Boss 被清场（例如测试里直接清空）—— 不算通关
			boss_active = false
			boss_hp = 0.0
		return

	if victory:
		return
	var bi2 := EnemyDB.idx_of(EnemyDB.BOSS_ID)
	for i in enemies.count:
		if enemies.type[i] == bi2:
			boss_active = true
			boss_hp = enemies.hp[i]
			boss_max_hp = enemies.hp[i]
			return


## Boss 召唤：围绕自己召一小圈垃圾文件 —— 切后排、堵走位。
## 玩家不能只顾风筝 Boss，还得清理脚边越堆越多的小怪。
func _boss_summon_tick(dt: float, boss_idx: int, boss_type: int) -> void:
	boss_summon_cd -= dt
	if boss_summon_cd > 0.0:
		return
	var enraged: bool = enemies.hp[boss_idx] < EnemyDB.DEFS[boss_type].hp * GameConfig.BOSS_ENRAGE_HP_FRAC
	sfx_events.append("elite")
	boss_summon_cd = GameConfig.BOSS_SUMMON_CD * (0.6 if enraged else 1.0)

	var ji := EnemyDB.idx_of("junk_file")
	if ji < 0:
		return
	var t := time
	var growth := 1.0 + t * GameConfig.ENEMY_HP_GROWTH
	var n := 0
	for k in GameConfig.BOSS_SUMMON_N:
		if enemies.count >= enemies.capacity():
			break
		var ang := TAU * float(k) / float(GameConfig.BOSS_SUMMON_N) + randf() * 0.5
		var dist: float = randf_range(GameConfig.BOSS_SUMMON_R_MIN, GameConfig.BOSS_SUMMON_R_MAX)
		var d: Dictionary = EnemyDB.DEFS[ji]
		if enemies.spawn(
				enemies.px[boss_idx] + cos(ang) * dist,
				enemies.py[boss_idx] + sin(ang) * dist,
				d.hp * growth, d.speed, d.radius, ji):
			n += 1
	boss_summons += 1
	_note_enemy_type(ji)


## 倒序回收：配合 swap_remove，被搬过来的元素本帧不再检查（延迟一帧，无影响）
func _reap() -> void:
	var e := enemies
	var i := e.count - 1
	while i >= 0:
		if e.hp[i] <= 0.0:
			var ti := e.type[i]
			# 经验按类型给：精英 20 点、大怪 3~4 点，杂兵 1 点。
			# 掉落价值必须跟"杀它花的功夫"成正比，否则玩家没有打精英的动力。
			gems.spawn(e.px[i], e.py[i], EnemyDB.DEFS[ti].xp)
			if ti == EnemyDB.idx_of(EnemyDB.BOSS_ID):
				# 终局奖励：经验宝石 + 三个宝箱（回血够玩家撑过庆祝时刻）
				for k in 3:
					_drop_heal(
						e.px[i] + randf_range(-20.0, 20.0),
						e.py[i] + randf_range(-20.0, 20.0),
						true
					)
				victory = true
				boss_active = false
				boss_hp = 0.0
			elif ti == EnemyDB.idx_of(EnemyDB.ELITE_ID):
				# 精英必掉宝箱（D 方案）。位置随机偏一点，别和宝石完全重叠。
				_drop_heal(
					e.px[i] + randf_range(-8.0, 8.0),
					e.py[i] + randf_range(-8.0, 8.0),
					true
				)
				_split_elite(e.px[i], e.py[i])
			# 补丁包是"额外掉落"：宝石必掉，保证经验曲线不受回血概率影响。
			# 位置随机偏一点，否则两个掉落物完全重叠，看不出是两个。
			elif randf() < GameConfig.PATCH_DROP_CHANCE:
				_drop_heal(
					e.px[i] + randf_range(-8.0, 8.0),
					e.py[i] + randf_range(-8.0, 8.0),
					false
				)
			e.kill(i)
			kills += 1
		i -= 1


# ---------------------------------------------------------------- 经验宝石

## 精英死亡时"异常扩散"：分裂出一小圈最弱杂兵。
##
## 为什么要有这个：精英的血量提高之后（150 → 350），玩家很自然会
## "贴上去磨死它"。一个会分裂的精英改变了这个决定 —— 磨它的时间越长，
## 分裂的怪越快把你围住。它把"打精英"从纯 DPS 检查变成"什么时候去收"的取舍。
func _split_elite(x: float, y: float) -> void:
	var bi := EnemyDB.BASIC_IDX
	var d: Dictionary = EnemyDB.DEFS[bi]
	var growth := 1.0 + time * GameConfig.ENEMY_HP_GROWTH
	for k in GameConfig.ELITE_SPLIT_N:
		if enemies.count >= enemies.capacity():
			break
		var ang := TAU * float(k) / float(GameConfig.ELITE_SPLIT_N) + randf()
		enemies.spawn(x + cos(ang) * 16.0, y + sin(ang) * 16.0,
			d.hp * growth, d.speed, d.radius, bi)
	elite_splits += 1
	_note_enemy_type(bi)


## 掉落回血物（补丁包 / 宝箱）。
##
## 地面上限：回血物不磁吸，玩家不捡就一直留在地上。没有上限的话，
## 长局会把掉落池（4096）堆满，把经验宝石和后面的宝箱挤掉 —— 那是真 bug。
## 到顶就不再掉落（而不是替换最远的那个）：地上的已经够了，
## 玩家没捡是因为用不上，再掉也是白掉。
func _drop_heal(x: float, y: float, chest: bool) -> void:
	if heal_on_ground >= GameConfig.MAX_HEAL_ON_GROUND:
		return
	var ok := gems.spawn_chest(x, y) if chest else gems.spawn(x, y, 0, GemPool.KIND_PATCH)
	if ok:
		heal_on_ground += 1

## 只有进入拾取范围的宝石才起飞 —— 否则满屏宝石一起飞过来，
## 既难看，又让每帧的距离计算全部变成插值移动。
##
## 倒序遍历 + swap_remove：被搬到位置 i 的元素是"最后一个"，
## 它在本次循环中已经被处理过了，所以 i -= 1 跳过它是安全的。
func _update_gems(dt: float) -> void:
	var pickup := loadout.pickup_range
	var pickup_sq := pickup * pickup
	var heal_r_sq := GameConfig.PATCH_PICKUP_RADIUS * GameConfig.PATCH_PICKUP_RADIUS
	var g := gems
	var i := g.count - 1

	while i >= 0:
		var dx := player_x - g.px[i]
		var dy := player_y - g.py[i]
		var d2 := dx * dx + dy * dy

		# 回血类掉落物（补丁包 / 宝箱）永不磁吸：
		# 不设 mag、不飞向玩家，只有玩家自己走上来踩到才算数。
		# 满血踩上去照常消耗（回血溢出就是浪费）—— 这是玩家的取舍，不是系统的失误。
		if GemPool.is_heal(g.kind[i]):
			if d2 <= heal_r_sq:
				_collect_gem(i)
			i -= 1
			continue

		if g.mag[i] == 0:
			if d2 > pickup_sq:
				i -= 1
				continue
			g.mag[i] = 1

		if d2 <= GameConfig.GEM_COLLECT_RADIUS * GameConfig.GEM_COLLECT_RADIUS:
			_collect_gem(i)
			i -= 1
			continue

		var d := sqrt(d2)
		# 越近飞越快：贴脸时还要等宝石慢慢飘过来是很烦的
		var boost := 1.0 + (1.0 - clampf(d / pickup, 0.0, 1.0)) * GameConfig.MAGNET_NEAR_BOOST
		var sp := GameConfig.MAGNET_SPEED * boost * dt
		g.px[i] += (dx / d) * sp
		g.py[i] += (dy / d) * sp
		i -= 1


func _collect_gem(i: int) -> void:
	var k := gems.kind[i]
	if k == GemPool.KIND_PATCH or k == GemPool.KIND_CHEST:
		heal_on_ground -= 1
		# 满血时踩上去 = 白白吃掉。不做"满血不拾取"的保护：
		# 那等于替玩家做决定，玩家就不用判断了 —— 浪费是他自己选的代价。
		var was_full := player_hp >= max_hp - 0.001
		if k == GemPool.KIND_PATCH:
			heal_player(GameConfig.PATCH_HEAL)
			patches_collected += 1
		else:
			heal_player(GameConfig.CHEST_HEAL)
			chests_collected += 1
		if was_full:
			heal_wasted += 1
	else:
		exp_cur += gems.value[i]
		gems_collected += 1
	gems.remove_at(i)

	# while 而不是 if：一次拾取可能连升多级（后期一颗高价值宝石就够了）
	while exp_cur >= exp_next:
		exp_cur -= exp_next
		level += 1
		exp_next = UpgradeDefs.exp_to_next(level)
		pending_levelups += 1
