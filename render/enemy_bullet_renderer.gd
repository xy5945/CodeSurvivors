extends Node2D
##
## 敌方弹幕渲染：一个 MultiMesh + 代码生成的圆形辉光贴图。
##
## 为什么代码生成贴图而不是用美术素材：弹幕是"纯功能件"，形状越简单越容易读。
## 一个带径向衰减的圆点，配加法混合（BLEND_MODE_ADD）就是发光的能量弹 ——
## 在深蓝电路板底图上足够醒目，而且换配色只改一个常量。
##
## 视觉尺寸刻意略大于判定半径（判定 4.5，显示约 8）：
## 反过来会让玩家觉得"明明没碰到却掉血"，那是竞技游戏才需要的宽容度。
##
## 显示位置直接取池坐标，不做插值 —— 弹速最高 196px/s，一帧移动 3.3px，
## 插值带来的观感提升为零，却要多维护一份上一帧坐标。
##

const DOT_SIZE := 16
# 弹幕是"敌意"的信号，用暖色系（红橙），和玩家那套青白冷色投射物天然区分。
const COLOR_SHARD := Color(1.0, 0.52, 0.28, 0.95)
const COLOR_HOMING := Color(1.0, 0.30, 0.72, 0.95)
const SHARD_SCALE := 1.0
const HOMING_SCALE := 1.35

var _mm: MultiMesh
var _pulse := 0.0


func setup(cap: int) -> void:
	var mesh := SpriteMesh.quad(float(DOT_SIZE))
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_2D
	_mm.use_colors = true
	_mm.mesh = mesh
	_mm.instance_count = cap
	_mm.visible_instance_count = 0

	var node := MultiMeshInstance2D.new()
	node.multimesh = _mm
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.texture = _make_dot()
	# 加法混合：弹幕叠在自己人或地形上都还是亮的，不会被背景吃掉
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	node.material = mat
	add_child(node)


func _make_dot() -> ImageTexture:
	var img := Image.create(DOT_SIZE, DOT_SIZE, false, Image.FORMAT_RGBA8)
	var c := float(DOT_SIZE - 1) * 0.5
	for y in DOT_SIZE:
		for x in DOT_SIZE:
			var dx := float(x) - c
			var dy := float(y) - c
			var d := sqrt(dx * dx + dy * dy) / c
			var a := clampf(1.0 - d, 0.0, 1.0)
			# 平方衰减 + 中心过曝：得到一个"核心实、边缘散"的辉光点
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a * a))
	return ImageTexture.create_from_image(img)


func _process(delta: float) -> void:
	_pulse += delta


func sync(pool: EnemyBulletPool) -> void:
	var n := 0
	var base := sin(_pulse * 9.0) * 0.12
	var i := 0
	while i < pool.count:
		var homing := pool.kind[i] == EnemyBulletPool.KIND_HOMING
		var s := (HOMING_SCALE if homing else SHARD_SCALE) * (1.0 + base * (1.4 if homing else 1.0))
		_mm.set_instance_transform_2d(n,
			Transform2D(0.0, Vector2(s, s), 0.0, Vector2(pool.px[i], pool.py[i])))
		_mm.set_instance_color(n, COLOR_HOMING if homing else COLOR_SHARD)
		n += 1
		i += 1
	_mm.visible_instance_count = n
