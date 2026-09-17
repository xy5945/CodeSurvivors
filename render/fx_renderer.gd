extends Node2D
##
## 范围特效表现：广播冲击波的一圈消息波 + 随机数审判的落雷。
##
## 数量很小（同时几个波、十来道雷），直接每帧重绘即可 ——
## 强行做 MultiMesh 反而要为了极少的对象维护一套并行数组，不划算。
##

const WAVE_COLOR := Color(0.45, 0.85, 1.0, 0.55)
const WAVE_BACK_COLOR := Color(1.0, 0.85, 0.40, 0.60)

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

	# 落雷已改由 BoltRenderer 播放手绘帧序列（assets/fx/bolt/），这里只画波。
