class_name EnemyPool
extends RefCounted
##
## 敌人对象池：扁平数组（Data-Oriented），紧凑存储 + swap_remove 删除。
##
## 为什么不用"每个敌人一个节点/对象"：
##   1000 个对象 = 1000 次内存分配 + 1000 次 _process 调用 + GC 压力。
##   这里是多条 PackedFloat32Array，遍历时缓存命中率极高，且零分配。
##
## swap_remove 的代价：索引不稳定。
##   死亡时把最后一个元素搬到死者的位置 —— 所以外部不能长期持有索引。
##   空间网格每帧重建，正好不依赖跨帧索引，两者是配套的。
##

# 行走动画帧数与播放速度。anim 存的是浮点相位，渲染时取 int(anim) 得帧号。
const FRAMES := 6
const ANIM_RATE := 8.0

var px := PackedFloat32Array()
var py := PackedFloat32Array()
var hp := PackedFloat32Array()
# 出生时的血量。垃圾回收要按"血量低于 X%"来判定残血，没有它就只能拿
# EnemyDB 的基准值反推 —— 而敌人血量是随时间成长的，反推会算错。
var hp_max := PackedFloat32Array()
var speed := PackedFloat32Array()
var radius := PackedFloat32Array()
var flash := PackedFloat32Array()   # 受击闪白剩余时间
var orb_cd := PackedFloat32Array()  # 循环护盾的独立受击冷却（每个敌人独立计时）
var mark := PackedFloat32Array()    # 指针追踪的标记剩余时间：>0 时受到的所有伤害 +10%
# 控制抗性：冻结时长的倍率，越小越抗控（杂兵 1.0 / 精英 0.5 / Boss 0.18）。
# 放池里而不是让武器自己判断类型，是因为「谁能被控多久」是敌人的属性，
# 将来加新控制手段（减速、眩晕）直接读这个字段就行，不用每个武器都抄一遍类型判断。
var cc_res := PackedFloat32Array()
# 断点调试的冻结剩余时间：>0 时敌人完全不动、技能不放。
# 冻结同时附带 +50% 易伤（见 dmg_mult）—— 只冻不打等于浪费一次控制，
# 玩家会觉得"这把武器没伤害"，所以控制和增伤必须绑在一起。
var freeze := PackedFloat32Array()
# 出生的时刻（sim.time 的绝对值，秒）。
# 只为**精英**统计战斗时长：精英要的是"值得点名的持久战"，
# 它的存活时间是一条平衡指标（目标 10~20 秒），没有这个字段就只能靠
# 拍脑袋调血量。杂兵成片生灭，记这个没有意义，但仍全员同构（池的要求）。
var spawn_t := PackedFloat32Array()
# 行走动画相位，取值 [0, FRAMES)。spawn 时随机初始化 ——
# 不随机的话全场敌人整齐划一地踏步，看着像机器军团。
var anim := PackedFloat32Array()
# 敌人类型（EnemyDB.DEFS 的下标）。血量/速度/半径在 spawn 时已拷入本池，
# type 留着是因为渲染要按类型挑 MultiMesh、死亡掉落要按类型分叉。
var type := PackedInt32Array()

# 精英 / Boss 的冲刺技能状态机（普通怪永远停在状态 0，字段照常存在 ——
# 池的字段必须全员同构，kill 搬移时才能无脑整条复制）。
# skill_state: 0=无 1=蓄力(白闪+减速) 2=冲刺(锁定方向加速)
var skill_cd := PackedFloat32Array()     # 距下次技能的倒计时
var skill_state := PackedInt32Array()
var skill_t := PackedFloat32Array()      # 当前状态剩余时间
var skill_dx := PackedFloat32Array()     # 蓄力结束时锁定的冲刺方向
var skill_dy := PackedFloat32Array()
# 技能轮盘指针：0..N-1，指向 BOSS_SKILLS / ELITE_SKILLS 里的第几个技能。
# 出生随机偏移 —— 同屏 3 只精英如果同步放招，看起来像三头一体的怪物。
var skill_seq := PackedInt32Array()

var count := 0


func _init(cap: int) -> void:
	px.resize(cap)
	py.resize(cap)
	hp.resize(cap)
	hp_max.resize(cap)
	speed.resize(cap)
	radius.resize(cap)
	flash.resize(cap)
	orb_cd.resize(cap)
	mark.resize(cap)
	cc_res.resize(cap)
	freeze.resize(cap)
	anim.resize(cap)
	type.resize(cap)
	spawn_t.resize(cap)
	skill_cd.resize(cap)
	skill_state.resize(cap)
	skill_t.resize(cap)
	skill_dx.resize(cap)
	skill_dy.resize(cap)
	skill_seq.resize(cap)


func capacity() -> int:
	return px.size()


func spawn(x: float, y: float, hp_v: float, spd_v: float, rad_v: float,
		type_v: int = 0, t: float = 0.0) -> bool:
	if count >= px.size():
		return false
	px[count] = x
	py[count] = y
	hp[count] = hp_v
	hp_max[count] = hp_v
	speed[count] = spd_v
	radius[count] = rad_v
	flash[count] = 0.0
	orb_cd[count] = 0.0
	mark[count] = 0.0
	freeze[count] = 0.0
	cc_res[count] = float(EnemyDB.DEFS[type_v].get("cc_res", 1.0))
	anim[count] = randf() * float(FRAMES)
	type[count] = type_v
	spawn_t[count] = t
	skill_cd[count] = 3.0 + randf() * 2.0    # 出生先普走几秒，技能别开场就放
	skill_state[count] = 0
	skill_t[count] = 0.0
	skill_dx[count] = 0.0
	skill_dy[count] = 0.0
	skill_seq[count] = randi() % 8
	count += 1
	return true


## O(1) 删除：把最后一个活着的元素搬到 i，然后 count--。
## 调用方必须倒序遍历，否则会漏掉被搬过来的那个元素。
func kill(i: int) -> void:
	var last := count - 1
	if i != last:
		px[i] = px[last]
		py[i] = py[last]
		hp[i] = hp[last]
		hp_max[i] = hp_max[last]
		speed[i] = speed[last]
		radius[i] = radius[last]
		flash[i] = flash[last]
		orb_cd[i] = orb_cd[last]
		mark[i] = mark[last]
		freeze[i] = freeze[last]
		cc_res[i] = cc_res[last]
		anim[i] = anim[last]
		type[i] = type[last]
		spawn_t[i] = spawn_t[last]
		skill_cd[i] = skill_cd[last]
		skill_state[i] = skill_state[last]
		skill_t[i] = skill_t[last]
		skill_dx[i] = skill_dx[last]
		skill_dy[i] = skill_dy[last]
		skill_seq[i] = skill_seq[last]
	count -= 1


## 该敌人当前受到的伤害倍率（标记的 +10% 与冻结的 +50% 可叠加）。
##
## 所有伤害结算点都必须乘它 —— 之前 mark 的判定是内联在每个伤害点里的，
## 加冻结时如果照抄一遍就会变成两处重复的三元表达式，以后再加"易伤"类
## 效果还得改第三、第四处。收成一个函数，加效果只改这里。
func dmg_mult(i: int) -> float:
	var m := 1.0
	if mark[i] > 0.0:
		m += GameConfig.MARK_BONUS
	if freeze[i] > 0.0:
		m += GameConfig.FREEZE_DMG_BONUS
	return m


func clear() -> void:
	count = 0
