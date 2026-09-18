extends Node2D
##
## 循环护盾渲染：读 OrbitWeapon 已经算好的 ox/oy，不去重复算三角函数。
##
## 环绕物上限 12 个，直接每个给一个 Sprite2D 播帧序列（shield_fx.png，
## 30 帧 10x3 精灵表），不需要 MultiMesh。
##

const ORB_SHEET := preload("res://assets/sprites/shield_fx.png")
const FRAME_COUNT := 30
const ANIM_FPS := 20.0
const MAX_ORBITERS := 12

var _sprites: Array[Sprite2D] = []
var _anim_time := 0.0


func setup() -> void:
	for i in MAX_ORBITERS:
		var s := Sprite2D.new()
		s.texture = ORB_SHEET
		s.hframes = 10
		s.vframes = 3
		s.visible = false
		add_child(s)
		_sprites.append(s)


func _process(delta: float) -> void:
	_anim_time += delta


func sync(orb) -> void:
	if orb == null or not orb.enabled:
		for s in _sprites:
			s.visible = false
		return

	# 进化（嵌套循环）后是双层：渲染数量由 draw_count 给，不再是 count
	var shown: int = orb.draw_count if orb.draw_count > 0 else orb.count
	var frame := int(_anim_time * ANIM_FPS) % FRAME_COUNT
	var i := 0
	while i < MAX_ORBITERS:
		var s := _sprites[i]
		if i >= shown:
			s.visible = false
		else:
			s.visible = true
			s.position = Vector2(orb.ox[i], orb.oy[i])
			s.frame = frame
		i += 1
