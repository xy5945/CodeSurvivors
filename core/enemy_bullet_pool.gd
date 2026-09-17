class_name EnemyBulletPool
extends RefCounted
##
## 敌方弹幕池：精英与 Boss 发射的子弹（玩家必须躲开的东西）。
##
## 和 ProjectilePool（玩家的弹）是两个独立的池 —— 它们的语义完全不同：
##   玩家的弹：找敌人打，走空间网格，有穿透/弹射/追踪
##   敌方的弹：找玩家打，只有一个目标，判定是 O(n) 的距离比较（子弹数 ≤ 数百）
## 合成一个池只会让两边的字段互相污染（一边有 bounces，一边有 homing）。
##
## 扁平数组 + swap_remove，理由同 EnemyPool：
##   弹幕峰值不过几百发，但每帧都要整体遍历一次做移动 + 碰撞，
##   PackedFloat32Array 的顺序访问比对象数组快一个量级。
##

# kind：渲染层据此挑颜色/形状，也决定是否追踪
const KIND_SHARD := 0     # 碎片弹（环形弹幕/扇形弹幕，直线）
const KIND_HOMING := 1    # 追踪弹（慢速但会拐弯，逼玩家改变方向而不是原路退）

var px := PackedFloat32Array()
var py := PackedFloat32Array()
var vx := PackedFloat32Array()
var vy := PackedFloat32Array()
var r := PackedFloat32Array()
var life := PackedFloat32Array()
var max_life := PackedFloat32Array()
var dmg := PackedFloat32Array()
var kind := PackedInt32Array()
var homing := PackedFloat32Array()   # 每秒可以转向的弧度（0 = 直线飞）
var spin := PackedFloat32Array()     # 视觉自旋相位

var count := 0


func _init(cap: int) -> void:
	px.resize(cap)
	py.resize(cap)
	vx.resize(cap)
	vy.resize(cap)
	r.resize(cap)
	life.resize(cap)
	max_life.resize(cap)
	dmg.resize(cap)
	kind.resize(cap)
	homing.resize(cap)
	spin.resize(cap)


func capacity() -> int:
	return px.size()


func spawn(x: float, y: float, dx: float, dy: float, spd: float,
		dmg_v: float, rad: float, life_v: float,
		kind_v: int = KIND_SHARD, homing_v: float = 0.0) -> bool:
	if count >= px.size():
		return false
	var i := count
	px[i] = x
	py[i] = y
	vx[i] = dx * spd
	vy[i] = dy * spd
	r[i] = rad
	life[i] = life_v
	max_life[i] = life_v
	dmg[i] = dmg_v
	kind[i] = kind_v
	homing[i] = homing_v
	# 每颗弹的相位随机：一波齐射如果自旋相位一致，看起来像一整块图案在转
	spin[i] = randf() * TAU
	count += 1
	return true


## O(1) 删除：把最后一个搬到 i。调用方必须倒序遍历。
func kill(i: int) -> void:
	var last := count - 1
	if i != last:
		px[i] = px[last]
		py[i] = py[last]
		vx[i] = vx[last]
		vy[i] = vy[last]
		r[i] = r[last]
		life[i] = life[last]
		max_life[i] = max_life[last]
		dmg[i] = dmg[last]
		kind[i] = kind[last]
		homing[i] = homing[last]
		spin[i] = spin[last]
	count -= 1


func clear() -> void:
	count = 0
