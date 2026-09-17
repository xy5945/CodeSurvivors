class_name EnemyDB
extends RefCounted
##
## 敌人类型表：11 类敌人的全部数据集中在这里，改数值只改这里。
##
## 设计依据（操作与界面设计文档"敌人分化"一节 + M2 实测结论）：
##   - 广播 361 杀/秒 vs 飞刃 4.9 杀/秒的 78 倍差距是内容缺口 ——
##     场上必须有"值得单体武器点名"的高血量目标，分化就是补这个缺口。
##   - 投放节奏：0-2 分钟只有弱杂兵 → 2-6 分钟混入中期类型 →
##     6 分钟起精英定时出场 → 18 分钟 Boss 编译器反噬终局决战（不进波次表）。
##   - 数值锚点：最弱怪 hp=10（低于长鞭 Lv1 的 12，开局必须一刀一个）；
##     精英 hp=150，是"追着打 5 秒"的量级，必掉宝箱回 50 血（D 方案）。
##
## 贴图是 convert_enemy_pack.py 产出的白色剪影横条精灵表，
## 颜色全部由渲染层染（BASE_COLOR），这里只存染什么颜色。
##

const ANIM_FRAMES := 6    # 所有类型统一重采样到 6 帧（帧数差 24~1，直接用会爆 draw call）

# 字段：id / 名字 / 贴图 / 帧数(表内) / hp / 速度 / 半径 / 接触伤害 / 经验 / 染色 /
#       from_sec(投放起始时间，-1 = 不进波次表) / weight(投放权重) / elite(是否精英)
const DEFS := [
	{
		"id": "error_red", "name": "报错红字",
		"tex": "res://assets/sprites/enemies/error_red.png",
		"sheet_frames": 24, "cell_w": 16, "cell_h": 14,
		"hp": 10.0, "speed": 55.0, "radius": 7.0, "damage": 9.0, "xp": 1,
		"color": Color(0.85, 0.28, 0.25),
		"from_sec": 0.0, "weight": 10, "elite": false,
	},
	{
		"id": "popup", "name": "弹窗",
		"tex": "res://assets/sprites/enemies/popup.png",
		"sheet_frames": 8, "cell_w": 14, "cell_h": 14,
		"hp": 8.0, "speed": 66.0, "radius": 6.0, "damage": 7.0, "xp": 1,
		"color": Color(0.95, 0.75, 0.30),
		"from_sec": 0.0, "weight": 6, "elite": false,
	},
	{
		"id": "junk_file", "name": "垃圾文件",
		"tex": "res://assets/sprites/enemies/junk_file.png",
		"sheet_frames": 6, "cell_w": 14, "cell_h": 16,
		"hp": 22.0, "speed": 40.0, "radius": 8.0, "damage": 9.0, "xp": 2,
		"color": Color(0.55, 0.50, 0.42),
		"from_sec": 45.0, "weight": 6, "elite": false,
	},
	{
		"id": "trojan", "name": "木马",
		"tex": "res://assets/sprites/enemies/trojan.png",
		"sheet_frames": 1, "cell_w": 10, "cell_h": 14,
		"hp": 16.0, "speed": 55.0, "radius": 7.0, "damage": 11.0, "xp": 2,
		"color": Color(0.72, 0.48, 0.30),
		"from_sec": 120.0, "weight": 5, "elite": false,
	},
	{
		"id": "virus", "name": "病毒总攻",
		"tex": "res://assets/sprites/enemies/virus.png",
		"sheet_frames": 8, "cell_w": 20, "cell_h": 18,
		"hp": 12.0, "speed": 76.0, "radius": 7.0, "damage": 9.0, "xp": 2,
		"color": Color(0.66, 0.42, 0.88),
		"from_sec": 180.0, "weight": 5, "elite": false,
	},
	{
		"id": "mojibake", "name": "乱码",
		"tex": "res://assets/sprites/enemies/mojibake.png",
		"sheet_frames": 3, "cell_w": 26, "cell_h": 14,
		"hp": 14.0, "speed": 70.0, "radius": 7.0, "damage": 10.0, "xp": 2,
		"color": Color(0.36, 0.80, 0.78),
		"from_sec": 240.0, "weight": 4, "elite": false,
	},
	{
		"id": "infinite_loop", "name": "死循环",
		"tex": "res://assets/sprites/enemies/infinite_loop.png",
		# 小恐龙（DinoSprites - vita 前 6 帧走路循环），源图朝左已在转换管线翻转
		"sheet_frames": 6, "cell_w": 14, "cell_h": 16,
		"hp": 40.0, "speed": 34.0, "radius": 10.0, "damage": 13.0, "xp": 3,
		"color": Color(0.92, 0.56, 0.20),
		"from_sec": 300.0, "weight": 3, "elite": false,
	},
	{
		"id": "bluescreen", "name": "蓝屏",
		"tex": "res://assets/sprites/enemies/bluescreen.png",
		"sheet_frames": 6, "cell_w": 10, "cell_h": 16,
		"hp": 28.0, "speed": 48.0, "radius": 9.0, "damage": 16.0, "xp": 3,
		"color": Color(0.36, 0.55, 0.95),
		"from_sec": 360.0, "weight": 3, "elite": false,
	},
	{
		"id": "oom", "name": "内存不足",
		"tex": "res://assets/sprites/enemies/oom.png",
		"sheet_frames": 8, "cell_w": 16, "cell_h": 20,
		"hp": 55.0, "speed": 32.0, "radius": 11.0, "damage": 18.0, "xp": 4,
		"color": Color(0.60, 0.66, 0.76),
		"from_sec": 480.0, "weight": 2, "elite": false,
	},
	{
		"id": "elite_skull", "name": "精英怪",
		"tex": "res://assets/sprites/enemies/elite_skull.png",
		"sheet_frames": 24, "cell_w": 22, "cell_h": 28,
		"hp": 350.0, "speed": 44.0, "radius": 14.0, "damage": 26.0, "xp": 20,
		"color": Color(0.75, 0.95, 0.60),
		"from_sec": 360.0, "weight": 0, "elite": true,   # 权重 0：不走普通刷怪，走精英定时器
	},
	{
		"id": "boss_compiler", "name": "编译器反噬",
		"tex": "res://assets/sprites/enemies/boss_compiler.png",
		"sheet_frames": 6, "cell_w": 52, "cell_h": 44,
		"hp": 80000.0, "speed": 48.0, "radius": 24.0, "damage": 34.0, "xp": 200,
		"color": Color(0.85, 0.22, 0.20),
		"from_sec": -1.0, "weight": 0, "elite": false, "boss": true,
		# 18 分钟终局出场（SpawnSystem.BOSS_AT），血量固定不随时间成长：
		# 它是"设计好的一场决战"，不该跟着杂兵一起被难度曲线放大。
	},
]

