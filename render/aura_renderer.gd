extends Node2D
##
## 后 6 把武器的表现层：常驻光环 + 一次性脉冲环。
##
## 这些武器（垃圾回收 / 缓冲区溢出 / 断点调试 / 永真力场 / 全量重编译）
## 全都是范围效果，而范围效果**没有视觉就等于不存在** ——
## 玩家看不到自己身上一直开着什么，也不知道刚那一下打到了多少人。
##
## 关键在于**形状要各不相同**。早期版本它们全都是"一圈实线"，只靠颜色区分，
## 结果是玩家分不清刚才是哪把武器在生效（颜色在混战里根本来不及分辨）。
## 现在每把武器有自己的形状语言：
##   永真力场 while(true) —— 会转的循环箭头环（停机时转停、变灰）
##   缓冲区溢出          —— 一圈格子槽，按层数点亮；满了方块漫出环外
##   全量重编译          —— 块状进度环（编译进度条），12 个方块依次点亮
##   垃圾回收            —— 手绘 24 帧火花序列（四周向中心汇聚内吸）
##   断点调试（冻结）    —— 六边形冰晶 + 放射线
##   全量重编译爆发      —— 方形环 + 四角方块向外
##   缓冲区爆发（溢出）  —— 手绘 16 帧能量球序列（亮起→撕裂→消散）
##
## 全部代码绘制（draw_arc / draw_polyline），和波/落雷/鞭子一样：
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

# 缓冲区爆发：16 帧序列（assets/fx/buffer_burst/burst_01..16.png，400x400）。
# 手绘能量球：亮起 → 撕裂 → 消散，末帧全透明。内容以画布中心对称，
# 峰值球径约 260px（帧 13~16 实测包围盒），缩放按球径贴齐伤害圈。
const BURST_SIZE := 400.0
const BURST_SCALE_PER_R := 1.0 / 130.0   # 纹理缩放 = 爆发半径 r * SCALE_PER_R

const BURST_FRAMES: Array[Texture2D] = [
	preload("res://assets/fx/buffer_burst/burst_01.png"),
	preload("res://assets/fx/buffer_burst/burst_02.png"),
	preload("res://assets/fx/buffer_burst/burst_03.png"),
	preload("res://assets/fx/buffer_burst/burst_04.png"),
	preload("res://assets/fx/buffer_burst/burst_05.png"),
	preload("res://assets/fx/buffer_burst/burst_06.png"),
	preload("res://assets/fx/buffer_burst/burst_07.png"),
	preload("res://assets/fx/buffer_burst/burst_08.png"),
	preload("res://assets/fx/buffer_burst/burst_09.png"),
	preload("res://assets/fx/buffer_burst/burst_10.png"),
	preload("res://assets/fx/buffer_burst/burst_11.png"),
	preload("res://assets/fx/buffer_burst/burst_12.png"),
	preload("res://assets/fx/buffer_burst/burst_13.png"),
	preload("res://assets/fx/buffer_burst/burst_14.png"),
	preload("res://assets/fx/buffer_burst/burst_15.png"),
	preload("res://assets/fx/buffer_burst/burst_16.png"),
]

# 垃圾回收：24 帧火花序列（assets/fx/gc_vacuum/gc_01..24.png，376x376）。
# 运动方向是"从四周向中心汇聚"—— 天然就是"回收"的语义，
# 比之前代码画的"碎块内吸"细腻得多。内容以画布中心对称，
# 峰值跨度约 340px（帧 12 实测包围盒），缩放按跨度贴齐回收半径。
const GC_SIZE := 376.0
const GC_SCALE_PER_R := 1.0 / 170.0     # 纹理缩放 = 回收半径 r * GC_SCALE_PER_R

