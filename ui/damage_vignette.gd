class_name DamageVignette
extends CanvasLayer
##
## 屏幕边缘的警示光。三件事：
##
## 1. 受击闪红 —— 玩家一掉血，四周红光闪一下（0.45 秒衰减）。
##    只靠血条掉一格太安静了；屏幕上百个敌人时玩家根本不看血条。
##
## 2. 残血脉冲 —— 血量低于 30% 后持续低频呼吸，越接近 0 越亮。
##    这是"你快死了"的环境提示，不占 HUD 空间。
##
## 3. 接近边界警示 —— 离某一边太近时，**那一侧**亮起琥珀光。
##    世界里的墙解决"看不看得见边界"，这个解决"有没有注意到自己在往边上走"。
##    用琥珀而不是红：红已经被"受伤"占用了，两套提示必须分色。
##
## 实现：启动时生成 5 张 160x90 的 alpha 渐变贴图，拉伸到全屏。
##   1 张四边渐变（红） + 4 张单边渐变（琥珀 × 4 个方向）
## 比每帧画几十个矩形便宜，比写 shader 好调试，且不需要任何美术资源。
##

const TEX_W := 160
const TEX_H := 90
const FALLOFF := 22.0        # 贴图内的渐隐宽度（像素）；拉伸 4 倍后 ≈ 88 屏幕像素
const RAMP_POW := 2.4
const RAMP_MAX := 0.90
const HURT_TIME := 0.45      # 受击红光从最亮到消失的时长（秒）
const HURT_PEAK := 0.62
const LOW_HP := 0.30         # 低于这个血量比例开始持续脉冲
const EDGE_PEAK := 0.50

const RED := Color(1.00, 0.13, 0.12)
const AMBER := Color(1.00, 0.52, 0.10)

var _root: Control
var _dmg: TextureRect
var _edges: Array[TextureRect] = []

var _hurt := 0.0
var _last_hp := 0.0
var _time := 0.0


func _ready() -> void:
	layer = 5                  # HUD 之上、升级弹窗（10）之下
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_dmg = _make_rect(_border_tex(RED))
	_edges.append(_make_rect(_side_tex(0, AMBER)))
	_edges.append(_make_rect(_side_tex(1, AMBER)))
	_edges.append(_make_rect(_side_tex(2, AMBER)))
	_edges.append(_make_rect(_side_tex(3, AMBER)))


func _make_rect(tex: Texture2D) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.modulate.a = 0.0
	_root.add_child(r)
	return r


func _border_tex(c: Color) -> ImageTexture:
	var img := Image.create(TEX_W, TEX_H, false, Image.FORMAT_RGBA8)
	for y in TEX_H:
		for x in TEX_W:
			var d := mini(mini(x, TEX_W - 1 - x), mini(y, TEX_H - 1 - y))
			img.set_pixel(x, y, Color(c.r, c.g, c.b, _ramp(float(d))))
	return ImageTexture.create_from_image(img)


## side: 0 左 / 1 右 / 2 上 / 3 下
func _side_tex(side: int, c: Color) -> ImageTexture:
	var img := Image.create(TEX_W, TEX_H, false, Image.FORMAT_RGBA8)
	for y in TEX_H:
		for x in TEX_W:
			var d := 0
			match side:
				0: d = x
				1: d = TEX_W - 1 - x
				2: d = y
				_: d = TEX_H - 1 - y
			img.set_pixel(x, y, Color(c.r, c.g, c.b, _ramp(float(d))))
	return ImageTexture.create_from_image(img)


func _ramp(d: float) -> float:
	var t := clampf(d / FALLOFF, 0.0, 1.0)
	return pow(1.0 - t, RAMP_POW) * RAMP_MAX


## 每帧由 main.gd 调用。放在 HUD 之后，这样红光盖在 UI 上 —— 受击时
## 整个屏幕一起红，比只红边缘更容易被余光捕捉到。
func update_fx(delta: float, sim: Sim) -> void:
	_time += delta

	# 掉血检测放在这里而不是 sim 里：任何来源的掉血都能捕获，
	# 以后加"环境伤害""Boss 技能伤害"都不用再改 sim。
	if sim.player_hp < _last_hp - 0.001:
		_hurt = 1.0
	_last_hp = sim.player_hp
	_hurt = maxf(_hurt - delta / HURT_TIME, 0.0)

	var low := 0.0
	if sim.max_hp > 0.0:
		var frac := clampf(sim.player_hp / sim.max_hp, 0.0, 1.0)
		if frac < LOW_HP:
			low = (1.0 - frac / LOW_HP) * (0.30 + 0.14 * sin(_time * 7.0))
	_dmg.modulate.a = clampf(maxf(_hurt * HURT_PEAK, low), 0.0, 1.0)

	var h := GameConfig.ARENA_HALF
	var warn := GameConfig.ARENA_EDGE_WARN
	var dists: Array[float] = [
		sim.player_x + h,      # 离左边
		h - sim.player_x,      # 离右边
		sim.player_y + h,      # 离上边
		h - sim.player_y,      # 离下边
	]
	var any := _dmg.modulate.a > 0.01
	for i in 4:
		var p := clampf((warn - dists[i]) / warn, 0.0, 1.0)
		var a := p * EDGE_PEAK * (0.78 + 0.22 * sin(_time * 9.0))
		_edges[i].modulate.a = a
		if a > 0.01:
			any = true
	_root.visible = any
