class_name GemPool
extends RefCounted
##
## 地面掉落物对象池：和 EnemyPool 同一套思路（扁平数组 + swap_remove）。
##
## 为什么掉落物也要池化：一局下来会掉落几千个，
## 每次 instantiate/queue_free 都会产生 GC 压力，而这恰恰发生在击杀最密集的时刻。
##
## 两种掉落物共用一个池（kind 区分）：经验宝石和补丁包（回血）。
## 它们 100% 的行为一致（躺在地上 → 进磁吸范围 → 飞向玩家 → 拾取），
## 只在拾取结算时按 kind 分叉，共用一套数组比并行维护两套更省事。
##
## 磁吸状态用 PackedByteArray 存：0 = 静止等待，1 = 正在飞向玩家。
## 只有进入拾取范围的才起飞 —— 否则满屏一起飞过来，
## 既难看，又会把 O(n) 的距离计算变成 O(n) 的插值移动。
##

const KIND_GEM := 0      # 经验宝石：加经验
const KIND_PATCH := 1    # 补丁包：回血
const KIND_CHEST := 2    # 宝箱：精英怪必掉，大额回血（后续扩展成"开升级"）

var px := PackedFloat32Array()
var py := PackedFloat32Array()
var value := PackedInt32Array()     # 经验值（目前所有宝石都是 1，但保留字段以支持精英掉落）
var mag := PackedByteArray()        # 磁吸状态
var kind := PackedByteArray()       # 掉落物类型（见上面两个常量）

var count := 0


func _init(cap: int) -> void:
	px.resize(cap)
	py.resize(cap)
	value.resize(cap)
	mag.resize(cap)
	kind.resize(cap)


func spawn(x: float, y: float, v: int, k: int = KIND_GEM) -> bool:
	if count >= px.size():
		return false        # 池满：直接放弃掉落。宁可少一颗，也不要动态扩容
	px[count] = x
	py[count] = y
	value[count] = v
	mag[count] = 0
	kind[count] = k
	count += 1
	return true


## 是不是"回血类"掉落物（补丁包 / 宝箱）。
## 回血物不参与磁吸、只有玩家踩上去才结算，这个判断在 sim 与测试里都要用，
## 放在这里避免两处各写一遍 kind 比较。
static func is_heal(k: int) -> bool:
	return k == KIND_PATCH or k == KIND_CHEST


## 宝箱专用落位：一局只有个位数颗，被杂兵宝石挤掉不可接受。
## 池满时覆盖 0 号槽（牺牲一颗宝石换一颗宝箱，稳赚的交易）。
## 返回是否真的落位成功 —— sim 靠它维护地面回血物计数。
func spawn_chest(x: float, y: float) -> bool:
	if count >= px.size():
		# 顶掉 0 号槽之前先看它是什么：如果它本身也是回血物（补丁包 / 宝箱），
		# 那地面上的回血物总数**没有变多**，就不能回报"新增了一个"。
		# 以前这里无条件 return true，sim 那边 heal_on_ground 就只增不减，
		# 累积几次之后顶到 MAX_HEAL_ON_GROUND，_drop_heal 从此提前 return ——
		# 之后精英该掉的宝箱、杂兵该掉的补丁包全被静默吞掉，玩家只会觉得
		# "这局怎么不掉血包了"。只有顶掉的是普通宝石才算真正多出一个回血物。
		var net_new := not is_heal(kind[0])
		px[0] = x
		py[0] = y
		value[0] = 0
		mag[0] = 0
		kind[0] = KIND_CHEST
		return net_new
	return spawn(x, y, 0, KIND_CHEST)


## O(1) 删除。调用方必须倒序遍历。
func remove_at(i: int) -> void:
	var last := count - 1
	if i != last:
		px[i] = px[last]
		py[i] = py[last]
		value[i] = value[last]
		mag[i] = mag[last]
		kind[i] = kind[last]
	count -= 1


func clear() -> void:
	count = 0
