extends Node2D
##
## 竞技场底图 —— 电子世界（创战纪 / Tron 风格）。
##
## 它要解决两个问题：
##
## 1. 科技感：深蓝电路板底 + 青色霓虹网格（细线 / 主线 / 交点焊盘 / 方块走线），
##    另加一条会发光的边界墙。原来那版是"纯色底 + 一条几乎看不见的白线"，
##    既没有主题，也看不出自己在不在动。
##
## 2. 边界可读：竞技场内外必须是两个世界 —— 里面是通电的网格地板，
##    外面是纯黑虚空（由 clear color 提供，这里不画）。边界本身是
##    三层结构：外侧青色辉光 → 亮青墙面 → 内侧 46px 琥珀警示斜纹带。
##    玩家在屏幕边缘也能一眼看出"再走就出界了"。
##
## 全部是静态几何：只在第一次绘制时画一次，不参与每帧开销。
##

const STEP := 100.0            # 细网格间距
const MAJOR := 500.0           # 主线间距（每 5 格）
const BAND := 46.0             # 边界内侧警示带宽度
const HATCH_STEP := 23.0       # 警示斜纹间距
const OUT_GLOW := 5            # 边界外侧辉光层数
const PAD := 6.0               # 主线交点的焊盘边长

# 配色：青 = 世界（与 HUD 的经验条同色系），琥珀 = 警示（与受击红光区分开）
const FLOOR := Color(0.020, 0.052, 0.092, 1.0)
const CYAN := Color(0.30, 0.92, 1.00)
const AMBER := Color(1.00, 0.55, 0.12)
const WHITE := Color(0.80, 1.00, 1.00)


func _draw() -> void:
	var h := GameConfig.ARENA_HALF
	var s := h * 2.0
	# 地板：比虚空（clear color，近黑）亮一档、蓝一档。
	# 光靠这一层，边界就已经有一道色阶了 —— 剩下的墙和斜纹是加强。
	draw_rect(Rect2(-h, -h, s, s), FLOOR)
	_draw_traces()
	_draw_grid(h)
	_draw_pads(h)
	_draw_hatch(h)
	_draw_wall(h)
	_draw_corners(h)


## 方块走线：几条 L 形亮线，让地板像一块真的电路板而不是方格纸。
## 用独立的 RandomNumberGenerator —— 绝不能碰全局 randf()，
## 那会把每局的刷怪随机序列锁死成同一套。
func _draw_traces() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20250918
	var line := Color(CYAN.r, CYAN.g, CYAN.b, 0.22)
	var node := Color(0.60, 0.98, 1.0, 0.45)

	var coords: Array[float] = []
	var v := -1000.0
	while v <= 1000.0:
		coords.append(v)
		v += MAJOR

	for k in 12:
		var x1: float = coords[rng.randi() % coords.size()]
		var y1: float = coords[rng.randi() % coords.size()]
		var x2: float = coords[rng.randi() % coords.size()]
		var y2: float = coords[rng.randi() % coords.size()]
		var cx: float = x2
		var cy: float = y1
		draw_line(Vector2(x1, y1), Vector2(cx, cy), line, 2.0)
		draw_line(Vector2(cx, cy), Vector2(x2, y2), line, 2.0)
		draw_rect(Rect2(cx - 3.0, cy - 3.0, 6.0, 6.0), node)


func _draw_grid(h: float) -> void:
	var x := -h
	while x <= h + 0.5:
		_grid_line(Vector2(x, -h), Vector2(x, h), _is_major(x))
		x += STEP
	var y := -h
	while y <= h + 0.5:
		_grid_line(Vector2(-h, y), Vector2(h, y), _is_major(y))
		y += STEP


func _is_major(v: float) -> bool:
	return absf(fmod(v, MAJOR)) < 0.5


