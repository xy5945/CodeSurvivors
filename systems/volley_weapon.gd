class_name VolleyWeapon
extends RefCounted
##
## 多线程齐射 `multithread_volley`：一次向多个**不同**敌人各射一发。
##
## 它和指针追踪共用同一套"锁定 N 个不同目标"的代码（Targeting.nearest_except），
## 区别在弹本身：指针会拐弯，齐射弹是直的 —— 打出去就不管了。
## 所以它的定位是"火力覆盖"：不需要瞄准，但每个目标只挨一发。
##
## 目标不够时重复锁定最后一个（和指针同样的处理）：
## 打 Boss 时全场只有一个目标，7 发弹必须都打它，
## 否则"弹数"这个升级项在单体战里等于白升。
##

const MAX_BOLTS := 8      # 齐射上限，预分配复用数组
const SEEK_R := 420.0     # 锁定半径

var enabled := false
var damage := 0.0
var cd_base := 0.0
var bolt_count := 1
var pspeed := 0.0
var pierce := 0
var evolved := false    # 线程池：两轮点射

var cooldown := 0.0
var fired_total := 0    # 本局开火轮数（测试用：线程池一轮变两轮）
var _second := 0.0      # 第二轮点射的倒计时（线程池）

# 复用数组：齐射是低频操作（每 0.7~1.1 秒一次），但每次要找 7 个目标，
# 每次都新建数组的话一局下来会产生上万个临时对象。
var _excl := PackedInt32Array()
var _targets := PackedInt32Array()


func _init() -> void:
	_excl.resize(MAX_BOLTS)
	_targets.resize(MAX_BOLTS)


func apply_stats(level: int, lo: Loadout) -> void:
	var s := UpgradeDefs.stats_for("volley", level)
	damage = float(s["dmg"]) * lo.damage_mult
	cd_base = float(s["cd"]) * lo.cooldown_mult
	bolt_count = int(s["bolts"])
	pspeed = float(s["pspeed"])
	pierce = int(s["pierce"])
	enabled = true
	evolved = lo.is_evolved("volley")


func update(dt: float, sim) -> void:
	if not enabled:
		return
	# 线程池：第一轮打完 0.18 秒再打第二轮，**重新锁定**当前的目标。
	# 重新锁定是关键 —— 同一个目标列表打两遍只是伤害翻倍（那是数值），
	# 重打一次目标才意味着"第二批线程接着处理新来的任务"。
	if _second > 0.0:
		_second -= dt
		# 冷却照走：等第二轮的那 0.18 秒不该白等，
		# 否则"一轮两射"实际变成"一轮变慢"，线程池就名不副实了。
		cooldown -= dt
		if _second <= 0.0:
			_second = 0.0
			var m: int = mini(bolt_count, MAX_BOLTS)
			if _pick_targets(sim, m) > 0:
				sim.sfx_events.append("shoot")
				fired_total += 1
				_fire(sim, m)
		return

	cooldown -= dt
	if cooldown > 0.0:
		return

	# 没目标就不开火、也不重置冷却：下一帧继续找。
	# 重置冷却会让"怪一冒头就已经被打了一梭子"变成"怪冒头后要等满冷却"。
	var n: int = mini(bolt_count, MAX_BOLTS)
	if _pick_targets(sim, n) <= 0:
		return

	cooldown = cd_base
	sim.sfx_events.append("shoot")
	fired_total += 1
	_fire(sim, n)
	if evolved:
		_second = 0.18


## 选出 n 个（尽量互不相同）的目标，返回找到的数量。
func _pick_targets(sim, n: int) -> int:
	var e: EnemyPool = sim.enemies
	var g: SpatialGrid = sim.grid
	var excl_n := 0
	var last := -1
	var found := 0
	for i in n:
		var t := Targeting.nearest_except(
			sim, g, e, sim.player_x, sim.player_y, SEEK_R, _excl, excl_n
		)
		if t < 0:
			t = last          # 目标不够：都打最后一个（单体战的关键）
		_targets[i] = t
		if t >= 0:
			found += 1
			last = t
			_excl[excl_n] = t
			excl_n += 1
	return found


func _fire(sim, n: int) -> void:
	var e: EnemyPool = sim.enemies

	for i in n:
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

		# 每发必须**精确指向自己的目标**，不做扇形展开。
		# 指针追踪可以打扇形是因为它的弹会拐回来；齐射弹是直的，
		# 27 度的扇角在 130px 外就是 60px 的偏差 —— 敌人半径才 10px，
		# 结果一梭子只有正中间那发命中（实测 7 发只打到 1 个目标）。
		sim.projectiles.spawn_volley(
			sim.player_x, sim.player_y,
			dx * pspeed, dy * pspeed,
			damage, pierce
		)
