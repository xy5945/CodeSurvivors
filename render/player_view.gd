class_name PlayerView
extends Sprite2D
##
## 玩家角色：单实例，用 Sprite2D 的 hframes 切帧，不需要 MultiMesh。
##
## 素材 player.png 是 6 帧 × 16x32 的走路循环，角色内容占下半部（约 14x24），
## 上方 7~8 像素是空的 —— 所以 offset 要往上抬一点，让"身体中心"对齐玩家坐标，
## 否则角色看起来会整体偏下，跟碰撞体对不上。
##
## 朝向只用 flip_h（左右镜像）：俯视视角下不存在"上下朝向"的贴图，
## 上下移动沿用上一次的左右朝向，这与操作文档里的规则一致。
##

const FRAME_PATH := "res://assets/sprites/player.png"
const WALK_FRAMES := 6
const ANIM_RATE := 10.0
# 帧内容中心在 y≈20，帧中心在 y=16 —— 上抬 4px 让角色身体落在玩家坐标上
const OFFSET_Y := -4.0

var _phase := 0.0
# 角色配色：五个角色共用一张贴图，靠染色区分（另做五套素材不划算）。
# 白（1,1,1）= 不改色，早期只有一种角色时就是这个值。
var _tint := Color(1.0, 1.0, 1.0)


func setup(tint := Color(1.0, 1.0, 1.0)) -> void:
	_tint = tint
	texture = load(FRAME_PATH)
	hframes = WALK_FRAMES
	vframes = 1
	centered = true
	offset = Vector2(0.0, OFFSET_Y)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## moving：本帧是否有移动输入。静止时回到第 0 帧（站立姿态），
## 不保留走路的中间帧，否则停下来时会"金鸡独立"。
func update_view(dt: float, moving: bool, facing_x: float, iframe: float) -> void:
	if moving:
		_phase += dt * ANIM_RATE
		if _phase >= float(WALK_FRAMES):
			_phase -= float(WALK_FRAMES)
		frame = int(_phase)
	else:
		frame = 0

	flip_h = facing_x < 0.0
	# 无敌帧闪烁：受伤后短暂半透明，让玩家知道"现在打不到我"
	modulate = Color(_tint.r, _tint.g, _tint.b, 0.45 if iframe > 0.0 else 1.0)
