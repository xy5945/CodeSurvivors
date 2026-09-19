class_name CharDefs
extends RefCounted
##
## 角色表：一个角色 = 起始武器 + 一组属性修正 + 一条特性。
##
## 设计原则（和武器/进化一致）：**特性改的是行为，不是数字**。
## 纯数值差异（+10% 伤害）玩家感觉不到，但"每 25 秒自动回一次血"
## "受击后无敌帧翻倍"会直接改变打法 —— 前者让人敢在残血时继续绕圈，
## 后者让人敢从敌群里穿过去。
##
## 角色定位刻意做得窄：每个角色只解决一种玩法诉求
## （成长速度 / 爆发节奏 / 堆叠收益 / 续航 / 容错），
## 不做"全能角"，否则选择题就变成"哪个数值高选哪个"。
##

# ---- 特性 ----
const T_LEARN := 0    # 实习生：每 10 级额外获得一次三选一
const T_RECUR := 1    # 算法工程师：每击杀 60 个，全部武器冷却立刻清零
const T_MODULE := 2   # 架构师：每持有一把武器，伤害 +5%
const T_CRON := 3     # 全栈工程师：每 25 秒自动回一次血
const T_BREAK := 4    # 测试工程师：受击后的无敌帧翻倍

# ---- 特性参数（改这里，不要散落到逻辑里）----
const LEARN_EVERY := 10          # 每多少级多给一次升级
const RECUR_KILLS := 60          # 每多少击杀触发一次全武器刷新
const MODULE_DMG := 0.05         # 每把武器的伤害加成
const CRON_INTERVAL := 25.0      # 定时任务的间隔（秒）
const CRON_HEAL_FRAC := 0.06     # 每次回最大生命的百分比
const BREAK_IFRAME_MULT := 2.0   # 无敌帧倍率

## ---- 难度 ----
## 每个角色一个难度系数，**目前只作用于敌人血量**：
##   实习生 0.7 → 测试 0.85 → 算法 1.0（基准）→ 全栈 1.1 → 架构师 1.2
## 越靠后的角色越强，敌人也就越硬 —— 解锁顺序和难度顺序是同一条线，
## 玩家每往前走一步，既拿到更强的角色，也接住更硬的一局。
## 只改血量不动速度/伤害：那两样一动，"这局难在哪"就说不清了。
## 头两档比"均匀等差"略低：这两个角色是刚上手的人最先碰到的，
## 先把反馈做足，再谈挑战。调整史：0.8/0.9 → 0.6/0.8 → 0.7/0.85。
const DEFAULT_ID := "intern"

const CHARACTERS: Array = [
	{
		"id": "intern", "name": "实习生", "term": "Hello World", "code": "print()",
		"plain": "第一个程序，先让它跑起来",
		"start": "whip",
		"trait": T_LEARN,
		"trait_name": "边学边练",
		"trait_desc": "每 10 级额外获得 1 次升级选择",
		"hp_mult": 1.0, "speed_mult": 1.0, "dmg_mult": 1.0,
		"cd_mult": 1.0, "pickup_mult": 1.0,
		"diff": 0.7,
		"color": Color(0.62, 0.86, 1.0),
	},
	{
		"id": "qa", "name": "测试工程师", "term": "断言", "code": "assert()",
		"plain": "先声明「这里必须对」，错了就停下来查",
		"start": "breakpoint",
		"trait": T_BREAK,
		"trait_name": "断点暂停",
		"trait_desc": "受伤后的无敌时间翻倍，可以从容脱离",
		"hp_mult": 1.05, "speed_mult": 1.08, "dmg_mult": 1.0,
		"cd_mult": 0.94, "pickup_mult": 1.0,
		"diff": 0.85,
		"color": Color(0.72, 0.72, 1.0),
	},
	{
		"id": "algo", "name": "算法工程师", "term": "递归", "code": "f(f(x))",
		"plain": "自己调用自己，一层层算到底",
		"start": "blade",
		"trait": T_RECUR,
		"trait_name": "递归返回",
		"trait_desc": "每消灭 60 个 Bug，全部武器立刻冷却完毕",
		"hp_mult": 0.95, "speed_mult": 1.0, "dmg_mult": 1.08,
		"cd_mult": 1.0, "pickup_mult": 1.0,
		"diff": 1.0,
		"color": Color(0.72, 1.0, 0.72),
	},
	{
		"id": "ops", "name": "全栈工程师", "term": "堆栈", "code": "stack",
		"plain": "后进先出 —— 最上面那层先处理，上下每一层都得管",
		"start": "forever",
		"trait": T_CRON,
		"trait_name": "全栈兜底",
		"trait_desc": "每 25 秒自动回复 6% 生命上限",
		"hp_mult": 1.25, "speed_mult": 0.94, "dmg_mult": 0.95,
		"cd_mult": 1.0, "pickup_mult": 1.0,
		"diff": 1.1,
		"color": Color(1.0, 0.62, 0.72),
	},
	{
		"id": "arch", "name": "架构师", "term": "模块化", "code": "import",
		"plain": "拆成一个个模块，拼起来用",
		"start": "orbit",
		"trait": T_MODULE,
		"trait_name": "模块堆叠",
		"trait_desc": "每持有一把武器，伤害 +5%",
		"hp_mult": 1.0, "speed_mult": 0.96, "dmg_mult": 1.0,
		"cd_mult": 1.0, "pickup_mult": 1.4,
		"diff": 1.2,
		"color": Color(1.0, 0.85, 0.55),
	},
]


## 按 id 取角色定义，找不到返回空字典。
static func def_of(id: String) -> Dictionary:
	for c in CHARACTERS:
		if str(c["id"]) == id:
			return c
	return {}


static func is_valid(id: String) -> bool:
	return not def_of(id).is_empty()


static func trait_of(id: String) -> int:
	var d := def_of(id)
	return int(d["trait"]) if not d.is_empty() else T_LEARN


## 角色在表里的下标（-1 = 不存在）。解锁链靠下标推进：第 n 个通关 → 开第 n+1 个。
static func index_of(id: String) -> int:
	for i in CHARACTERS.size():
		if str(CHARACTERS[i]["id"]) == id:
			return i
	return -1


static func def_at(i: int) -> Dictionary:
	if i < 0 or i >= CHARACTERS.size():
		return {}
	return CHARACTERS[i]


## 难度系数：敌人血量倍率。
static func diff_of(id: String) -> float:
	var d := def_of(id)
	return float(d["diff"]) if not d.is_empty() else 1.0
