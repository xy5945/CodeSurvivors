class_name PointerWeapon
extends RefCounted
##
## 指针追踪 `pointer_lock`：发射自动追踪的投射物，必定命中。
##
## 它是**唯一必中**的武器，所以单发伤害刻意压低 —— 真正的价值在第 4 级的标记：
## 被命中的目标 3 秒内受到的所有伤害 +10%，也就是说它自己打得不疼，
## 但它让**别的武器**变疼了。
##

const SPREAD := 0.18      # 多发时的角度间隔（弧度）
const MAX_BOLTS := 8      # 齐射上限，用于预分配复用数组（零分配）

var enabled := false
var damage := 0.0
var cd_base := 0.0
var seek_r := 0.0
var bolt_count := 1
var pspeed := 0.0
var pierce := 0
var apply_mark := false
var evolved := false    # 引用计数：命中后分裂成两发

var cooldown := 0.0

# 齐射临时数组：每次发射复用，不在战斗循环里分配
var _excl := PackedInt32Array()
var _targets := PackedInt32Array()


func _init() -> void:
	_excl.resize(MAX_BOLTS)
	_targets.resize(MAX_BOLTS)


func apply_stats(level: int, lo: Loadout) -> void:
	var s := UpgradeDefs.stats_for("pointer", level)
	damage = float(s["dmg"]) * lo.damage_mult
	cd_base = float(s["cd"]) * lo.cooldown_mult
	seek_r = float(s["radius"])
	bolt_count = int(s["bolts"])
	pspeed = float(s["pspeed"])
	pierce = int(s["pierce"])
	apply_mark = bool(s["mark"])
	enabled = true
	evolved = lo.is_evolved("pointer")


func update(dt: float, sim) -> void:
	if not enabled:
		return
	cooldown -= dt
	if cooldown > 0.0:
		return
	cooldown = cd_base
	sim.sfx_events.append("shoot")
	_fire(sim)


func _fire(sim) -> void:
	var e: EnemyPool = sim.enemies
	var g: SpatialGrid = sim.grid
	var n: int = mini(bolt_count, MAX_BOLTS)

	# 每发锁定一个还没锁过的目标；找不到新的就沿用上一发的目标 ——
	# 打精英/Boss 时全场只有一个目标，所有弹必须都打它，
	# 否则"弹数"升级在单体战里白升（上一轮踩过的坑，别再回去）。
	var excl_n := 0
	var last := -1
	for i in n:
		var t := Targeting.nearest_except(
			sim, g, e, sim.player_x, sim.player_y, seek_r, _excl, excl_n
		)
		if t < 0:
			t = last
		_targets[i] = t
		if t >= 0:
			last = t
			_excl[excl_n] = t
			excl_n += 1

	# 所有弹都指向同一个目标（单体战）就不做扇形展开：
	# 近距离下边弹转向来不及，会直接飞过头，实测贴脸时只有中间那发命中。
	var same := true
	for i in n:
		if _targets[i] != _targets[0]:
			same = false
			break

	var i := 0
	while i < n:
		var t: int = _targets[i]
		var dx: float = sim.facing_x
		var dy: float = sim.facing_y

		if t >= 0:
			dx = e.px[t] - sim.player_x
			dy = e.py[t] - sim.player_y
			var d := sqrt(dx * dx + dy * dy)
			if d > 0.001:
				dx /= d
				dy /= d
			else:
				dx = sim.facing_x
				dy = sim.facing_y

		# 多发时呈小扇形射出，纯视觉 —— 它们反正会各自拐向目标。
		var a := 0.0 if same else (float(i) - float(n - 1) * 0.5) * SPREAD
		var ca := cos(a)
		var sa := sin(a)
		var rx := dx * ca - dy * sa
		var ry := dx * sa + dy * ca

		sim.projectiles.spawn_pointer(
			sim.player_x, sim.player_y,
			rx * pspeed, ry * pspeed,
			damage, seek_r, pierce, apply_mark,
			1 if evolved else 0
		)
		i += 1
