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
## 池满不是"少掉一颗"那么轻：它会让玩家身边也掉不出东西，见 _replace_farthest_gem。
##
## 磁吸状态用 PackedByteArray 存：0 = 静止等待，1 = 正在飞向玩家。
## 只有进入拾取范围的才起飞 —— 否则满屏一起飞过来，
## 既难看，又会把 O(n) 的距离计算变成 O(n) 的插值移动。
##

const KIND_GEM := 0      # 经验宝石：加经验
const KIND_PATCH := 1    # 补丁包：回血
const KIND_CHEST := 2    # 宝箱：精英怪必掉 —— 拾取＝回满血 + 清掉视野内敌人（Boss 除外）

var px := PackedFloat32Array()
var py := PackedFloat32Array()
var value := PackedInt32Array()     # 经验值（目前所有宝石都是 1，但保留字段以支持精英掉落）
var mag := PackedByteArray()        # 磁吸状态
var kind := PackedByteArray()       # 掉落物类型（见上面两个常量）

var count := 0

## 池满时"顶掉最远的那颗"用的基准点（玩家位置）。
## GemPool 不知道自己在服务谁，所以由 sim 每帧喂进来（见 sim._update_gems）。
var focus_x := 0.0
var focus_y := 0.0

## 溢出计数：池满之后又发生了几次掉落（每次都顶掉一颗最远宝石）。
## 这是个纯观测口径 —— 以前这种时刻是"静默丢一颗经验"，
## 不报错、没统计，只能靠盯 --smoke 的"地面残留"曲线才看得出异常。
var overflow := 0


func _init(cap: int) -> void:
	px.resize(cap)
	py.resize(cap)
	value.resize(cap)
	mag.resize(cap)
	kind.resize(cap)


func spawn(x: float, y: float, v: int, k: int = KIND_GEM) -> bool:
	if count >= px.size():
		if k != KIND_GEM:
			return false        # 池满时不掉回血物：它承接不了被顶掉那颗的经验（见下）
		return _replace_farthest_gem(x, y, v)
	px[count] = x
	py[count] = y
	value[count] = v
	mag[count] = 0
	kind[count] = k
	count += 1
	return true


## 池满时的兜底：顶掉离玩家最远的那一颗普通宝石。
##
## 为什么不能像以前那样直接 return false 丢掉：那次丢弃是**静默且不可恢复**的。
## 池满之后，玩家身边击杀的敌人也掉不出宝石 —— 而地上那 4096 颗全在屏幕外，
## 玩家不会跑回去捡，于是空位永远腾不出来：经验彻底断供、等级一动不动。
## 整局模拟（--smoke=20）实测到过这条死亡螺旋：8 分钟顶满池，
## 之后 11 分钟里击杀从 1.1 万涨到 3 万，等级却一直停在 Lv35。
##
## 顶掉"最远的"而不是"最旧的"：最远的那颗几乎总在屏幕外，是玩家最不可能回头捡的；
## 而新掉落就落在击杀点上（玩家身边），能被磁吸吃掉。
## 代价是每颗溢出掉落多一次 O(4096) 的扫描 —— 只在池满之后才发生，
## 后期每秒几十颗也就是几十次扫描，相比"经验凭空消失"完全值得。
##
## 回血物（补丁包 / 宝箱）不在候选里：它们不能磁吸，玩家得自己走过去踩，
## 被顶掉就等于白捡了一个宝箱。它们另有 MAX_HEAL_ON_GROUND 的上限管着。
func _replace_farthest_gem(x: float, y: float, v: int) -> bool:
	var far_i := -1
	var far_d := -1.0
	for i in count:
		if is_heal(kind[i]):
			continue
		var dx := px[i] - focus_x
		var dy := py[i] - focus_y
		var d := dx * dx + dy * dy
		if d > far_d:
			far_d = d
			far_i = i
	if far_i < 0:
		return false        # 池子里一颗普通宝石都没有（理论上不可能）：真的放不下了
	overflow += 1
	# 承接：把被顶掉那颗的经验一起带走，新宝石替它站在玩家身边。
	# 这一行让"池满"从"有代价的降级"变成"零代价的搬家" ——
	# 经验一点不丢，丢的只是"躺在地图远处"这个位置。
	# 没有它的话，池满每溢出一次就真丢一份经验（实测一局能溢出 1.4 万次），
	# 而且那个损失会随池容量来回变，容量反而成了隐性平衡杠杆。
	var carried := value[far_i]
	px[far_i] = x
	py[far_i] = y
	value[far_i] = v + carried
	mag[far_i] = 0
	kind[far_i] = KIND_GEM
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