const ELITE_ID := "elite_skull"
const BOSS_ID := "boss_compiler"
const BASIC_IDX := 0            # 开局预铺/最弱杂兵 = 报错红字


## 按时间档位 + 权重随机选一种普通怪。精英与 Boss 不走这里。
##
## 权重会随"该类型已登场多久"衰减（见 _weight_at）。
## 不衰减的话，开局最弱的报错红字在 19 分钟仍占场上 23%
## （实测 smoke 日志），后期全靠数量堆压力，没有威胁升级感。
static func pick_type(t: float) -> int:
	var total := 0.0
	for d in DEFS:
		if d.from_sec >= 0.0 and d.from_sec <= t and not d.elite:
			total += _weight_at(d, t)
	if total <= 0.0:
		return BASIC_IDX
	var roll := randf() * total
	for i in DEFS.size():
		var d: Dictionary = DEFS[i]
		if d.from_sec >= 0.0 and d.from_sec <= t and not d.elite:
			roll -= _weight_at(d, t)
			if roll < 0.0:
				return i
	return BASIC_IDX


## 投放权重的实际值：登场越早的怪，后期出现得越少。
##
## 衰减速度由 from_sec 反推，不给每张卡加参数 ——
##   0 秒登场的开局杂兵 → 0.85/分（19 分钟后只剩 20%）
##   8 分钟登场的最强杂兵（内存不足）→ 1.0，不衰减
## 封底 0.2 倍：直接归零会掉敌人多样性，留一点让老怪偶尔露脸。
static func _weight_at(d: Dictionary, t: float) -> float:
	var since: float = maxf(0.0, t - float(d.from_sec))
	var per_min: float = clampf(0.85 + float(d.from_sec) / 480.0 * 0.15, 0.85, 1.0)
	return float(d.weight) * maxf(0.2, pow(per_min, since / 60.0))


static func idx_of(id: String) -> int:
	for i in DEFS.size():
		if DEFS[i].id == id:
			return i
	return -1


## 场上活着的精英数（精英定时器用来限制同屏数量，调用频率低，O(n) 无所谓）
static func elite_alive(pool: EnemyPool) -> int:
	var ei := idx_of(ELITE_ID)
	var n := 0
	for i in pool.count:
		if pool.type[i] == ei:
			n += 1
	return n
