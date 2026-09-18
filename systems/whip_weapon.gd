class_name WhipWeapon
extends RefCounted
##
## 分支长鞭：朝玩家朝向挥出 90° 扇形，范围内所有敌人各受一次伤害。
##
## 朝向规则：facing = 最后一次移动方向，静止时保持，开局朝右（见 Sim）。
## 扇形判定完全不调用 sqrt()：
##   dot = d · facing，夹角 θ 满足 cos θ = dot / |d|
##   θ <= 45°  <=>  dot > 0 且 dot² >= cos²(45°) · |d|²  = 0.5 · d2
## 这在每帧几百次判定的热路径上是实打实的开销差异。
##
## 分支方向（branches）：
##   1 = 只打正面
##   2 = 正面 + 反面（L4）
##   3 = 正面 + 反面 + 垂直一侧（L7）
## 垂直只有一条：数值表和 DPS 都按 3 条计算。若实测手感不足，
## 把 _dir_for 的分支 2 改成同时打 ±垂直（4 方向十字），DPS 会显著变高，需要回改文档。
##

# 挥击动画时长。命中判定是"cooldown 到点瞬间结算一次"，这个时间只影响表现。
# 表现层（whip_arc）读它来算动画进度，所以必须是常量而不是散落的魔数。
const SWING_TIME := 0.22

# 数值（由 Loadout.recompute 写入，热路径只读这些字段）
var enabled := false
var damage := 0.0
var cd_base := 0.0
var reach := 0.0
var branches := 1
var push := 0.0
var heal := 0.0
var hit_cap := 0        # 每条分支的命中上限（0 = 不限）

# 运行时状态
var cooldown := 0.0
var swing := 0.0            # 挥击动画剩余时间，>0 时表现层画弧线
var last_hit_count := 0     # 仅供 HUD 显示


func apply_stats(level: int, lo: Loadout) -> void:
	var s := UpgradeDefs.stats_for("whip", level)
	damage = float(s["dmg"]) * lo.damage_mult
	cd_base = float(s["cd"]) * lo.cooldown_mult
	reach = float(s["reach"])
	branches = int(s["branches"])
	hit_cap = int(s["hit_cap"])
	push = float(s["push"])
	heal = float(s["heal"])
	enabled = true


func update(dt: float, sim) -> void:
	if not enabled:
		return
	if swing > 0.0:
		swing -= dt
	cooldown -= dt
	if cooldown > 0.0:
		return
	cooldown = cd_base
	sim.sfx_events.append("whip")
	swing = SWING_TIME
	last_hit_count = 0

	# 回血按"每次挥鞭"结算，不按命中次数。
	#
	# 按命中次数算的时候，3 分支 × 命中上限 16 = 一鞭回 48 点，
	# 每秒回 50 血 —— 比敌人接触伤害（11 点 / 0.6 秒无敌帧 ≈ 18 血/秒）还高，
	# 玩家站着不动反而越打越健康（站桩测试 8 分钟零死亡就是这么来的）。
	# 而且它和命中上限一样是"敌群越密回得越多"的正反馈，必须掐掉。
	if heal > 0.0:
		sim.heal_player(heal)

	for b in branches:
		_sector(sim, b)


func _sector(sim, branch: int) -> void:
	var fx: float = sim.facing_x
	var fy: float = sim.facing_y
	match branch:
		1:
			fx = -fx
			fy = -fy
		2:
			# 垂直方向：把朝向旋转 90°
			fx = -sim.facing_y
			fy = sim.facing_x

	var e: EnemyPool = sim.enemies
	var g: SpatialGrid = sim.grid
	var px: float = sim.player_x
	var py: float = sim.player_y
	var r: float = reach
	var r2 := r * r
	# 每条分支的命中上限（0 = 不限）。
	# 理由同广播：没有上限时，敌群越密、一鞭抽到的人越多，
	# "堆怪"会反过来让玩家更安全。封顶后多出来的敌人才能真的贴上来。
	var hits := 0

	var n := g.query(px, py, r)
	var k := 0
	while k < n:
		if hit_cap > 0 and hits >= hit_cap:
			break
		var i := g.out[k]
		k += 1

		var dx := e.px[i] - px
		var dy := e.py[i] - py
		var d2 := dx * dx + dy * dy
		if d2 > r2:
			continue

		var dot := dx * fx + dy * fy
		if dot <= 0.0:
			continue
		if dot * dot < GameConfig.WHIP_COS_SQ * d2:
			continue

		e.hp[i] -= damage * e.dmg_mult(i)
		e.flash[i] = GameConfig.WHIP_FLASH
		last_hit_count += 1
		hits += 1

		if push > 0.0 and d2 > 1.0:
			var inv := push / sqrt(d2)
			e.px[i] += dx * inv
			e.py[i] += dy * inv