const GC_FRAMES: Array[Texture2D] = [
	preload("res://assets/fx/gc_vacuum/gc_01.png"),
	preload("res://assets/fx/gc_vacuum/gc_02.png"),
	preload("res://assets/fx/gc_vacuum/gc_03.png"),
	preload("res://assets/fx/gc_vacuum/gc_04.png"),
	preload("res://assets/fx/gc_vacuum/gc_05.png"),
	preload("res://assets/fx/gc_vacuum/gc_06.png"),
	preload("res://assets/fx/gc_vacuum/gc_07.png"),
	preload("res://assets/fx/gc_vacuum/gc_08.png"),
	preload("res://assets/fx/gc_vacuum/gc_09.png"),
	preload("res://assets/fx/gc_vacuum/gc_10.png"),
	preload("res://assets/fx/gc_vacuum/gc_11.png"),
	preload("res://assets/fx/gc_vacuum/gc_12.png"),
	preload("res://assets/fx/gc_vacuum/gc_13.png"),
	preload("res://assets/fx/gc_vacuum/gc_14.png"),
	preload("res://assets/fx/gc_vacuum/gc_15.png"),
	preload("res://assets/fx/gc_vacuum/gc_16.png"),
	preload("res://assets/fx/gc_vacuum/gc_17.png"),
	preload("res://assets/fx/gc_vacuum/gc_18.png"),
	preload("res://assets/fx/gc_vacuum/gc_19.png"),
	preload("res://assets/fx/gc_vacuum/gc_20.png"),
	preload("res://assets/fx/gc_vacuum/gc_21.png"),
	preload("res://assets/fx/gc_vacuum/gc_22.png"),
	preload("res://assets/fx/gc_vacuum/gc_23.png"),
	preload("res://assets/fx/gc_vacuum/gc_24.png"),
]

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

	# 永真力场：while(true) 的循环符 —— 虚线环 + 3 个追着跑的循环箭头。
	# 停机时不转 + 变灰，玩家一眼能看出安全阀启动了。
	if lo.forever != null and lo.forever.enabled:
		var run: bool = lo.forever.running
		var base := C_FOREVER if run else C_FOREVER_OFF
		var r := lo.forever.radius
		var spin: float = sim.time * 1.6 if run else 0.0
		_dashed_ring(pos, r, base, 10, 0.5, spin, 2.0)
		if run:
			var i := 0
			while i < 3:
				var a := spin + TAU * float(i) / 3.0
				_chevron(pos + Vector2(cos(a), sin(a)) * r, a + PI * 0.5, 7.0,
					Color(base.r, base.g, base.b, 0.62), 2.5)
				i += 1

	# 缓冲区溢出：12 格"槽"，按层数从 12 点方向顺时针点亮；满了还有方块漫出环外。
	# 用格子而不是整圈实线，是为了让"叠了几层"能数出来 —— 这是这把武器唯一的反馈。
	if lo.buffer != null and lo.buffer.enabled:
		var s := lo.buffer.stack_ratio()
		var r := lo.buffer.radius
		draw_arc(pos, r, 0.0, TAU, 48,
			Color(C_BUFFER_AURA.r, C_BUFFER_AURA.g, C_BUFFER_AURA.b, 0.16), 1.5)
		var segs := 12
		var step := TAU / float(segs)
		var lit_f := s * float(segs)
		var i := 0
		while i < segs:
			var a0 := -PI * 0.5 + step * float(i)
			var f := clampf(lit_f - float(i), 0.0, 1.0)
			if f > 0.01:
				# 段间留缝（0.82），看着才是一格一格而不是一整圈
				draw_arc(pos, r, a0, a0 + step * f * 0.82, 6,
					Color(C_BUFFER_AURA.r, C_BUFFER_AURA.g, C_BUFFER_AURA.b,
						0.30 + 0.55 * s), 2.5 + 2.0 * s)
			i += 1
		if s > 0.85:
			var spill: float = (s - 0.85) / 0.15
			var k := 0
			while k < 4:
				var a := sim.time * 0.8 + TAU * float(k) / 4.0
				_square(pos + Vector2(cos(a), sin(a)) * (r + 8.0), 3.4, a,
					Color(C_BUFFER_AURA.r, C_BUFFER_AURA.g, C_BUFFER_AURA.b, 0.40 * spill))
				k += 1

	# 全量重编译蓄力：块状进度环（编译进度条）。
	# 不画这个的话，玩家只会觉得"它好像卡住了没伤害"。
	if lo.rebuild != null and lo.rebuild.enabled and lo.rebuild.charging:
		var p := lo.rebuild.charge_ratio()
		draw_arc(pos, CHARGE_R, 0.0, TAU, 40, Color(1.0, 0.62, 0.24, 0.18), 2.0)
		var segs2 := 12
		var step2 := TAU / float(segs2)
		var lit2 := p * float(segs2)
		var i2 := 0
		while i2 < segs2:
			var a := -PI * 0.5 + step2 * float(i2)
			var on := float(i2) < lit2
			var col := Color(1.0, 0.78, 0.32, 0.90) if on else Color(1.0, 0.62, 0.24, 0.22)
			_square(pos + Vector2(cos(a), sin(a)) * CHARGE_R, 4.2 if on else 3.0,
				a + PI * 0.25, col)
			i2 += 1


