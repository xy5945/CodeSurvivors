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

# ---- 玩家 ----
var player_x := 0.0
var player_y := 0.0
var facing_x := 1.0      # 开局默认面向右侧
var facing_y := 0.0
var player_hp := GameConfig.PLAYER_MAX_HP
var max_hp := GameConfig.PLAYER_MAX_HP
var iframe := 0.0
var dead := false

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
var boss_summon_cd := 4.0  # Boss 落地后 4 秒先召第一波

var kills := 0
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

	loadout.setup()
	_refresh_max_hp()
	player_hp = max_hp
	exp_next = UpgradeDefs.exp_to_next(1)
	spawn.prewarm(self)


func step(dt: float, dir_x: float, dir_y: float) -> void:
	if dead:
		return
	time += dt

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
	fx.update(dt, self)

	_reap()
	_update_gems(dt)
	_update_boss(dt)


# ---------------------------------------------------------------- 玩家

func _move_player(dt: float, dir_x: float, dir_y: float) -> void:
	if iframe > 0.0:
		iframe -= dt

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


## 兜底选项"紧急补丁"：不占等级、不进 loadout。
func apply_heal_pick(amount: float) -> void:
	heal_player(amount)
	if pending_levelups > 0:
		pending_levelups -= 1


func _refresh_max_hp() -> void:
	max_hp = GameConfig.PLAYER_MAX_HP + loadout.max_hp_bonus


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
				player_hp -= EnemyDB.DEFS[e.type[i]].damage
				iframe = GameConfig.PLAYER_IFRAME
				if player_hp <= 0.0:
					player_hp = 0.0
					dead = true

		i += 1


## 精英 / Boss 的冲刺技能状态机（每帧只对精英和 Boss 调用，全屏 ≤ 4 个）。
##
## 三态：
##   0 待机   —— 技能倒计时；归零且玩家在射程内 → 进入蓄力
##   1 蓄力   —— 白闪（渲染层把 flash>0 的实例画成放大的白剪影）+ 移速压到 25%，
##               结束时把"此刻到玩家的方向"锁进 skill_dx/dy
##   2 冲刺   —— 沿锁定方向以数倍速度突进，扫到玩家就是一次全额接触伤害
##
## 设计意图（机制问题用玩法解决）：冲刺速度 ≈ 或 > 玩家移速 ——
## 顺着跑是跑不掉的，必须**横向**让开。这是逼走位，不是数值威胁。
func _skill_tick(i: int, e: EnemyPool, dt: float,
		dx: float, dy: float, dist: float, ti: int, boss_i: int) -> float:
	var is_boss := ti == boss_i
	var cd: float = GameConfig.BOSS_DASH_CD if is_boss else GameConfig.ELITE_DASH_CD
	var rng: float = GameConfig.BOSS_DASH_RANGE if is_boss else GameConfig.ELITE_DASH_RANGE
	var windup: float = GameConfig.BOSS_DASH_WINDUP if is_boss else GameConfig.ELITE_DASH_WINDUP
	var dash_t: float = GameConfig.BOSS_DASH_TIME if is_boss else GameConfig.ELITE_DASH_TIME
	var dash_mul: float = GameConfig.BOSS_DASH_MULT if is_boss else GameConfig.ELITE_DASH_MULT
	if is_boss and e.hp[i] < EnemyDB.DEFS[boss_i].hp * GameConfig.BOSS_ENRAGE_HP_FRAC:
		cd *= 0.6    # 狂暴：血量低于 40% 后技能转得更快

	match e.skill_state[i]:
		0:
			e.skill_cd[i] -= dt
			if e.skill_cd[i] <= 0.0:
				if dist > 40.0 and dist < rng:
					e.skill_state[i] = 1
					e.skill_t[i] = windup
					e.skill_dx[i] = dx
					e.skill_dy[i] = dy
				else:
					e.skill_cd[i] = 1.0    # 距离不合适，稍后再试
			return 1.0
		1:
			# 持续白闪当蓄力提示（flash 同时被渲染层放大 1.4 倍，"蓄力鼓胀"）
			e.flash[i] = maxf(e.flash[i], 0.12)
			e.skill_t[i] -= dt
			if e.skill_t[i] <= 0.0:
				e.skill_state[i] = 2
				e.skill_t[i] = dash_t
				if is_boss:
					boss_dashes += 1
				else:
					elite_dashes += 1
				return dash_mul
			return GameConfig.SKILL_WINDUP_MULT
		_:
			e.skill_t[i] -= dt
			if e.skill_t[i] <= 0.0:
				e.skill_state[i] = 0
				e.skill_cd[i] = cd * (0.9 + randf() * 0.2)
				return 1.0
			return dash_mul


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