## 主线画三层（宽而淡 → 窄而亮），模拟霓虹灯的辉光；细线只画一层。
func _grid_line(a: Vector2, b: Vector2, major: bool) -> void:
	if major:
		draw_line(a, b, Color(CYAN.r, CYAN.g, CYAN.b, 0.06), 7.0)
		draw_line(a, b, Color(CYAN.r, CYAN.g, CYAN.b, 0.12), 3.0)
		draw_line(a, b, Color(CYAN.r, CYAN.g, CYAN.b, 0.38), 1.0)
	else:
		draw_line(a, b, Color(CYAN.r, CYAN.g, CYAN.b, 0.035), 3.0)
		draw_line(a, b, Color(CYAN.r, CYAN.g, CYAN.b, 0.14), 1.0)


## 主线交点焊盘 —— 网格的"节点感"全靠它
func _draw_pads(h: float) -> void:
	var c := Color(0.55, 0.98, 1.0, 0.50)
	var x := -h
	while x <= h + 0.5:
		if not _is_major(x):
			x += STEP
			continue
		var y := -h
		while y <= h + 0.5:
			if _is_major(y):
				draw_rect(Rect2(x - PAD * 0.5, y - PAD * 0.5, PAD, PAD), c)
			y += STEP
		x += STEP
	# 出生点：画大一点，开局能立刻知道自己在哪
	draw_rect(Rect2(-5.0, -5.0, 10.0, 10.0), Color(0.75, 1.0, 1.0, 0.75))


## 内侧警示带：先压一层琥珀底，再铺 45° 斜纹。
## 斜纹用"工程警示带"的语言，玩家不用读字就知道这里不能待。
func _draw_hatch(h: float) -> void:
	var s := h * 2.0
	var fill := Color(AMBER.r, AMBER.g, AMBER.b, 0.05)
	draw_rect(Rect2(-h, -h, s, BAND), fill)
	draw_rect(Rect2(-h, h - BAND, s, BAND), fill)
	draw_rect(Rect2(-h, -h, BAND, s), fill)
	draw_rect(Rect2(h - BAND, -h, BAND, s), fill)

	var line := Color(AMBER.r, AMBER.g, AMBER.b, 0.16)
	var x := -h
	while x <= h:
		draw_line(Vector2(x, -h), Vector2(x + BAND, -h + BAND), line, 2.0)
		draw_line(Vector2(x, h), Vector2(x + BAND, h - BAND), line, 2.0)
		x += HATCH_STEP
	var y := -h
	while y <= h:
		draw_line(Vector2(-h, y), Vector2(-h + BAND, y + BAND), line, 2.0)
		draw_line(Vector2(h, y), Vector2(h - BAND, y + BAND), line, 2.0)
		y += HATCH_STEP


## 边界墙：外侧一圈套一圈的辉光 + 亮青墙身 + 内侧一道白衬线
func _draw_wall(h: float) -> void:
	var s := h * 2.0
	for i in OUT_GLOW:
		var g := float(i + 1) * 8.0
		var a := 0.15 * (1.0 - float(i) / float(OUT_GLOW))
		draw_rect(Rect2(-h - g, -h - g, s + g * 2.0, s + g * 2.0),
			Color(CYAN.r, CYAN.g, CYAN.b, a), false, 6.0)
	draw_rect(Rect2(-h - 2.0, -h - 2.0, s + 4.0, s + 4.0),
		Color(0.40, 0.95, 1.0, 0.95), false, 4.0)
	draw_rect(Rect2(-h + 5.0, -h + 5.0, s - 10.0, s - 10.0),
		Color(WHITE.r, WHITE.g, WHITE.b, 0.16), false, 2.0)


## 四角括号：创战纪里"区域标线"的味道，也顺便盖住斜纹在角落的重叠
func _draw_corners(h: float) -> void:
	var c := Color(0.75, 1.0, 1.0, 0.90)
	var L := 70.0
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var cx: float = sx * h
			var cy: float = sy * h
			draw_line(Vector2(cx - sx * L, cy), Vector2(cx, cy), c, 3.0)
			draw_line(Vector2(cx, cy - sy * L), Vector2(cx, cy), c, 3.0)
