extends Node2D
##
## 落雷表现：16 帧手绘序列（雷击落地 → 火花爆发 → 消散）。
##
## 仿真层（sim.fx.bolts）只管伤害与生命周期，这里只负责"放片"：
## 每帧按剩余寿命换算进度，从序列里取对应贴图。
##
## 并发量很小（同时最多十来道），Sprite2D 池直接复用即可，
## 不值得为它上 MultiMesh。
##
## 素材约定（assets/fx/bolt/bolt_01..16.png，400x400）：
##   - 爆点基线在 y≈360，水平中心 x≈205（已实测 16 帧包围盒）
##   - 有效内容宽度约 230px（落地环），缩放按 r/96 让环径略大于伤害圈
##

const SIZE := 400.0
const BASE := Vector2(205.0, 360.0)   # 素材里的爆点位置（画布中心是 200,200）
const SCALE_PER_R := 1.0 / 96.0       # 纹理缩放 = 落雷半径 r * SCALE_PER_R
const SKY_FLASH := 0.15               # 进度前 15% 画一道从天而降的雷光柱

const FRAMES: Array[Texture2D] = [
	preload("res://assets/fx/bolt/bolt_01.png"),
	preload("res://assets/fx/bolt/bolt_02.png"),
	preload("res://assets/fx/bolt/bolt_03.png"),
	preload("res://assets/fx/bolt/bolt_04.png"),
	preload("res://assets/fx/bolt/bolt_05.png"),
	preload("res://assets/fx/bolt/bolt_06.png"),
	preload("res://assets/fx/bolt/bolt_07.png"),
	preload("res://assets/fx/bolt/bolt_08.png"),
	preload("res://assets/fx/bolt/bolt_09.png"),
	preload("res://assets/fx/bolt/bolt_10.png"),
	preload("res://assets/fx/bolt/bolt_11.png"),
	preload("res://assets/fx/bolt/bolt_12.png"),
	preload("res://assets/fx/bolt/bolt_13.png"),
	preload("res://assets/fx/bolt/bolt_14.png"),
	preload("res://assets/fx/bolt/bolt_15.png"),
	preload("res://assets/fx/bolt/bolt_16.png"),
]

var sim: Sim = null

var _pool: Array[Sprite2D] = []


func _process(_delta: float) -> void:
	queue_redraw()
	if sim == null:
		return

	var bolts: Array = sim.fx.bolts
	while _pool.size() < bolts.size():
		var sp := Sprite2D.new()
		sp.centered = true
		add_child(sp)
		_pool.append(sp)

	for i in _pool.size():
		var sp := _pool[i]
		if i >= bolts.size():
			sp.visible = false
			continue
		var b: Dictionary = bolts[i]
		var p := _progress(b)
		var sc: float = float(b["r"]) * SCALE_PER_R
		sp.texture = FRAMES[mini(int(p * FRAMES.size()), FRAMES.size() - 1)]
		sp.scale = Vector2(sc, sc)
		# 素材爆点对准落雷落点：把基线平移回原点
		sp.position = Vector2(b["x"], b["y"]) - (BASE - Vector2(SIZE, SIZE) * 0.5) * sc
		sp.visible = true


## 进度前段补一道竖直雷光柱，保证"从天而降"的阅读性
## （序列第 1 帧已经是落地火花，天上的部分由这里补）
func _draw() -> void:
	if sim == null:
		return
	for b in sim.fx.bolts:
		var p := _progress(b)
		if p >= SKY_FLASH:
			continue
		var a := 1.0 - p / SKY_FLASH
		var pos := Vector2(b["x"], b["y"])
		draw_line(pos + Vector2(0, -300), pos + Vector2(0, 24),
			Color(0.85, 0.95, 1.0, 0.7 * a), 3.0)
		draw_line(pos + Vector2(0, -300), pos + Vector2(0, 24),
			Color(1.0, 1.0, 1.0, 0.45 * a), 1.5)


func _progress(b: Dictionary) -> float:
	var life0 := float(b.get("life0", 0.55))
	return clampf(1.0 - float(b["life"]) / life0, 0.0, 0.999)
