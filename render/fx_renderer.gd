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

	_draw_hazards()


## 危险区（Boss"编译锁定"）：地上的预警圈，读秒结束后爆炸。
##
## 可读性的关键在"收缩的内圈"：外圈闪烁告诉你"这里危险"，
## 内圈随进度缩到中心告诉你"还有多久"。只看闪烁是读不出剩余时间的，
## 而玩家必须知道还剩几秒才能决定"是绕开还是赌一把冲过去"。
func _draw_hazards() -> void:
	for h in sim.hazards.hazards:
		var r := float(h["r"])
		var warn := maxf(float(h["warn"]), 0.01)
		var p := 1.0 - clampf(float(h["t"]) / warn, 0.0, 1.0)   # 0 → 1 的进度
		var pos := Vector2(float(h["x"]), float(h["y"]))
		# 越接近爆炸闪得越快（p 平方让加速感明显）
		var blink := 0.55 + 0.45 * sin(p * p * 46.0)
		draw_circle(pos, r, Color(1.0, 0.22, 0.20, 0.08 + 0.18 * p))
		draw_arc(pos, r, 0.0, TAU, 48,
			Color(1.0, 0.38, 0.30, (0.30 + 0.60 * p) * blink), 2.5)
		# 读秒环：从外圈缩到中心
		draw_arc(pos, maxf(r * (1.0 - p), 1.0), 0.0, TAU, 32,
			Color(1.0, 0.62, 0.42, 0.85), 2.0)
