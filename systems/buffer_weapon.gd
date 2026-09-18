class_name BufferWeapon
extends RefCounted
##
## 缓冲区溢出 `buffer_overflow`：以自身为中心的范围灼烧，每次命中都让下一次更疼。
##
## 名字的语义是"越界增长"：伤害加成会一直往上叠，直到撞上上限。
## 叠的是**这把武器自己的伤害**，不是全局加成 —— 所以它是"滚起来很可怕，
## 断一次就得重来"的类型。
##
## 停火 2.5 秒后加成清零。这是必要的：不衰减的话它只要打中十来次就永久满层，
## 上限就形同虚设，武器退化成"常驻 +150% 的范围伤害"。加了衰减之后，
## "维持火力"本身变成一件要主动去做的事 —— 这是玩法，不是数值削弱。
##

const IDLE_RESET := 2.5   # 多久没命中就把加成清空
const FLASH := 0.10

var enabled := false
var damage := 0.0
var cd_base := 0.0
var radius := 0.0
var gain := 0.0      # 每次命中的加成
var cap := 0.0       # 加成上限
var hit_cap := 0

var cooldown := 0.0
var stacks := 0.0    # 当前加成比例（0 ~ cap）
var _idle := 0.0     # 距上次命中过了多久


func apply_stats(level: int, lo: Loadout) -> void:
	var s := UpgradeDefs.stats_for("buffer", level)
	damage = float(s["dmg"]) * lo.damage_mult
	cd_base = float(s["cd"]) * lo.cooldown_mult
	radius = float(s["radius"])
	gain = float(s["gain"])
	cap = float(s["cap"])
	hit_cap = int(s["hit_cap"])
	enabled = true


func update(dt: float, sim) -> void:
	if not enabled:
		return

	if stacks > 0.0:
		_idle += dt
		if _idle >= IDLE_RESET:
			stacks = 0.0
			_idle = 0.0

	cooldown -= dt
	if cooldown > 0.0:
		return
	cooldown = cd_base
	_burst(sim)


func _burst(sim) -> void:
	var e: EnemyPool = sim.enemies
	var cx: float = sim.player_x
	var cy: float = sim.player_y
	var r2 := radius * radius

	# 本次爆发用爆发开始时的加成（先读后叠），
	# 否则同一波里后面的敌人享受的比前面的高，看着像 bug
	var dmg: float = damage * (1.0 + stacks)

	var n: int = sim.grid.query(cx, cy, radius, hit_cap)
	var hits := 0
	var k := 0
	while k < n and hits < hit_cap:
		var j: int = sim.grid.out[k]
		k += 1
		var dx := e.px[j] - cx
		var dy := e.py[j] - cy
		if dx * dx + dy * dy > r2:
			continue
		e.hp[j] -= dmg * e.dmg_mult(j)
		e.flash[j] = FLASH
		stacks = minf(stacks + gain, cap)
		_idle = 0.0
		hits += 1

	# 寿命 0.5s：16 帧序列按 32fps 播完。只影响表现（pulse 无伤害逻辑），
	# 但太短的话帧序列会糊成一闪而过，看不清"亮起→撕裂→消散"的过程。
	sim.fx.add_pulse(cx, cy, radius * 0.35, radius, 0.5, 3, false)
	sim.sfx_events.append("wave")


## 渲染层用：当前加成比例，用来让光环随层数变亮。
func stack_ratio() -> float:
	if cap <= 0.0:
		return 0.0
	return stacks / cap
