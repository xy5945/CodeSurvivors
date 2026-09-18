extends Node2D
##
## 投射物渲染：递归飞刃走 MultiMesh（量可能很大，纯贴图不需要逐帧动画），
## 指针追踪走 Sprite2D 池播帧序列（30 帧蓝色火焰，pointer_fx.png 10x3 表）。
##
## 指针为什么不用 MultiMesh：一个 MultiMesh 只能有一张图的一个区域，
## 逐实例换帧要么拆 N 个 MultiMesh 要么写 shader + instance_custom_data。
## 指针是主力的常驻弹（能穿透），但同屏几十个 Sprite2D 在 2D 批处理下
## 依然是同一纹理的一批 draw call，性能可接受。
##
## 火焰贴图亮头朝右（0 弧度方向），rotation 直接用 pool.ang。
## 每颗弹在（重新）出现时取随机动画相位，否则一波齐射像复制粘贴。
##

const BLADE_PATH := "res://assets/sprites/proj_blade.png"
const POINTER_SHEET := preload("res://assets/sprites/pointer_fx.png")
const WHITE := Color(1.0, 1.0, 1.0, 1.0)
const BASE_SIZE := 12.0
const BLADE_SCALE := 1.2
const POINTER_SCALE := 1.0   # 素材内容占 14/16 帧，接近旧色块的视觉尺寸
# 多线程齐射的弹没有贴图：它是"一串并发的线程"，画成纯色小方块最贴题，
# 也省一张素材。颜色走 MultiMesh 的实例色，青色和递归飞刃/指针一眼分得开。
const VOLLEY_SIZE := 9.0
const C_VOLLEY := Color(0.40, 0.95, 1.0, 1.0)
const POINTER_FRAMES := 30
const POINTER_FPS := 20.0
# 贴图里刀尖指向的角度修正。素材刀身若不是朝右（0 弧度方向），改这一个常量即可。
const BLADE_ROT_OFFSET := 0.0

var _blade: MultiMesh
var _volley: MultiMesh
var _ptr_sprites: Array[Sprite2D] = []
var _ptr_phase := PackedFloat32Array()   # 每颗弹自己的动画偏移
var _prev_alive := 0                     # 上一帧的投射物总数（池是紧凑数组，下标 >= 它的就是新弹）
var _anim_time := 0.0


func setup(cap: int) -> void:
	_blade = _make(cap, SpriteMesh.quad(BASE_SIZE * BLADE_SCALE), BLADE_PATH)
	_volley = _make(cap, SpriteMesh.quad(VOLLEY_SIZE), "")

	_ptr_phase.resize(cap)
	for i in cap:
		var s := Sprite2D.new()
		s.texture = POINTER_SHEET
		s.hframes = 10
		s.vframes = 3
		s.visible = false
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(s)
		_ptr_sprites.append(s)


func _make(cap: int, mesh: ArrayMesh, tex_path: String) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = cap
	mm.visible_instance_count = 0

	var node := MultiMeshInstance2D.new()
	node.multimesh = mm
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if tex_path != "":
		node.texture = load(tex_path)
	add_child(node)
	return mm


func _process(delta: float) -> void:
	_anim_time += delta


func sync(pool: ProjectilePool) -> void:
	var nb := 0
	var np := 0
	var nv := 0
	var base_frame := int(_anim_time * POINTER_FPS) % POINTER_FRAMES

	var i := 0
	while i < pool.count:
		if pool.kind[i] == ProjectilePool.KIND_BLADE:
			_blade.set_instance_transform_2d(
				nb, Transform2D(pool.ang[i] + BLADE_ROT_OFFSET, Vector2.ONE, 0.0, Vector2(pool.px[i], pool.py[i]))
			)
			_blade.set_instance_color(nb, WHITE)
			nb += 1
		elif pool.kind[i] == ProjectilePool.KIND_VOLLEY:
			_volley.set_instance_transform_2d(
				nv, Transform2D(pool.ang[i], Vector2.ONE, 0.0, Vector2(pool.px[i], pool.py[i]))
			)
			_volley.set_instance_color(nv, C_VOLLEY)
			nv += 1
		else:
			# 池用 swap_remove 保持紧凑：下标 >= 上一帧总数的必然是刚 spawn 的弹
			if i >= _prev_alive:
				_ptr_phase[i] = randf() * float(POINTER_FRAMES)
			var s := _ptr_sprites[np]
			s.visible = true
			s.position = Vector2(pool.px[i], pool.py[i])
			s.rotation = pool.ang[i]
			s.frame = (int(_ptr_phase[i]) + base_frame) % POINTER_FRAMES
			np += 1
		i += 1

	_blade.visible_instance_count = nb
	_volley.visible_instance_count = nv
	while np < _ptr_sprites.size():
		_ptr_sprites[np].visible = false
		np += 1
	_prev_alive = pool.count
