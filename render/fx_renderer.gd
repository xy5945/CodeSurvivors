extends Node2D
##
## 范围特效表现：广播冲击波的一圈消息波 + 随机数审判的落雷。
##
## 数量很小（同时几个波、十来道雷），直接每帧重绘即可 ——
## 强行做 MultiMesh 反而要为了极少的对象维护一套并行数组，不划算。
##

const WAVE_COLOR := Color(0.45, 0.85, 1.0, 0.55)
const WAVE_BACK_COLOR := Color(1.0, 0.85, 0.40, 0.60)
const BOLT_FILL := Color(0.95, 0.95, 1.0, 0.16)
const BOLT_EDGE := Color(0.85, 0.90, 1.0, 0.85)

var sim: Sim = null


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if sim == null:
		return

	for w in sim.fx.waves:
		var r := float(w["r"])
		if r <= 1.0:
			continue
		var back := int(w["phase"]) == 1
		var c := WAVE_BACK_COLOR if back else WAVE_COLOR
		var fade := 1.0 - (r / maxf(float(w["max"]), 1.0)) * 0.35
		# 回卷画成虚线感的细环，和扩散阶段一眼能区分开
		draw_arc(Vector2(w["x"], w["y"]), r, 0.0, TAU, 40,
			Color(c.r, c.g, c.b, c.a * fade), 3.0 if not back else 2.0)

	for b in sim.fx.bolts:
		var life := float(b["life"])
		var p := clampf(life / 0.5, 0.0, 1.0)
		var pos := Vector2(b["x"], b["y"])
		var rad := float(b["r"])
		draw_circle(pos, rad * (0.4 + p * 0.6), Color(BOLT_FILL.r, BOLT_FILL.g, BOLT_FILL.b, BOLT_FILL.a * p))
		draw_arc(pos, rad, 0.0, TAU, 24, Color(BOLT_EDGE.r, BOLT_EDGE.g, BOLT_EDGE.b, BOLT_EDGE.a * p), 2.0)
		# 一道竖直的雷光，让"落雷"看得出来是从天而降
		var h := rad * 2.4
		draw_line(pos + Vector2(0, -h), pos + Vector2(0, h * 0.6),
			Color(0.9, 0.95, 1.0, 0.8 * p), 3.0)
