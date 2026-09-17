extends Node2D
##
## 地面掉落物渲染：经验宝石 / 补丁包 / 宝箱三种，各一个 MultiMesh（3 次 draw call）。
##
## 必须分开：一个 MultiMesh 只能有一张贴图，而三者外观完全不同：
##   宝石   = gem.png（紫色水晶，加经验）
##   补丁包 = patch.png（绿色医疗包，回血 —— RPG Icon Pack icon_390）
##   宝箱   = 暂无贴图，用金色方块代替（精英怪必掉，大额回血；贴图到位再换）
## 玩家要在混战里一眼分清"经验 / 救命 / 大奖"。
##

const GEM_PATH := "res://assets/sprites/gem.png"
const PATCH_PATH := "res://assets/sprites/patch.png"
const WHITE := Color(1.0, 1.0, 1.0, 1.0)
const CHEST_COLOR := Color(1.0, 0.82, 0.25, 1.0)   # 金色，与绿色补丁包、紫色宝石拉开
# 碰撞半径只有 5px（直径 10），但 32x32 的水晶图标压到 10px 就糊成一团了。
# 放大到 16px 让它看得清是什么 —— 宝石是"奖励反馈"，宁可画大一点也不画糊。
const VISUAL_SCALE := 1.6
const PATCH_VISUAL_SCALE := 1.4    # patch.png 是 16px 满幅图标，稍微放大到 20px
const CHEST_SIZE := 20.0           # 宝箱是"大奖"，要明显比宝石补丁包大一圈
const MAGNET_SCALE := 1.25         # 磁吸中的额外放大，让"被吸过来了"看得见
# 回血物不磁吸（见 GameConfig.PATCH_PICKUP_RADIUS），它不会飞过来提示你它的存在，
# 只能靠自己在满地宝石里"跳"出来。呼吸脉动只加在回血物上 —— 宝石加就成了满屏抖动。
const HEAL_PULSE := 0.14           # 补丁包呼吸幅度（±14%）
const CHEST_PULSE := 0.20          # 宝箱是"大奖"，脉动更明显
const PULSE_SPEED := 4.0           # 呼吸频率（弧度/秒）

var _t := 0.0

var _gem: MultiMesh
var _patch: MultiMesh
var _chest: MultiMesh


func setup(cap: int) -> void:
	var r := GameConfig.GEM_RADIUS * 2.0 * VISUAL_SCALE
	_gem = _make(cap, SpriteMesh.quad(r), GEM_PATH)
	_patch = _make(cap, SpriteMesh.quad(GameConfig.PATCH_RADIUS * 2.0 * PATCH_VISUAL_SCALE), PATCH_PATH)
	_chest = _make(cap, SpriteMesh.quad(CHEST_SIZE), "")


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


func sync(pool: GemPool, dt: float) -> void:
	_t += dt
	var ng := 0
	var np := 0
	var nc := 0
	var pulse_p := 1.0 + sin(_t * PULSE_SPEED) * HEAL_PULSE
	var pulse_c := 1.0 + sin(_t * PULSE_SPEED) * CHEST_PULSE

	var i := 0
	while i < pool.count:
		var s := MAGNET_SCALE if pool.mag[i] == 1 else 1.0
		var pos := Vector2(pool.px[i], pool.py[i])
		match pool.kind[i]:
			GemPool.KIND_PATCH:
				s *= pulse_p
				_patch.set_instance_transform_2d(
					np, Transform2D(0.0, Vector2(s, s), 0.0, pos)
				)
				_patch.set_instance_color(np, WHITE)
				np += 1
			GemPool.KIND_CHEST:
				s *= pulse_c
				_chest.set_instance_transform_2d(
					nc, Transform2D(0.0, Vector2(s, s), 0.0, pos)
				)
				_chest.set_instance_color(nc, CHEST_COLOR)
				nc += 1
			_:
				_gem.set_instance_transform_2d(
					ng, Transform2D(0.0, Vector2(s, s), 0.0, pos)
				)
				_gem.set_instance_color(ng, WHITE)
				ng += 1
		i += 1

	_gem.visible_instance_count = ng
	_patch.visible_instance_count = np
	_chest.visible_instance_count = nc
