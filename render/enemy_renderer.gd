extends Node2D
##
## 敌人渲染：每个 (类型×帧) 一个 MultiMesh，双组 —— 彩色组 + 白色闪白层。
## 11 类敌人 × 统一 6 帧 = 66 组 × 2 = 132 次 draw call —— 2D 下这个量级
## 完全无所谓（几千次才需要担心），换来的是零 shader、零自定义数据通道。
##
## 为什么统一重采样到 6 帧：素材帧数从 1（木马）到 24（精英/报错红字）不等，
## 按"每类型实际帧数"建会到 100+ 个 MultiMesh。第 f 帧映射到表内第
## floor(f * N / 6) 帧 —— 24 帧取 0/4/8/12/16/20，动作还是连贯的；
## 3 帧的乱码会重复取帧（0/0/1/1/2/2→映射后 0/0/1/2/2/0），观感是"抖动少一点"，
## 对一只小怪足够了。
##
## 颜色方案（convert_enemy_pack.py 双输出）：
##   enemies/        彩色表 —— 主渲染，instance_color 恒白，显示素材原色
##   enemies_flash/  白剪影表 —— 受击的敌人从彩色组"搬"到这一组画，
##                     整只闪白。乘法混合闪不了彩色贴图的白，
##                     所以白层必须是独立的白剪影表。
##

const FLASH_COLOR := Color(1.0, 0.98, 0.95, 1.0)
# convert_enemy_pack.py 产出的表按"碰撞直径 = 内容高度"精确归一化（裁掉透明边），
# 内容占满整个单元格 —— 所以 quad 高度直接取碰撞直径，视觉大小 = 判定大小，
# 玩家看到的敌人有多大、就能打到多大。想整体调大/调小改这一个系数。
const VISUAL_SCALE := 1.0

var _mm: Array[MultiMesh] = []          # 彩色组
var _flash_mm: Array[MultiMesh] = []    # 白色闪白层
var _counts := PackedInt32Array()
var _flash_counts := PackedInt32Array()
var _n_types := 0


func _build_mm(tex: Texture2D, qw: float, qh: float, uv: Rect2, cap: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.mesh = SpriteMesh.quad_uv(qw, qh, uv)
	mm.instance_count = cap
	mm.visible_instance_count = 0

	var node := MultiMeshInstance2D.new()
	node.multimesh = mm
	node.texture = tex
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 白层永远画在彩色之上（后 add 的节点后绘制）
	add_child(node)
	return mm


func setup(cap: int) -> void:
	_n_types = EnemyDB.DEFS.size()
	var frames := EnemyPool.FRAMES
	_counts.resize(_n_types * frames)
	_flash_counts.resize(_n_types * frames)

	for t in _n_types:
		var d: Dictionary = EnemyDB.DEFS[t]
		var tex: Texture2D = load(d.tex)
		# 白剪影表：同目录结构，enemies/ -> enemies_flash/
		var flash_tex: Texture2D = load(String(d.tex).replace("/enemies/", "/enemies_flash/"))
		var tw: float = float(tex.get_width())
		var th: float = float(tex.get_height())
		var n: int = d.sheet_frames
		# 碰撞直径定宽，高度按单元格纵横比走，素材不被拉变形
		var qw: float = d.radius * 2.0 * VISUAL_SCALE
		var qh: float = qw * th / (tw / float(n))

		for f in frames:
			# 动画第 f 帧 → 精灵表第 floor(f*N/6) 格。
			# UV 必须归一化到 0~1（Godot 的 UV 是比例不是像素），
			# 传像素值会采样到贴图外，被钳到透明边缘 → 整只隐形。
			var sheet_f := int(float(f) * float(n) / float(frames))
			sheet_f = clampi(sheet_f, 0, n - 1)
			var cw := tw / float(n)
			var uv := Rect2(float(sheet_f) * cw / tw, 0.0, cw / tw, 1.0)
			_mm.append(_build_mm(tex, qw, qh, uv, cap))
			_flash_mm.append(_build_mm(flash_tex, qw, qh, uv, cap))


func sync(pool: EnemyPool, player_x: float) -> void:
	var frames := EnemyPool.FRAMES
	_counts.fill(0)
	_flash_counts.fill(0)
	var white := Color.WHITE

	var i := 0
	while i < pool.count:
		var t := pool.type[i]
		var f := int(pool.anim[i])
		if f >= frames:
			f = frames - 1

		var idx := t * frames + f
		var flashing := pool.flash[i] > 0.0
		var s := 1.4 if flashing else 1.0
		# 左右翻转：素材统一画成朝右，敌人在玩家左边时镜像（scale.x 取负）。
		#
		# 不往对象池里加 facing 字段 —— 敌人永远朝玩家走，朝向可以直接由
		# 相对位置算出来，加字段就要改 声明/init/spawn/kill 四处，白担风险。
		# 判定大小也不受影响：镜像不改变碰撞半径，只改画法。
		var flip := -1.0 if pool.px[i] > player_x else 1.0
		var xf := Transform2D(0.0, Vector2(s * flip, s), 0.0, Vector2(pool.px[i], pool.py[i]))

		if flashing:
			var fmm: MultiMesh = _flash_mm[idx]
			var fslot := _flash_counts[idx]
			fmm.set_instance_transform_2d(fslot, xf)
			fmm.set_instance_color(fslot, FLASH_COLOR)
			_flash_counts[idx] = fslot + 1
		else:
			var mm: MultiMesh = _mm[idx]
			var slot := _counts[idx]
			mm.set_instance_transform_2d(slot, xf)
			mm.set_instance_color(slot, white)
			_counts[idx] = slot + 1
		i += 1

	for idx in _mm.size():
		_mm[idx].visible_instance_count = _counts[idx]
		_flash_mm[idx].visible_instance_count = _flash_counts[idx]
