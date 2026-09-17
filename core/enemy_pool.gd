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
var speed := PackedFloat32Array()
var radius := PackedFloat32Array()
var flash := PackedFloat32Array()   # 受击闪白剩余时间
var orb_cd := PackedFloat32Array()  # 循环护盾的独立受击冷却（每个敌人独立计时）
var mark := PackedFloat32Array()    # 指针追踪的标记剩余时间：>0 时受到的所有伤害 +10%
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

var count := 0


func _init(cap: int) -> void:
	px.resize(cap)
	py.resize(cap)
	hp.resize(cap)
	speed.resize(cap)
	radius.resize(cap)
	flash.resize(cap)
	orb_cd.resize(cap)
	mark.resize(cap)
	anim.resize(cap)
	type.resize(cap)
	skill_cd.resize(cap)
	skill_state.resize(cap)
	skill_t.resize(cap)
	skill_dx.resize(cap)
	skill_dy.resize(cap)


func capacity() -> int:
	return px.size()


func spawn(x: float, y: float, hp_v: float, spd_v: float, rad_v: float, type_v: int = 0) -> bool:
	if count >= px.size():
		return false
	px[count] = x
	py[count] = y
	hp[count] = hp_v
	speed[count] = spd_v
	radius[count] = rad_v
	flash[count] = 0.0
	orb_cd[count] = 0.0
	mark[count] = 0.0
	anim[count] = randf() * float(FRAMES)
	type[count] = type_v
	skill_cd[count] = 3.0 + randf() * 2.0    # 出生先普走几秒，技能别开场就放
	skill_state[count] = 0
	skill_t[count] = 0.0
	skill_dx[count] = 0.0
	skill_dy[count] = 0.0
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
		speed[i] = speed[last]
		radius[i] = radius[last]
		flash[i] = flash[last]
		orb_cd[i] = orb_cd[last]
		mark[i] = mark[last]
		anim[i] = anim[last]
		type[i] = type[last]
		skill_cd[i] = skill_cd[last]
		skill_state[i] = skill_state[last]
		skill_t[i] = skill_t[last]
		skill_dx[i] = skill_dx[last]
		skill_dy[i] = skill_dy[last]
	count -= 1


func clear() -> void:
	count = 0