## 一次性脉冲：范围事件发生的那一下，扩散一圈然后淡出。
## 形状按 kind 分开 —— 同样是一圈线的话，玩家只能靠颜色分辨，混战里分辨不出来。
func _draw_pulses() -> void:
	for p in sim.fx.pulses:
		var life0: float = float(p["life0"])
		var t: float = 1.0 - float(p["life"]) / maxf(life0, 0.001)   # 0 → 1
		var r: float = lerpf(float(p["r0"]), float(p["r1"]), t)
		var c := _pulse_color(int(p["kind"]))
		var col := Color(c.r, c.g, c.b, c.a * (1.0 - t))
		var pos := Vector2(float(p["x"]), float(p["y"]))
		match int(p["kind"]):
			0:
				_pulse_gc_frames(pos, float(p["r1"]), t)
			1:
				_pulse_freeze(pos, r, t, col)
			2:
				_pulse_rebuild(pos, r, t, col)
			3:
				_pulse_buffer_frames(pos, float(p["r1"]), t)


## 垃圾回收：手绘 24 帧火花序列，四周向中心汇聚 —— "垃圾被吸走"。
func _pulse_gc_frames(c: Vector2, r1: float, t: float) -> void:
	var idx := mini(int(t * GC_FRAMES.size()), GC_FRAMES.size() - 1)
	var tex := GC_FRAMES[idx]
	var sc: float = r1 * GC_SCALE_PER_R
	draw_texture_rect(tex, Rect2(c - Vector2(GC_SIZE, GC_SIZE) * 0.5 * sc,
		Vector2(GC_SIZE, GC_SIZE) * sc), false)


## 断点调试（冻结）：六边形冰晶 + 放射线，和圆环一眼区分。
func _pulse_freeze(c: Vector2, r: float, t: float, col: Color) -> void:
	_poly_ring(c, r, 6, t * 0.6, col, 3.0)
	var k := 0
	while k < 6:
		var a := TAU * float(k) / 6.0 + t * 0.6
		var d := Vector2(cos(a), sin(a))
		draw_line(c + d * r * 0.35, c + d * r, col, 2.0)
		k += 1


## 全量重编译：方形环（重编译是"方"的、块状的）+ 四角向外飞。
func _pulse_rebuild(c: Vector2, r: float, t: float, col: Color) -> void:
	_poly_ring(c, r, 4, PI * 0.25 + t * 0.5, col, 3.5)
	var k := 0
	while k < 4:
		var a := PI * 0.25 + TAU * float(k) / 4.0 + t * 0.5
		var rr := r * 1.30 + 26.0 * t
		_square(c + Vector2(cos(a), sin(a)) * rr, lerpf(6.0, 3.0, t), a,
			Color(col.r, col.g, col.b, col.a * 0.85))
		k += 1


## 缓冲区溢出：手绘 16 帧能量球序列（亮起 → 撕裂 → 消散）。
## 帧本身自带起承转合，这里只负责按进度取帧、把球径对齐伤害圈。
func _pulse_buffer_frames(c: Vector2, r1: float, t: float) -> void:
	var idx := mini(int(t * BURST_FRAMES.size()), BURST_FRAMES.size() - 1)
	var tex := BURST_FRAMES[idx]
	var sc: float = r1 * BURST_SCALE_PER_R
	draw_texture_rect(tex, Rect2(c - Vector2(BURST_SIZE, BURST_SIZE) * 0.5 * sc,
		Vector2(BURST_SIZE, BURST_SIZE) * sc), false)


func _pulse_color(kind: int) -> Color:
	match kind:
		1:
			return C_FREEZE
		2:
			return C_REBUILD
		3:
			return C_BUFFER
	return C_GC


# ---- 绘制小工具（几个形状都要用，抽出来免得每处都手写三角函数） ----

func _dashed_ring(c: Vector2, r: float, col: Color, segs: int, duty: float,
		rot: float, w: float) -> void:
	var step := TAU / float(segs)
	var on := step * duty
	var i := 0
	while i < segs:
		var a0 := rot + step * float(i)
		draw_arc(c, r, a0, a0 + on, 8, col, w)
		i += 1


func _poly_ring(c: Vector2, r: float, sides: int, rot: float, col: Color,
		w: float) -> void:
	var pts := PackedVector2Array()
	var i := 0
	while i <= sides:
		var a := rot + TAU * float(i) / float(sides)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
		i += 1
	draw_polyline(pts, col, w)


## 箭头：ang 是它指的方向
func _chevron(p: Vector2, ang: float, size: float, col: Color, w: float = 2.0) -> void:
	var d := Vector2(cos(ang), sin(ang))
	var n := Vector2(-d.y, d.x)
	var tip := p + d * size
	draw_line(tip, p + n * size * 0.8, col, w)
	draw_line(tip, p - n * size * 0.8, col, w)


func _square(c: Vector2, half: float, rot: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var i := 0
	while i < 4:
		var a := rot + PI * 0.25 + PI * 0.5 * float(i)
		pts.append(c + Vector2(cos(a), sin(a)) * half)
		i += 1
	draw_colored_polygon(pts, col)
