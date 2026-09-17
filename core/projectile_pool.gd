class_name ProjectilePool
extends RefCounted
##
## 投射物对象池：递归飞刃和指针追踪共用。
##
## 两种投射物 90% 的行为一致（飞、找目标、结算伤害），只在命中时按 kind 分叉，
## 所以放进同一个池子，省掉一整套并行数组和一次遍历。
##

const KIND_BLADE := 0
const KIND_POINTER := 1

const BLADE_LIFE := 2.0
const POINTER_LIFE := 3.0

var px := PackedFloat32Array()
var py := PackedFloat32Array()
var vx := PackedFloat32Array()
var vy := PackedFloat32Array()
var dmg := PackedFloat32Array()
var life := PackedFloat32Array()
var radius := PackedFloat32Array()
var decay := PackedFloat32Array()      # 每次弹射的伤害衰减（递归飞刃）
var spd_bonus := PackedFloat32Array()  # 每次弹射的速度增益
var seek := PackedFloat32Array()       # 追踪半径（指针追踪）
var ang := PackedFloat32Array()        # 朝向，渲染用
var cd := PackedFloat32Array()         # 命中冷却，防止穿透弹同帧反复结算

var kind := PackedByteArray()
var bounces := PackedByteArray()       # 剩余弹射次数（递归深度）
var pierce := PackedByteArray()        # 剩余穿透次数
var mark := PackedByteArray()          # 命中后是否给目标打标记（指针追踪 L4+）

var count := 0


func _init(cap: int) -> void:
	px.resize(cap)
	py.resize(cap)
	vx.resize(cap)
	vy.resize(cap)
	dmg.resize(cap)
	life.resize(cap)
	radius.resize(cap)
	decay.resize(cap)
	spd_bonus.resize(cap)
	seek.resize(cap)
	ang.resize(cap)
	cd.resize(cap)
	kind.resize(cap)
	bounces.resize(cap)
	pierce.resize(cap)
	mark.resize(cap)


func spawn_blade(x: float, y: float, vel_x: float, vel_y: float, damage: float,
		times: int, decay_v: float, spd_v: float) -> bool:
	if count >= px.size():
		return false
	px[count] = x
	py[count] = y
	vx[count] = vel_x
	vy[count] = vel_y
	dmg[count] = damage
	life[count] = BLADE_LIFE
	radius[count] = GameConfig.BLADE_RADIUS
	decay[count] = decay_v
	spd_bonus[count] = spd_v
	seek[count] = 0.0
	ang[count] = atan2(vel_y, vel_x)
	cd[count] = 0.0
	kind[count] = KIND_BLADE
	bounces[count] = times
	pierce[count] = 0
	mark[count] = 0
	count += 1
	return true


func spawn_pointer(x: float, y: float, vel_x: float, vel_y: float, damage: float,
		seek_r: float, pierce_v: int, mark_v: bool) -> bool:
	if count >= px.size():
		return false
	px[count] = x
	py[count] = y
	vx[count] = vel_x
	vy[count] = vel_y
	dmg[count] = damage
	life[count] = POINTER_LIFE
	radius[count] = GameConfig.POINTER_RADIUS
	decay[count] = 1.0
	spd_bonus[count] = 0.0
	seek[count] = seek_r
	ang[count] = atan2(vel_y, vel_x)
	cd[count] = 0.0
	kind[count] = KIND_POINTER
	bounces[count] = 0
	pierce[count] = pierce_v
	mark[count] = 1 if mark_v else 0
	count += 1
	return true


func remove_at(i: int) -> void:
	var last := count - 1
	if i != last:
		px[i] = px[last]
		py[i] = py[last]
		vx[i] = vx[last]
		vy[i] = vy[last]
		dmg[i] = dmg[last]
		life[i] = life[last]
		radius[i] = radius[last]
		decay[i] = decay[last]
		spd_bonus[i] = spd_bonus[last]
		seek[i] = seek[last]
		ang[i] = ang[last]
		cd[i] = cd[last]
		kind[i] = kind[last]
		bounces[i] = bounces[last]
		pierce[i] = pierce[last]
		mark[i] = mark[last]
	count -= 1


func clear() -> void:
	count = 0
