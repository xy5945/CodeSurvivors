extends Node2D
##
## 后 6 把武器的表现层：常驻光环 + 一次性脉冲环。
##
## 这些武器（垃圾回收 / 缓冲区溢出 / 断点调试 / 永真力场 / 全量重编译）
## 全都是范围效果，而范围效果**没有视觉就等于不存在** ——
## 玩家看不到自己身上一直开着什么，也不知道刚那一下打到了多少人。
## 所以哪怕逻辑完全正确，不画出来这 5 把武器就是废的。
##
## 全部代码绘制（draw_arc），和波/落雷/鞭子一样：
## 这几个对象数量是个位数，为它们维护 MultiMesh 不划算。
##
## 位置全部用世界坐标（相机跟随玩家，Node2D 在相机之下），
## 与 FxRenderer 保持一致。
##

# 脉冲颜色按 kind：0=回收 1=冻结 2=重编译 3=溢出
const C_GC := Color(0.36, 0.95, 0.72, 0.60)
const C_FREEZE := Color(0.55, 0.85, 1.0, 0.65)
const C_REBUILD := Color(1.0, 0.62, 0.24, 0.70)
const C_BUFFER := Color(1.0, 0.35, 0.75, 0.50)

# 常驻光环画得比脉冲淡：它一直在屏幕上，太抢眼会盖住敌人
const C_FOREVER := Color(0.75, 1.0, 0.35, 0.30)
const C_FOREVER_OFF := Color(0.55, 0.55, 0.55, 0.16)
const C_BUFFER_AURA := Color(1.0, 0.35, 0.75, 0.22)

# 蓄力环画在玩家身周固定半径，不按爆炸半径画 ——
# 满级爆炸半径 320，照实画会占掉大半个屏幕，那就不是"读秒"而是"糊屏"
const CHARGE_R := 62.0

var sim: Sim = null


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if sim == null:
		return
	_draw_auras()
	_draw_pulses()


## 常驻光环：跟着玩家走，用来回答"我现在身上开着什么"。
func _draw_auras() -> void:
	var lo: Loadout = sim.loadout
	var pos := Vector2(sim.player_x, sim.player_y)

	# 永真力场：停机时画成灰环，玩家一眼能看出安全阀启动了
	if lo.forever != null and lo.forever.enabled:
		var c := C_FOREVER if lo.forever.running else C_FOREVER_OFF
		draw_arc(pos, lo.forever.radius, 0.0, TAU, 48, c, 2.0)

	# 缓冲区溢出：环随层数变亮变粗 —— "越打越满"这件事必须看得见
	if lo.buffer != null and lo.buffer.enabled:
		var s := lo.buffer.stack_ratio()
		draw_arc(pos, lo.buffer.radius, 0.0, TAU, 48,
			Color(C_BUFFER_AURA.r, C_BUFFER_AURA.g, C_BUFFER_AURA.b,
				C_BUFFER_AURA.a + 0.45 * s), 2.0 + 2.5 * s)

	# 全量重编译蓄力：底环 + 从 12 点方向顺时针填充的进度弧。
	# 不画这个的话，玩家只会觉得"它好像卡住了没伤害"。
	if lo.rebuild != null and lo.rebuild.enabled and lo.rebuild.charging:
		var p := lo.rebuild.charge_ratio()
		draw_arc(pos, CHARGE_R, 0.0, TAU, 40, Color(1.0, 0.62, 0.24, 0.22), 2.0)
		draw_arc(pos, CHARGE_R, -PI * 0.5, -PI * 0.5 + TAU * p, 40,
			Color(1.0, 0.78, 0.32, 0.90), 3.5)


## 一次性脉冲：范围事件发生的那一下，扩散一圈然后淡出。
func _draw_pulses() -> void:
	for p in sim.fx.pulses:
		var life0: float = float(p["life0"])
		var t: float = 1.0 - float(p["life"]) / maxf(life0, 0.001)   # 0 → 1
		var r: float = lerpf(float(p["r0"]), float(p["r1"]), t)
		var c := _pulse_color(int(p["kind"]))
		var a: float = c.a * (1.0 - t)
		draw_arc(Vector2(float(p["x"]), float(p["y"])), r, 0.0, TAU, 44,
			Color(c.r, c.g, c.b, a), 3.0)


func _pulse_color(kind: int) -> Color:
	match kind:
		1:
			return C_FREEZE
		2:
			return C_REBUILD
		3:
			return C_BUFFER
	return C_GC
