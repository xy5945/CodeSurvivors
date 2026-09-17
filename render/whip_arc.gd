extends Node2D
##
## 分支长鞭的表现层，同时负责两件事：
##
##   1. 常驻朝向指示 —— 一条带箭头的小短线，任何时候都画。
##      它解决的是"玩家不知道自己朝哪"：挥击每 1.2 秒才闪 0.22 秒，
##      光靠那一闪，玩家建立不起朝向认知，也就不可能理解"往哪走就打哪"。
##
##   2. 挥击扇形 —— 从起手边扫到结束边，末端画一条亮线当鞭梢。
##      直接画一整个扇形会看起来像"慢慢变大的三角形"，不像挥击。
##
## 两种画法都用本地原点（Vector2.ZERO）作中心，所以节点位置必须每帧跟随玩家。
## 这个同步在 main.gd 的 _sync_player() 里，删了它整个表现层就废了。
##

const ARC_COLOR := Color(1.0, 0.88, 0.45, 0.30)
const EDGE_COLOR := Color(1.0, 0.88, 0.45, 0.85)
const TIP_COLOR := Color(1.0, 0.97, 0.85, 0.95)
const IDLE_COLOR := Color(1.0, 0.88, 0.45, 0.38)

const SEGMENTS := 16
const HALF := PI * 0.25          # 半角 45°，与判定的 WHIP_COS_SQ 保持一致
const IDLE_LEN := 24.0
const IDLE_HEAD := 7.0
const IDLE_HALF_W := 4.5

var sim: Sim = null


# 朝向指示每帧都在，所以不再需要"只在挥击时重绘"的开关。
# 一个 Node2D 每帧画三条线的开销可以忽略。
func _process(_delta: float) -> void:
	if sim == null:
		return
	queue_redraw()


func _draw() -> void:
	if sim == null:
		return

	_draw_facing_marker()

	var w := sim.loadout.whip
	if w == null or w.swing <= 0.0:
		return

	# 进度 0 → 1：0 = 刚挥出，1 = 扫完
	var p := 1.0 - clampf(w.swing / WhipWeapon.SWING_TIME, 0.0, 1.0)
	# 缓出：起手快、收尾慢，比线性更像甩出去的一鞭
	var sweep := 1.0 - (1.0 - p) * (1.0 - p)
	# 平方淡出，末尾归零，不会突然消失
	var fade := 1.0 - p * p

	var r := w.reach
	var center := atan2(sim.facing_y, sim.facing_x)

	var b := 0
	while b < w.branches:
		var base := center
		match b:
			1:
				base = center + PI
			2:
				base = center + PI * 0.5
		_draw_sector(base, r, sweep, fade)
		b += 1


func _draw_facing_marker() -> void:
	var fx: float = sim.facing_x
	var fy: float = sim.facing_y
	if fx == 0.0 and fy == 0.0:
		return

	var tip := Vector2(fx * IDLE_LEN, fy * IDLE_LEN)
	# 垂直向量 (-fy, fx)，用来张开箭头的两笔
	var ax := -fy * IDLE_HALF_W
	var ay := fx * IDLE_HALF_W
	var back_x := fx * IDLE_HEAD
	var back_y := fy * IDLE_HEAD

	draw_line(Vector2.ZERO, tip, IDLE_COLOR, 2.0)
	draw_line(tip, Vector2(tip.x - back_x + ax, tip.y - back_y + ay), IDLE_COLOR, 2.0)
	draw_line(tip, Vector2(tip.x - back_x - ax, tip.y - back_y - ay), IDLE_COLOR, 2.0)


func _draw_sector(center: float, r: float, sweep: float, fade: float) -> void:
	var a0 := center - HALF
	var a1 := a0 + HALF * 2.0 * sweep
	if a1 <= a0:
		return

	var pts := PackedVector2Array([Vector2.ZERO])
	var i := 0
	while i <= SEGMENTS:
		var a := lerpf(a0, a1, float(i) / float(SEGMENTS))
		pts.append(Vector2(cos(a) * r, sin(a) * r))
		i += 1

	draw_colored_polygon(pts, Color(ARC_COLOR.r, ARC_COLOR.g, ARC_COLOR.b, ARC_COLOR.a * fade))
	draw_arc(Vector2.ZERO, r, a0, a1, SEGMENTS,
		Color(EDGE_COLOR.r, EDGE_COLOR.g, EDGE_COLOR.b, EDGE_COLOR.a * fade), 3.0)

	var tip := Vector2(cos(a1) * r, sin(a1) * r)
	draw_line(Vector2.ZERO, tip,
		Color(TIP_COLOR.r, TIP_COLOR.g, TIP_COLOR.b, TIP_COLOR.a * fade), 2.5)
